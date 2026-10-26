import AppKit
import Common

struct SetFrameCommand: Command {
    let args: SetFrameCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) async -> BinaryExitCode {
        guard let target = args.resolveTargetOrReportError(env, io) else { return .fail }
        guard let window = target.windowOrNil else {
            return .fail(io.err(noWindowIsFocused))
        }
        guard window.isFloating else {
            return .fail(io.err("set-frame command works only on floating windows"))
        }
        let requestedFrame = Rect(
            topLeftX: args.x.val,
            topLeftY: args.y.val,
            width: args.width.val,
            height: args.height.val,
        )
        let monitor = monitorWithLargestOverlap(of: requestedFrame)
        let frame = clampFrame(requestedFrame, to: monitor.visibleRect)
        await window.setAxFrameSync(frame.topLeftCorner, frame.size)
        return .succ
    }
}

/// Clamp the frame to stay inside the visible rect. Never loses a window off-screen
func clampFrame(_ frame: Rect, to visibleRect: Rect) -> Rect {
    let width = min(frame.width, visibleRect.width)
    let height = min(frame.height, visibleRect.height)
    let x = frame.topLeftX.coerce(in: visibleRect.minX ... max(visibleRect.minX, visibleRect.maxX - width))
    let y = frame.topLeftY.coerce(in: visibleRect.minY ... max(visibleRect.minY, visibleRect.maxY - height))
    return Rect(topLeftX: x, topLeftY: y, width: width, height: height)
}

func monitorWithLargestOverlap(of rect: Rect) -> MonitorInfo {
    let monitor = monitorInfos.max { lhs, rhs in
        rectsIntersectionArea(rect, lhs.visibleRect) < rectsIntersectionArea(rect, rhs.visibleRect)
    }
    if let monitor, rectsIntersectionArea(rect, monitor.visibleRect) > 0 {
        return monitor
    }
    // The frame doesn't overlap with any monitor. Use the closest one
    return rect.center.monitorApproximation
}

func rectsIntersectionArea(_ lhs: Rect, _ rhs: Rect) -> CGFloat {
    let xOverlap = min(lhs.maxX, rhs.maxX) - max(lhs.minX, rhs.minX)
    let yOverlap = min(lhs.maxY, rhs.maxY) - max(lhs.minY, rhs.minY)
    guard xOverlap > 0, yOverlap > 0 else { return 0 }
    return xOverlap * yOverlap
}
