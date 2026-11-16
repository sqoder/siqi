import AppKit
import Combine
import Foundation
import GhosttyTheme
import GhosttyTerminal

/// Typed surface delegate bridging libghostty callbacks to TerminalViewState and SiqiTerminalSession
/// without Objective-C associated objects.
@MainActor
final class SiqiSurfaceDelegate:
    TerminalSurfaceTitleDelegate,
    TerminalSurfaceGridResizeDelegate,
    TerminalSurfaceFocusDelegate,
    TerminalSurfaceCloseDelegate,
    TerminalSurfaceBellDelegate,
    TerminalSurfaceDesktopNotificationDelegate,
    TerminalSurfacePwdDelegate,
    TerminalSurfaceScrollbarDelegate,
    TerminalSurfaceCommandFinishedDelegate,
    TerminalSurfaceLifecycleDelegate,
    TerminalSurfaceOpenURLDelegate,
    TerminalSurfaceHoverLinkDelegate,
    TerminalSurfaceSearchDelegate
{
    weak var state: TerminalViewState?
    weak var session: SiqiTerminalSession?

    init(state: TerminalViewState, session: SiqiTerminalSession) {
        self.state = state
        self.session = session
    }

    func detach() {
        state = nil
        session = nil
    }

    func terminalDidChangeTitle(_ title: String) { state?.terminalDidChangeTitle(title) }
    func terminalDidResize(_ size: TerminalGridMetrics) { state?.terminalDidResize(size) }
    func terminalDidChangeFocus(_ focused: Bool) { state?.terminalDidChangeFocus(focused) }
    func terminalDidClose(processAlive: Bool) { state?.terminalDidClose(processAlive: processAlive) }
    func terminalDidRingBell() { state?.terminalDidRingBell() }
    func terminalDidRequestDesktopNotification(title: String, body: String) {
        state?.terminalDidRequestDesktopNotification(title: title, body: body)
    }
    func terminalDidChangeWorkingDirectory(_ path: String) { state?.terminalDidChangeWorkingDirectory(path) }
    func terminalDidUpdateScrollbar(_ scrollbar: TerminalScrollbar) { state?.terminalDidUpdateScrollbar(scrollbar) }
    func terminalDidFinishCommand(exitCode: Int?, durationNanos: UInt64) {
        state?.terminalDidFinishCommand(exitCode: exitCode, durationNanos: durationNanos)
    }
    func terminalDidAttachSurface(_ surface: TerminalSurface) { state?.terminalDidAttachSurface(surface) }
    func terminalDidDetachSurface() { state?.terminalDidDetachSurface() }

    func terminalDidRequestOpenURL(_ url: String, kind: TerminalOpenURLKind) {
        guard let target = TerminalLinkResolver.resolve(url, workingDirectory: session?.fullDirectory ?? state?.workingDirectory) else {
            return
        }
        NSWorkspace.shared.open(target)
    }

    func terminalDidUpdateHoverLink(_ url: String?) {
        session?.updateHoveredLink(url)
    }

    func terminalDidStartSearch(needle: String) {
        session?.handleSearchStarted(needle: needle)
    }

    func terminalDidEndSearch() {
        session?.handleSearchEnded()
    }

    func terminalDidUpdateSearchTotal(_ total: Int?) {
        session?.searchTotal = total
    }

    func terminalDidUpdateSearchSelected(_ selected: Int?) {
        session?.searchSelected = selected
    }
}

@MainActor
public final class SiqiTerminalSession: ObservableObject, Identifiable, Equatable {
    public let id: UUID
    public let createdAt: Date

    @Published public private(set) var state: TerminalViewState
    @Published public var customTitle: String?
    @Published public var hoveredDisplayPath: String?
    @Published public private(set) var isTornDown: Bool = false
    @Published public var searchTotal: Int?
    @Published public var searchSelected: Int?

    public var initialWorkingDirectory: String
    public var onFocused: (() -> Void)?
    public var onClosed: (() -> Void)?
    public let terminalView: SiqiTerminalNSView
    public private(set) var isCwdMonitorActive: Bool = false

    private var surfaceDelegate: SiqiSurfaceDelegate?
    private var cancellables = Set<AnyCancellable>()
    private var cwdMonitorTimer: Timer?
    private var latestProcessInfo: (name: String?, cwd: String?, date: Date)?
    private var lastKnownDirectory: String = ""
    private var lastKnownProcessName: String?

    public nonisolated static func == (lhs: SiqiTerminalSession, rhs: SiqiTerminalSession) -> Bool {
        lhs.id == rhs.id
    }

    public init(id: UUID = UUID(), workingDirectory: String? = nil) {
        self.id = id
        self.createdAt = Date()
        let initialDir = DirectoryStore.resolvedInitialWorkingDirectory(explicit: workingDirectory)
        self.initialWorkingDirectory = initialDir
        self.lastKnownDirectory = initialDir

        let state = Self.buildTerminalViewState(workingDirectory: initialDir)
        self.state = state
        self.terminalView = SiqiTerminalNSView(frame: .zero)

        let surfaceDel = SiqiSurfaceDelegate(state: state, session: self)
        self.surfaceDelegate = surfaceDel

        wireTerminalView(viewDelegate: surfaceDel)
        bindState()
        resumeCwdMonitor(forceUpdate: false)
    }

    deinit {
        cwdMonitorTimer?.invalidate()
        cancellables.removeAll()
    }

    private func wireTerminalView(viewDelegate: SiqiSurfaceDelegate) {
        terminalView.delegate = viewDelegate
        terminalView.controller = state.controller
        terminalView.configuration = state.configuration

        terminalView.onActivateSession = { [weak self] in
            self?.onFocused?()
        }
        terminalView.shouldHandOffContextClick = { [weak self] controlPressed in
            let processRunning = self?.activeProcessNameFresh() != nil
            return SiqiTerminalNSView.handsOffContextMenu(control: controlPressed, processRunning: processRunning)
        }
        terminalView.contextMenuBuilder = { [weak view = terminalView] in
            guard let view else { return nil }
            return TerminalContextMenuBridge.shared.buildMenu(for: view)
        }
    }

    private func bindState() {
        cancellables.removeAll()

        state.onClose = { [weak self] _ in
            self?.onClosed?()
        }

        state.$isFocused
            .filter { $0 }
            .sink { [weak self] _ in
                guard let self else { return }
                self.onFocused?()
                DirectoryStore.saveLastWorkingDirectory(self.fullDirectory)
            }
            .store(in: &cancellables)

        state.$workingDirectory
            .sink { [weak self] newDir in
                guard let self else { return }
                if let newDir, !newDir.isEmpty {
                    let normalized = Self.normalizeWorkingDirectory(newDir)
                    if !normalized.isEmpty {
                        self.lastKnownDirectory = normalized
                        DirectoryStore.saveLastWorkingDirectory(normalized)
                        SiqiWindowManager.shared.scheduleSaveWindowState()
                    }
                }
                self.objectWillChange.send()
            }
            .store(in: &cancellables)

        state.$title
            .sink { [weak self] _ in
                guard let self else { return }
                DirectoryStore.saveLastWorkingDirectory(self.fullDirectory)
                self.objectWillChange.send()
            }
            .store(in: &cancellables)

        state.$scrollbar
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        state.$bellCount
            .dropFirst()
            .sink { _ in
                NSSound(named: "Glass")?.play()
            }
            .store(in: &cancellables)

        state.$lastDesktopNotificationAt
            .compactMap { $0 }
            .sink { [weak self] _ in
                guard let self else { return }
                TerminalNotificationService.post(
                    title: self.state.lastDesktopNotificationTitle ?? "siqi",
                    body: self.state.lastDesktopNotificationBody ?? ""
                )
            }
            .store(in: &cancellables)
    }

    fileprivate func updateHoveredLink(_ rawUrl: String?) {
        if let rawUrl, !rawUrl.isEmpty {
            let display = TerminalLinkResolver.resolveDisplayPath(rawUrl, workingDirectory: fullDirectory)
            hoveredDisplayPath = display
            terminalView.toolTip = display
        } else {
            hoveredDisplayPath = nil
            terminalView.toolTip = nil
        }
    }

    fileprivate func handleSearchStarted(needle: String) {
        if needle.isEmpty {
            searchTotal = nil
            searchSelected = nil
        }
    }

    fileprivate func handleSearchEnded() {
        searchTotal = nil
        searchSelected = nil
    }

    // MARK: - CWD Monitoring

    public func pauseCwdMonitor() {
        cwdMonitorTimer?.invalidate()
        cwdMonitorTimer = nil
        isCwdMonitorActive = false
    }

    public func resumeCwdMonitor(forceUpdate: Bool = true) {
        if forceUpdate {
            let current = fullDirectory
            if current != lastKnownDirectory {
                lastKnownDirectory = current
                DirectoryStore.saveLastWorkingDirectory(current)
                SiqiWindowManager.shared.scheduleSaveWindowState()
                objectWillChange.send()
            }
            lastKnownProcessName = processName(fresh: true)
        }
        guard cwdMonitorTimer == nil, !isTornDown else { return }
        isCwdMonitorActive = true
        cwdMonitorTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isCwdMonitorActive, !self.isTornDown else { return }
                let current = self.fullDirectory
                if current != self.lastKnownDirectory {
                    self.lastKnownDirectory = current
                    DirectoryStore.saveLastWorkingDirectory(current)
                    SiqiWindowManager.shared.scheduleSaveWindowState()
                    self.objectWillChange.send()
                }
                let proc = self.processName(fresh: true)
                if proc != self.lastKnownProcessName {
                    self.lastKnownProcessName = proc
                    self.objectWillChange.send()
                }
            }
        }
    }

    // MARK: - Titles & Process Inspection

    public var title: String {
        if let customTitle, !customTitle.isEmpty { return customTitle }
        if !state.title.isEmpty { return state.title }
        return "zsh"
    }

    public var activeProcessName: String? { processName(fresh: false) }

    public func activeProcessNameFresh() -> String? { processName(fresh: true) }

    public func hasRunningChildProcess() -> Bool {
        activeProcessNameFresh() != nil
    }

    private func processName(fresh: Bool) -> String? {
        let defaultShells: Set<String> = [
            "zsh", "bash", "fish", "sh", "tcsh", "csh", "ksh", "login",
            "-zsh", "-bash", "-fish", "siqi",
        ]

        if let kernelProc = currentChildInfo(fresh: fresh).name {
            let clean = kernelProc.lowercased()
            if !defaultShells.contains(clean) {
                return kernelProc
            }
        }

        let raw = state.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.isEmpty {
            if raw == "~" || raw.hasPrefix("~/") || raw.hasPrefix("/") || raw.hasPrefix("./") || raw.contains("/") {
                return nil
            }
            let firstToken = raw.components(separatedBy: .whitespaces).first?.lowercased() ?? ""
            let cleanToken = firstToken.hasPrefix("-") ? String(firstToken.dropFirst()) : firstToken
            if !defaultShells.contains(cleanToken) && cleanToken != "~" {
                return raw
            }
        }

        return nil
    }

    public var hasActiveProcess: Bool {
        activeProcessName != nil
    }

    public var foregroundPid: pid_t? { terminalView.foregroundPid }

    private func currentChildInfo(fresh: Bool = false) -> (name: String?, cwd: String?) {
        if !fresh, let cached = latestProcessInfo, Date().timeIntervalSince(cached.date) < 1.0 {
            return (cached.name, cached.cwd)
        }
        let pid = foregroundPid
        let name = pid.flatMap { ProcessInspector.processName(for: $0) }
        let cwd = pid.flatMap { ProcessInspector.currentWorkingDirectory(for: $0) }
        if let cwd, !cwd.isEmpty {
            lastKnownDirectory = cwd
        }
        latestProcessInfo = (name, cwd, Date())
        return (name, cwd)
    }

    public static func normalizeWorkingDirectory(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.hasPrefix("file://") {
            if let parsed = URL(string: trimmed)?.path, !parsed.isEmpty {
                return parsed
            }
            let withoutScheme = String(trimmed.dropFirst("file://".count))
            if let slashIdx = withoutScheme.firstIndex(of: "/") {
                let rawPath = String(withoutScheme[slashIdx...])
                return rawPath.removingPercentEncoding ?? rawPath
            }
        }
        return NSString(string: trimmed).expandingTildeInPath
    }

    @discardableResult
    public func refreshWorkingDirectory() -> String {
        _ = currentChildInfo(fresh: true)
        return fullDirectory
    }

    public var tabDisplayTitle: String {
        if let proc = activeProcessName {
            return proc.components(separatedBy: .whitespaces).first ?? proc
        }
        return displayPathFormatted
    }

    public var displayDirectory: String {
        let full = fullDirectory
        if full == NSHomeDirectory() { return "~" }
        let last = URL(fileURLWithPath: full).lastPathComponent
        return last.isEmpty ? "~" : last
    }

    public var displayPathFormatted: String {
        let full = fullDirectory
        let home = NSHomeDirectory()
        if full == home { return "~" }
        if full.hasPrefix(home + "/") {
            return "~" + full.dropFirst(home.count)
        }
        return full
    }

    public var fullDirectory: String {
        if let childCwd = currentChildInfo().cwd, !childCwd.isEmpty {
            return childCwd
        }
        if let cwd = state.workingDirectory, !cwd.isEmpty {
            let normalized = Self.normalizeWorkingDirectory(cwd)
            if !normalized.isEmpty {
                return normalized
            }
        }
        if !lastKnownDirectory.isEmpty {
            return lastKnownDirectory
        }
        return initialWorkingDirectory
    }

    // MARK: - Lifecycle & Configuration

    public func reloadConfiguration() {
        guard !isTornDown else { return }
        let (userConfig, resolvedPath) = SiqiUserConfig.load()
        let configSource = Self.makeConfigSource(filePath: resolvedPath)
        _ = state.controller.updateConfigSource(configSource)

        let theme = Self.buildTerminalTheme(userConfig: userConfig)
        _ = state.setTheme(theme)

        let config = Self.buildTerminalConfiguration(userConfig: userConfig)
        _ = state.setTerminalConfiguration(config)
        objectWillChange.send()
    }

    public func tearDown() {
        guard !isTornDown else { return }
        let finalDir = refreshWorkingDirectory()
        lastKnownDirectory = finalDir
        DirectoryStore.saveLastWorkingDirectory(finalDir)

        isTornDown = true
        pauseCwdMonitor()
        hoveredDisplayPath = nil
        terminalView.toolTip = nil

        state.onClose = nil
        cancellables.removeAll()
        onFocused = nil
        onClosed = nil

        surfaceDelegate?.detach()
        surfaceDelegate = nil

        terminalView.onActivateSession = nil
        terminalView.shouldHandOffContextClick = nil
        terminalView.contextMenuBuilder = nil
        _ = state.surface?.performBindingAction("close_surface")
        terminalView.delegate = nil
        terminalView.controller = nil
        terminalView.removeFromSuperview()
    }

    public func restart() {
        let currentCwd = fullDirectory
        isTornDown = false
        state.onClose = nil
        hoveredDisplayPath = nil
        terminalView.toolTip = nil
        surfaceDelegate?.detach()

        let newState = Self.buildTerminalViewState(workingDirectory: currentCwd)
        state = newState
        let newDelegate = SiqiSurfaceDelegate(state: newState, session: self)
        surfaceDelegate = newDelegate

        wireTerminalView(viewDelegate: newDelegate)
        bindState()
        resumeCwdMonitor(forceUpdate: false)
    }

    public func send(_ text: String) {
        _ = state.send(text)
    }

    public func clearScreen() {
        _ = state.performBindingAction("clear_screen")
    }

    public static func makeConfigSource(filePath: String?) -> TerminalController.ConfigSource {
        guard let filePath,
              let sanitized = SiqiConfigStore.rawGhosttyCompatibleContent(from: URL(fileURLWithPath: filePath)) else {
            return .none
        }
        return .generated(sanitized)
    }

    public static func buildTerminalConfiguration(
        userConfig: SiqiUserConfig,
        workingDirectory: String? = nil
    ) -> TerminalConfiguration {
        let cursorStyle: TerminalCursorStyle
        switch userConfig.cursorStyle {
        case "block": cursorStyle = .block
        case "underline": cursorStyle = .underline
        default: cursorStyle = .bar
        }

        return TerminalConfiguration { builder in
            builder.withFontSize(Float(userConfig.fontSize))
            builder.withFontFamily(userConfig.fontFamily)
            builder.withCursorStyle(cursorStyle)
            builder.withCursorStyleBlink(userConfig.cursorBlink)

            if userConfig.backgroundOpacityCells {
                builder.withCustom("background-opacity-cells", "true")
                builder.withBackgroundOpacity(userConfig.backgroundOpacity)
            } else {
                builder.withBackgroundOpacity(0)
            }

            if let workingDirectory, !workingDirectory.isEmpty {
                builder.withCustom("working-directory", workingDirectory)
            } else if let cfgDir = userConfig.workingDirectory, !cfgDir.isEmpty {
                builder.withCustom("working-directory", NSString(string: cfgDir).expandingTildeInPath)
            }

            builder.withWindowPaddingX(userConfig.windowPaddingX)
            builder.withWindowPaddingY(userConfig.windowPaddingY)
            builder.withCustom("window-padding-balance", "false")
            builder.withCustom("window-padding-color", "extend")

            builder.withFontThicken(userConfig.fontThicken)
            builder.withCustom("copy-on-select", userConfig.copyOnSelect ? "clipboard" : "false")

            if !userConfig.shellIntegration.isEmpty {
                builder.withCustom("shell-integration", userConfig.shellIntegration)
            }
            if userConfig.adjustCellHeight != 0 {
                builder.withCustom("adjust-cell-height", "\(userConfig.adjustCellHeight)")
            }
            if userConfig.mouseScrollMultiplier != 1.0 {
                builder.withCustom("mouse-scroll-multiplier", "\(userConfig.mouseScrollMultiplier)")
            }
            if let cmd = userConfig.command, !cmd.isEmpty {
                builder.withCustom("command", cmd)
            }
            if let bg = userConfig.background, !bg.isEmpty {
                builder.withBackground("#\(bg)")
            }
            if let fg = userConfig.foreground, !fg.isEmpty {
                builder.withForeground("#\(fg)")
            }
            for feature in userConfig.fontFeatures {
                builder.withCustom("font-feature", feature)
            }
            for opt in userConfig.extraGhosttyOptions {
                builder.withCustom(opt.key, opt.value)
            }

            builder.withCustom("keybind", "super+c=copy_to_clipboard")
            builder.withCustom("keybind", "super+a=select_all")
        }
    }

    public static func buildTerminalTheme(userConfig: SiqiUserConfig) -> TerminalTheme {
        let cleanBg = userConfig.background?.trimmingCharacters(in: CharacterSet(charactersIn: "#\"' "))
        let cleanFg = userConfig.foreground?.trimmingCharacters(in: CharacterSet(charactersIn: "#\"' "))

        guard let themeDef = GhosttyThemeCatalog.theme(named: userConfig.themeName) else {
            let defConfig = TerminalConfiguration { builder in
                if userConfig.backgroundOpacityCells {
                    builder.withCustom("background-opacity-cells", "true")
                    builder.withBackgroundOpacity(userConfig.backgroundOpacity)
                } else {
                    builder.withBackgroundOpacity(0)
                }
                if let cleanBg, !cleanBg.isEmpty {
                    builder.withBackground("#\(cleanBg)")
                }
                if let cleanFg, !cleanFg.isEmpty {
                    builder.withForeground("#\(cleanFg)")
                }
            }
            return TerminalTheme(light: defConfig, dark: defConfig)
        }

        let baseConfig = themeDef.toTerminalConfiguration()
        let customConfig = TerminalConfiguration(startingFrom: baseConfig) { builder in
            if userConfig.backgroundOpacityCells {
                builder.withCustom("background-opacity-cells", "true")
                builder.withBackgroundOpacity(userConfig.backgroundOpacity)
            } else {
                builder.withBackgroundOpacity(0)
            }
            if let cleanBg, !cleanBg.isEmpty {
                builder.withBackground("#\(cleanBg)")
            }
            if let cleanFg, !cleanFg.isEmpty {
                builder.withForeground("#\(cleanFg)")
            }
        }
        return TerminalTheme(light: customConfig, dark: customConfig)
    }

    public static func buildTerminalViewState(workingDirectory: String) -> TerminalViewState {
        let (userConfig, resolvedPath) = SiqiUserConfig.load()
        let resolvedDir: String = {
            if workingDirectory.isEmpty || workingDirectory == "~" {
                return NSHomeDirectory()
            }
            return NSString(string: workingDirectory).expandingTildeInPath
        }()

        let theme = buildTerminalTheme(userConfig: userConfig)
        let config = buildTerminalConfiguration(userConfig: userConfig, workingDirectory: resolvedDir)
        let configSource = makeConfigSource(filePath: resolvedPath)

        let viewState = TerminalViewState(
            configSource: configSource,
            theme: theme,
            terminalConfiguration: config
        )

        viewState.configuration = TerminalSurfaceOptions(
            backend: .exec,
            workingDirectory: resolvedDir,
            envVars: [
                "TERM_PROGRAM": "siqi",
                "TERM_PROGRAM_VERSION": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
            ]
        )

        return viewState
    }
}
