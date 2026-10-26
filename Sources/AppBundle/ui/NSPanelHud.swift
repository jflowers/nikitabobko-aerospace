import AppKit
import Common

open class NSPanelHud: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless, .hudWindow, .utilityWindow],
            backing: .buffered,
            defer: false,
        )
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isReleasedWhenClosed = false
        self.hidesOnDeactivate = false
        self.isMovableByWindowBackground = false
        self.alphaValue = 1
        self.hasShadow = true
        self.backgroundColor = .clear
    }

    static func centered(_ size: NSSize, on monitor: MonitorInfo) -> NSRect {
        let screenFrame =
            NSScreen.screens.getOrNil(atIndex: monitor.monitorAppKitNsScreenScreensId - 1)?.frame
                ?? NSScreen.main?.frame
                ?? .zero
        return NSRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.midY - size.height / 2,
            width: size.width,
            height: size.height,
        )
    }
}
