import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var sigtermSource: DispatchSourceSignal?

    public func applicationWillFinishLaunching(_ notification: Notification) {
        for key in ProcessInfo.processInfo.environment.keys {
            if key.hasPrefix("HERDR_") || key == "TMUX" || key == "STY" || key == "WINDOW" {
                unsetenv(key)
            }
        }
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        _ = ConfigFileWatcher.shared
        _ = QuickTerminalController.shared
        DirectoryStore.prunePasteCache()
        setupSigtermHandler()

        if !SiqiWindowManager.shared.restoreWindowsFromState() {
            _ = SiqiWindowManager.shared.createWindow()
        }
    }

    private func setupSigtermHandler() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            SiqiWindowManager.shared.saveWindowState()
            exit(0)
        }
        source.resume()
        sigtermSource = source
    }

    public func applicationWillTerminate(_ notification: Notification) {
        SiqiWindowManager.shared.saveWindowState()
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let (config, _) = SiqiUserConfig.load()
        let running = SiqiWindowManager.shared.runningProcessNames
        guard SiqiWindowModel.needsCloseConfirmation(config: config, runningProcessNames: running) else {
            return .terminateNow
        }
        let alert = NSAlert()
        alert.messageText = "Quit siqi with running processes?"
        alert.informativeText = "Quitting will terminate: \(running.joined(separator: ", "))."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag || SiqiWindowManager.shared.windowControllers.isEmpty {
            _ = SiqiWindowManager.shared.createWindow()
        } else if let first = SiqiWindowManager.shared.windowControllers.first {
            first.showWindow()
        }
        return true
    }

    public func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    // MARK: - Dock Menu

    public func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()

        let newWindowItem = NSMenuItem(title: "New Window", action: #selector(dockNewWindow), keyEquivalent: "")
        newWindowItem.target = self
        menu.addItem(newWindowItem)

        let newTabItem = NSMenuItem(title: "New Tab", action: #selector(dockNewTab), keyEquivalent: "")
        newTabItem.target = self
        menu.addItem(newTabItem)

        menu.addItem(.separator())

        let quickTermItem = NSMenuItem(title: "Toggle Quick Terminal", action: #selector(dockToggleQuickTerminal), keyEquivalent: "")
        quickTermItem.target = self
        menu.addItem(quickTermItem)

        return menu
    }

    @objc private func dockNewWindow() { SiqiWindowManager.shared.createWindow() }
    @objc private func dockNewTab() { SiqiWindowManager.shared.activeWindowController?.model.createNewTab() }
    @objc private func dockToggleQuickTerminal() { QuickTerminalController.shared.toggle() }

    // MARK: - Finder Services

    @objc public func openInSiqi(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let urls = pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard let url = urls.first else {
            error.pointee = "No file provided" as NSString
            return
        }
        var isDirectory: ObjCBool = false
        let path = url.path
        let directory = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
            ? path
            : url.deletingLastPathComponent().path
        SiqiWindowManager.shared.createWindow(workingDirectory: directory)
    }
}
