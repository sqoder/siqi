import AppKit
import GhosttyTerminal

@MainActor
public enum TerminalActionBridge {
    public static func findTerminalView(in view: NSView) -> SiqiTerminalNSView? {
        if let tv = view as? SiqiTerminalNSView {
            return tv
        }
        for subview in view.subviews {
            if let found = findTerminalView(in: subview) {
                return found
            }
        }
        return nil
    }

    public static func getActiveTerminalView(for window: NSWindow?) -> SiqiTerminalNSView? {
        guard let window else { return nil }
        if let tv = window.firstResponder as? SiqiTerminalNSView {
            return tv
        }
        if let contentView = window.contentView {
            return findTerminalView(in: contentView)
        }
        return nil
    }

    public static func isTextInputFocused(in window: NSWindow?) -> Bool {
        guard let window, let responder = window.firstResponder else { return false }
        if responder is NSText || responder is NSTextField || responder is NSSearchField {
            if responder is AppTerminalView { return false }
            return true
        }
        return false
    }

    public static func isAiCliActive(in session: SiqiTerminalSession?) -> Bool {
        guard let session else { return false }
        let (config, _) = SiqiUserConfig.load()
        let aiToolKeywords = Set(config.aiTools.map { $0.lowercased() })

        if let proc = session.activeProcessName?.lowercased(),
           aiToolKeywords.contains(where: { proc.contains($0) }) {
            return true
        }

        guard let pid = session.foregroundPid else { return false }
        if let currentName = ProcessInspector.processName(for: pid)?.lowercased(),
           aiToolKeywords.contains(where: { currentName.contains($0) }) {
            return true
        }

        for child in ProcessInspector.childPids(for: pid) {
            if let childName = ProcessInspector.processName(for: child)?.lowercased(),
               aiToolKeywords.contains(where: { childName.contains($0) }) {
                return true
            }
        }

        return ProcessInspector.hasDescendantProcess(for: pid, matching: aiToolKeywords, maxDepth: 2)
    }

    public static func pasteboardContainsImage(_ pb: NSPasteboard) -> Bool {
        if pb.canReadObject(forClasses: [NSImage.self], options: nil) {
            return true
        }
        if let types = pb.types {
            let imageTypes: Set<NSPasteboard.PasteboardType> = [.png, .tiff]
            if types.contains(where: {
                imageTypes.contains($0)
                    || $0.rawValue.lowercased().contains("image")
                    || $0.rawValue.lowercased().contains("png")
            }) {
                return true
            }
        }
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "heic", "tiff", "svg"]
            if urls.contains(where: { imageExtensions.contains($0.pathExtension.lowercased()) }) {
                return true
            }
        }
        return false
    }

    public static func getPasteboardImageData(_ pb: NSPasteboard) -> Data? {
        if let data = pb.data(forType: .png), !data.isEmpty, NSBitmapImageRep(data: data) != nil {
            return data
        }
        if let data = pb.data(forType: .tiff),
           let rep = NSBitmapImageRep(data: data),
           let png = rep.representation(using: .png, properties: [:]) {
            return png
        }
        if let images = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let first = images.first,
           let tiff = first.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            return png
        }
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let first = urls.first,
           let data = try? Data(contentsOf: first) {
            return data
        }
        return nil
    }

    public static func escapedShellPath(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    public static func savePasteboardImageToDisk(_ pb: NSPasteboard) -> String? {
        guard let imgData = getPasteboardImageData(pb) else { return nil }
        let cacheDir = DirectoryStore.pasteCacheDirectoryPath
        try? FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss_SSS"
        let filename = "paste_\(formatter.string(from: Date())).png"
        let filePath = (cacheDir as NSString).appendingPathComponent(filename)

        do {
            try imgData.write(to: URL(fileURLWithPath: filePath))
            DirectoryStore.prunePasteCache()
            return filePath
        } catch {
            return nil
        }
    }

    public static func handlePaste(in window: NSWindow?, model: SiqiWindowModel, saveImageAsPath: Bool = false) {
        guard let window else { return }
        let terminalView = getActiveTerminalView(for: window)

        if let terminalView, window.firstResponder !== terminalView {
            window.makeFirstResponder(terminalView)
        }

        let pb = NSPasteboard.general

        if saveImageAsPath {
            if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
                let paths = urls.map { escapedShellPath($0.path) }
                model.activeSession?.send(paths.joined(separator: " ") + " ")
                return
            }
            if let savedPath = savePasteboardImageToDisk(pb) {
                model.activeSession?.send(escapedShellPath(savedPath) + " ")
                return
            }
        }

        if pasteboardContainsImage(pb) {
            if isAiCliActive(in: model.activeSession), let terminalView {
                terminalView.triggerImagePasteShortcut()
                return
            } else if let savedPath = savePasteboardImageToDisk(pb) {
                model.activeSession?.send(escapedShellPath(savedPath) + " ")
                return
            }
        }

        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            let paths = urls.map { escapedShellPath($0.path) }
            model.activeSession?.send(paths.joined(separator: " ") + " ")
            return
        }

        if let session = model.activeSession {
            _ = session.state.performBindingAction("paste_from_clipboard")
        }
    }

    public static func handleCopy(in window: NSWindow?, model: SiqiWindowModel) {
        if let terminalView = getActiveTerminalView(for: window), terminalView.copySelectedTextToPasteboard() {
            return
        }
        if let session = model.activeSession {
            _ = session.state.performBindingAction("copy_to_clipboard")
        }
    }

    public static func handleSelectAll(model: SiqiWindowModel) {
        if let session = model.activeSession {
            _ = session.state.performBindingAction("select_all")
        }
    }

    // MARK: - User Keybindings

    public static func hasUserBinding(for event: NSEvent, in keybindings: [SiqiKeybinding]) -> Bool {
        keybindings.contains { matches($0, event: event) }
    }

    public static func hasUserBinding(for event: NSEvent) -> Bool {
        hasUserBinding(for: event, in: SiqiUserConfig.load().config.keybindings)
    }

    private static func matches(_ binding: SiqiKeybinding, event: NSEvent) -> Bool {
        var expected: NSEvent.ModifierFlags = []
        if binding.modifiers.contains("cmd") { expected.insert(.command) }
        if binding.modifiers.contains("ctrl") { expected.insert(.control) }
        if binding.modifiers.contains("alt") { expected.insert(.option) }
        if binding.modifiers.contains("shift") { expected.insert(.shift) }
        guard event.modifierFlags.intersection([.command, .control, .option, .shift]) == expected else {
            return false
        }
        return keyMatches(binding.key, event: event)
    }

    private static let namedKeys: [String: [UInt16]] = [
        "enter": [36, 76], "return": [36, 76], "escape": [53], "esc": [53],
        "tab": [48], "backspace": [51], "delete": [117],
        "up": [126], "down": [125], "left": [123], "right": [124],
        "home": [115], "end": [119], "page_up": [116], "page_down": [121],
    ]

    private static let characters: [String: String] = [
        "space": " ", "equal": "=", "minus": "-", "backquote": "`",
        "comma": ",", "period": ".", "slash": "/", "semicolon": ";",
        "quote": "'", "backslash": "\\", "bracket_left": "[", "bracket_right": "]",
    ]

    private static let punctuationCodes: [String: UInt16] = [
        "space": 49, "equal": 24, "minus": 27, "backquote": 50,
        "comma": 43, "period": 47, "slash": 44, "semicolon": 41,
        "quote": 39, "backslash": 42, "bracket_left": 33, "bracket_right": 30,
    ]

    private static func keyMatches(_ key: String, event: NSEvent) -> Bool {
        if let codes = namedKeys[key] {
            return codes.contains(event.keyCode)
        }
        if let character = characters[key] {
            return event.charactersIgnoringModifiers == character
                || punctuationCodes[key] == event.keyCode
        }
        return event.charactersIgnoringModifiers?.lowercased() == key
    }

    private static func perform(
        _ action: String,
        window: NSWindow,
        model: SiqiWindowModel,
        onCloseRequested: @escaping () -> Void
    ) -> Bool {
        switch action {
        case "new_tab": model.createNewTab()
        case "new_window": SiqiWindowManager.shared.createWindow(workingDirectory: model.activeSession?.fullDirectory)
        case "close_surface", "close_tab": model.closeActiveSessionWithConfirmation(in: window)
        case "close_window": onCloseRequested()
        case "new_split:right": model.splitRight()
        case "new_split:down": model.splitDown()
        case "toggle_split_zoom": model.toggleZoom()
        case "equalize_splits": model.equalizeSplits()
        case "goto_split:left": model.focusPane(in: .left)
        case "goto_split:right": model.focusPane(in: .right)
        case "goto_split:up": model.focusPane(in: .up)
        case "goto_split:down": model.focusPane(in: .down)
        case "toggle_quick_terminal": QuickTerminalController.shared.toggle()
        case "search": model.toggleSearch()
        case "copy_to_clipboard": handleCopy(in: window, model: model)
        case "paste_from_clipboard": handlePaste(in: window, model: model)
        case "select_all": handleSelectAll(model: model)
        case "clear_screen": model.clearActiveSession()
        case "reload_config": SiqiWindowManager.shared.reloadAllWindows()
        case "increase_font_size", "increase_font_size:1":
            _ = model.activeSession?.state.performBindingAction("increase_font_size:1")
        case "decrease_font_size", "decrease_font_size:1":
            _ = model.activeSession?.state.performBindingAction("decrease_font_size:1")
        case "reset_font_size":
            _ = model.activeSession?.state.performBindingAction("reset_font_size")
        case "next_tab": model.nextTab()
        case "previous_tab": model.previousTab()
        case "toggle_fullscreen": window.toggleFullScreen(nil)
        default:
            guard action.hasPrefix("goto_tab:"), let index = Int(action.dropFirst("goto_tab:".count)) else {
                return false
            }
            model.selectTab(at: index - 1)
        }
        return true
    }

    public static func dispatchKeyEvent(
        event: NSEvent,
        window: NSWindow,
        model: SiqiWindowModel,
        onCloseRequested: @escaping () -> Void
    ) -> NSEvent? {
        let isRelevant = window.isKeyWindow || window.isMainWindow || event.window === window
        guard isRelevant else { return event }

        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])

        if isTextInputFocused(in: window) {
            if event.keyCode == 53 && model.isSearching {
                model.endSearch()
                return nil
            }
            if flags == .command {
                let char = event.charactersIgnoringModifiers?.lowercased()
                if char == "c" || char == "v" || char == "a" || char == "x" {
                    return event
                }
                if char == "f" {
                    model.endSearch()
                    return nil
                }
                if char == "g" && model.isSearching {
                    _ = model.activeSession?.terminalView.navigateSearch(forward: true)
                    return nil
                }
            }
            if flags == [.command, .shift] && event.charactersIgnoringModifiers?.lowercased() == "g" && model.isSearching {
                _ = model.activeSession?.terminalView.navigateSearch(forward: false)
                return nil
            }
        }

        for binding in SiqiUserConfig.load().config.keybindings where matches(binding, event: event) {
            if perform(binding.action, window: window, model: model, onCloseRequested: onCloseRequested) {
                return nil
            }
        }

        if flags == [.command, .option] && event.charactersIgnoringModifiers?.lowercased() == "v" {
            handlePaste(in: window, model: model, saveImageAsPath: true)
            return nil
        }

        if flags == [.command, .option] && event.charactersIgnoringModifiers?.lowercased() == "m" {
            if let wc = window.windowController as? TerminalWindowController {
                wc.toggleCapsuleMode()
            } else {
                model.onToggleCapsuleRequested?()
            }
            return nil
        }

        if flags == .command && event.charactersIgnoringModifiers?.lowercased() == "v" {
            handlePaste(in: window, model: model, saveImageAsPath: false)
            return nil
        }

        if flags == .command && event.charactersIgnoringModifiers?.lowercased() == "c" {
            handleCopy(in: window, model: model)
            return nil
        }

        if flags == .command && event.charactersIgnoringModifiers?.lowercased() == "a" {
            handleSelectAll(model: model)
            return nil
        }

        if flags == .command && event.charactersIgnoringModifiers?.lowercased() == "n" {
            SiqiWindowManager.shared.createWindow(workingDirectory: model.activeSession?.fullDirectory)
            return nil
        }

        if flags == .command && event.charactersIgnoringModifiers?.lowercased() == "t" {
            model.createNewTab()
            return nil
        }

        if flags == .command && event.charactersIgnoringModifiers?.lowercased() == "d" {
            model.splitRight()
            return nil
        }

        if flags == [.command, .shift] && event.charactersIgnoringModifiers?.lowercased() == "d" {
            model.splitDown()
            return nil
        }

        if (flags == [.control, .command] || flags == [.command, .shift])
            && (event.charactersIgnoringModifiers == "=" || event.charactersIgnoringModifiers == "+") {
            model.equalizeSplits()
            return nil
        }

        if flags == [.command, .shift] && (event.keyCode == 36 || event.charactersIgnoringModifiers == "\r") {
            model.toggleZoom()
            return nil
        }

        if flags == [.command, .shift] && event.charactersIgnoringModifiers?.lowercased() == "p" {
            model.togglePin(in: window)
            return nil
        }

        if flags == [.control, .command] {
            let char = event.charactersIgnoringModifiers?.lowercased()
            if char == "h" || event.specialKey == .leftArrow {
                model.focusPane(in: .left)
                return nil
            }
            if char == "l" || event.specialKey == .rightArrow {
                model.focusPane(in: .right)
                return nil
            }
            if char == "k" || event.specialKey == .upArrow {
                model.focusPane(in: .up)
                return nil
            }
            if char == "j" || event.specialKey == .downArrow {
                model.focusPane(in: .down)
                return nil
            }
        }

        if flags == .command && event.charactersIgnoringModifiers?.lowercased() == "f" {
            model.toggleSearch()
            return nil
        }

        if flags == .command && event.charactersIgnoringModifiers?.lowercased() == "g" && model.isSearching {
            _ = model.activeSession?.terminalView.navigateSearch(forward: true)
            return nil
        }

        if flags == [.command, .shift] && event.charactersIgnoringModifiers?.lowercased() == "g" && model.isSearching {
            _ = model.activeSession?.terminalView.navigateSearch(forward: false)
            return nil
        }

        if flags == [.command, .option] {
            if event.specialKey == .leftArrow { model.focusPane(in: .left); return nil }
            if event.specialKey == .rightArrow { model.focusPane(in: .right); return nil }
            if event.specialKey == .upArrow { model.focusPane(in: .up); return nil }
            if event.specialKey == .downArrow { model.focusPane(in: .down); return nil }
            if event.charactersIgnoringModifiers == "[" { model.previousPane(); return nil }
            if event.charactersIgnoringModifiers == "]" { model.nextPane(); return nil }
        }

        if flags == .command && event.charactersIgnoringModifiers?.lowercased() == "w" {
            model.closeActiveSessionWithConfirmation(in: window)
            return nil
        }

        if flags == [.command, .shift] && event.charactersIgnoringModifiers?.lowercased() == "w" {
            onCloseRequested()
            return nil
        }

        if flags == .command, let char = event.charactersIgnoringModifiers?.first, char >= "1" && char <= "9" {
            if let tabIndex = Int(String(char)) {
                model.selectTab(at: tabIndex - 1)
                return nil
            }
        }

        if flags == .command && event.charactersIgnoringModifiers == "[" {
            model.previousTab()
            return nil
        }
        if flags == .command && event.charactersIgnoringModifiers == "]" {
            model.nextTab()
            return nil
        }

        if flags == [.command, .shift] {
            if event.charactersIgnoringModifiers == "{" || event.charactersIgnoringModifiers == "[" {
                model.previousTab()
                return nil
            }
            if event.charactersIgnoringModifiers == "}" || event.charactersIgnoringModifiers == "]" {
                model.nextTab()
                return nil
            }
        }

        if flags == .command && event.charactersIgnoringModifiers?.lowercased() == "k" {
            model.clearActiveSession()
            return nil
        }

        if flags == .command && event.charactersIgnoringModifiers?.lowercased() == "r" {
            model.restartActiveSession()
            return nil
        }

        if flags == [.command, .shift] && event.charactersIgnoringModifiers?.lowercased() == "r" {
            SiqiWindowManager.shared.reloadAllWindows()
            return nil
        }

        if flags == .command || flags == [.command, .shift] {
            let char = event.charactersIgnoringModifiers
            if char == "=" || char == "+" {
                _ = model.activeSession?.state.performBindingAction("increase_font_size:1")
                return nil
            } else if char == "-" {
                _ = model.activeSession?.state.performBindingAction("decrease_font_size:1")
                return nil
            } else if char == "0" {
                _ = model.activeSession?.state.performBindingAction("reset_font_size")
                return nil
            }
        }

        if flags == .command && (event.keyCode == 43 || event.charactersIgnoringModifiers == ",") {
            SiqiWindowManager.shared.openSettingsWindow()
            return nil
        }

        if flags == [.command, .option] && (event.keyCode == 43 || event.charactersIgnoringModifiers == ",") {
            let targetUrl = SiqiConfigStore.ensureConfigFileExists()
            NSWorkspace.shared.open(targetUrl)
            return nil
        }

        if flags == [.command, .shift] && (event.charactersIgnoringModifiers == "<" || event.charactersIgnoringModifiers == ",") {
            SiqiWindowManager.shared.reloadAllWindows()
            return nil
        }

        return event
    }
}
