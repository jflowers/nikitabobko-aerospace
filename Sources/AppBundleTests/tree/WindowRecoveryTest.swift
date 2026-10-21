@testable import AppBundle
import Common
import XCTest

@MainActor
final class WindowRecoveryTest: XCTestCase {
    private var fileUrl: URL!

    override func setUp() async throws {
        setUpWorkspacesForTests()
        fileUrl = FileManager.default.temporaryDirectory
            .appending(component: "window-recovery-test-\(UUID().uuidString)")
            .appending(component: "window-recovery.json")
        try FileManager.default.createDirectory(at: fileUrl.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: fileUrl.deletingLastPathComponent())
        fileUrl = nil
    }

    private func buildWorld() -> FrozenWorld {
        let ws1 = Workspace.get(byName: "wr1")
        let ws2 = Workspace.get(byName: "wr2")
        ws1.rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                TestWindow.new(id: 2, parent: $0)
            }
        }
        TestWindow.new(id: 3, parent: ws1.floatingWindowsContainer)
        TestWindow.new(id: 4, parent: ws2.rootTilingContainer)
        return snapshotFrozenWorld()
    }

    func testSaveAndLoadRoundTrip() {
        let world = buildWorld()
        assertEquals(world.windowIds, [1, 2, 3, 4].toSet())
        assertEquals(world.workspaces.count, 3) // setUpWorkspacesForTests workspace + wr1 + wr2
        try? FileManager.default.removeItem(at: fileUrl.deletingLastPathComponent()) // save must create the directory itself
        saveWindowRecoveryState(to: fileUrl)
        assertEquals(loadWindowRecoveryState(from: fileUrl), world)
    }

    func testSaveOverwritesPreviousState() {
        let world = buildWorld()
        saveWindowRecoveryState(to: fileUrl)
        assertEquals(loadWindowRecoveryState(from: fileUrl), world)

        TestWindow.new(id: 5, parent: Workspace.get(byName: "wr2").rootTilingContainer)
        saveWindowRecoveryState(to: fileUrl)
        assertEquals(loadWindowRecoveryState(from: fileUrl)?.windowIds, [1, 2, 3, 4, 5].toSet())
    }

    func testLoadMissingFile() {
        assertNil(loadWindowRecoveryState(from: fileUrl))
    }

    func testLoadCorruptedFile() {
        try! "not a json".write(to: fileUrl, atomically: true, encoding: .utf8)
        assertNil(loadWindowRecoveryState(from: fileUrl))
    }

    func testLoadUnsupportedVersion() {
        let json = #"{"version": 999, "world": {"workspaces": [], "monitors": [], "windowIds": []}}"#
        try! json.write(to: fileUrl, atomically: true, encoding: .utf8)
        assertNil(loadWindowRecoveryState(from: fileUrl))
    }

    func testCodableRoundTripOfFrozenWorld() {
        let world = buildWorld()
        let data = try! JSONEncoder().encode(WindowRecoveryState(version: WindowRecoveryState.currentVersion, world: world))
        let decoded = try! JSONDecoder().decode(WindowRecoveryState.self, from: data)
        assertEquals(decoded.world, world)
        assertEquals(decoded.version, WindowRecoveryState.currentVersion)
    }

    func testCodableRoundTripOfFrozenWindowWithFrame() {
        let ws1 = Workspace.get(byName: "wr1")
        let testWindow = TestWindow.new(id: 7, parent: ws1.floatingWindowsContainer)
        let frame = FrozenFrame(topLeftX: 5.5, topLeftY: 10.25, width: 100, height: 200)
        let frozenWindow = FrozenWindow(testWindow, frame: frame)
        let data = try! JSONEncoder().encode(frozenWindow)
        let decoded = try! JSONDecoder().decode(FrozenWindow.self, from: data)
        assertEquals(decoded, frozenWindow)
        assertEquals(decoded.frame, frame)
    }

    func testFrozenWindowDecodesLegacyJsonWithoutFrame() {
        let json = #"{"id": 42, "weight": 1.0}"#
        let decoded = try! JSONDecoder().decode(FrozenWindow.self, from: json.data(using: .utf8)!)
        assertEquals(decoded.id, 42)
        assertEquals(decoded.weight, 1)
        assertNil(decoded.frame)
        assertEquals(decoded.isSticky, false) // isSticky was added after frame; legacy files don't have it
    }

    func testCodableRoundTripOfFrozenWindowWithSticky() {
        let ws1 = Workspace.get(byName: "wr1")
        let testWindow = TestWindow.new(id: 8, parent: ws1.floatingWindowsContainer)
        testWindow.isSticky = true
        let frozenWindow = FrozenWindow(testWindow)
        assertEquals(frozenWindow.isSticky, true)
        let data = try! JSONEncoder().encode(frozenWindow)
        let decoded = try! JSONDecoder().decode(FrozenWindow.self, from: data)
        assertEquals(decoded, frozenWindow)
        assertEquals(decoded.isSticky, true)
    }

    func testSnapshotFrozenWorldAttachesFloatingFrames() {
        let ws1 = Workspace.get(byName: "wr1")
        let floating = TestWindow.new(id: 9, parent: ws1.floatingWindowsContainer)
        let frame = FrozenFrame(topLeftX: 1, topLeftY: 2, width: 3, height: 4)
        let world = snapshotFrozenWorld(floatingFrames: [floating.windowId: frame])
        let frozenWorkspace = world.workspaces.first { $0.name == "wr1" }!
        let frozenWindow = frozenWorkspace.floatingWindows.first { $0.id == floating.windowId }!
        assertEquals(frozenWindow.frame, frame)
    }
}
