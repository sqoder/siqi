import Carbon
import SwiftUI

@main
struct SiqiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var secureInputEnabled = IsSecureEventInputEnabled()

    init() {
        for key in ProcessInfo.processInfo.environment.keys {
            if key.hasPrefix("HERDR_") || key == "TMUX" || key == "STY" || key == "WINDOW" {
                unsetenv(key)
            }
        }
    }

    var body: some Scene {
        Settings {
            SettingsView()
        }
        .commands {
            SiqiCommands(secureInputEnabled: $secureInputEnabled)
        }
    }
}
