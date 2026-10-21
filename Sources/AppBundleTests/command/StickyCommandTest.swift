@testable import AppBundle
import Common
import XCTest

@MainActor
final class StickyCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testStickyOnFloatingWindow() async {
        let ws = Workspace.get(byName: name)
        TestWindow.new(id: 1, parent: ws.floatingWindowsContainer)

        let result = await parseCommand("sticky --window-id 1 on").cmdOrDie.run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(Window.get(byId: 1)?.isSticky, true)
        assertEquals(Window.get(byId: 1)?.isFloating, true)
    }

    func testStickyToggle() async {
        let ws = Workspace.get(byName: name)
        TestWindow.new(id: 1, parent: ws.floatingWindowsContainer)

        await parseCommand("sticky --window-id 1").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(Window.get(byId: 1)?.isSticky, true)

        await parseCommand("sticky --window-id 1").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(Window.get(byId: 1)?.isSticky, false)
    }

    func testStickyOff() async {
        let ws = Workspace.get(byName: name)
        TestWindow.new(id: 1, parent: ws.floatingWindowsContainer)
        await parseCommand("sticky --window-id 1 on").cmdOrDie.run(.defaultEnv, .emptyStdin)

        let result = await parseCommand("sticky --window-id 1 off").cmdOrDie.run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(Window.get(byId: 1)?.isSticky, false)
    }

    func testTiledWindowAutoFloats() async {
        let ws = Workspace.get(byName: name)
        TestWindow.new(id: 1, parent: ws.rootTilingContainer)

        let result = await parseCommand("sticky --window-id 1 on").cmdOrDie.run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode.rawValue, 0)
        let window = Window.get(byId: 1)
        assertEquals(window?.isSticky, true)
        assertEquals(window?.isFloating, true)
    }

    func testNoop() async {
        let ws = Workspace.get(byName: name)
        TestWindow.new(id: 1, parent: ws.floatingWindowsContainer)
        await parseCommand("sticky --window-id 1 on").cmdOrDie.run(.defaultEnv, .emptyStdin)

        let succResult = await parseCommand("sticky --window-id 1 on").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(succResult.exitCode.rawValue, 0)
        assertEquals(succResult.stderr, ["Already sticky. Tip: use --fail-if-noop to exit with non-zero code"])

        let failResult = await parseCommand("sticky --fail-if-noop --window-id 1 on").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(failResult.exitCode.rawValue, 2)
        assertEquals(Window.get(byId: 1)?.isSticky, true)
    }

    func testNoWindowIsFocused() async {
        let result = await parseCommand("sticky").cmdOrDie.run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode.rawValue, 2)
        assertEquals(result.stderr, ["No window is focused"])
    }
}
