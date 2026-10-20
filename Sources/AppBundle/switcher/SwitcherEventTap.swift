import AppKit
import Common
import CoreGraphics
import Foundation

/// Observes system events while the window switcher GUI session is open (see `WindowSwitcherController`):
/// * Commit the selection when the anchor modifier is released (native `Cmd+Tab` semantics)
/// * Cancel the session on `Escape`
/// * Commit the session on `Return`/`Enter`
///
/// Requires Accessibility (and possibly Input Monitoring) permission; `start()` returns `false` if the event tap
/// can't be created, in which case the caller should fall back to the immediate focus behavior
final class SwitcherEventTap {
    private let anchorModifiers: NSEvent.ModifierFlags
    private let onCommit: @MainActor () -> Void
    private let onCancel: @MainActor () -> Void
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private static let escapeKeyCode: Int64 = 53
    private static let returnKeyCode: Int64 = 36
    private static let keypadEnterKeyCode: Int64 = 76

    init(anchorModifiers: NSEvent.ModifierFlags, onCommit: @escaping @MainActor () -> Void, onCancel: @escaping @MainActor () -> Void) {
        self.anchorModifiers = anchorModifiers
        self.onCommit = onCommit
        self.onCancel = onCancel
    }

    /// Must be called on the main thread
    func start() -> Bool {
        let eventMask =
            CGEventMask(1 << CGEventType.flagsChanged.rawValue) |
            CGEventMask(1 << CGEventType.keyDown.rawValue)
        let createdTap = unsafe CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: switcherEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque(),
        )
        guard let tap = createdTap else {
            eprint(
                "aerospace: Can't create CGEventTap for the window switcher GUI. " +
                    "Make sure AeroSpace has Accessibility permission, and try granting Input Monitoring permission " +
                    "(System Settings -> Privacy & Security). Falling back to immediate focus",
            )
            return false
        }
        self.tap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        guard let tap else { return }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFMachPortInvalidate(tap)
        self.tap = nil
    }

    func enable() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    /// Returns the event to pass through, or `nil` to consume it. Must not be called after `stop()`
    func handle(_ type: CGEventType, _ event: CGEvent) -> CGEvent? {
        switch type {
            case .tapDisabledByTimeout, .tapDisabledByUserInput:
                // Re-enabled eagerly by `switcherEventTapCallback`
                return event
            case .flagsChanged:
                let flags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
                if flags.isDisjoint(with: anchorModifiers) {
                    // The event tap source is attached to the main run loop, so the callback runs on the main thread
                    MainActor.assumeIsolated(onCommit)
                }
                return event
            case .keyDown:
                switch event.getIntegerValueField(.keyboardEventKeycode) {
                    case Self.escapeKeyCode:
                        MainActor.assumeIsolated(onCancel)
                        return nil
                    case Self.returnKeyCode, Self.keypadEnterKeyCode:
                        MainActor.assumeIsolated(onCommit)
                        return nil
                    default:
                        return event
                }
            default:
                return event
        }
    }
}

private func switcherEventTapCallback(
    _ proxy: CGEventTapProxy,
    _ type: CGEventType,
    _ event: CGEvent,
    _ userInfo: UnsafeMutableRawPointer?,
) -> Unmanaged<CGEvent>? {
    let eventTap = unsafe Unmanaged<SwitcherEventTap>.fromOpaque(userInfo!).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        eventTap.enable()
    }
    return unsafe eventTap.handle(type, event).map { unsafe Unmanaged.passUnretained($0) }
}
