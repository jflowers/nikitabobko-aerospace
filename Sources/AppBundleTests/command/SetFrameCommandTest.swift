@testable import AppBundle
import Common
import XCTest

@MainActor
final class SetFrameCommandTest: XCTestCase {
    override func setUp() async throws {
        setUpWorkspacesForTests()
    }

    // MARK: parse errors

    func testParseFailOnNonNumberArg() {
        testParseCommandFail("set-frame --window-id 1 foo 0 100 100", msg: "ERROR: Can't convert 'foo' to a number", exitCode: 2)
    }

    func testParseFailOnNonPositiveWidth() {
        testParseCommandFail("set-frame --window-id 1 0 0 0 100", msg: "<width> must be a positive number", exitCode: 2)
    }

    func testParseFailOnNonPositiveHeight() {
        testParseCommandFail("set-frame --window-id 1 0 0 100 0", msg: "<height> must be a positive number", exitCode: 2)
    }

    func testParseFailOnNegativeWidth() {
        testParseCommandFail("set-frame --window-id 1 0 0 -5 100", msg: "<width> must be a positive number", exitCode: 2)
    }

    // MARK: happy path

    func testRunAppliesFrame() async throws {
        let workspace = Workspace.get(byName: name)
        let window = TestWindow.new(id: 1, parent: workspace.floatingWindowsContainer)
        window.setAxFrame(CGPoint(x: 50, y: 60), CGSize(width: 200, height: 100))

        let result = await parseCommand("set-frame --window-id 1 10 20 300 200").cmdOrDie.run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode.rawValue, 0)
        let rect = try await window.getAxRect(.nonCancellable)!
        assertEquals(rect.topLeftX, 10)
        assertEquals(rect.topLeftY, 20)
        assertEquals(rect.width, 300)
        assertEquals(rect.height, 200)
    }

    func testRunDefaultsToFocusedWindow() async throws {
        let workspace = Workspace.get(byName: name)
        let window = TestWindow.new(id: 1, parent: workspace.floatingWindowsContainer)
        _ = window.focusWindow()

        let result = await parseCommand("set-frame 0 0 100 100").cmdOrDie.run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode.rawValue, 0)
        let rect = try await window.getAxRect(.nonCancellable)!
        assertEquals(rect.width, 100)
        assertEquals(rect.height, 100)
    }

    func testRunFractionalCoordinates() async throws {
        let workspace = Workspace.get(byName: name)
        let window = TestWindow.new(id: 1, parent: workspace.floatingWindowsContainer)

        let result = await parseCommand("set-frame --window-id 1 10.5 20.25 300.5 100").cmdOrDie.run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode.rawValue, 0)
        let rect = try await window.getAxRect(.nonCancellable)!
        assertEquals(rect.topLeftX, 10.5)
        assertEquals(rect.topLeftY, 20.25)
        assertEquals(rect.width, 300.5)
    }

    // MARK: errors

    func testFailOnTilingWindow() async throws {
        let workspace = Workspace.get(byName: name)
        let window = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)

        let result = await parseCommand("set-frame --window-id 1 0 0 100 100").cmdOrDie.run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode.rawValue, 2)
        assertEquals(result.stderr, ["set-frame command works only on floating windows"])
        let rect = try await window.getAxRect(.nonCancellable)
        assertNil(rect)
    }

    func testFailOnInvalidWindowId() async {
        let result = await parseCommand("set-frame --window-id 42 0 0 100 100").cmdOrDie.run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode.rawValue, 2)
        assertEquals(result.stderr, ["Invalid <window-id> 42 passed to --window-id"])
    }

    // MARK: FR4 clamping

    func testRunClampsPartiallyOffScreenFrame() async throws {
        let workspace = Workspace.get(byName: name)
        let window = TestWindow.new(id: 1, parent: workspace.floatingWindowsContainer)

        // Test monitor is 1920x1080; the window sticks out to the left and to the bottom
        let result = await parseCommand("set-frame --window-id 1 -100 -50 300 2000").cmdOrDie.run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode.rawValue, 0)
        let rect = try await window.getAxRect(.nonCancellable)!
        assertEquals(rect.topLeftX, 0)
        assertEquals(rect.topLeftY, 0)
        assertEquals(rect.width, 300)
        assertEquals(rect.height, 1080)
    }

    func testRunClampsOversizedFrame() async throws {
        let workspace = Workspace.get(byName: name)
        let window = TestWindow.new(id: 1, parent: workspace.floatingWindowsContainer)

        let result = await parseCommand("set-frame --window-id 1 500 500 3000 3000").cmdOrDie.run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode.rawValue, 0)
        let rect = try await window.getAxRect(.nonCancellable)!
        assertEquals(rect.topLeftX, 0)
        assertEquals(rect.topLeftY, 0)
        assertEquals(rect.width, 1920)
        assertEquals(rect.height, 1080)
    }

    func testRunClampsFrameFullyOffScreen() async throws {
        let workspace = Workspace.get(byName: name)
        let window = TestWindow.new(id: 1, parent: workspace.floatingWindowsContainer)

        // Completely off-screen to the right; must not stay off-screen
        let result = await parseCommand("set-frame --window-id 1 5000 100 200 200").cmdOrDie.run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode.rawValue, 0)
        let rect = try await window.getAxRect(.nonCancellable)!
        assertEquals(rect.topLeftX, 1720)
        assertEquals(rect.topLeftY, 100)
        assertEquals(rect.width, 200)
        assertEquals(rect.height, 200)
    }

    // MARK: pure helpers

    func testClampFrame() {
        let visibleRect = Rect(topLeftX: 0, topLeftY: 25, width: 1000, height: 500)
        let frame = clampFrame(Rect(topLeftX: -10, topLeftY: 100, width: 300, height: 200), to: visibleRect)
        assertEquals(frame.topLeftX, 0)
        assertEquals(frame.topLeftY, 100)
        assertEquals(frame.width, 300)
        assertEquals(frame.height, 200)
    }

    func testRectsIntersectionArea() {
        let a = Rect(topLeftX: 0, topLeftY: 0, width: 100, height: 100)
        let b = Rect(topLeftX: 50, topLeftY: 50, width: 100, height: 100)
        let noOverlap = Rect(topLeftX: 200, topLeftY: 200, width: 10, height: 10)
        assertEquals(rectsIntersectionArea(a, b), 2500)
        assertEquals(rectsIntersectionArea(a, noOverlap), 0)
    }
}
