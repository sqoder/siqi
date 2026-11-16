import XCTest
@testable import siqi

@MainActor
final class PaneAndTabTests: XCTestCase {
    func testClosingLastSessionReportsNoPanesRemaining() {
        let session = SiqiTerminalSession(workingDirectory: NSHomeDirectory())
        let tab = SiqiTab(session: session)
        XCTAssertFalse(tab.closeSession(id: session.id))
    }

    func testClosingOneOfTwoPanesKeepsTab() {
        let first = SiqiTerminalSession(workingDirectory: NSHomeDirectory())
        let tab = SiqiTab(session: first)
        let second = SiqiTerminalSession(workingDirectory: NSHomeDirectory())
        tab.splitActive(axis: .horizontal, newSession: second)
        XCTAssertTrue(tab.closeSession(id: second.id))
        XCTAssertEqual(tab.allSessions.map(\.id), [first.id])
        first.tearDown()
    }

    func testClosingUnknownSessionReportsWhatRemains() {
        let session = SiqiTerminalSession(workingDirectory: NSHomeDirectory())
        let tab = SiqiTab(session: session)
        XCTAssertTrue(tab.closeSession(id: UUID()))
        session.tearDown()
    }

    func testCloseOtherTabsKeepsOnlySelectedTab() {
        let model = SiqiWindowModel()
        _ = model.createNewTab()
        _ = model.createNewTab()
        XCTAssertEqual(model.tabs.count, 3)

        let targetId = model.tabs[1].id
        model.closeOtherTabs(keeping: targetId)

        XCTAssertEqual(model.tabs.count, 1)
        XCTAssertEqual(model.tabs.first?.id, targetId)
        XCTAssertEqual(model.activeTabId, targetId)
        model.tearDownAllSessions()
    }

    func testCloseConfirmationPolicy() {
        var config = SiqiUserConfig()
        config.confirmCloseSurface = true
        XCTAssertTrue(SiqiWindowModel.needsCloseConfirmation(config: config, runningProcessNames: ["sleep"]))
        XCTAssertFalse(SiqiWindowModel.needsCloseConfirmation(config: config, runningProcessNames: []))

        config.confirmCloseSurface = false
        XCTAssertFalse(SiqiWindowModel.needsCloseConfirmation(config: config, runningProcessNames: ["sleep"]))
    }

    func testPersistedStateSurvivesJSONRoundTrip() throws {
        let leaf = SiqiPersistedPane.leaf(cwd: "/tmp")
        let state = SiqiPersistedState(windows: [
            SiqiPersistedWindow(
                frame: [10, 20, 800, 500],
                activeTabIndex: 1,
                tabs: [
                    SiqiPersistedTab(activePaneIndex: 0, root: leaf),
                    SiqiPersistedTab(
                        activePaneIndex: 1,
                        root: .split(axis: "horizontal", fraction: 0.5, first: leaf, second: .leaf(cwd: "/Users"))
                    ),
                ]
            ),
        ])
        let data = try JSONEncoder().encode(state)
        XCTAssertEqual(try JSONDecoder().decode(SiqiPersistedState.self, from: data), state)
    }

    func testSessionPreservesLastKnownDirectoryAfterTearDown() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("siqi-session-dir-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let session = SiqiTerminalSession(workingDirectory: NSHomeDirectory())
        session.state.terminalDidChangeWorkingDirectory("file://localhost\(tempDir.path)")
        XCTAssertEqual(session.fullDirectory, tempDir.path)

        session.tearDown()
        XCTAssertEqual(session.fullDirectory, tempDir.path)
    }

    func testEnsureLiveSessionRecoversAfterTearDown() {
        let model = SiqiWindowModel()
        let deadId = model.activeSession?.id
        model.activeSession?.tearDown()
        XCTAssertTrue(model.activeSession?.isTornDown == true)

        model.ensureLiveSession()
        XCTAssertNotNil(model.activeSession)
        XCTAssertFalse(model.activeSession?.isTornDown == true)
        XCTAssertNotEqual(model.activeSession?.id, deadId)
        model.tearDownAllSessions()
    }
}
