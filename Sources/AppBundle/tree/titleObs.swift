import AppKit
import Common

@MainActor
private var lastEmittedTitles: [UInt32: String] = [:]

func titleObs(_: AXObserver, ax: AXUIElement, _: CFString, _: UnsafeMutableRawPointer?) {
    let windowId = ax.containingWindowId()
    let title: String? = ax.get(Ax.titleAttr)
    Task.startUnstructured { @MainActor in
        guard RunSessionGuard.isServerEnabled != nil else { return }
        guard let windowId, let window = Window.get(byId: windowId) else {
            if let windowId {
                lastEmittedTitles.removeValue(forKey: windowId)
            }
            return
        }
        guard let title else { return } // Ignore windows without a title
        if lastEmittedTitles[windowId] == title { return } // Deduplicate: don't emit if the title hasn't changed
        lastEmittedTitles[windowId] = title
        broadcastEvent(.windowTitleChanged(
            windowId: window.windowId,
            title: title,
            appBundleId: window.app.rawAppBundleId,
            appName: window.app.name,
            workspace: window.nodeWorkspace?.name,
        ))
    }
}
