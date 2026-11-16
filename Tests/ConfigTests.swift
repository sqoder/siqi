import AppKit
import XCTest
@testable import siqi

final class ConfigTests: XCTestCase {
    func testDefaultBackgroundOverrideIsNil() {
        let config = SiqiUserConfig()
        XCTAssertNil(config.background)
        XCTAssertEqual(config.windowCornerRadius, 16.0)
    }

    func testCustomWindowCornerRadiusAndCommaSeparatedPadding() {
        let text = """
        window-corner-radius = 22
        window-padding-x = 16,16
        window-padding-y = 10,10
        """
        let (config, _) = SiqiUserConfig.load(from: text)
        XCTAssertEqual(config.windowCornerRadius, 22.0)
        XCTAssertEqual(config.windowPaddingX, 16)
        XCTAssertEqual(config.windowPaddingY, 10)
    }

    func testGhosttyCompatibleContentStripsSiqiOnlyKeys() {
        let raw = """
        # Comment preserved
        theme = Dracula
        window-corner-radius = 16
        restore-last-working-directory = true
        ai-tools = claude,codex
        ai-tool = gemini
        initial-working-directory = /tmp
        font-size = 14
        """
        let sanitized = SiqiUserConfig.ghosttyCompatibleContent(from: raw)
        XCTAssertTrue(sanitized.contains("# Comment preserved"))
        XCTAssertTrue(sanitized.contains("theme = Dracula"))
        XCTAssertTrue(sanitized.contains("font-size = 14"))
        XCTAssertFalse(sanitized.contains("window-corner-radius"))
        XCTAssertFalse(sanitized.contains("restore-last-working-directory"))
        XCTAssertFalse(sanitized.contains("ai-tools"))
        XCTAssertFalse(sanitized.contains("ai-tool"))
        XCTAssertFalse(sanitized.contains("initial-working-directory"))
    }

    func testSaveValuesUpdatesAndDeletesKeysWithoutTouchingExternalConfig() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("siqi-config-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let configURL = tempDir.appendingPathComponent("config")
        try """
        theme = Catppuccin Mocha
        background = 112233
        font-size = 13
        """.write(to: configURL, atomically: true, encoding: .utf8)

        SiqiConfigStore.saveValues([
            "theme": "Monokai Pro",
            "background": nil,
            "font-family": "JetBrains Mono",
        ], at: configURL)

        let updated = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertTrue(updated.contains("theme = Monokai Pro"))
        XCTAssertTrue(updated.contains("font-family = JetBrains Mono"))
        XCTAssertFalse(updated.contains("background ="))
        XCTAssertTrue(updated.contains("font-size = 13"))
    }

    func testThemeHexParsingShortAndAlpha() {
        let shortColor = NSColor(hex: "#fff")
        XCTAssertEqual(shortColor.redComponent, 1.0, accuracy: 0.01)
        XCTAssertEqual(shortColor.greenComponent, 1.0, accuracy: 0.01)
        XCTAssertEqual(shortColor.blueComponent, 1.0, accuracy: 0.01)

        let alphaColor = NSColor(hex: "#ffffff80")
        XCTAssertEqual(alphaColor.alphaComponent, 128.0 / 255.0, accuracy: 0.01)
    }

    func testReadOnlyFallbackDoesNotMutateFallbackFile() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("siqi-fallback-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let siqiConfigURL = tempDir.appendingPathComponent("siqi-config")
        let ghosttyFallbackURL = tempDir.appendingPathComponent("ghostty-config")
        let originalGhostty = """
        background = #30333E
        background-opacity = 0.82
        background-blur = 20
        """
        try originalGhostty.write(to: ghosttyFallbackURL, atomically: true, encoding: .utf8)

        let loaded = SiqiConfigStore.load(from: siqiConfigURL, fallbackURL: ghosttyFallbackURL)
        XCTAssertEqual(loaded.filePath, ghosttyFallbackURL.path)
        XCTAssertEqual(loaded.config.background, "30333E")
        XCTAssertEqual(loaded.config.backgroundOpacity, 0.82, accuracy: 0.001)
        XCTAssertEqual(loaded.config.backgroundBlur, 20)

        SiqiConfigStore.saveValues(["font-size": "15"], at: siqiConfigURL)
        let ghosttyAfterSave = try String(contentsOf: ghosttyFallbackURL, encoding: .utf8)
        XCTAssertEqual(ghosttyAfterSave, originalGhostty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: siqiConfigURL.path))
    }

    func testDefaultRestoreLastWorkingDirectoryIsTrueAndPersists() throws {
        let config = SiqiUserConfig()
        XCTAssertTrue(config.restoreLastWorkingDirectory)

        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("siqi-dir-restore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let suiteName = "siqi.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        DirectoryStore.saveLastWorkingDirectory(tempDir.path, defaults: defaults)
        let resolved = DirectoryStore.resolvedInitialWorkingDirectory(defaults: defaults)
        XCTAssertEqual(resolved, tempDir.path)
    }

    func testRestoredDirectoryValidation() {
        XCTAssertEqual(SiqiWindowStateStore.usableDirectory("/definitely/not/here"), NSHomeDirectory())
        XCTAssertEqual(SiqiWindowStateStore.usableDirectory("/etc/hosts"), NSHomeDirectory())
        XCTAssertEqual(SiqiWindowStateStore.usableDirectory("/tmp"), "/tmp")
    }
}
