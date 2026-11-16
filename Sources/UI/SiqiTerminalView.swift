import AppKit
import GhosttyTerminal
import SwiftUI

public struct PersistentTerminalSurfaceView: NSViewRepresentable {
    let session: SiqiTerminalSession

    public func makeNSView(context: Context) -> SiqiTerminalNSView {
        session.terminalView.removeFromSuperview()
        return session.terminalView
    }

    public func updateNSView(_ nsView: SiqiTerminalNSView, context: Context) {}
}

public struct SiqiTerminalView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var session: SiqiTerminalSession
    @ObservedObject var model: SiqiWindowModel
    @State private var configReloadToken = UUID()

    public init(session: SiqiTerminalSession, model: SiqiWindowModel) {
        self.session = session
        self.model = model
    }

    private var isMultiPane: Bool {
        (model.activeTab?.allSessions.count ?? 1) > 1
    }

    private var isActivePane: Bool {
        model.activeSessionId == session.id
    }

    private var userConfig: SiqiUserConfig {
        _ = configReloadToken
        return SiqiUserConfig.load().config
    }

    public var body: some View {
        ZStack(alignment: .bottomLeading) {
            PersistentTerminalSurfaceView(session: session)
                .id(session.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transaction { $0.animation = nil }

            TerminalScrollbarView(session: session)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)

            if isMultiPane && !isActivePane {
                let dimOpacity = max(0.0, min(1.0, 1.0 - userConfig.unfocusedSplitOpacity))
                if dimOpacity > 0.001 {
                    Color.black
                        .opacity(dimOpacity)
                        .allowsHitTesting(false)
                        .animation(.easeInOut(duration: 0.15), value: isActivePane)
                }
            }

            if let path = session.hoveredDisplayPath, !path.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: path.lowercased().hasPrefix("http") ? "link" : "doc.text")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.80))
                    Text(path)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.95))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(red: 24 / 255.0, green: 26 / 255.0, blue: 32 / 255.0).opacity(0.95))
                        .shadow(color: Color.black.opacity(0.40), radius: 6, x: 0, y: 2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                )
                .padding(.leading, 12)
                .padding(.bottom, 8)
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            session.state.adopt(colorScheme: colorScheme)
            if model.activeSessionId == session.id {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    session.terminalView.window?.makeFirstResponder(session.terminalView)
                }
            }
        }
        .onChange(of: colorScheme) { _, newScheme in
            session.state.adopt(colorScheme: newScheme)
        }
        .onChange(of: model.activeSessionId) { _, newId in
            if newId == session.id {
                session.terminalView.window?.makeFirstResponder(session.terminalView)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .siqiConfigDidChange)) { _ in
            configReloadToken = UUID()
        }
    }
}

struct TerminalScrollbarView: View {
    @ObservedObject var session: SiqiTerminalSession
    @State private var isVisible: Bool = false
    @State private var isDragging: Bool = false
    @State private var isHovering: Bool = false
    @State private var dragStartThumbY: CGFloat = 0
    @State private var hideTask: DispatchWorkItem? = nil

    private let thumbColor = Color(red: 157 / 255.0, green: 159 / 255.0, blue: 162 / 255.0)

    var body: some View {
        if let scrollbar = session.state.scrollbar, scrollbar.total > scrollbar.len {
            GeometryReader { proxy in
                let height = Int(round(proxy.size.height))
                let total = max(1, Int(scrollbar.total))
                let len = Int(scrollbar.len)
                let offset = Int(scrollbar.offset)
                let maxOffset = max(1, total - len)

                let thumbHeight = max(28, min(height, Int(round(Double(height) * Double(len) / Double(total)))))
                let trackDistance = max(0, height - thumbHeight)
                let progress = min(1.0, Double(min(offset, maxOffset)) / Double(maxOffset))
                let currentThumbY = Int(round(Double(trackDistance) * progress))
                let barWidth: CGFloat = (isHovering || isDragging) ? 7 : 5

                ZStack(alignment: .topTrailing) {
                    Color.clear
                        .frame(width: 16)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    if !isDragging {
                                        isDragging = true
                                        dragStartThumbY = CGFloat(currentThumbY)
                                    }
                                    showScrollbar()
                                    let newThumbY = min(max(0, dragStartThumbY + value.translation.height), CGFloat(trackDistance))
                                    let newProgress = trackDistance > 0 ? (newThumbY / CGFloat(trackDistance)) : 1.0
                                    let targetRow = UInt(round(Double(newProgress) * Double(maxOffset)))
                                    _ = session.state.scrollToRow(targetRow)
                                }
                                .onEnded { _ in
                                    isDragging = false
                                    scheduleHide()
                                }
                        )

                    Capsule(style: .continuous)
                        .fill(thumbColor)
                        .frame(width: barWidth, height: CGFloat(thumbHeight))
                        .offset(x: -3, y: CGFloat(currentThumbY))
                        .opacity(isVisible ? (isDragging ? 1.0 : (isHovering ? 0.95 : 0.85)) : 0.0)
                        .animation(.easeInOut(duration: 0.25), value: isVisible)
                        .animation(.easeInOut(duration: 0.15), value: barWidth)
                        .allowsHitTesting(false)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .onHover { hovering in
                    isHovering = hovering
                    if hovering {
                        showScrollbar()
                        scheduleHide(delay: 0.8)
                    } else if !isDragging {
                        scheduleHide(delay: 0.5)
                    }
                }
            }
            .onChange(of: session.state.scrollbar?.offset) { _, _ in
                showAndScheduleHide()
            }
            .onChange(of: session.state.scrollbar?.total) { _, _ in
                showAndScheduleHide()
            }
            .onDisappear {
                hideTask?.cancel()
                hideTask = nil
            }
        }
    }

    private func showScrollbar() {
        hideTask?.cancel()
        hideTask = nil
        withAnimation(.easeInOut(duration: 0.12)) {
            isVisible = true
        }
    }

    private func scheduleHide(delay: Double = 0.65) {
        hideTask?.cancel()
        let task = DispatchWorkItem {
            guard !isDragging else { return }
            withAnimation(.easeInOut(duration: 0.28)) {
                isVisible = false
            }
        }
        hideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
    }

    private func showAndScheduleHide() {
        showScrollbar()
        if !isDragging {
            scheduleHide(delay: 0.65)
        }
    }
}
