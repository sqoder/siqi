import Foundation

/// Persists working directory state and prunes pasted image caches.
public enum DirectoryStore {
    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
    private static let lastDirKey = "siqi.lastWorkingDirectory"
    private static let testLastDirKey = "siqi.test.lastWorkingDirectory"
    private static var cacheDirectoryPath: String {
        if isRunningTests {
            return (NSTemporaryDirectory() as NSString).appendingPathComponent("siqi-test-cache")
        }
        return NSString(string: "~/.cache/siqi").expandingTildeInPath
    }
    private static var lastDirCacheFilePath: String {
        (cacheDirectoryPath as NSString).appendingPathComponent("last_working_directory")
    }
    public static var pasteCacheDirectoryPath: String {
        (cacheDirectoryPath as NSString).appendingPathComponent("pastes")
    }

    private static func resolvedLastDirKey(for defaults: UserDefaults) -> String {
        (isRunningTests && defaults === UserDefaults.standard) ? testLastDirKey : lastDirKey
    }

    public static func saveLastWorkingDirectory(_ path: String?, defaults: UserDefaults = .standard) {
        guard let path else { return }
        let expanded = NSString(string: path.trimmingCharacters(in: .whitespacesAndNewlines)).expandingTildeInPath
        guard !expanded.isEmpty, directoryExists(expanded) else { return }

        defaults.set(expanded, forKey: resolvedLastDirKey(for: defaults))
        try? FileManager.default.createDirectory(atPath: cacheDirectoryPath, withIntermediateDirectories: true)
        try? expanded.write(toFile: lastDirCacheFilePath, atomically: true, encoding: .utf8)
    }

    public static func resolvedInitialWorkingDirectory(
        explicit: String? = nil,
        defaults: UserDefaults = .standard
    ) -> String {
        if let explicit, !explicit.isEmpty {
            let expanded = NSString(string: explicit).expandingTildeInPath
            if directoryExists(expanded) {
                return expanded
            }
        }

        let (config, _) = SiqiUserConfig.load()
        if config.restoreLastWorkingDirectory {
            if let saved = defaults.string(forKey: resolvedLastDirKey(for: defaults)), !saved.isEmpty, directoryExists(saved) {
                return saved
            }
            if let fileSaved = try? String(contentsOfFile: lastDirCacheFilePath, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !fileSaved.isEmpty,
               directoryExists(fileSaved) {
                return fileSaved
            }
        }

        if let configuredDir = config.workingDirectory, !configuredDir.isEmpty {
            let expanded = NSString(string: configuredDir).expandingTildeInPath
            if directoryExists(expanded) {
                return expanded
            }
        }

        return NSHomeDirectory()
    }

    /// Asynchronously removes old or oversized PNG files from ~/.cache/siqi/pastes.
    public static func prunePasteCache(maxAgeDays: Int = 14, maxSizeBytes: UInt64 = 500 * 1024 * 1024) {
        let dir = pasteCacheDirectoryPath
        Task.detached(priority: .background) {
            let fm = FileManager.default
            guard let items = try? fm.contentsOfDirectory(atPath: dir) else { return }

            let cutoffDate = Date().addingTimeInterval(-Double(maxAgeDays * 86400))
            var remainingFiles: [(path: String, size: UInt64, mtime: Date)] = []

            for item in items where item.hasPrefix("paste_") && item.hasSuffix(".png") {
                let fullPath = (dir as NSString).appendingPathComponent(item)
                guard let attrs = try? fm.attributesOfItem(atPath: fullPath),
                      let mtime = attrs[.modificationDate] as? Date,
                      let size = attrs[.size] as? UInt64 else { continue }

                if mtime < cutoffDate {
                    try? fm.removeItem(atPath: fullPath)
                } else {
                    remainingFiles.append((fullPath, size, mtime))
                }
            }

            var totalSize = remainingFiles.reduce(0) { $0 + $1.size }
            if totalSize > maxSizeBytes {
                remainingFiles.sort { $0.mtime < $1.mtime }
                for file in remainingFiles {
                    try? fm.removeItem(atPath: file.path)
                    totalSize -= file.size
                    if totalSize <= maxSizeBytes { break }
                }
            }
        }
    }

    private static func directoryExists(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }
}
