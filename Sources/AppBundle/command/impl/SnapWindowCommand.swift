import AppKit
import Common

struct SnapWindowCommand: Command {
    let args: SnapWindowCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) async -> BinaryExitCode {
        guard let target = args.resolveTargetOrReportError(env, io) else { return .fail }
        guard let window = target.windowOrNil else {
            return .fail(io.err(noWindowIsFocused))
        }
        guard window.isFloating else {
            return .fail(io.err("snap-window command works only on floating windows"))
        }
        let windowRect = try? await window.getAxRect(.nonCancellable)
        let monitor = monitorForWindow(windowRect: windowRect, nodeMonitor: window.nodeMonitor)
        let visibleRect = monitor.visibleRect
        let frame: Rect = switch args.region.val {
            case .leftHalf:
                Rect(topLeftX: visibleRect.minX, topLeftY: visibleRect.minY, width: visibleRect.width / 2, height: visibleRect.height)
            case .rightHalf:
                Rect(topLeftX: visibleRect.minX + visibleRect.width / 2, topLeftY: visibleRect.minY, width: visibleRect.width / 2, height: visibleRect.height)
            case .topHalf:
                Rect(topLeftX: visibleRect.minX, topLeftY: visibleRect.minY, width: visibleRect.width, height: visibleRect.height / 2)
            case .bottomHalf:
                Rect(topLeftX: visibleRect.minX, topLeftY: visibleRect.minY + visibleRect.height / 2, width: visibleRect.width, height: visibleRect.height / 2)
            case .center:
                centerFrame(windowSize: windowRect?.size, in: visibleRect)
        }
        await window.setAxFrameSync(frame.topLeftCorner, frame.size)
        return .succ
    }
}

func centerFrame(windowSize: CGSize?, in visibleRect: Rect) -> Rect {
    let size = windowSize ?? visibleRect.size
    return clampFrame(
        Rect(
            topLeftX: visibleRect.minX + (visibleRect.width - size.width) / 2,
            topLeftY: visibleRect.minY + (visibleRect.height - size.height) / 2,
            width: size.width,
            height: size.height,
        ),
        to: visibleRect,
    )
}

func monitorForWindow(windowRect: Rect?, nodeMonitor: MonitorInfo?) -> MonitorInfo {
    if let center = windowRect?.center {
        return center.monitorApproximation
    }
    return nodeMonitor ?? mainMonitorInfo
}
