import Common
import Foundation
import os

/// Persisted across AeroSpace restarts to restore windows to the workspaces they belonged to before quit.
/// Opt-in via the `window-recovery` config option
struct WindowRecoveryState: Codable {
    static let currentVersion = 1

    let version: Int
    let world: FrozenWorld
}

let defaultWindowRecoveryFileUrl = URL
    .applicationSupportDirectory
    .appending(component: "AeroSpace")
    .appending(component: "window-recovery.json")

private let windowRecoveryLog = Logger(subsystem: aeroSpaceAppId, category: "window-recovery")

@MainActor
func saveWindowRecoveryState(to url: URL = defaultWindowRecoveryFileUrl) {
    // Collect floating window frames before the quit float-all-windows loop destroys them.
    // Frames are in top-left origin coordinates (same convention as `Rect`)
    var floatingFrames: [UInt32: FrozenFrame] = [:]
    for workspace in Workspace.all {
        for window in workspace.floatingWindows {
            if let macWindow = window as? MacWindow, let frame = macWindow.realFrameForRecovery() {
                floatingFrames[macWindow.windowId] = FrozenFrame(frame)
            }
        }
    }
    let state = WindowRecoveryState(
        version: WindowRecoveryState.currentVersion,
        world: snapshotFrozenWorld(floatingFrames: floatingFrames),
    )
    do {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: url, options: .atomic)
    } catch {
        windowRecoveryLog.warning("Can't save window recovery state to \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }
}

func loadWindowRecoveryState(from url: URL = defaultWindowRecoveryFileUrl) -> FrozenWorld? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    do {
        let state = try JSONDecoder().decode(WindowRecoveryState.self, from: Data(contentsOf: url))
        guard state.version == WindowRecoveryState.currentVersion else {
            windowRecoveryLog.warning("Ignoring window recovery state with unsupported version \(state.version, privacy: .public)")
            return nil
        }
        return state.world
    } catch {
        windowRecoveryLog.warning("Can't load window recovery state from \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        return nil
    }
}
