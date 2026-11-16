import AppKit
import SwiftUI

public struct ContentView: View {
    @ObservedObject public var model: SiqiWindowModel
    @State private var configReloadToken = UUID()
    @State private var isNewTabHovered = false

    public init(model: SiqiWindowModel) {
        self.model = model
    }

    private var userConfig: SiqiUserConfig {
        _ = configReloadToken
        return SiqiUserConfig.load().config
    }

    private var isTranslucent: Bool {
        userConfig.backgroundOpacity < 1.0 || userConfig.backgroundBlur > 0
    }

    private var themeBg: Color {
        SiqiTheme.backgroundColor(for: userConfig.themeName, customBackground: userConfig.background)
    }

    private var showsTitlebarStrip: Bool {
        userConfig.macosTitlebarStyle != "hidden" || model.tabs.count > 1
    }

    public var body: some View {
        GeometryReader { windowProxy in
            let windowWidth = Int(round(windowProxy.size.width))
            let windowHeight = Int(round(windowProxy.size.height))
            let isMiniCapsule = windowHeight <= 36 || windowWidth < 120

            ZStack(alignment: .topLeading) {
                if isMiniCapsule {
                    ZStack(alignment: .trailing) {
                        WindowDragArea()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        Button {
                            model.onRestoreCapsuleRequested?()
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.65))
                                .frame(width: 14, height: 14)
                                .background(Circle().fill(Color.white.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 8)
                        .help("Restore Window Size (⌘⌥M / Double-click capsule)")
                    }
                } else {
                    VStack(spacing: 0) {
                        if showsTitlebarStrip {
                            ZStack(alignment: .trailing) {
                                WindowDragArea()
                                    .frame(height: 36)

                                if model.tabs.count > 1 && windowWidth > 140 {
                                    SiqiTabBar(model: model)
                                        .frame(height: 36)
                                } else if windowWidth > 140 {
                                    Button {
                                        model.createNewTab()
                                    } label: {
                                        Image(systemName: "plus")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(isNewTabHovered ? Color.white.opacity(0.95) : Color.white.opacity(0.50))
                                            .frame(width: 22, height: 22)
                                            .background(
                                                Circle()
                                                    .fill(isNewTabHovered ? Color.white.opacity(0.14) : Color.white.opacity(0.05))
                                            )
                                    }
                                    .buttonStyle(.plain)
                                    .onHover { isNewTabHovered = $0 }
                                    .padding(.trailing, 10)
                                    .help("New Tab (⌘T)")
                                }
                            }
                            .frame(height: 36)
                        }

                        ZStack(alignment: .topTrailing) {
                            if let activeTab = model.activeTab {
                                ActiveTabView(tab: activeTab, model: model)
                                    .id(activeTab.id)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else {
                                Color.clear
                            }

                            if model.isSearching {
                                TerminalSearchBar(model: model)
                                    .padding(.top, 6)
                                    .padding(.trailing, 14)
                                    .transition(.opacity)
                                    .zIndex(999)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .frame(minWidth: 80, minHeight: 32)
        .background(isTranslucent ? Color.clear : themeBg)
        .ignoresSafeArea()
        .transaction { $0.animation = nil }
        .onReceive(NotificationCenter.default.publisher(for: .siqiConfigDidChange)) { _ in
            configReloadToken = UUID()
        }
    }
}
