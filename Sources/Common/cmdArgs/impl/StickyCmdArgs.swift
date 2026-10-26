public struct StickyCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    fileprivate init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public init(rawArgs: [String], toggle: ToggleEnum) {
        self.commonState = .init(rawArgs.slice)
        self.toggle = toggle
    }
    public static let parser: CmdParser<Self> = .init(
        kind: .sticky,
        help: sticky_help_generated,
        flags: [
            "--fail-if-noop": trueBoolFlag(\.failIfNoop),
            "--window-id": windowIdSubArgParser(),
        ],
        posArgs: [ArgParser(\.toggle, parseToggleEnum)],
    )

    public var toggle: ToggleEnum = .toggle
    public var failIfNoop: Bool = false
}

public func parseStickyCmdArgs(_ args: StrArrSlice) -> ParsedCmd<StickyCmdArgs> {
    parseSpecificCmdArgs(StickyCmdArgs(rawArgs: args), args)
        .filter("--fail-if-noop requires 'on' or 'off' argument") { $0.failIfNoop.implies($0.toggle == .on || $0.toggle == .off) }
}
