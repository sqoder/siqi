import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
public final class TabDragSessionCoordinator: ObservableObject {
    public static let shared = TabDragSessionCoordinator()

    public private(set) var activeTabId: UUID?
    private weak var sourceModel: SiqiWindowModel?
    private weak var sourceWindow: NSWindow?
    public var didDropInDestination: Bool = false

    private init() {}

    public func beginSession(tabId: UUID, sourceModel: SiqiWindowModel, sourceWindow: NSWindow) {
        activeTabId = tabId
        self.sourceModel = sourceModel
        self.sourceWindow = sourceWindow
        didDropInDestination = false
    }

    public func markDroppedInDestination() {
        didDropInDestination = true
    }

    public func sessionEnded(at screenPoint: NSPoint, operation: NSDragOperation) {
        defer {
            activeTabId = nil
            sourceModel = nil
            sourceWindow = nil
            didDropInDestination = false
        }

        guard let tabId = activeTabId, let sourceModel else { return }
        if didDropInDestination { return }
        guard sourceModel.tabs.count > 1 else { return }

        let isOutsideSourceWindow = sourceWindow.map { !NSPointInRect(screenPoint, $0.frame) } ?? true
        if isOutsideSourceWindow {
            sourceModel.detachTabToNewWindow(id: tabId, at: screenPoint)
        }
    }
}

public final class TabDragHandleView: NSView, NSDraggingSource {
    public var tab: SiqiTab
    public weak var model: SiqiWindowModel?
    public var reservesTrailingCloseArea: Bool = false
    public var onSelect: (() -> Void)?
    public var onHover: ((Bool) -> Void)?

    private var mouseDownPoint: NSPoint = .zero
    private var isDraggingSessionActive = false
    private var trackingArea: NSTrackingArea?

    public init(tab: SiqiTab, model: SiqiWindowModel, onSelect: @escaping () -> Void, onHover: @escaping (Bool) -> Void) {
        self.tab = tab
        self.model = model
        self.onSelect = onSelect
        self.onHover = onHover
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    public override func mouseEntered(with event: NSEvent) { onHover?(true) }
    public override func mouseExited(with event: NSEvent) { onHover?(false) }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        // Yield trailing 24pt to the close button only while hovered and showing the button.
        if reservesTrailingCloseArea && point.x > bounds.width - 24 {
            return nil
        }
        return super.hitTest(point)
    }

    public override func mouseDown(with event: NSEvent) {
        mouseDownPoint = event.locationInWindow
        isDraggingSessionActive = false
    }

    public override func mouseDragged(with event: NSEvent) {
        guard !isDraggingSessionActive else { return }
        let currentPoint = event.locationInWindow
        let dx = abs(currentPoint.x - mouseDownPoint.x)
        let dy = abs(currentPoint.y - mouseDownPoint.y)
        if dx > 4 || dy > 4 {
            isDraggingSessionActive = true
            startDraggingSession(with: event)
        }
    }

    public override func mouseUp(with event: NSEvent) {
        if !isDraggingSessionActive {
            onSelect?()
        }
        isDraggingSessionActive = false
    }

    private func startDraggingSession(with event: NSEvent) {
        guard let window, let model else { return }

        let pboardItem = NSPasteboardItem()
        pboardItem.setString(tab.id.uuidString, forType: .string)
        pboardItem.setString(tab.id.uuidString, forType: NSPasteboard.PasteboardType("com.siqi.tab"))

        let dragItem = NSDraggingItem(pasteboardWriter: pboardItem)
        let dragBounds = bounds.size.width > 0 ? bounds : NSRect(x: 0, y: 0, width: 120, height: 24)
        let dragImage = createDragImage(title: tab.tabDisplayTitle.isEmpty ? tab.title : tab.tabDisplayTitle)
        dragItem.setDraggingFrame(dragBounds, contents: dragImage)

        TabDragSessionCoordinator.shared.beginSession(tabId: tab.id, sourceModel: model, sourceWindow: window)
        beginDraggingSession(with: [dragItem], event: event, source: self)
    }

    private func createDragImage(title: String) -> NSImage {
        let size = bounds.size.width > 0 ? bounds.size : NSSize(width: 120, height: 24)
        let image = NSImage(size: size)
        image.lockFocus()

        let rect = NSRect(origin: .zero, size: size)
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 11, yRadius: 11)
        NSColor.white.withAlphaComponent(0.18).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.25).setStroke()
        path.lineWidth = 1
        path.stroke()

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byTruncatingMiddle
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.95),
            .paragraphStyle: paragraphStyle,
        ]
        let textRect = NSRect(x: 10, y: Int(round((size.height - 14) / 2)), width: max(10, Int(round(size.width)) - 20), height: 14)
        (title as NSString).draw(in: textRect, withAttributes: attrs)

        image.unlockFocus()
        return image
    }

    public func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .move
    }

    public func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        DispatchQueue.main.async {
            TabDragSessionCoordinator.shared.sessionEnded(at: screenPoint, operation: operation)
        }
    }
}

public struct TabDragHandleRepresentable: NSViewRepresentable {
    let tab: SiqiTab
    let model: SiqiWindowModel
    let reservesTrailingCloseArea: Bool
    let onSelect: () -> Void
    let onHover: (Bool) -> Void

    public func makeNSView(context: Context) -> TabDragHandleView {
        let view = TabDragHandleView(tab: tab, model: model, onSelect: onSelect, onHover: onHover)
        view.reservesTrailingCloseArea = reservesTrailingCloseArea
        return view
    }

    public func updateNSView(_ nsView: TabDragHandleView, context: Context) {
        nsView.tab = tab
        nsView.model = model
        nsView.reservesTrailingCloseArea = reservesTrailingCloseArea
        nsView.onSelect = onSelect
        nsView.onHover = onHover
    }
}

public typealias GhosttyTabBar = SiqiTabBar

public struct SiqiTabBar: View {
    @ObservedObject public var model: SiqiWindowModel
    @State private var hoveredTabId: UUID?
    @State private var draggingTabId: UUID?
    @State private var isPlusHovered: Bool = false

    public init(model: SiqiWindowModel) {
        self.model = model
    }

    private func targetWindow(for tab: SiqiTab? = nil) -> NSWindow? {
        tab?.activeSession?.terminalView.window
            ?? model.activeSession?.terminalView.window
            ?? NSApp.keyWindow
    }

    public var body: some View {
        HStack(spacing: 0) {
            Spacer()
                .frame(width: 92)

            HStack(spacing: 4) {
                ForEach(Array(model.tabs.enumerated()), id: \.element.id) { index, tab in
                    tabItem(tab: tab, index: index)
                }

                plusButton
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
            .padding(.trailing, 6)
        }
        .frame(height: 36)
        .background(Color.clear)
    }

    @ViewBuilder
    private func tabItem(tab: SiqiTab, index: Int) -> some View {
        let isActive = model.activeTabId == tab.id
        let isHovered = hoveredTabId == tab.id

        SiqiTabItemView(
            tab: tab,
            model: model,
            index: index,
            isActive: isActive,
            isTabHovered: isHovered,
            onSelect: { model.selectTab(id: tab.id) },
            onClose: { model.closeTabWithConfirmation(id: tab.id, in: targetWindow(for: tab)) },
            onHover: { hoveredTabId = $0 ? tab.id : nil }
        )
        .onHover { hoveredTabId = $0 ? tab.id : nil }
        .contextMenu { tabContextMenu(tab) }
        .onDrop(
            of: [UTType.text, UTType.plainText],
            delegate: TabDropDelegate(
                destinationTab: tab,
                model: model,
                draggingTabId: $draggingTabId
            )
        )
    }

    @ViewBuilder
    private func tabContextMenu(_ tab: SiqiTab) -> some View {
        Button("New Tab") { model.createNewTab() }
        Button("Split Right") { _ = model.splitTab(id: tab.id, axis: .horizontal) }
        Button("Split Down") { _ = model.splitTab(id: tab.id, axis: .vertical) }
        if model.tabs.count > 1 {
            Divider()
            Button("Move Tab to New Window") { model.detachTabToNewWindow(id: tab.id) }
            Button("Close Other Tabs") {
                model.closeOtherTabsWithConfirmation(keeping: tab.id, in: targetWindow(for: tab))
            }
        }
        Divider()
        Button("Close Tab") {
            model.closeTabWithConfirmation(id: tab.id, in: targetWindow(for: tab))
        }
    }

    private var plusButton: some View {
        Button {
            model.createNewTab()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isPlusHovered ? Color.white.opacity(0.95) : Color.white.opacity(0.55))
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(isPlusHovered ? Color.white.opacity(0.14) : Color.white.opacity(0.05))
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(isPlusHovered ? 0.14 : 0.04), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .onHover { isPlusHovered = $0 }
        .help("New Tab (⌘T)")
    }
}

private struct SiqiTabItemView: View {
    @ObservedObject var tab: SiqiTab
    let model: SiqiWindowModel
    let index: Int
    let isActive: Bool
    let isTabHovered: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onHover: (Bool) -> Void

    @State private var isCloseHovered: Bool = false

    var body: some View {
        ZStack {
            backgroundView

            TabDragHandleRepresentable(
                tab: tab,
                model: model,
                reservesTrailingCloseArea: isTabHovered,
                onSelect: onSelect,
                onHover: onHover
            )

            HStack(spacing: 0) {
                Spacer(minLength: 26)
                tabTitle
                Spacer(minLength: 26)
            }
            .allowsHitTesting(false)

            HStack {
                if tab.hasActiveProcess {
                    Circle()
                        .fill(Color(red: 1.0, green: 0.65, blue: 0.25))
                        .frame(width: 5, height: 5)
                        .shadow(color: Color.orange.opacity(0.60), radius: 2)
                        .padding(.leading, 9)
                }
                Spacer()
            }
            .allowsHitTesting(false)

            HStack {
                Spacer()
                if isTabHovered {
                    closeButton
                        .padding(.trailing, 6)
                } else if index < 9 {
                    shortcutBadge
                        .padding(.trailing, 9)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 24)
        .contentShape(Capsule(style: .continuous))
    }

    private var tabTitle: some View {
        let title = tab.tabDisplayTitle.isEmpty ? tab.title : tab.tabDisplayTitle
        let textColor = isActive ? Color.white.opacity(0.96) : (isTabHovered ? Color.white.opacity(0.85) : Color.white.opacity(0.52))
        return Text(title)
            .font(.system(size: 11, weight: isActive ? .medium : .regular))
            .foregroundStyle(textColor)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private var shortcutBadge: some View {
        Text("⌘\(index + 1)")
            .font(.system(size: 10, weight: isActive ? .medium : .regular))
            .foregroundStyle(isActive ? Color.white.opacity(0.65) : Color.white.opacity(0.32))
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(isCloseHovered ? Color.white.opacity(0.95) : Color.white.opacity(0.60))
                .frame(width: 14, height: 14)
                .background(
                    Circle()
                        .fill(isCloseHovered ? Color.white.opacity(0.24) : Color.white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
        .onHover { isCloseHovered = $0 }
        .help("Close Tab (⌘W)")
    }

    private var backgroundView: some View {
        let fillColor: Color = isActive
            ? Color.white.opacity(0.14)
            : (isTabHovered ? Color.white.opacity(0.07) : Color.white.opacity(0.03))
        let strokeColor: Color = isActive
            ? Color.white.opacity(0.18)
            : (isTabHovered ? Color.white.opacity(0.06) : Color.white.opacity(0.02))
        let shadowColor: Color = isActive ? Color.black.opacity(0.15) : Color.clear

        return Capsule(style: .continuous)
            .fill(fillColor)
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(strokeColor, lineWidth: 1)
            )
            .shadow(color: shadowColor, radius: 2, y: 1)
    }
}

struct TabDropDelegate: DropDelegate {
    let destinationTab: SiqiTab
    let model: SiqiWindowModel
    @Binding var draggingTabId: UUID?

    func dropEntered(info: DropInfo) {
        guard let currentId = TabDragSessionCoordinator.shared.activeTabId ?? draggingTabId,
              currentId != destinationTab.id,
              let fromIndex = model.tabs.firstIndex(where: { $0.id == currentId }),
              let toIndex = model.tabs.firstIndex(where: { $0.id == destinationTab.id })
        else { return }

        withAnimation(.easeInOut(duration: 0.15)) {
            model.moveTab(from: fromIndex, to: toIndex)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        TabDragSessionCoordinator.shared.markDroppedInDestination()
        draggingTabId = nil

        if let draggingId = TabDragSessionCoordinator.shared.activeTabId,
           !model.tabs.contains(where: { $0.id == draggingId }),
           let (sourceModel, sourceTab) = SiqiWindowManager.shared.findTabAndModel(id: draggingId) {
            sourceModel.removeTabWithoutClosingWindow(id: draggingId)
            let destIndex = model.tabs.firstIndex(where: { $0.id == destinationTab.id }) ?? model.tabs.count
            model.insertTab(sourceTab, at: destIndex)
            return true
        }

        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}
