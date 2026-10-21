import AppKit
import Common

struct StickyCommand: Command {
    let args: StickyCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) -> BinaryExitCode {
        guard let target = args.resolveTargetOrReportError(env, io) else { return .fail }
        guard let window = target.windowOrNil else {
            return .fail(io.err(noWindowIsFocused))
        }
        let newState: Bool = switch args.toggle {
            case .on: true
            case .off: false
            case .toggle: !window.isSticky
        }
        if newState == window.isSticky {
            switch args.failIfNoop {
                case true: return .fail
                case false:
                    let msg = newState
                        ? "Already sticky. Tip: use --fail-if-noop to exit with non-zero code"
                        : "Already not sticky. Tip: use --fail-if-noop to exit with non-zero code"
                    return .succ(io.err(msg))
            }
        }
        if newState && !window.isFloating {
            // A tiled window can't be displayed on all workspaces; sticky windows must be floating
            window.bindAsFloatingWindow(to: window.nodeWorkspace ?? focus.workspace)
        }
        window.isSticky = newState
        if newState {
            // Make the window visible immediately if its workspace is not visible; otherwise the next
            // layout pass would keep it hidden (layoutWorkspaces skips sticky windows when hiding)
            (window as? MacWindow)?.unhideFromCorner()
        }

        // Focus on its own workspace
        window.markAsMostRecentChild()
        return .succ
    }
}
