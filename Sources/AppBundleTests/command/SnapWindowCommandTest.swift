@testable import AppBundle
import Common
import XCTest

@MainActor
final class SnapWindowCommandTest: XCTestCase {
    override func setUp() async throws {
        setUpWorkspacesForTests()
    }

    private func newFloatingWindow(rect: Rect?) -> TestWindow {
        let workspace = Workspace.get(byName: name)
        return TestWindow.new(id: 1, parent: workspace.floatingWindowsContainer, rect: rect)
    }

    // Test monitor visible rect is 1920x1080 at (0,0)

    private func assertFrame(_ window: TestWindow, _ expected: Rect, _ file: StaticString = #filePath, _ line: UInt = #line) async throws {
        let rect = try await window.getAxRect(.nonCancellable)!
        assertEquals(rect.topLeftX, expected.topLeftX, file: file, line: line)
        assertEquals(rect.topLeftY, expected.topLeftY, file: file, line: line)
        assertEquals(rect.width, expected.width, file: file, line: line)
        assertEquals(rect.height, expected.height, file: file, line: line)
    }

    // MARK: halves

    func testRunLeftHalf() async throws {
        let window = newFloatingWindow(rect: Rect(topLeftX: 960, topLeftY: 540, width: 100, height: 100))
        let result = await parseCommand("snap-window --window-id 1 left-half").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        try await assertFrame(window, Rect(topLeftX: 0, topLeftY: 0, width: 960, height: 1080))
    }

    func testRunRightHalf() async throws {
        let window = newFloatingWindow(rect: Rect(topLeftX: 0, topLeftY: 0, width: 100, height: 100))
        let result = await parseCommand("snap-window --window-id 1 right-half").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        try await assertFrame(window, Rect(topLeftX: 960, topLeftY: 0, width: 960, height: 1080))
    }

    func testRunTopHalf() async throws {
        let window = newFloatingWindow(rect: nil)
        let result = await parseCommand("snap-window --window-id 1 top-half").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        try await assertFrame(window, Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 540))
    }

    func testRunBottomHalf() async throws {
        let window = newFloatingWindow(rect: nil)
        let result = await parseCommand("snap-window --window-id 1 bottom-half").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        try await assertFrame(window, Rect(topLeftX: 0, topLeftY: 540, width: 1920, height: 540))
    }

    func testRunCenter() async throws {
        let window = newFloatingWindow(rect: Rect(topLeftX: 0, topLeftY: 0, width: 200, height: 100))
        let result = await parseCommand("snap-window --window-id 1 center").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        try await assertFrame(window, Rect(topLeftX: 860, topLeftY: 490, width: 200, height: 100))
    }

    func testRunCenterClampsOversizedWindow() async throws {
        let window = newFloatingWindow(rect: Rect(topLeftX: 0, topLeftY: 0, width: 3000, height: 2000))
        let result = await parseCommand("snap-window --window-id 1 center").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        try await assertFrame(window, Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080))
    }

    func testRunDefaultsToFocusedWindow() async throws {
        let workspace = Workspace.get(byName: name)
        let window = TestWindow.new(id: 1, parent: workspace.floatingWindowsContainer)
        _ = window.focusWindow()

        let result = await parseCommand("snap-window left-half").cmdOrDie.run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode.rawValue, 0)
        try await assertFrame(window, Rect(topLeftX: 0, topLeftY: 0, width: 960, height: 1080))
    }

    // MARK: errors

    func testFailOnTilingWindow() async {
        let workspace = Workspace.get(byName: name)
        _ = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)

        let result = await parseCommand("snap-window --window-id 1 left-half").cmdOrDie.run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode.rawValue, 2)
        assertEquals(result.stderr, ["snap-window command works only on floating windows"])
    }

    func testParseFailOnBadRegion() {
        testParseCommandFail(
            "snap-window --window-id 1 wrong-region",
            msg: "ERROR: Can't parse 'wrong-region'.\n       Possible values: (left-half|right-half|top-half|bottom-half|center)",
            exitCode: 2,
        )
    }
}
