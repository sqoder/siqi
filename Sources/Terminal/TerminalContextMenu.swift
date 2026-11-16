import AppKit

/// Builds and handles native right-click context menus for terminal views.
@MainActor
public final class TerminalContextMenuBridge: NSObject {
    public static let shared = TerminalContextMenuBridge()

    private weak var currentTerminalView: SiqiTerminalNSView?

    public func buildMenu(for view: SiqiTerminalNSView) -> NSMenu {
        currentTerminalView = view
        if let model = targetModel,
           let session = model.tabs.flatMap({ $0.allSessions }).first(where: { $0.terminalView === view }) {
            model.activeSessionId = session.id
        }

        let menu = NSMenu(title: "Terminal Context")
        menu.allowsContextMenuPlugIns = false
        menu.autoenablesItems = false

        let isMultiPane = (targetModel?.activeTab?.allSessions.count ?? 1) > 1

        addItem("Copy", key: "c", modifiers: .command, action: #selector(menuCopy), to: menu)
        addItem("Paste", key: "v", modifiers: .command, action: #selector(menuPaste), to: menu)
        addItem("Select All", key: "a", modifiers: .command, action: #selector(menuSelectAll), to: menu)

        menu.addItem(.separator())

        addItem("Split Right", key: "d", modifiers: .command, action: #selector(menuSplitRight), to: menu)
        addItem("Split Down", key: "d", modifiers: [.command, .shift], action: #selector(menuSplitDown), to: menu)
        addItem(
            "Equalize Splits",
            key: "=",
            modifiers: [.command, .shift],
            action: #selector(menuEqualizeSplits),
            enabled: isMultiPane,
            to: menu
        )
        addItem(
            "Toggle Split Zoom",
            key: "\r",
            modifiers: [.command, .shift],
            action: #selector(menuToggleZoom),
            enabled: isMultiPane,
            to: menu
        )

        menu.addItem(.separator())

        addItem("Find...", key: "f", modifiers: .command, action: #selector(menuFind), to: menu)
        addItem("Clear Screen", key: "k", modifiers: .command, action: #selector(menuClear), to: menu)

        menu.addItem(.separator())

        addItem("New Tab", key: "t", modifiers: .command, action: #selector(menuNewTab), to: menu)
        addItem("New Window", key: "n", modifiers: .command, action: #selector(menuNewWindow), to: menu)

        menu.addItem(.separator())

        addItem(
            isMultiPane ? "Close Pane" : "Close Tab",
            key: "w",
            modifiers: .command,
            action: #selector(menuClosePane),
            to: menu
        )

        return menu
    }

    private func addItem(
        _ title: String,
        key: String,
        modifiers: NSEvent.ModifierFlags,
        action: Selector,
        enabled: Bool = true,
        to menu: NSMenu
    ) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = self
        item.isEnabled = enabled
        menu.addItem(item)
    }

    private var targetModel: SiqiWindowModel? {
        guard let window = currentTerminalView?.window else { return nil }
        if window is QuickTerminalPanel {
            return QuickTerminalController.shared.model
        }
        if let wc = window.windowController as? TerminalWindowController {
            return wc.model
        }
        return nil
    }

    private var targetWindow: NSWindow? {
        currentTerminalView?.window ?? SiqiWindowManager.shared.activeWindowController?.window
    }

    @objc private func menuCopy() {
        if let model = targetModel {
            TerminalActionBridge.handleCopy(in: targetWindow, model: model)
        }
    }

    @objc private func menuPaste() {
        if let model = targetModel {
            TerminalActionBridge.handlePaste(in: targetWindow, model: model)
        }
    }

    @objc private func menuSelectAll() {
        if let model = targetModel {
            TerminalActionBridge.handleSelectAll(model: model)
        }
    }

    @objc private func menuSplitRight() { targetModel?.splitRight() }
    @objc private func menuSplitDown() { targetModel?.splitDown() }
    @objc private func menuEqualizeSplits() { targetModel?.equalizeSplits() }
    @objc private func menuToggleZoom() { targetModel?.toggleZoom() }
    @objc private func menuFind() { targetModel?.beginSearch() }
    @objc private func menuClear() { targetModel?.clearActiveSession() }
    @objc private func menuNewTab() { targetModel?.createNewTab() }

    @objc private func menuNewWindow() {
        SiqiWindowManager.shared.createWindow(workingDirectory: targetModel?.activeSession?.fullDirectory)
    }

    @objc private func menuClosePane() {
        guard let model = targetModel, let session = model.activeSession else { return }
        if let wc = targetWindow?.windowController as? TerminalWindowController {
            wc.requestCloseSession(session.id)
        } else if !session.hasRunningChildProcess() {
            model.closeSession(id: session.id)
        } else if let wc = targetWindow as? QuickTerminalPanel {
            _ = wc
            model.closeSession(id: session.id)
        } else {
            model.closeSession(id: session.id)
        }
    }
}
