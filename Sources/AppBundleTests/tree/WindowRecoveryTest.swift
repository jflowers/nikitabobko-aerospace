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
}
