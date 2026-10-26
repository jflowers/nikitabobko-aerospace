public struct SnapWindowCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    fileprivate init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .snapWindow,
        help: snap_window_help_generated,
        flags: [
            "--window-id": windowIdSubArgParser(),
        ],
        posArgs: [
            newMandatoryPosArgParser(\.region, parseRegion, placeholder: "(left-half|right-half|top-half|bottom-half|center)"),
        ],
    )

    public var region: Lateinit<SnapWindowCmdArgs.Region> = .uninitialized

    public enum Region: String, CaseIterable, Equatable, Sendable {
        case leftHalf = "left-half"
        case rightHalf = "right-half"
        case topHalf = "top-half"
        case bottomHalf = "bottom-half"
        case center
    }
}

func parseSnapWindowCmdArgs(_ args: StrArrSlice) -> ParsedCmd<SnapWindowCmdArgs> {
    parseSpecificCmdArgs(SnapWindowCmdArgs(rawArgs: args), args)
}

private func parseRegion(i: PosArgParserInput) -> ParsedCliArgs<SnapWindowCmdArgs.Region> {
    .init(parseEnum(i.arg, SnapWindowCmdArgs.Region.self), advanceBy: 1)
}
