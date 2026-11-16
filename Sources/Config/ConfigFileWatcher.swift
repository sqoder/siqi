import Foundation

public extension Notification.Name {
    static let siqiConfigDidChange = Notification.Name("siqiConfigDidChange")
}

/// Watches ~/.config/siqi/config and its parent directory for modifications or atomic saves.
@MainActor
public final class ConfigFileWatcher {
    public static let shared = ConfigFileWatcher {
        SiqiConfigStore.invalidateCache()
        NotificationCenter.default.post(name: .siqiConfigDidChange, object: nil)
        SiqiWindowManager.shared.reloadAllWindows()
    }

    private let fileURL: URL
    private let onChange: @MainActor () -> Void

    private var fileSource: DispatchSourceFileSystemObject?
    private var dirSource: DispatchSourceFileSystemObject?
    private var debounceWorkItem: DispatchWorkItem?
    private var lastModificationDate: Date?

    public init(fileURL: URL = SiqiConfigStore.configFileURL, onChange: @escaping @MainActor () -> Void) {
        self.fileURL = fileURL
        self.onChange = onChange
        start()
    }

    deinit {
        fileSource?.cancel()
        dirSource?.cancel()
        debounceWorkItem?.cancel()
    }

    public func stop() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        fileSource?.cancel()
        fileSource = nil
        dirSource?.cancel()
        dirSource = nil
    }

    private func start() {
        watchParentDirectory()
        watchConfigFile()
    }

    private func watchParentDirectory() {
        let dirURL = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)

        let fd = open(dirURL.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .extend],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.handleDirectoryEvent()
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        dirSource = source
    }

    private func watchConfigFile() {
        fileSource?.cancel()
        fileSource = nil

        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        lastModificationDate = modificationDate()

        let fd = open(fileURL.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .attrib],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = source.data
            if flags.contains(.delete) || flags.contains(.rename) {
                self.watchConfigFile()
            }
            self.scheduleReload()
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        fileSource = source
    }

    private func handleDirectoryEvent() {
        if fileSource == nil && FileManager.default.fileExists(atPath: fileURL.path) {
            watchConfigFile()
            scheduleReload()
            return
        }
        let currentMod = modificationDate()
        if currentMod != lastModificationDate {
            lastModificationDate = currentMod
            watchConfigFile()
            scheduleReload()
        }
    }

    private func modificationDate() -> Date? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        return attrs?[.modificationDate] as? Date
    }

    private func scheduleReload() {
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.onChange()
            }
        }
        debounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
}
