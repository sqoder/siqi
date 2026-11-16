import AppKit
import Carbon
import SwiftUI

struct SiqiCommands: Commands {
    @Binding var secureInputEnabled: Bool

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                SiqiWindowManager.shared.openSettingsWindow()
            }
        }

        CommandGroup(replacing: .newItem) {
            Button("New Window") {
                SiqiWindowManager.shared.createWindow()
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("New Tab") {
                SiqiWindowManager.shared.activeWindowController?.model.createNewTab()
            }
            .keyboardShortcut("t", modifiers: .command)

            Divider()

            Button("Split Right") {
                SiqiWindowManager.shared.activeWindowController?.model.splitRight()
            }
            .keyboardShortcut("d", modifiers: .command)

            Button("Split Down") {
                SiqiWindowManager.shared.activeWindowController?.model.splitDown()
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])

            Button("Toggle Split Zoom") {
                SiqiWindowManager.shared.activeWindowController?.model.toggleZoom()
            }
            .keyboardShortcut(.return, modifiers: [.command, .shift])

            Button("Equalize Splits") {
                SiqiWindowManager.shared.activeWindowController?.model.equalizeSplits()
            }
            .keyboardShortcut("=", modifiers: [.command, .shift])

            Divider()

            Button("Close Split / Tab") {
                SiqiWindowManager.shared.activeWindowController?.closeCurrentTabOrWindow()
            }
            .keyboardShortcut("w", modifiers: .command)

            Button("Close Window") {
                if let ctrl = SiqiWindowManager.shared.activeWindowController,
                   ctrl.windowShouldClose(ctrl.window ?? NSWindow()) {
                    ctrl.closeWindow()
                }
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .pasteboard) {
            Button("Cut") {
                NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("x", modifiers: .command)

            Button("Copy") {
                if !NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil) {
                    SiqiWindowManager.shared.activeWindowController?.handleCopy()
                }
            }
            .keyboardShortcut("c", modifiers: .command)

            Button("Paste") {
                SiqiWindowManager.shared.activeWindowController?.handlePaste()
            }
            .keyboardShortcut("v", modifiers: .command)

            Button("Paste Image as File Path") {
                if let ctrl = SiqiWindowManager.shared.activeWindowController {
                    TerminalActionBridge.handlePaste(in: ctrl.window, model: ctrl.model, saveImageAsPath: true)
                }
            }
            .keyboardShortcut("v", modifiers: [.command, .option])

            Divider()

            Button("Select All") {
                if !NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) {
                    SiqiWindowManager.shared.activeWindowController?.handleSelectAll()
                }
            }
            .keyboardShortcut("a", modifiers: .command)
        }

        CommandGroup(replacing: .textEditing) {
            Button("Find...") {
                SiqiWindowManager.shared.activeWindowController?.model.toggleSearch()
            }
            .keyboardShortcut("f", modifiers: .command)

            Button("Find Next") {
                _ = SiqiWindowManager.shared.activeWindowController?.model.activeSession?.terminalView.navigateSearch(forward: true)
            }
            .keyboardShortcut("g", modifiers: .command)

            Button("Find Previous") {
                _ = SiqiWindowManager.shared.activeWindowController?.model.activeSession?.terminalView.navigateSearch(forward: false)
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
        }

        CommandMenu("Terminal") {
            Button("Toggle Quick Terminal") {
                QuickTerminalController.shared.toggle()
            }
            .keyboardShortcut("`", modifiers: .control)

            Divider()

            Button("Clear Scrollback") {
                SiqiWindowManager.shared.activeWindowController?.model.clearActiveSession()
            }
            .keyboardShortcut("k", modifiers: .command)

            Button("Restart Active Session") {
                SiqiWindowManager.shared.activeWindowController?.model.restartActiveSession()
            }
            .keyboardShortcut("r", modifiers: .command)

            Button("Reload Configuration") {
                SiqiWindowManager.shared.reloadAllWindows()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Divider()

            Button(secureInputEnabled ? "Disable Secure Keyboard Entry" : "Enable Secure Keyboard Entry") {
                if secureInputEnabled {
                    DisableSecureEventInput()
                } else {
                    EnableSecureEventInput()
                }
                secureInputEnabled = IsSecureEventInputEnabled()
            }

            Divider()

            Button("Previous Tab") {
                SiqiWindowManager.shared.activeWindowController?.model.previousTab()
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])

            Button("Next Tab") {
                SiqiWindowManager.shared.activeWindowController?.model.nextTab()
            }
            .keyboardShortcut("]", modifiers: [.command, .shift])

            Divider()

            ForEach(1...9, id: \.self) { index in
                Button("Select Tab \(index)") {
                    SiqiWindowManager.shared.activeWindowController?.model.selectTab(at: index - 1)
                }
                .keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(0x30 + index)!)), modifiers: .command)
            }
        }

        CommandGroup(after: .toolbar) {
            Button("Pin Window on Top") {
                if let ctrl = SiqiWindowManager.shared.activeWindowController {
                    ctrl.model.togglePin(in: ctrl.window)
                }
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])

            Button("Toggle Capsule Mode") {
                SiqiWindowManager.shared.activeWindowController?.toggleCapsuleMode()
            }
            .keyboardShortcut("m", modifiers: [.command, .option])

            Divider()

            Button("Increase Font Size") {
                _ = SiqiWindowManager.shared.activeWindowController?.model.activeSession?.state.performBindingAction("increase_font_size:1")
            }
            .keyboardShortcut("+", modifiers: .command)

            Button("Decrease Font Size") {
                _ = SiqiWindowManager.shared.activeWindowController?.model.activeSession?.state.performBindingAction("decrease_font_size:1")
            }
            .keyboardShortcut("-", modifiers: .command)

            Button("Reset Font Size") {
                _ = SiqiWindowManager.shared.activeWindowController?.model.activeSession?.state.performBindingAction("reset_font_size")
            }
            .keyboardShortcut("0", modifiers: .command)

            Divider()

            Button("Open Configuration File") {
                let targetUrl = SiqiConfigStore.ensureConfigFileExists()
                NSWorkspace.shared.open(targetUrl)
            }
            .keyboardShortcut(",", modifiers: [.command, .option])
        }
    }
}
