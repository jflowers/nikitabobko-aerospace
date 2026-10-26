@testable import AppBundle
import Common
import XCTest

@MainActor
final class WorkspacePickerTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    override func tearDown() async throws {
        WorkspacePickerController.shared.cancel()
    }

    func testParseGui() {
        var expected = MoveNodeToWorkspaceCmdArgs(rawArgs: [])
        expected.gui = true
        testParseSingleCommandSucc("move-node-to-workspace --gui", expected)

        var expectedFocusFollows = MoveNodeToWorkspaceCmdArgs(rawArgs: [])
        expectedFocusFollows.gui = true
        expectedFocusFollows.focusFollowsWindow = true
        testParseSingleCommandSucc("move-node-to-workspace --focus-follows-window --gui", expectedFocusFollows)

        assertEquals(parseCommand("move-node-to-workspace").errorOrNil, "Either --gui or (<workspace-name>|next|prev) argument is required")
        assertEquals(parseCommand("move-node-to-workspace --gui foo").errorOrNil, "--gui is incompatible with (<workspace-name>|next|prev)")
        assertEquals(parseCommand("move-node-to-workspace --gui next").errorOrNil, "--gui is incompatible with (<workspace-name>|next|prev)")
        assertEquals(parseCommand("move-node-to-workspace --wrap-around --gui").errorOrNil, "--wrapAround requires using (prev|next) argument")
        assertEquals(parseCommand("move-node-to-workspace --stdin --gui").errorOrNil, "--stdin and --no-stdin require using (next|prev) argument")
        assertNil(parseCommand("move-node-to-workspace --fail-if-noop --gui").errorOrNil)
        assertNil(parseCommand("move-node-to-workspace --window-id 42 --gui").errorOrNil)
    }

    func testGuiPreviewAndCommit() async {
        let workspaceA = Workspace.get(byName: name)
        workspaceA.rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
        }
        let workspaceB = Workspace.get(byName: "wsB")
        workspaceB.rootTilingContainer.apply {
            TestWindow.new(id: 2, parent: $0)
        }

        let controller = WorkspacePickerController.shared
        assertNil(controller.session)

        await parseCommand("move-node-to-workspace --gui").cmdOrDie.run(.defaultEnv, .emptyStdin)
        // The picker lists all the workspaces, including the one created by setUpWorkspacesForTests()
        assertEquals(controller.session?.workspaces.map(\.name), [name, "setUpWorkspacesForTests", "wsB"])
        assertEquals(controller.session?.selectedIndex, 0) // the selection starts on the workspace of the window in question
        assertEquals(focus.windowOrNil?.windowId, 1) // focus is never changed during the preview

        // Re-triggering the command while the session is open is a no-op
        await parseCommand("move-node-to-workspace --gui").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(controller.session?.selectedIndex, 0)

        let wsBIndex = controller.session!.workspaces.firstIndex { $0.name == "wsB" }!
        controller.moveSelection(by: wsBIndex)
        assertEquals(controller.session?.selectedIndex, wsBIndex)
        assertEquals(focus.windowOrNil?.windowId, 1) // still no focus change during the preview

        controller.commit()
        assertEquals(workspaceA.rootTilingContainer.allLeafWindowsRecursive.count, 0)
        assertEquals(workspaceB.rootTilingContainer.allLeafWindowsRecursive.map(\.windowId).sorted(), [1, 2])
        assertEquals(focus.workspace.name, name) // focus stays on the source workspace without --focus-follows-window
        assertNil(controller.session)
    }

    func testGuiCancel() async {
        let workspaceA = Workspace.get(byName: name)
        workspaceA.rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
        }
        Workspace.get(byName: "wsB").rootTilingContainer.apply {
            TestWindow.new(id: 2, parent: $0)
        }

        let controller = WorkspacePickerController.shared
        await parseCommand("move-node-to-workspace --gui").cmdOrDie.run(.defaultEnv, .emptyStdin)
        controller.moveSelection(by: 1)
        assertEquals(controller.session?.selectedIndex, 1)

        controller.cancel()
        assertNil(controller.session)
        assertEquals(workspaceA.rootTilingContainer.allLeafWindowsRecursive.map(\.windowId), [1]) // the window stays
        assertEquals(focus.windowOrNil?.windowId, 1)
    }

    func testGuiArrowKeysMoveSelection() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
        }
        Workspace.get(byName: "wsA").rootTilingContainer.apply {
            TestWindow.new(id: 2, parent: $0)
        }
        Workspace.get(byName: "wsB").rootTilingContainer.apply {
            TestWindow.new(id: 3, parent: $0)
        }

        let controller = WorkspacePickerController.shared
        await parseCommand("move-node-to-workspace --gui").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(controller.session?.selectedIndex, 0)
        assertEquals(controller.session?.workspaces.map(\.name), [name, "setUpWorkspacesForTests", "wsA", "wsB"])

        controller.moveSelection(by: 1)
        assertEquals(controller.session?.selectedIndex, 1)
        assertEquals(focus.windowOrNil?.windowId, 1) // focus is never changed during the preview

        controller.moveSelection(by: 1)
        assertEquals(controller.session?.selectedIndex, 2)

        controller.moveSelection(by: 1)
        assertEquals(controller.session?.selectedIndex, 3) // the last workspace

        controller.moveSelection(by: 1)
        assertEquals(controller.session?.selectedIndex, 0) // wraps around

        controller.moveSelection(by: -1)
        assertEquals(controller.session?.selectedIndex, 3) // wraps around backward

        let wsAIndex = controller.session!.workspaces.firstIndex { $0.name == "wsA" }!
        controller.commitSelection(at: wsAIndex)
        assertEquals(Workspace.get(byName: "wsA").rootTilingContainer.allLeafWindowsRecursive.map(\.windowId).sorted(), [1, 2])
        assertNil(controller.session)
    }

    func testGuiCommitSelection() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
        }
        Workspace.get(byName: "wsA").rootTilingContainer.apply {
            TestWindow.new(id: 2, parent: $0)
        }

        let controller = WorkspacePickerController.shared
        await parseCommand("move-node-to-workspace --gui").cmdOrDie.run(.defaultEnv, .emptyStdin)

        let wsAIndex = controller.session!.workspaces.firstIndex { $0.name == "wsA" }!
        controller.commitSelection(at: wsAIndex)
        assertEquals(Workspace.get(byName: "wsA").rootTilingContainer.allLeafWindowsRecursive.map(\.windowId).sorted(), [1, 2])
        assertNil(controller.session)

        // Invalid index is ignored without ending the session
        _ = TestWindow.new(id: 3, parent: Workspace.get(byName: name).rootTilingContainer).focusWindow()
        await parseCommand("move-node-to-workspace --gui").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertNotNil(controller.session)
        controller.commitSelection(at: 42)
        assertNotNil(controller.session)
        controller.cancel()
    }

    func testGuiCommitWithClosedWindow() async {
        var closedWindow: TestWindow?
        Workspace.get(byName: name).rootTilingContainer.apply {
            closedWindow = TestWindow.new(id: 1, parent: $0)
            _ = closedWindow?.focusWindow()
        }
        Workspace.get(byName: "wsB").rootTilingContainer.apply {
            TestWindow.new(id: 2, parent: $0)
        }

        let controller = WorkspacePickerController.shared
        await parseCommand("move-node-to-workspace --gui").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertNotNil(controller.session)
        controller.moveSelection(by: 1)

        closedWindow?.closeAxWindow()
        controller.commit()

        assertNil(controller.session) // the session still ends
        assertEquals(Workspace.get(byName: "wsB").rootTilingContainer.allLeafWindowsRecursive.map(\.windowId), [2]) // nothing moved
    }

    func testGuiFocusFollowsWindow() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
        }
        Workspace.get(byName: "wsB").rootTilingContainer.apply {
            TestWindow.new(id: 2, parent: $0)
        }

        let controller = WorkspacePickerController.shared
        await parseCommand("move-node-to-workspace --focus-follows-window --gui").cmdOrDie.run(.defaultEnv, .emptyStdin)
        let wsBIndex = controller.session!.workspaces.firstIndex { $0.name == "wsB" }!
        controller.moveSelection(by: wsBIndex)
        controller.commit()

        assertEquals(Workspace.get(byName: "wsB").rootTilingContainer.allLeafWindowsRecursive.map(\.windowId).sorted(), [1, 2])
        assertEquals(focus.windowOrNil?.windowId, 1)
        assertEquals(focus.workspace.name, "wsB")
    }

    func testGuiWindowId() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            _ = TestWindow.new(id: 2, parent: $0).focusWindow()
        }
        Workspace.get(byName: "wsB").rootTilingContainer.apply {
            TestWindow.new(id: 3, parent: $0)
        }

        let controller = WorkspacePickerController.shared
        await parseCommand("move-node-to-workspace --window-id 1 --gui").cmdOrDie.run(.defaultEnv, .emptyStdin)
        // The selection starts on the workspace of the target window, not on the workspace of the focused window
        assertEquals(controller.session?.selectedIndex, 0)

        let wsBIndex = controller.session!.workspaces.firstIndex { $0.name == "wsB" }!
        controller.moveSelection(by: wsBIndex)
        controller.commit()
        assertEquals(Workspace.get(byName: "wsB").rootTilingContainer.allLeafWindowsRecursive.map(\.windowId).sorted(), [1, 3])
        assertEquals(focus.windowOrNil?.windowId, 2) // focus is untouched
    }

    func testParseWorkspaceGui() {
        var expected = WorkspaceCmdArgs(target: .relative(.next), wrapAround: true)
        expected.gui = true
        testParseSingleCommandSucc("workspace --wrap-around --gui next", expected)

        assertEquals(parseCommand("workspace --gui foo").errorOrNil, "--gui requires using (next|prev) argument")
        assertNil(parseCommand("workspace --stdin --gui --wrap-around prev").errorOrNil)
    }

    func testWorkspaceGuiCyclePreviewAndCommit() async {
        let workspaceA = Workspace.get(byName: name)
        workspaceA.rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
        }
        Workspace.get(byName: "wsA").rootTilingContainer.apply {
            TestWindow.new(id: 2, parent: $0)
        }
        Workspace.get(byName: "wsB").rootTilingContainer.apply {
            TestWindow.new(id: 3, parent: $0)
        }
        // A window in every workspace so that `garbageCollectUnusedWorkspaces()` (which runs after every command)
        // doesn't shrink the list between the invocations
        Workspace.get(byName: "setUpWorkspacesForTests").rootTilingContainer.apply {
            TestWindow.new(id: 4, parent: $0)
        }

        let controller = WorkspacePickerController.shared
        assertNil(controller.session)

        let code = await parseCommand("workspace --gui next").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(code.exitCode.rawValue, 0)
        // The list is all the workspaces on the focused monitor (including the one created by setUpWorkspacesForTests)
        assertEquals(controller.session?.workspaces.map(\.name), [name, "setUpWorkspacesForTests", "wsA", "wsB"])
        assertEquals(controller.session?.selectedIndex, 1) // the selection starts on the focused workspace and advances
        assertEquals(focus.workspace.name, name) // focus is never changed during the preview

        // Every invocation advances the selection
        await parseCommand("workspace --gui next").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(controller.session?.selectedIndex, 2)
        assertEquals(focus.workspace.name, name)

        controller.commit()
        assertEquals(focus.workspace.name, "wsA")
        assertNil(controller.session)
    }

    func testWorkspaceGuiCycleWrapAroundAndBoundaries() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
        }
        // A window in every workspace so that `garbageCollectUnusedWorkspaces()` (which runs after every command)
        // doesn't shrink the list between the invocations
        Workspace.get(byName: "setUpWorkspacesForTests").rootTilingContainer.apply {
            TestWindow.new(id: 2, parent: $0)
        }
        Workspace.get(byName: "wsA").rootTilingContainer.apply {
            TestWindow.new(id: 3, parent: $0)
        }
        Workspace.get(byName: "wsB").rootTilingContainer.apply {
            TestWindow.new(id: 4, parent: $0)
        }

        let controller = WorkspacePickerController.shared

        // prev from the first workspace wraps around to the last one
        await parseCommand("workspace --gui --wrap-around prev").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(controller.session?.workspaces.map(\.name), [name, "setUpWorkspacesForTests", "wsA", "wsB"])
        assertEquals(controller.session?.selectedIndex, 3)
        controller.cancel()

        // Without --wrap-around the cycling stops at the boundaries of the list
        await parseCommand("workspace --gui next").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(controller.session?.selectedIndex, 1)
        await parseCommand("workspace --gui next").cmdOrDie.run(.defaultEnv, .emptyStdin)
        await parseCommand("workspace --gui next").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(controller.session?.selectedIndex, 3) // the last workspace
        await parseCommand("workspace --gui next").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(controller.session?.selectedIndex, 3) // clamped

        controller.cancel()
        assertEquals(focus.workspace.name, name) // cancel keeps the current workspace focused
        assertNil(controller.session)
    }

    func testWorkspaceGuiCycleWithStdin() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
        }

        let controller = WorkspacePickerController.shared

        // The list is taken from stdin; the focused workspace isn't in the list, so the selection starts at index 0
        await parseCommand("workspace --stdin --gui --wrap-around next").cmdOrDie.run(.defaultEnv, CmdStdin("a\nb\nc\n"))
        assertEquals(controller.session?.workspaces.map(\.name), ["a", "b", "c"])
        assertEquals(controller.session?.selectedIndex, 1)

        controller.commit()
        assertEquals(focus.workspace.name, "b")
        assertNil(controller.session)
    }

    func testWorkspaceGuiEmptyListFallsBackToImmediateBehavior() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
        }

        let controller = WorkspacePickerController.shared
        let code = await parseCommand("workspace --stdin --gui next").cmdOrDie.run(.defaultEnv, CmdStdin(""))
        assertNotEquals(code.exitCode.rawValue, 0)
        assertNil(controller.session)
    }
}
