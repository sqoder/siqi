import XCTest
@testable import siqi

final class TerminalLinkResolverTests: XCTestCase {
    func testResolvesHttpsAndWwwLinks() {
        XCTAssertEqual(
            TerminalLinkResolver.resolve("https://example.com/docs", workingDirectory: nil)?.absoluteString,
            "https://example.com/docs"
        )
        XCTAssertEqual(
            TerminalLinkResolver.resolve("www.example.com", workingDirectory: nil)?.absoluteString,
            "https://www.example.com"
        )
    }

    func testResolvesExistingRelativeAndAbsoluteFiles() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("siqi-link-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let file = tempDir.appendingPathComponent("notes.txt")
        try "hello".write(to: file, atomically: true, encoding: .utf8)

        let resolvedRel = TerminalLinkResolver.resolve("notes.txt", workingDirectory: tempDir.path)
        XCTAssertEqual(resolvedRel?.path, file.path)

        let resolvedAbs = TerminalLinkResolver.resolve(file.path, workingDirectory: nil)
        XCTAssertEqual(resolvedAbs?.path, file.path)
    }
}
