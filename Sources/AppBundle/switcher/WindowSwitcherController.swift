import AppKit
import Common

/// Implements the native App Switcher-like GUI for `focus dfs-next|dfs-prev --gui`.
///
/// The lifecycle (all on MainActor):
/// 1. The first `focus dfs-next --gui` invocation opens a session: it snapshots the workspace windows (in DFS order,
///    floating windows included) and the sticky windows of the monitor, captures the anchor modifier (the modifiers
///    currently held, `Shift` excluded) and shows the overlay panel. The selection starts on the focused window and
///    advances by one
/// 2. Every subsequent invocation while the session is open advances the selection by one. Focus is never changed
///    during the preview. Arrow keys move the selection (wrapping around); a mouse click on a cell commits it
/// 3. The session ends on the anchor modifier release or `Enter` (commit: focus the selected window), on `Escape`
///    (cancel: keep the current focus), or on the idle timeout (cancel)
///
/// If the GUI can't be opened (no anchor modifier is held, e.g. when the command is triggered from CLI; or the event
/// tap can't be created), `cycle` returns `nil` and the caller should fall back to the regular immediate behavior
@MainActor
final class WindowSwitcherController {
    static let shared = WindowSwitcherController()

    struct Session {
        let workspace: Workspace
        let boundariesAction: FocusCmdArgs.WhenBoundariesCrossed
        var windows: [Window]
        var selectedIndex: Int
    }

    private(set) var session: Session?

    private var eventTap: SwitcherEventTap?
    private var idleTimer: Timer?
    private var titleCache: [UInt32: String] = [:]
    /// Guards async title fetches against completed sessions
    private var sessionGeneration = 0

    /// `Shift` is excluded, because it's typically used to change the cycling direction (alt-tab vs alt-shift-tab)
    private static let anchorModifiersMask: NSEvent.ModifierFlags = [.command, .option, .control]
    private static let idleTimeout: TimeInterval = 10 /* seconds */

    /// Returns `nil` if the GUI session can't be opened and the caller should fall back to the immediate focus
    func cycle(
        dfsRelative: DfsNextPrev,
        windows: [Window],
        currentIndex: Int,
        boundariesAction: FocusCmdArgs.WhenBoundariesCrossed,
        workspace: Workspace,
    ) -> BinaryExitCode? {
        if let session, session.workspace !== workspace {
            // The focus moved to another workspace mid-session (e.g. with a mouse click)
            endSession()
        }
        if session == nil {
            let anchorModifiers = NSEvent.modifierFlags.intersection(Self.anchorModifiersMask)
            if !isUnitTest && anchorModifiers.isEmpty {
                // Without a held anchor modifier there is no way to detect the commit moment
                return nil
            }
            session = Session(
                workspace: workspace,
                boundariesAction: boundariesAction,
                windows: windows,
                selectedIndex: currentIndex,
            )
            sessionGeneration += 1
            if !isUnitTest {
                let tap = SwitcherEventTap(
                    anchorModifiers: anchorModifiers,
                    onCommit: { [weak self] in self?.commit() },
                    onCancel: { [weak self] in self?.cancel() },
                    onArrowPrev: { [weak self] in self?.moveSelection(by: -1) },
                    onArrowNext: { [weak self] in self?.moveSelection(by: 1) },
                )
                if tap.start() {
                    eventTap = tap
                } else {
                    // Without the event tap there is no way to detect the modifier release; degrade to immediate focus
                    endSession()
                    return nil
                }
            }
        }

        guard var liveSession = session else { return nil }

        // The snapshot could become stale while the session is open: windows could be closed or moved to another
        // workspace. Keep the selected window if it's still valid, clamp the index otherwise.
        // Sticky windows are visible on all workspaces of the monitor, so they stay even when bound to another workspace
        let selectedWindow = liveSession.windows.getOrNil(atIndex: liveSession.selectedIndex)
        liveSession.windows = liveSession.windows.filter { $0.isSticky || $0.nodeWorkspace == workspace }
        if liveSession.windows.isEmpty {
            endSession()
            return .succ
        }
        liveSession.selectedIndex = liveSession.windows.firstIndex(where: { $0 == selectedWindow })
            ?? min(liveSession.selectedIndex, liveSession.windows.count - 1)

        let nextIndex = switch dfsRelative {
            case .dfsNext: liveSession.selectedIndex + 1
            case .dfsPrev: liveSession.selectedIndex - 1
        }
        switch liveSession.boundariesAction {
            // `fail` degrades to `stop` in GUI mode: there is no meaningful way to report the error to the user
            case .stop, .fail:
                liveSession.selectedIndex = min(max(nextIndex, 0), liveSession.windows.count - 1)
            case .wrapAroundTheWorkspace, .wrapAroundAllMonitors:
                liveSession.selectedIndex = (nextIndex + liveSession.windows.count) % liveSession.windows.count
        }

        session = liveSession
        restartIdleTimer()
        updatePanel()
        return .succ
    }

    func commit() {
        guard let session else { return }
        let windowToFocus = session.windows.getOrNil(atIndex: session.selectedIndex)
        endSession()
        _ = windowToFocus?.focusWindow()
        windowToFocus?.nativeFocus() // syncFocusToMacOs
    }

    func cancel() {
        endSession()
    }

    /// Moves the selection by `delta` positions (e.g. triggered by arrow keys). Wraps around the window list
    func moveSelection(by delta: Int) {
        guard var liveSession = session, !liveSession.windows.isEmpty else { return }
        liveSession.selectedIndex = (liveSession.selectedIndex + delta + liveSession.windows.count) % liveSession.windows.count
        session = liveSession
        restartIdleTimer()
        updatePanel()
    }

    /// Commits the selection at `index` (e.g. triggered by a mouse click on the corresponding panel cell)
    func commitSelection(at index: Int) {
        guard var liveSession = session, liveSession.windows.indices.contains(index) else { return }
        liveSession.selectedIndex = index
        session = liveSession
        commit()
    }

    private func endSession() {
        session = nil
        sessionGeneration += 1
        idleTimer?.invalidate()
        idleTimer = nil
        if !isUnitTest {
            SwitcherPanel.shared.closePanel()
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
        SwitcherPanel.shared.update(
            with: viewModel(session),
            on: session.workspace.workspaceMonitor,
            onSelect: { [weak self] index in self?.commitSelection(at: index) },
        )
        fetchTitle(ofSelectedWindowIn: session)
    }

    private func viewModel(_ session: Session) -> SwitcherViewModel {
        .init(
            items: session.windows.map { window in
                .init(
                    icon: (window.app as? MacApp)?.nsApp.icon,
                    title: titleCache[window.windowId] ?? window.app.name ?? "Window \(window.windowId)",
                )
            },
            selectedIndex: session.selectedIndex,
        )
    }

    /// Window titles require async AX reads, so they are fetched lazily, only for the selected window
    private func fetchTitle(ofSelectedWindowIn session: Session) {
        guard let window = session.windows.getOrNil(atIndex: session.selectedIndex),
              titleCache[window.windowId] == nil
        else { return }
        let generation = sessionGeneration
        Task.startUnstructured { @MainActor in
            guard let title = try? await window.getTitle(.nonCancellable), !title.isEmpty else { return }
            guard generation == self.sessionGeneration else { return }
            self.titleCache[window.windowId] = title
            if self.session != nil {
                self.updatePanel()
            }
        }
    }
}
