import Foundation

public struct SetFrameCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    fileprivate init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .setFrame,
        help: set_frame_help_generated,
        flags: [
            "--window-id": windowIdSubArgParser(),
        ],
        posArgs: [
            newMandatoryPosArgParser(\.x, parseFrameCoordinate, placeholder: "<x>"),
            newMandatoryPosArgParser(\.y, parseFrameCoordinate, placeholder: "<y>"),
            newMandatoryPosArgParser(\.width, parseFrameCoordinate, placeholder: "<width>"),
            newMandatoryPosArgParser(\.height, parseFrameCoordinate, placeholder: "<height>"),
        ],
    )

    public var x: Lateinit<CGFloat> = .uninitialized
    public var y: Lateinit<CGFloat> = .uninitialized
    public var width: Lateinit<CGFloat> = .uninitialized
    public var height: Lateinit<CGFloat> = .uninitialized
}

func parseSetFrameCmdArgs(_ args: StrArrSlice) -> ParsedCmd<SetFrameCmdArgs> {
    parseSpecificCmdArgs(SetFrameCmdArgs(rawArgs: args), args)
        .filter("<width> must be a positive number") { $0.width.val > 0 }
        .filter("<height> must be a positive number") { $0.height.val > 0 }
}

private func parseFrameCoordinate(i: PosArgParserInput) -> ParsedCliArgs<CGFloat> {
    if let number = Double(i.arg) {
        .succ(CGFloat(number), advanceBy: 1)
    } else {
        .fail("Can't convert '\(i.arg)' to a number", advanceBy: 1)
    }
}
