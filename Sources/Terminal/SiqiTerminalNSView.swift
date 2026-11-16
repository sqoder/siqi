import AppKit
import GhosttyTerminal

/// Native AppTerminalView subclass replacing Objective-C runtime swizzling for focus,
/// context menus, drag-and-drop, IME window level, and shortcut routing.
@MainActor
public final class SiqiTerminalNSView: AppTerminalView {
    public var onActivateSession: (() -> Void)?
    public var shouldHandOffContextClick: ((_ controlPressed: Bool) -> Bool)?
    public var contextMenuBuilder: (() -> NSMenu?)?

    public override init(frame: NSRect) {
        super.init(frame: frame)
        registerTerminalDragTypes()
    }

    public static func handsOffContextMenu(control: Bool, processRunning: Bool) -> Bool {
        control || processRunning
    }

    public static func isSettingsShortcut(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command else {
            return false
        }
        return event.keyCode == 43 || event.charactersIgnoringModifiers == ","
    }

    // MARK: - Focus & Context Menu

    public override func mouseDown(with event: NSEvent) {
        onActivateSession?()
        super.mouseDown(with: event)
    }

    public override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        onActivateSession?()

        let controlPressed = event.modifierFlags.contains(.control)
        if shouldHandOffContextClick?(controlPressed) == true {
            super.rightMouseDown(with: event)
            return
        }

        if let menu = contextMenuBuilder?() {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
    }

    public override func menu(for event: NSEvent) -> NSMenu? {
        let controlPressed = event.modifierFlags.contains(.control)
        if shouldHandOffContextClick?(controlPressed) == true {
            return super.menu(for: event)
        }
        return contextMenuBuilder?()
    }

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if Self.isSettingsShortcut(event) {
            if TerminalActionBridge.hasUserBinding(for: event) {
                return false
            }
            SiqiWindowManager.shared.openSettingsWindow()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    // MARK: - IME Window Level

    /// Informs IME candidate windows of the host window level so overlays stay above floating panels.
    @objc public func windowLevel() -> Int {
        if let window {
            return Int(window.level.rawValue)
        }
        return Int(NSWindow.Level.normal.rawValue)
    }

    // MARK: - Synthetic Image Paste

    /// Triggers a synthetic Control+V event so TUI CLIs read image data from the macOS pasteboard.
    public func triggerImagePasteShortcut() {
        let timestamp = ProcessInfo.processInfo.systemUptime
        let windowNum = window?.windowNumber ?? 0

        guard let downEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .control,
            timestamp: timestamp,
            windowNumber: windowNum,
            context: nil,
            characters: "\u{16}",
            charactersIgnoringModifiers: "v",
            isARepeat: false,
            keyCode: 0x09
        ) else { return }

        guard let upEvent = NSEvent.keyEvent(
            with: .keyUp,
            location: .zero,
            modifierFlags: .control,
            timestamp: timestamp + 0.005,
            windowNumber: windowNum,
            context: nil,
            characters: "\u{16}",
            charactersIgnoringModifiers: "v",
            isARepeat: false,
            keyCode: 0x09
        ) else { return }

        keyDown(with: downEvent)
        keyUp(with: upEvent)
    }

    // MARK: - Drag and Drop

    private func registerTerminalDragTypes() {
        registerForDraggedTypes([
            .fileURL,
            .string,
            .rtf,
            .html,
            .URL,
            NSPasteboard.PasteboardType("NSStringPboardType"),
            NSPasteboard.PasteboardType("public.utf8-plain-text"),
            NSPasteboard.PasteboardType("public.plain-text"),
            NSPasteboard.PasteboardType("NSFilenamesPboardType"),
        ])
    }

    public override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard let types = sender.draggingPasteboard.types, !types.isEmpty else { return [] }
        return .copy
    }

    public override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    public override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        true
    }

    public override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let pboard = sender.draggingPasteboard

        if let urls = pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            let paths = urls.map { TerminalActionBridge.escapedShellPath($0.path) }
            dispatchDraggedText(paths.joined(separator: " ") + " ")
            return true
        }

        if let filenames = pboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String],
           !filenames.isEmpty {
            let paths = filenames.map { TerminalActionBridge.escapedShellPath($0) }
            dispatchDraggedText(paths.joined(separator: " ") + " ")
            return true
        }

        for type in [
            NSPasteboard.PasteboardType.string,
            NSPasteboard.PasteboardType("public.utf8-plain-text"),
            NSPasteboard.PasteboardType("public.plain-text"),
            NSPasteboard.PasteboardType("NSStringPboardType"),
        ] {
            if let text = pboard.string(forType: type), !text.isEmpty {
                dispatchDraggedText(text)
                return true
            }
        }

        if let strings = pboard.readObjects(forClasses: [NSString.self], options: nil) as? [String],
           let first = strings.first, !first.isEmpty {
            dispatchDraggedText(first)
            return true
        }

        return false
    }

    private func dispatchDraggedText(_ text: String) {
        window?.makeFirstResponder(self)
        if let state = delegate as? TerminalViewState {
            _ = state.send(text)
        } else {
            sendText(text)
        }
    }
}
