import XCTest

final class ReleaseCompatibilityTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testReleaseProjectPinsUniversalArchitecturesAndCleanLayout() throws {
        let project = try String(contentsOf: repositoryRoot.appendingPathComponent("project.yml"), encoding: .utf8)
        XCTAssertTrue(project.contains("ARCHS: \"arm64 x86_64\""), "project.yml must pin Universal architectures")
        XCTAssertTrue(project.contains("- Sources"))
        XCTAssertTrue(project.contains("- Tests"))
    }

    func testInstallScriptChecksUniversalArchitectures() throws {
        let script = try String(contentsOf: repositoryRoot.appendingPathComponent("scripts/install.sh"), encoding: .utf8)
        XCTAssertTrue(script.contains("lipo -archs"), "install.sh must verify installed app architectures")
        XCTAssertTrue(script.contains("x86_64"), "install.sh must reject a non-Universal app")
    }

    func testReadmeAndLicenseAreCleanAndProperlyAttributed() throws {
        let readme = try String(contentsOf: repositoryRoot.appendingPathComponent("README.md"), encoding: .utf8)
        XCTAssertFalse(readme.contains("codesign -s -"))
        XCTAssertTrue(readme.contains("Ghostty"))
        XCTAssertTrue(readme.contains("Mitchell Hashimoto"))

        let license = try String(contentsOf: repositoryRoot.appendingPathComponent("LICENSE"), encoding: .utf8)
        XCTAssertTrue(license.contains("Ghostty"))
        XCTAssertTrue(license.contains("Mitchell Hashimoto"))
    }

    func testNoLegacyDirectoriesOrCommittedDmg() throws {
        let entries = try FileManager.default.contentsOfDirectory(atPath: repositoryRoot.path)
        XCTAssertFalse(entries.contains("Siqi.dmg"))
        XCTAssertFalse(entries.contains("siqi"))
        XCTAssertFalse(entries.contains("tests"))
        XCTAssertTrue(entries.contains("Sources"))
        XCTAssertTrue(entries.contains("Tests"))
    }
}
