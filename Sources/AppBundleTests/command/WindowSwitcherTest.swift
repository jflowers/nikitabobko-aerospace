@testable import AppBundle
import Common
import XCTest

@MainActor
final class WindowSwitcherTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    override func tearDown() async throws {
        WindowSwitcherController.shared.cancel()
    }

    func testParseGui() {
        var expected = FocusCmdArgs(rawArgs: [], cardinalOrDfsDirection: .dfsRelative(.dfsNext))
        expected.gui = true
        testParseSingleCommandSucc("focus dfs-next --gui", expected)

        assertEquals(parseCommand("focus left --gui").errorOrNil, "--gui is compatible only with (dfs-next|dfs-prev)")
        assertEquals(parseCommand("focus --window-id 42 --gui").errorOrNil, "--window-id is incompatible with other options")
        assertEquals(parseCommand("focus --dfs-index 1 --gui").errorOrNil, "--dfs-index is incompatible with other options")
        assertNil(parseCommand("focus --wrap-around dfs-next --gui").errorOrNil)
        assertNil(parseCommand("focus dfs-prev --gui").errorOrNil)
    }

    func testGuiPreviewAndCommit() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
            TestWindow.new(id: 3, parent: $0)
        }

        let controller = WindowSwitcherController.shared
        assertNil(controller.session)

        await parseCommand("focus dfs-next --gui").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 1)
        assertEquals(controller.session?.windows.map(\.windowId), [1, 2, 3] as [UInt32])
        assertEquals(controller.session?.selectedIndex, 1)

        await parseCommand("focus dfs-next --gui").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 1)
        assertEquals(controller.session?.selectedIndex, 2)
        assertNil(TestApp.shared.focusedWindow)

        controller.commit()
        assertEquals(focus.windowOrNil?.windowId, 3)
        assertEquals(TestApp.shared.focusedWindow?.windowId, 3)
        assertNil(controller.session)
    }

    func testGuiCancel() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }

        let controller = WindowSwitcherController.shared

        await parseCommand("focus dfs-next --gui").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(controller.session?.selectedIndex, 1)
        assertEquals(focus.windowOrNil?.windowId, 1)

        controller.cancel()
        assertEquals(focus.windowOrNil?.windowId, 1)
        assertNil(TestApp.shared.focusedWindow)
        assertNil(controller.session)
    }

    func testGuiBoundaries() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }

        let controller = WindowSwitcherController.shared

        await parseCommand("focus dfs-prev --gui").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(controller.session?.selectedIndex, 0)
        controller.cancel()

        await parseCommand("focus --boundaries-action fail dfs-prev --gui").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(controller.session?.selectedIndex, 0)
        controller.cancel()

        await parseCommand("focus --wrap-around dfs-prev --gui").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(controller.session?.selectedIndex, 1)
        controller.commit()
        assertEquals(focus.windowOrNil?.windowId, 2)
        assertEquals(TestApp.shared.focusedWindow?.windowId, 2)
    }

    func testGuiDropsClosedWindows() async {
        var closedWindow: TestWindow?
        Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            closedWindow = TestWindow.new(id: 2, parent: $0)
            TestWindow.new(id: 3, parent: $0)
        }

        let controller = WindowSwitcherController.shared

        await parseCommand("focus dfs-next --gui").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(controller.session?.selectedIndex, 1)

        closedWindow?.closeAxWindow()

        await parseCommand("focus dfs-next --gui").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(controller.session?.windows.map(\.windowId), [1, 3] as [UInt32])
        assertEquals(controller.session?.selectedIndex, 1)

        controller.commit()
        assertEquals(focus.windowOrNil?.windowId, 3)
        assertEquals(TestApp.shared.focusedWindow?.windowId, 3)
    }

    func testGuiOverFloatingWindows() async {
        let workspace = Workspace.get(byName: name)
        workspace.floatingWindowsContainer.apply {
            TestWindow.new(id: 1, parent: $0, rect: Rect(topLeftX: 0, topLeftY: 0, width: 100, height: 100))
            TestWindow.new(id: 2, parent: $0, rect: Rect(topLeftX: 10, topLeftY: 10, width: 100, height: 100))
            TestWindow.new(id: 3, parent: $0, rect: Rect(topLeftX: 20, topLeftY: 20, width: 100, height: 100))
            assertEquals(
                TestWindow.new(id: 4, parent: $0, rect: Rect(topLeftX: 30, topLeftY: 30, width: 100, height: 100)).focusWindow(),
                true,
            )
        }

        let controller = WindowSwitcherController.shared

        await parseCommand("focus --wrap-around dfs-next --gui").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 4)
        assertEquals(controller.session?.windows.map(\.windowId), [1, 2, 3, 4] as [UInt32])
        assertEquals(controller.session?.selectedIndex, 0)

        await parseCommand("focus --wrap-around dfs-next --gui").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 4)
        assertEquals(controller.session?.selectedIndex, 1)

        controller.commit()
        assertEquals(focus.windowOrNil?.windowId, 2)
        assertEquals(TestApp.shared.focusedWindow?.windowId, 2)
        assertEquals(workspace.floatingWindows.count, 4)
        assertEquals(workspace.rootTilingContainer.allLeafWindowsRecursive.count, 0)
    }

    func testGuiReopensOnWorkspaceChange() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }

        let controller = WindowSwitcherController.shared

        await parseCommand("focus dfs-next --gui").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(controller.session?.windows.map(\.windowId), [1, 2] as [UInt32])
        assertEquals(controller.session?.selectedIndex, 1)

        let otherWorkspace = Workspace.get(byName: "\(name)-other")
        otherWorkspace.rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 11, parent: $0).focusWindow(), true)
            TestWindow.new(id: 12, parent: $0)
        }

        await parseCommand("focus dfs-next --gui").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 11)
        assertEquals(controller.session?.windows.map(\.windowId), [11, 12] as [UInt32])
        assertEquals(controller.session?.selectedIndex, 1)

        controller.cancel()
        assertEquals(focus.windowOrNil?.windowId, 11)
    }

    func testGuiArrowKeysMoveSelection() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
            TestWindow.new(id: 3, parent: $0)
        }

        let controller = WindowSwitcherController.shared
        await parseCommand("focus dfs-next --gui").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(controller.session?.selectedIndex, 1)

        controller.moveSelection(by: 1)
        assertEquals(controller.session?.selectedIndex, 2)
        assertEquals(focus.windowOrNil?.windowId, 1) // focus is never changed during the preview

        controller.moveSelection(by: 1)
        assertEquals(controller.session?.selectedIndex, 0) // wraps around

        controller.moveSelection(by: -1)
        assertEquals(controller.session?.selectedIndex, 2) // wraps around backward

        controller.commit()
        assertEquals(focus.windowOrNil?.windowId, 3)
        assertEquals(TestApp.shared.focusedWindow?.windowId, 3)
    }

    func testGuiCommitSelection() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
            TestWindow.new(id: 3, parent: $0)
        }

        let controller = WindowSwitcherController.shared
        await parseCommand("focus dfs-next --gui").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(controller.session?.selectedIndex, 1)

        controller.commitSelection(at: 2)
        assertEquals(focus.windowOrNil?.windowId, 3)
        assertEquals(TestApp.shared.focusedWindow?.windowId, 3)
        assertNil(controller.session)

        // Invalid index is ignored without ending the session
        await parseCommand("focus dfs-prev --gui").cmdOrDie.run(.defaultEnv, .emptyStdin)
        controller.commitSelection(at: 42)
        assertNotNil(controller.session)
        assertEquals(controller.session?.selectedIndex, 1)
        controller.cancel()
    }
}
