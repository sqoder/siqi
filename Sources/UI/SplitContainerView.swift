import AppKit
import SwiftUI

public struct ActiveTabView: View {
    @ObservedObject var tab: SiqiTab
    let model: SiqiWindowModel

    public init(tab: SiqiTab, model: SiqiWindowModel) {
        self.tab = tab
        self.model = model
    }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            if tab.isZoomed, let activeSession = tab.activeSession {
                SiqiTerminalView(session: activeSession, model: model)
                    .id(activeSession.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                HStack(spacing: 5) {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 9, weight: .bold))
                    Text("ZOOMED · ⌘⇧↩ Unzoom")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                }
                .foregroundStyle(Color.white.opacity(0.85))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.60))
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                        )
                )
                .padding(.top, 6)
                .padding(.trailing, 10)
                .onTapGesture {
                    tab.toggleZoom()
                }
            } else {
                PaneContainerView(node: tab.rootPane, model: model)
                    .id(tab.id)
            }
        }
    }
}

public struct PaneContainerView: View {
    let node: PaneNode
    let model: SiqiWindowModel

    public init(node: PaneNode, model: SiqiWindowModel) {
        self.node = node
        self.model = model
    }

    public var body: some View {
        switch node {
        case .terminal(let session):
            SiqiTerminalView(session: session, model: model)
                .id(session.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .split(let splitId, let axis, let fraction, let first, let second):
            GeometryReader { proxy in
                let size = proxy.size
                if size.width > 20 && size.height > 20 {
                    let safeFraction = (fraction.isNaN || !fraction.isFinite) ? 0.5 : min(max(fraction, 0.05), 0.95)
                    if axis == .horizontal {
                        let dividerThickness: CGFloat = 1
                        let availableWidth = max(0, size.width - dividerThickness)
                        let firstWidth = floor(availableWidth * safeFraction)
                        let secondWidth = max(0, availableWidth - firstWidth)

                        HStack(spacing: 0) {
                            PaneContainerView(node: first, model: model)
                                .frame(width: firstWidth, height: size.height)

                            SplitDividerView(
                                axis: .horizontal,
                                splitId: splitId,
                                currentFraction: safeFraction,
                                availableLength: availableWidth,
                                model: model
                            )
                            .frame(width: dividerThickness, height: size.height)

                            PaneContainerView(node: second, model: model)
                                .frame(width: secondWidth, height: size.height)
                        }
                        .frame(width: size.width, height: size.height)
                    } else {
                        let dividerThickness: CGFloat = 1
                        let availableHeight = max(0, size.height - dividerThickness)
                        let firstHeight = floor(availableHeight * safeFraction)
                        let secondHeight = max(0, availableHeight - firstHeight)

                        VStack(spacing: 0) {
                            PaneContainerView(node: first, model: model)
                                .frame(width: size.width, height: firstHeight)

                            SplitDividerView(
                                axis: .vertical,
                                splitId: splitId,
                                currentFraction: safeFraction,
                                availableLength: availableHeight,
                                model: model
                            )
                            .frame(width: size.width, height: dividerThickness)

                            PaneContainerView(node: second, model: model)
                                .frame(width: size.width, height: secondHeight)
                        }
                        .frame(width: size.width, height: size.height)
                    }
                } else {
                    Color.clear
                }
            }
            .id(splitId)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

public struct SplitDividerView: NSViewRepresentable {
    let axis: Axis
    let splitId: UUID
    let currentFraction: CGFloat
    let availableLength: CGFloat
    let model: SiqiWindowModel

    public init(axis: Axis, splitId: UUID, currentFraction: CGFloat, availableLength: CGFloat, model: SiqiWindowModel) {
        self.axis = axis
        self.splitId = splitId
        self.currentFraction = currentFraction
        self.availableLength = availableLength
        self.model = model
    }

    public func makeNSView(context: Context) -> SplitDividerNSView {
        let view = SplitDividerNSView()
        view.axis = axis
        view.splitId = splitId
        view.currentFraction = currentFraction
        view.availableLength = availableLength
        view.model = model
        return view
    }

    public func updateNSView(_ nsView: SplitDividerNSView, context: Context) {
        nsView.axis = axis
        nsView.splitId = splitId
        nsView.currentFraction = currentFraction
        nsView.availableLength = availableLength
        nsView.model = model
        nsView.window?.invalidateCursorRects(for: nsView)
    }
}

public final class SplitDividerNSView: NSView {
    var axis: Axis = .horizontal
    var splitId: UUID = UUID()
    var currentFraction: CGFloat = 0.5
    var availableLength: CGFloat = 100
    weak var model: SiqiWindowModel?

    private var isDragging = false
    private var dragStartLocation: NSPoint = .zero
    private var dragStartFraction: CGFloat = 0.5

    private var isHovering = false {
        didSet {
            if oldValue != isHovering { needsDisplay = true }
        }
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.zPosition = 1000
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.zPosition = 1000
    }

    public override func resetCursorRects() {
        super.resetCursorRects()
        let cursor = (axis == .horizontal) ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown
        let hitRect = bounds.insetBy(dx: axis == .horizontal ? -4 : 0, dy: axis == .vertical ? -4 : 0)
        addCursorRect(hitRect, cursor: cursor)
    }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview else { return super.hitTest(point) }
        let localPoint = convert(point, from: superview)
        let hitRect = bounds.insetBy(dx: axis == .horizontal ? -4 : 0, dy: axis == .vertical ? -4 : 0)
        if hitRect.contains(localPoint) {
            return self
        }
        return super.hitTest(point)
    }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let color = (isHovering || isDragging)
            ? NSColor.white.withAlphaComponent(0.35)
            : NSColor.white.withAlphaComponent(0.08)
        color.setFill()
        bounds.fill()
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        let hitRect = bounds.insetBy(dx: axis == .horizontal ? -4 : 0, dy: axis == .vertical ? -4 : 0)
        let area = NSTrackingArea(
            rect: hitRect,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    public override func mouseEntered(with event: NSEvent) { isHovering = true }
    public override func mouseExited(with event: NSEvent) { isHovering = false }

    public override func cursorUpdate(with event: NSEvent) {
        let cursor = (axis == .horizontal) ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown
        cursor.set()
    }

    public override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            model?.updateSplitFraction(splitId: splitId, fraction: 0.5)
            return
        }
        guard availableLength > 20 else { return }
        isDragging = true
        needsDisplay = true
        dragStartLocation = event.locationInWindow
        dragStartFraction = currentFraction
        (window as? SiqiTerminalWindow)?.isSplitDragging = true
    }

    public override func mouseDragged(with event: NSEvent) {
        guard isDragging, availableLength > 20 else { return }
        let currentLocation = event.locationInWindow
        let delta = (axis == .horizontal)
            ? (currentLocation.x - dragStartLocation.x)
            : -(currentLocation.y - dragStartLocation.y)
        guard !delta.isNaN, !availableLength.isNaN else { return }
        let computed = dragStartFraction + (delta / availableLength)
        guard !computed.isNaN, computed.isFinite else { return }
        let newFraction = min(max(computed, 0.08), 0.92)
        if abs(newFraction - currentFraction) >= 0.002 {
            model?.updateSplitFraction(splitId: splitId, fraction: newFraction)
        }
    }

    public override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        needsDisplay = true
        (window as? SiqiTerminalWindow)?.isSplitDragging = false

        let currentLocation = event.locationInWindow
        let delta = (axis == .horizontal)
            ? (currentLocation.x - dragStartLocation.x)
            : -(currentLocation.y - dragStartLocation.y)
        if !delta.isNaN && !availableLength.isNaN {
            let computed = dragStartFraction + (delta / availableLength)
            if !computed.isNaN && computed.isFinite {
                model?.updateSplitFraction(splitId: splitId, fraction: min(max(computed, 0.08), 0.92))
            }
        }
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil && isDragging {
            isDragging = false
        }
    }
}
