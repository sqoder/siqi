import Foundation

enum TerminalLinkResolver {
    static func resolve(_ raw: String, workingDirectory: String?) -> URL? {
        let target = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return nil }

        if let url = URL(string: target), let scheme = url.scheme?.lowercased() {
            if scheme == "file" {
                let path = url.path
                if FileManager.default.fileExists(atPath: path) {
                    return URL(fileURLWithPath: path)
                }
                if let decoded = path.removingPercentEncoding, FileManager.default.fileExists(atPath: decoded) {
                    return URL(fileURLWithPath: decoded)
                }
                return nil
            }
            return url
        }

        if target.lowercased().hasPrefix("www.") {
            return URL(string: "https://" + target)
        }

        let path: String
        if target.hasPrefix("/") {
            path = target
        } else if target.hasPrefix("~/") {
            path = NSString(string: target).expandingTildeInPath
        } else if let workingDirectory, !workingDirectory.isEmpty {
            path = URL(fileURLWithPath: workingDirectory).appendingPathComponent(target).path
        } else {
            return nil
        }

        if FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        if let workingDirectory, !workingDirectory.isEmpty, !target.hasPrefix("/") {
            for folder in ["docs", "docx", "doc", "src", "tests", "test"] {
                let candidatePath = URL(fileURLWithPath: workingDirectory)
                    .appendingPathComponent(folder)
                    .appendingPathComponent(target).path
                if FileManager.default.fileExists(atPath: candidatePath) {
                    return URL(fileURLWithPath: candidatePath)
                }
            }
        }

        return nil
    }

    static func resolveDisplayPath(_ raw: String, workingDirectory: String?) -> String {
        let target = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return "" }

        if let resolvedUrl = resolve(target, workingDirectory: workingDirectory) {
            return resolvedUrl.isFileURL ? resolvedUrl.path : resolvedUrl.absoluteString
        }

        if target.lowercased().hasPrefix("file://") {
            return URL(string: target)?.path ?? String(target.dropFirst("file://".count))
        }

        if target.lowercased().hasPrefix("http://") || target.lowercased().hasPrefix("https://") {
            return target
        }

        if target.hasPrefix("/") {
            return target
        } else if target.hasPrefix("~/") {
            return NSString(string: target).expandingTildeInPath
        } else if let workingDirectory, !workingDirectory.isEmpty {
            return URL(fileURLWithPath: workingDirectory).appendingPathComponent(target).path
        }

        return target
    }
}
