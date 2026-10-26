import AppKit
import Common

/// Implements the vertical workspace picker GUI for `move-node-to-workspace --gui` and `workspace (next|prev) --gui`.
///
/// The lifecycle (all on MainActor):
/// 1. The command opens a session: it snapshots the relevant workspaces, captures the anchor modifier (the
///    modifiers currently held, `Shift` excluded) and shows the overlay panel centered on the target monitor
/// 2. While the session is open, arrow keys move the selection; a mouse click on a row commits it.
///    Neither the windows nor the focus are touched during the preview
/// 3. The session ends on the anchor modifier release or `Enter` (commit), on `Escape` (cancel), or on the idle
///    timeout (cancel)
///
/// `move-node-to-workspace --gui` opens the session with the selection on the workspace of the target window and
/// commits by moving the window to the selected workspace.
///
/// `workspace (next|prev) --gui` opens the session with the selection on the focused workspace, advances the
/// selection by one workspace on every invocation (the command is typically bound to a hotkey that is tapped
/// repeatedly while the modifiers are held), and commits by focusing the selected workspace. If no anchor
/// modifier is held when the session is about to open (e.g. when the command is triggered from CLI), the session
/// isn't opened and the command falls back to the immediate non-GUI behavior.
///
/// The command returns immediately after opening the session; the actual action happens later in `commit()` with
/// the result discarded (mirroring `WindowSwitcherController`). If no anchor modifier is held (e.g. when
/// `move-node-to-workspace --gui` is triggered from CLI), the session still opens, but it can only be committed
/// with `Enter` or a mouse click
@MainActor
final class WorkspacePickerController {
    static let shared = WorkspacePickerController()

    enum SessionAction: Equatable {
        case moveWindow(windowId: UInt32, focusFollowsWindow: Bool, failIfNoop: Bool)
        case focusWorkspace
    }

    struct Session {
        let action: SessionAction
        let monitor: MonitorInfo
        var workspaces: [Workspace]
        var selectedIndex: Int
        /// Whether moving the selection (with arrow keys or by re-triggering the command) wraps around the list
        let wrapsAround: Bool
    }

    private(set) var session: Session?

    private var eventTap: SwitcherEventTap?
    private var idleTimer: Timer?

    /// `Shift` is excluded, because it's typically used to change the cycling direction
    private static let anchorModifiersMask: NSEvent.ModifierFlags = [.command, .option, .control]
    private static let idleTimeout: TimeInterval = 10 /* seconds */

    /// Returns `nil` if the GUI session can't be opened
    func open(
        windowId: UInt32,
        workspaces: [Workspace],
        selectedIndex: Int,
        monitor: MonitorInfo,
        focusFollowsWindow: Bool,
        failIfNoop: Bool,
    ) -> BinaryExitCode? {
        guard !workspaces.isEmpty, workspaces.indices.contains(selectedIndex) else { return nil }
        if session != nil {
            // Re-triggering the command while the session is open is a no-op
            restartIdleTimer()
            return .succ
        }
        return startSession(
            action: .moveWindow(windowId: windowId, focusFollowsWindow: focusFollowsWindow, failIfNoop: failIfNoop),
            workspaces: workspaces,
            selectedIndex: selectedIndex,
            monitor: monitor,
            wrapsAround: true,
        )
    }

    /// Opens (if needed) and advances the cycling session for `workspace (next|prev) --gui`.
    ///
    /// The session starts with the selection on the currently focused workspace, and every invocation advances it
    /// by one workspace in the requested direction, wrapping around if `wrapAround` is set and stopping at the
    /// boundaries otherwise. The workspaces list is recomputed by the caller on every invocation; the selection is
    /// kept by workspace name.
    ///
    /// Returns `nil` if the GUI session can't be opened (no anchor modifier is held, the list is empty, or the
    /// event tap creation fails), in which case the caller falls back to the immediate non-GUI behavior
    func cycle(
        workspaces: [Workspace],
        currentIndex: Int,
        isNext: Bool,
        wrapAround: Bool,
        monitor: MonitorInfo,
    ) -> BinaryExitCode? {
        if session?.action != .focusWorkspace {
            // Take over a session opened by another command (e.g. `move-node-to-workspace --gui`)
            endSession()
        }
        if workspaces.isEmpty {
            guard session != nil else { return nil }
            endSession()
            return .succ
        }
        if session == nil {
            if !isUnitTest, NSEvent.modifierFlags.isDisjoint(with: Self.anchorModifiersMask) {
                // No anchor modifier is held (e.g. the command is triggered from CLI); the caller falls back to
                // the immediate non-GUI behavior
                return nil
            }
            let code = startSession(
                action: .focusWorkspace,
                workspaces: workspaces,
                selectedIndex: min(max(currentIndex, 0), workspaces.count - 1),
                monitor: monitor,
                wrapsAround: wrapAround,
            )
            guard code != nil else { return nil }
        }
        guard var liveSession = session else { return nil }
        // The list could change between invocations (e.g. workspaces are created or destroyed); keep the selection
        // by workspace name
        let selectedName = liveSession.workspaces.getOrNil(atIndex: liveSession.selectedIndex)?.name
        liveSession.workspaces = workspaces
        liveSession.selectedIndex = selectedName
            .flatMap { name in workspaces.firstIndex { $0.name == name } }
            ?? min(max(liveSession.selectedIndex, 0), workspaces.count - 1)
        liveSession.selectedIndex = Self.advanceIndex(
            liveSession.selectedIndex,
            by: isNext ? 1 : -1,
            count: workspaces.count,
            wrapAround: liveSession.wrapsAround,
        )
        session = liveSession
        restartIdleTimer()
        updatePanel()
        return .succ
    }

    func commit() {
        guard let liveSession = session else { return }
        let selectedWorkspace = liveSession.workspaces.getOrNil(atIndex: liveSession.selectedIndex)
        let action = liveSession.action
        endSession()
        switch action {
            case let .moveWindow(windowId, focusFollowsWindow, failIfNoop):
                // The window could be closed mid-session. In production `Window.get(byId:)` may still return a recently closed
                // window, so also require it to still be bound to a workspace (the switcher uses the same liveness heuristic)
                guard let selectedWorkspace, let window = Window.get(byId: windowId), window.nodeWorkspace != nil else { return }
                // The workspace could be garbage-collected mid-session; re-resolve by name, recreating it if needed (the same
                // happens when moving by name on the CLI)
                let targetWorkspace = Workspace.get(byName: selectedWorkspace.name)
                // There is no meaningful way to report the error to the user at this point, so the result is discarded
                _ = moveWindowToWorkspace(
                    window,
                    targetWorkspace,
                    CmdIoImpl.emptyStdinIgnoringOut,
                    focusFollowsWindow: focusFollowsWindow,
                    failIfNoop: failIfNoop,
                )
                if focusFollowsWindow {
                    window.nativeFocus() // syncFocusToMacOs
                }
            case .focusWorkspace:
                // The workspace could be garbage-collected mid-session; re-resolve by name, recreating it if needed (the same
                // happens when focusing by name on the CLI)
                guard let selectedWorkspace else { return }
                // There is no meaningful way to report the error to the user at this point, so the result is discarded
                _ = Workspace.get(byName: selectedWorkspace.name).focusWorkspace()
                focus.windowOrNil?.nativeFocus() // syncFocusToMacOs
        }
        // Model mutations happen outside `runLightSession`; schedule the same complete refresh that AX
        // notifications trigger, so that `layoutWorkspaces` hides/shows windows immediately
        if !isUnitTest {
            scheduleCancellableCompleteRefreshSession(.ax("WorkspacePickerController.commit"))
        }
    }

    func cancel() {
        endSession()
    }

    /// Moves the selection by `delta` positions (e.g. triggered by arrow keys)
    func moveSelection(by delta: Int) {
        guard var liveSession = session, !liveSession.workspaces.isEmpty else { return }
        liveSession.selectedIndex = Self.advanceIndex(
            liveSession.selectedIndex,
            by: delta,
            count: liveSession.workspaces.count,
            wrapAround: liveSession.wrapsAround,
        )
        session = liveSession
        restartIdleTimer()
        updatePanel()
    }

    /// Commits the selection at `index` (e.g. triggered by a mouse click on the corresponding panel row)
    func commitSelection(at index: Int) {
        guard var liveSession = session, liveSession.workspaces.indices.contains(index) else { return }
        liveSession.selectedIndex = index
        session = liveSession
        commit()
    }

    /// Returns `nil` if the GUI session can't be opened
    private func startSession(
        action: SessionAction,
        workspaces: [Workspace],
        selectedIndex: Int,
        monitor: MonitorInfo,
        wrapsAround: Bool,
    ) -> BinaryExitCode? {
        guard !workspaces.isEmpty, workspaces.indices.contains(selectedIndex) else { return nil }
        session = Session(
            action: action,
            monitor: monitor,
            workspaces: workspaces,
            selectedIndex: selectedIndex,
            wrapsAround: wrapsAround,
        )
        if !isUnitTest {
            let anchorModifiers = NSEvent.modifierFlags.intersection(Self.anchorModifiersMask)
            let tap = SwitcherEventTap(
                anchorModifiers: anchorModifiers.isEmpty ? nil : anchorModifiers,
                onCommit: { [weak self] in self?.commit() },
                onCancel: { [weak self] in self?.cancel() },
                onArrowPrev: { [weak self] in self?.moveSelectionByArrow(up: true) },
                onArrowNext: { [weak self] in self?.moveSelectionByArrow(up: false) },
                tapCreationFailureMessage:
                "aerospace: Can't create CGEventTap for the workspace picker GUI. " +
                    "Make sure AeroSpace has Accessibility permission, and try granting Input Monitoring permission " +
                    "(System Settings -> Privacy & Security)",
            )
            if tap.start() {
                eventTap = tap
            } else {
                endSession()
                return nil
            }
        }
        restartIdleTimer()
        updatePanel()
        return .succ
    }

    private func moveSelectionByArrow(up: Bool) {
        moveSelection(by: up ? -1 : 1)
    }

    private static func advanceIndex(_ index: Int, by delta: Int, count: Int, wrapAround: Bool) -> Int {
        if wrapAround {
            return (index + delta + count) % count
        } else {
            return min(max(index + delta, 0), count - 1)
        }
    }

    private func endSession() {
        session = nil
        idleTimer?.invalidate()
        idleTimer = nil
        if !isUnitTest {
            WorkspacePickerPanel.shared.closePanel()
        }
        if let tap = eventTap {
            eventTap = nil
            // Defer the teardown, because the method can be triggered from within the event tap callback
            DispatchQueue.main.async { tap.stop() }
        }
    }

    private func restartIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: Self.idleTimeout, repeats: false) { [weak self] _ in
            Task.startUnstructured { @MainActor in
                guard let self, self.session != nil else { return }
                self.endSession()
            }
        }
    }

    private func updatePanel() {
        guard let session, !isUnitTest else { return }
        WorkspacePickerPanel.shared.update(
            with: viewModel(session),
            on: session.monitor,
            onSelect: { [weak self] index in self?.commitSelection(at: index) },
        )
    }

    private func viewModel(_ session: Session) -> WorkspacePickerViewModel {
        .init(
            names: session.workspaces.map(\.name),
            selectedIndex: session.selectedIndex,
        )
    }
}
