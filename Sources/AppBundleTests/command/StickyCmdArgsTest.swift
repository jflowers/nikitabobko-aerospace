@testable import AppBundle
import Common
import XCTest

final class StickyCmdArgsTest: XCTestCase {
    func testParseOnOffAndToggle() {
        assertEquals(parseStickyCmdArgs(["on"].slice).cmdOrNil?.toggle, .on)
        assertEquals(parseStickyCmdArgs(["off"].slice).cmdOrNil?.toggle, .off)
        assertEquals(parseStickyCmdArgs([].slice).cmdOrNil?.toggle, .toggle)
    }

    func testParseWindowId() {
        let args = parseStickyCmdArgs(["--window-id", "42", "on"].slice).cmdOrNil
        assertEquals(args?.windowId, 42)
        assertEquals(args?.toggle, .on)
    }

    func testParseFailIfNoop() {
        let args = parseStickyCmdArgs(["--fail-if-noop", "on"].slice).cmdOrNil
        assertEquals(args?.failIfNoop, true)
        assertEquals(args?.toggle, .on)
    }

    func testParseFailIfNoopRequiresOnOrOff() {
        let result = parseStickyCmdArgs(["--fail-if-noop"].slice)
        switch result {
            case .cmd, .help:
                XCTFail("Expected failure")
            case .failure(let err):
                assertEquals(err, .init("--fail-if-noop requires 'on' or 'off' argument", 2))
        }
    }
}
