public struct MoveNodeToWorkspaceCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public static let parser: CmdParser<Self> = .init(
        kind: .moveNodeToWorkspace,
        help: move_node_to_workspace_help_generated,
        flags: [
            "--wrap-around": ArgParser(\._wrapAround, constSubArgParserFun(true)),
            "--fail-if-noop": trueBoolFlag(\.failIfNoop),
            "--window-id": windowIdSubArgParser(),
            "--focus-follows-window": ArgParser(\.focusFollowsWindow, constSubArgParserFun(true)),
            "--gui": trueBoolFlag(\.gui),

            "--stdin": ArgParser(\.commonState.explicitStdinFlag, constSubArgParserFun(true)),
            "--no-stdin": ArgParser(\.commonState.explicitStdinFlag, constSubArgParserFun(false)),
        ],
        posArgs: [
            dashDashArg(mandatory: false),
            ArgParser(\.target, upcastArgParserFun(parseWorkspaceTarget)),
        ],
        conflictingOptions: [
            ["--stdin", "--no-stdin"],
        ],
    )

    public var _wrapAround: Bool?
    public var failIfNoop: Bool = false
    public var focusFollowsWindow: Bool = false
    public var gui: Bool = false
    public var target: WorkspaceTarget?

    public init(rawArgs: StrArrSlice) {
        self.commonState = .init(rawArgs)
    }
}

extension MoveNodeToWorkspaceCmdArgs {
    public var wrapAround: Bool { _wrapAround ?? false }
    public var useStdin: Bool { commonState.explicitStdinFlag ?? false }
}

func parseMoveNodeToWorkspaceCmdArgs(_ args: StrArrSlice) -> ParsedCmd<MoveNodeToWorkspaceCmdArgs> {
    parseSpecificCmdArgs(MoveNodeToWorkspaceCmdArgs(rawArgs: args), args)
        .filter("Either --gui or \(workspaceTargetPlaceholder) argument is required") { $0.gui || $0.target != nil }
        .filterNot("--gui is incompatible with \(workspaceTargetPlaceholder)") { $0.gui && $0.target != nil }
        .filter("--wrapAround requires using (prev|next) argument") { ($0._wrapAround != nil).implies($0.target?.isRelatve ?? false) }
        .filterNot("--fail-if-noop is incompatible with (next|prev)") { $0.failIfNoop && ($0.target?.isRelatve ?? false) }
        .filterNot("--window-id is incompatible with (next|prev)") { $0.windowId != nil && ($0.target?.isRelatve ?? false) }
        .filter("--stdin and --no-stdin require using \(NextPrev.unionLiteral) argument") { ($0.commonState.explicitStdinFlag != nil).implies($0.target?.isRelatve ?? false) }
}
