import AppKit
import XCTest
@testable import siqi

@MainActor
final class KeybindingAndInputTests: XCTestCase {
    func testEscapedShellPathRoundTripsThroughSh() throws {
        let cases = [
            "/tmp/plain.png",
            "/tmp/with space.png",
            "/tmp/quote'.png",
            "/tmp/parens (1) [2].png",
            "/tmp/back\\slash.png",
            "/tmp/dollar$var.png",
        ]
        for path in cases {
            let escaped = TerminalActionBridge.escapedShellPath(path)
            XCTAssertEqual(try sh("printf %s \(escaped)"), path)
        }
    }

    func testKeybindingParser() {
        let binding = SiqiUserConfig.parseKeybinding("cmd+shift+e=new_tab")
        XCTAssertEqual(binding?.key, "e")
        XCTAssertEqual(binding?.modifiers, ["cmd", "shift"])
        XCTAssertEqual(binding?.action, "new_tab")
        XCTAssertNil(SiqiUserConfig.parseKeybinding("noaction"))
        XCTAssertNil(SiqiUserConfig.parseKeybinding("=new_tab"))
    }

    func testSettingsShortcutAndUserBindingPrecedence() {
        XCTAssertTrue(SiqiTerminalNSView.isSettingsShortcut(makeEvent(",", keyCode: 43, modifiers: .command)))
        XCTAssertTrue(SiqiTerminalNSView.isSettingsShortcut(makeEvent("，", keyCode: 43, modifiers: .command)))
        XCTAssertFalse(SiqiTerminalNSView.isSettingsShortcut(makeEvent("t", keyCode: 17, modifiers: .command)))
        XCTAssertFalse(SiqiTerminalNSView.isSettingsShortcut(makeEvent(",", keyCode: 43, modifiers: [.command, .shift])))

        let bindings = [SiqiUserConfig.parseKeybinding("super+comma=new_tab")!]
        XCTAssertTrue(TerminalActionBridge.hasUserBinding(for: makeEvent(",", keyCode: 43, modifiers: .command), in: bindings))
        XCTAssertTrue(TerminalActionBridge.hasUserBinding(for: makeEvent("，", keyCode: 43, modifiers: .command), in: bindings))
        XCTAssertFalse(TerminalActionBridge.hasUserBinding(for: makeEvent(",", keyCode: 43, modifiers: .command), in: []))
    }

    func testContextMenuHandoffPolicy() {
        XCTAssertTrue(SiqiTerminalNSView.handsOffContextMenu(control: true, processRunning: false))
        XCTAssertTrue(SiqiTerminalNSView.handsOffContextMenu(control: false, processRunning: true))
        XCTAssertFalse(SiqiTerminalNSView.handsOffContextMenu(control: false, processRunning: false))
    }

    func testTabDragHandleTrailingAreaHitTest() {
        let model = SiqiWindowModel()
        let tab = model.tabs[0]
        let handle = TabDragHandleView(tab: tab, model: model, onSelect: {}, onHover: { _ in })
        handle.frame = NSRect(x: 0, y: 0, width: 120, height: 24)

        handle.reservesTrailingCloseArea = false
        XCTAssertIdentical(handle.hitTest(NSPoint(x: 110, y: 12)), handle)

        handle.reservesTrailingCloseArea = true
        XCTAssertNil(handle.hitTest(NSPoint(x: 110, y: 12)))
        XCTAssertIdentical(handle.hitTest(NSPoint(x: 60, y: 12)), handle)

        model.tearDownAllSessions()
    }

    func testProcessInspectorFindsSpawnedChild() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["5"]
        try process.run()
        defer {
            process.terminate()
            process.waitUntilExit()
        }

        var foundSleep = false
        for _ in 0..<20 {
            let children = ProcessInspector.childPids(for: getpid())
            if children.contains(where: { ProcessInspector.processName(for: $0) == "sleep" }) {
                foundSleep = true
                break
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertTrue(foundSleep)
        XCTAssertNotNil(ProcessInspector.findLatestChildInfo()?.cwd)
    }

    private func makeEvent(_ characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 1,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )!
    }

    private func sh(_ script: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }
}
