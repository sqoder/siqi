import AppKit
import Combine
import GhosttyTerminal
import SwiftUI

public final class SiqiHostingView<Content: View>: NSHostingView<Content> {
    public override var intrinsicContentSize: NSSize {
        NSSize(width: 80, height: 32)
    }

    public override var fittingSize: NSSize {
        NSSize(width: 80, height: 32)
    }
}

public final class SiqiTerminalWindow: NSWindow {
    public var isFullScreenTransitioning: Bool = false
    public var isSplitDragging: Bool = false
    public let pinButton = NativePinButtonView(frame: NSRect(x: 0, y: 0, width: 14, height: 14))

    public override var inLiveResize: Bool {
        super.inLiveResize || isSplitDragging
    }

    public override var minSize: NSSize {
        get { NSSize(width: 80, height: 32) }
        set { super.minSize = NSSize(width: 80, height: 32) }
    }

    public override var contentMinSize: NSSize {
        get { NSSize(width: 80, height: 32) }
        set { super.contentMinSize = NSSize(width: 80, height: 32) }
    }

    public override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        var rect = super.constrainFrameRect(frameRect, to: screen)
        if rect.size.width < 140 || rect.size.height < 60 {
            rect.size.width = 80
            rect.size.height = 32
        }
        return rect
    }

    public override func layoutIfNeeded() {
        super.layoutIfNeeded()
        adjustTrafficLights()
        cleanTitlebarDecorations()
    }

    public override func setFrame(_ frameRect: NSRect, display displayFlag: Bool) {
        super.setFrame(frameRect, display: displayFlag)
        adjustTrafficLights()
        cleanTitlebarDecorations()
    }

    public override func makeKeyAndOrderFront(_ sender: Any?) {
        super.makeKeyAndOrderFront(sender)
        adjustTrafficLights()
        cleanTitlebarDecorations()
    }

    public override func orderFront(_ sender: Any?) {
        super.orderFront(sender)
        adjustTrafficLights()
        cleanTitlebarDecorations()
    }

    public func adjustTrafficLights() {
        guard !styleMask.contains(.fullScreen), !isFullScreenTransitioning else {
            pinButton.isHidden = true
            return
        }
        guard let close = standardWindowButton(.closeButton),
              let mini = standardWindowButton(.miniaturizeButton),
              let zoom = standardWindowButton(.zoomButton),
              let buttonContainer = close.superview else {
            pinButton.isHidden = true
            return
        }

        let superHeight = buttonContainer.frame.height
        let targetY = max(0, Int(round(superHeight)) - 14 - 11)
        let targetStartX = 14
        let spacing = 20

        close.setFrameOrigin(NSPoint(x: targetStartX, y: targetY))
        mini.setFrameOrigin(NSPoint(x: targetStartX + spacing, y: targetY))
        zoom.setFrameOrigin(NSPoint(x: targetStartX + spacing * 2, y: targetY))

        // Mount pinButton in the wider titlebar container (buttonContainer is ~70pt wide and clips x=74..88)
        let hostView = buttonContainer.superview ?? contentView?.superview ?? buttonContainer
        if pinButton.superview !== hostView {
            pinButton.removeFromSuperview()
            hostView.addSubview(pinButton)
        }
        let zoomRectInHost = hostView.convert(zoom.frame, from: buttonContainer)
        pinButton.frame = NSRect(
            x: Int(round(zoomRectInHost.minX)) + spacing,
            y: Int(round(zoomRectInHost.minY)),
            width: 14,
            height: 14
        )
        pinButton.updateContainerTracking()
        pinButton.isHidden = (frame.width < 120)
    }

    public func cleanTitlebarDecorations() {
        guard let titlebarContainer = contentView?.superview?.subviews.first(where: {
            NSStringFromClass(type(of: $0)).contains("NSTitlebarContainerView")
        }) else { return }

        let isNative = SiqiUserConfig.load().config.macosTitlebarStyle.lowercased() == "native"
        for sub in titlebarContainer.subviews {
            let subName = NSStringFromClass(type(of: sub))
            if subName.contains("NSTitlebarBackgroundView") || subName.contains("_NSTitlebarDecorationView") {
                sub.isHidden = !isNative
            }
            for inner in sub.subviews {
                let innerName = NSStringFromClass(type(of: inner))
                if innerName.contains("NSTitlebarBackgroundView") || innerName.contains("NSVisualEffectView") {
                    inner.isHidden = !isNative
                }
            }
        }
    }
}

// MARK: - WindowServer Blur Bridge

private typealias CGSConnectionID = UnsafeMutableRawPointer

@_silgen_name("CGSDefaultConnectionForThread")
private func CGSDefaultConnectionForThread() -> CGSConnectionID?

@_silgen_name("CGSSetWindowBackgroundBlurRadius")
private func CGSSetWindowBackgroundBlurRadius(_ connection: CGSConnectionID?, _ windowNumber: Int, _ radius: Int32) -> Int32

@MainActor
public final class TerminalWindowController: NSWindowController, NSWindowDelegate {
    public let model: SiqiWindowModel
    private var eventMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private var occlusionObserver: Any?
    public var previousExpandedFrame: NSRect?
    private var isClosed = false

    public static func applyWindowBlur(window: NSWindow, radius: Int32) {
        if let conn = CGSDefaultConnectionForThread() {
            _ = CGSSetWindowBackgroundBlurRadius(conn, window.windowNumber, radius)
        }
    }

    public static func applyTitlebarStyle(_ style: String, to window: NSWindow) {
        if style.lowercased() == "native" {
            window.titleVisibility = .visible
            window.titlebarAppearsTransparent = false
        } else {
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
        }
    }

    public init(model: SiqiWindowModel) {
        self.model = model

        let (userConfig, _) = SiqiUserConfig.load()
        let isTranslucent = userConfig.backgroundOpacity < 1.0 || userConfig.backgroundBlur > 0

        let initialWidth: Int = {
            if let preferred = SiqiWindowManager.shared.preferredWindowSize {
                return Int(round(preferred.width))
            }
            let font = NSFont(name: userConfig.fontFamily, size: userConfig.fontSize)
                ?? NSFont.monospacedSystemFont(ofSize: userConfig.fontSize, weight: .regular)
            let cellWidth = font.maximumAdvancement.width > 0 ? font.maximumAdvancement.width : (userConfig.fontSize * 0.60)
            let padding = userConfig.windowPaddingX * 2
            if let w = userConfig.windowWidth {
                return w > 200 ? w : Int(round(Double(w) * Double(cellWidth))) + padding
            }
            return Int(round(100.0 * Double(cellWidth))) + padding
        }()

        let initialHeight: Int = {
            if let preferred = SiqiWindowManager.shared.preferredWindowSize {
                return Int(round(preferred.height))
            }
            let font = NSFont(name: userConfig.fontFamily, size: userConfig.fontSize)
                ?? NSFont.monospacedSystemFont(ofSize: userConfig.fontSize, weight: .regular)
            let cellHeight = Int(ceil(font.ascender - font.descender + font.leading)) + userConfig.adjustCellHeight
            let padding = userConfig.windowPaddingY * 2 + 36
            if let h = userConfig.windowHeight {
                return h > 150 ? h : h * cellHeight + padding
            }
            return 30 * cellHeight + padding
        }()

        let window = SiqiTerminalWindow(
            contentRect: NSRect(x: 0, y: 0, width: initialWidth, height: initialHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.title = "siqi"
        Self.applyTitlebarStyle(userConfig.macosTitlebarStyle, to: window)
        window.isMovableByWindowBackground = false

        let baseBg = SiqiTheme.nsBackgroundColor(for: userConfig.themeName, customBackground: userConfig.background)
        if isTranslucent {
            window.isOpaque = false
            window.backgroundColor = baseBg.withAlphaComponent(CGFloat(userConfig.backgroundOpacity))
            let blurRadius = userConfig.backgroundBlur > 0 ? Int32(userConfig.backgroundBlur) : 20
            Self.applyWindowBlur(window: window, radius: blurRadius)
        } else {
            window.backgroundColor = baseBg
            window.isOpaque = true
            Self.applyWindowBlur(window: window, radius: 0)
        }

        window.hasShadow = true
        window.minSize = NSSize(width: 80, height: 32)
        window.contentMinSize = NSSize(width: 80, height: 32)
        window.isReleasedWhenClosed = false

        if userConfig.windowSaveState.lowercased() != "never" {
            window.setFrameAutosaveName("SiqiTerminalWindow")
        }

        let hostingView = SiqiHostingView(rootView: ContentView(model: model))
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = isTranslucent ? NSColor.clear.cgColor : baseBg.cgColor
        window.contentView = hostingView
        window.pinButton.model = model

        super.init(window: window)
        window.delegate = self

        model.onCloseWindowRequested = { [weak self] in
            self?.closeWindow()
        }
        model.onRestoreCapsuleRequested = { [weak self] in
            self?.restoreFromCapsule()
        }
        model.onToggleCapsuleRequested = { [weak self] in
            self?.toggleCapsuleMode()
        }

        model.$isPinned
            .receive(on: DispatchQueue.main)
            .sink { [weak window] _ in
                window?.pinButton.updateTooltip()
                window?.pinButton.needsDisplay = true
            }
            .store(in: &cancellables)

        setupKeyEventMonitor()
        setupOcclusionStateObserver()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupOcclusionStateObserver() {
        guard let window else { return }
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            guard let self, let window = self.window else { return }
            if window.occlusionState.contains(.visible) {
                self.model.resumeBackgroundRendering()
            } else {
                self.model.pauseBackgroundRendering()
            }
        }
    }

    private func setupKeyEventMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window else { return event }
            return TerminalActionBridge.dispatchKeyEvent(
                event: event,
                window: window,
                model: self.model,
                onCloseRequested: { [weak self] in
                    guard let self, let window = self.window else { return }
                    if self.windowShouldClose(window) {
                        self.closeWindow()
                    }
                }
            )
        }
    }

    public func getActiveTerminalView() -> SiqiTerminalNSView? {
        TerminalActionBridge.getActiveTerminalView(for: window)
    }

    public func handlePaste() { TerminalActionBridge.handlePaste(in: window, model: model) }
    public func handleCopy() { TerminalActionBridge.handleCopy(in: window, model: model) }
    public func handleSelectAll() { TerminalActionBridge.handleSelectAll(model: model) }

    public func requestCloseSession(_ sessionId: UUID) {
        model.closeSessionWithConfirmation(id: sessionId, in: window)
    }

    public func closeCurrentTabOrWindow() {
        model.closeActiveSessionWithConfirmation(in: window)
    }

    public func closeWindow() {
        performTeardown()
        window?.close()
    }

    private func performTeardown() {
        guard !isClosed else { return }
        isClosed = true

        saveWindowFrameIfNeeded()
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        if let occlusionObserver {
            NotificationCenter.default.removeObserver(occlusionObserver)
            self.occlusionObserver = nil
        }
        cancellables.removeAll()
        (window as? SiqiTerminalWindow)?.pinButton.model = nil
        SiqiWindowManager.shared.removeWindow(self)
        model.tearDownAllSessions()
    }

    public func saveWindowFrameIfNeeded() {
        guard let window else { return }
        let (userConfig, _) = SiqiUserConfig.load()
        guard userConfig.windowSaveState.lowercased() != "never" else { return }

        if window.frame.width >= 140 && window.frame.height >= 60 {
            SiqiWindowManager.shared.updateLastWindowFrame(window.frame)
            if SiqiWindowManager.shared.windowControllers.first === self || SiqiWindowManager.shared.windowControllers.count <= 1 {
                window.saveFrame(usingName: "SiqiTerminalWindow")
            }
            SiqiWindowManager.shared.scheduleSaveWindowState()
        }
    }

    public func toggleCapsuleMode() {
        guard let window else { return }
        if window.frame.width < 120 || window.frame.height <= 36 {
            restoreFromCapsule()
        } else {
            previousExpandedFrame = window.frame
            let target = NSRect(
                x: Int(round(window.frame.minX)),
                y: Int(round(window.frame.maxY)) - 32,
                width: 80,
                height: 32
            )
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().setFrame(target, display: true)
            }
        }
    }

    public func restoreFromCapsule() {
        guard let window else { return }
        let targetFrame: NSRect = {
            if let prev = previousExpandedFrame, prev.width >= 200, prev.height >= 100 {
                return prev
            }
            let screen = window.screen ?? NSScreen.main
            let screenFrame = screen?.visibleFrame ?? NSRect(x: 100, y: 100, width: 900, height: 600)
            let width = 800
            let height = 500
            let x = Int(round(window.frame.minX))
            let y = Int(round(window.frame.maxY)) - height
            return NSRect(
                x: max(Int(round(screenFrame.minX)), min(x, Int(round(screenFrame.maxX)) - width)),
                y: max(Int(round(screenFrame.minY)), min(y, Int(round(screenFrame.maxY)) - height)),
                width: width,
                height: height
            )
        }()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(targetFrame, display: true)
        }
    }

    public func updateThemeBackground() {
        guard let window else { return }
        let (userConfig, _) = SiqiUserConfig.load()
        Self.applyTitlebarStyle(userConfig.macosTitlebarStyle, to: window)
        (window as? SiqiTerminalWindow)?.cleanTitlebarDecorations()

        let isTranslucent = userConfig.backgroundOpacity < 1.0 || userConfig.backgroundBlur > 0
        let baseBg = SiqiTheme.nsBackgroundColor(for: userConfig.themeName, customBackground: userConfig.background)
        if isTranslucent {
            window.isOpaque = false
            window.backgroundColor = baseBg.withAlphaComponent(CGFloat(userConfig.backgroundOpacity))
            let blurRadius = userConfig.backgroundBlur > 0 ? Int32(userConfig.backgroundBlur) : 20
            Self.applyWindowBlur(window: window, radius: blurRadius)
        } else {
            window.backgroundColor = baseBg
            window.isOpaque = true
            Self.applyWindowBlur(window: window, radius: 0)
        }
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = isTranslucent ? NSColor.clear.cgColor : baseBg.cgColor
        window.invalidateShadow()
    }

    public func showWindow() {
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - NSWindowDelegate

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        let (config, _) = SiqiUserConfig.load()
        guard config.confirmCloseSurface else { return true }

        let running = model.sessions.filter { $0.hasActiveProcess }
        if let first = running.first, let proc = first.activeProcessName {
            let alert = NSAlert()
            alert.messageText = "Close window with running process '\(proc)'?"
            alert.informativeText = "Closing this window will terminate all active processes running inside it."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Close Window")
            alert.addButton(withTitle: "Cancel")
            return alert.runModal() == .alertFirstButtonReturn
        }
        return true
    }

    public func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        if let win = window, win.frame.width >= 140 && win.frame.height >= 60 {
            previousExpandedFrame = win.frame
        }
        if frameSize.width < 140 || frameSize.height < 60 {
            return NSSize(width: 80, height: 32)
        }
        return NSSize(width: max(80, frameSize.width), height: max(32, frameSize.height))
    }

    public func windowDidResize(_ notification: Notification) {
        saveWindowFrameIfNeeded()
        (window as? SiqiTerminalWindow)?.adjustTrafficLights()
    }

    public func windowDidEndLiveResize(_ notification: Notification) {
        saveWindowFrameIfNeeded()
        SiqiWindowManager.shared.saveWindowState()
    }

    public func windowDidMove(_ notification: Notification) {
        saveWindowFrameIfNeeded()
    }

    public func windowWillClose(_ notification: Notification) {
        performTeardown()
    }

    public func windowDidBecomeKey(_ notification: Notification) {
        (window as? SiqiTerminalWindow)?.adjustTrafficLights()
        if let terminalView = getActiveTerminalView() {
            window?.makeFirstResponder(terminalView)
        }
    }

    public func windowWillEnterFullScreen(_ notification: Notification) {
        (window as? SiqiTerminalWindow)?.isFullScreenTransitioning = true
    }

    public func windowDidEnterFullScreen(_ notification: Notification) {
        (window as? SiqiTerminalWindow)?.isFullScreenTransitioning = false
    }

    public func windowWillExitFullScreen(_ notification: Notification) {
        (window as? SiqiTerminalWindow)?.isFullScreenTransitioning = true
    }

    public func windowDidExitFullScreen(_ notification: Notification) {
        let terminalWin = window as? SiqiTerminalWindow
        terminalWin?.isFullScreenTransitioning = false
        DispatchQueue.main.async {
            terminalWin?.adjustTrafficLights()
        }
    }
}
