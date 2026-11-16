import AppKit
import Combine
import SwiftUI

@MainActor
public final class SiqiWindowModel: ObservableObject {
    @Published public private(set) var tabs: [SiqiTab] = []
    @Published public var activeTabId: UUID?
    @Published public var isSearching: Bool = false
    @Published public var isPinned: Bool = false

    public var onCloseWindowRequested: (() -> Void)?
    public var onRestoreCapsuleRequested: (() -> Void)?
    public var onToggleCapsuleRequested: (() -> Void)?

    public var sessions: [SiqiTerminalSession] {
        tabs.flatMap { $0.allSessions }
    }

    public var activeTab: SiqiTab? {
        guard let activeTabId else { return tabs.first }
        return tabs.first { $0.id == activeTabId } ?? tabs.first
    }

    public var activeSession: SiqiTerminalSession? {
        activeTab?.activeSession
    }

    public var activeSessionId: UUID? {
        get { activeTab?.activeSessionId }
        set {
            if let val = newValue {
                activeTab?.activeSessionId = val
            }
        }
    }

    public var activeIndex: Int {
        guard let activeTabId else { return 0 }
        return tabs.firstIndex { $0.id == activeTabId } ?? 0
    }

    public init(initialWorkingDirectory: String? = nil) {
        let dir = DirectoryStore.resolvedInitialWorkingDirectory(explicit: initialWorkingDirectory)
        let session = SiqiTerminalSession(workingDirectory: dir)
        let tab = SiqiTab(session: session)
        self.tabs = [tab]
        self.activeTabId = tab.id
        attachSessionCallbacks(session)
    }

    public init(withTab tab: SiqiTab) {
        self.tabs = [tab]
        self.activeTabId = tab.id
        for session in tab.allSessions {
            attachSessionCallbacks(session)
        }
    }

    public init(tabs: [SiqiTab], activeTabId: UUID?) {
        self.tabs = tabs
        self.activeTabId = activeTabId ?? tabs.first?.id
        for tab in tabs {
            tab.observeAllSessions()
            for session in tab.allSessions {
                attachSessionCallbacks(session)
            }
        }
    }

    private func attachSessionCallbacks(_ session: SiqiTerminalSession) {
        session.onFocused = { [weak self, weak session] in
            guard let self, let session else { return }
            self.selectSession(id: session.id)
        }
        session.onClosed = { [weak self, weak session] in
            guard let self, let session else { return }
            _ = self.closeSession(id: session.id)
        }
    }

    // MARK: - Search

    public func beginSearch() {
        isSearching = true
        _ = activeSession?.terminalView.startSearch()
    }

    public func endSearch() {
        isSearching = false
        _ = activeSession?.terminalView.endSearch()
        focusActiveSession()
    }

    public func toggleSearch() {
        if isSearching {
            endSearch()
        } else {
            beginSearch()
        }
    }

    // MARK: - Live Session Recovery (Quick Terminal)

    /// Ensures the window model has at least one live (non-torn-down) terminal session.
    public func ensureLiveSession() {
        let hasLive = tabs.contains { tab in
            tab.allSessions.contains { !$0.isTornDown }
        }
        if hasLive {
            focusActiveSession()
            return
        }
        tearDownAllSessions()
        let session = SiqiTerminalSession(workingDirectory: DirectoryStore.resolvedInitialWorkingDirectory())
        attachSessionCallbacks(session)
        let tab = SiqiTab(session: session)
        tabs = [tab]
        activeTabId = tab.id
        focusActiveSession()
    }

    // MARK: - Focus & Timers

    public func synchronizeSessionTimers() {
        guard let currentTab = activeTab else { return }
        for tab in tabs {
            if tab.id == currentTab.id {
                for session in tab.allSessions {
                    session.resumeCwdMonitor(forceUpdate: true)
                }
            } else {
                for session in tab.allSessions {
                    session.pauseCwdMonitor()
                }
            }
        }
    }

    public func focusActiveSession() {
        synchronizeSessionTimers()
        DispatchQueue.main.async { [weak self] in
            guard let session = self?.activeSession else { return }
            session.terminalView.window?.makeFirstResponder(session.terminalView)
        }
    }

    // MARK: - Tabs & Panes

    @discardableResult
    public func closeSession(id: UUID) -> Bool {
        objectWillChange.send()
        for tab in tabs {
            if tab.allSessions.contains(where: { $0.id == id }) {
                tab.objectWillChange.send()
                let hasPanesRemaining = tab.closeSession(id: id)
                if !hasPanesRemaining {
                    return closeTab(id: tab.id)
                }
                focusActiveSession()
                SiqiWindowManager.shared.scheduleSaveWindowState()
                return true
            }
        }
        return false
    }

    @discardableResult
    public func createNewTab(workingDirectory: String? = nil) -> SiqiTerminalSession {
        objectWillChange.send()
        let initialDir = DirectoryStore.resolvedInitialWorkingDirectory(
            explicit: workingDirectory ?? activeSession?.fullDirectory
        )
        let session = SiqiTerminalSession(workingDirectory: initialDir)
        attachSessionCallbacks(session)
        let tab = SiqiTab(session: session)
        tabs.append(tab)
        activeTabId = tab.id
        focusActiveSession()
        SiqiWindowManager.shared.scheduleSaveWindowState()
        return session
    }

    @discardableResult
    public func splitRight(workingDirectory: String? = nil) -> SiqiTerminalSession {
        splitActivePane(axis: .horizontal, workingDirectory: workingDirectory)
    }

    @discardableResult
    public func splitDown(workingDirectory: String? = nil) -> SiqiTerminalSession {
        splitActivePane(axis: .vertical, workingDirectory: workingDirectory)
    }

    @discardableResult
    public func splitTab(id tabId: UUID, axis: Axis) -> SiqiTerminalSession? {
        guard let tab = tabs.first(where: { $0.id == tabId }) else { return nil }
        activeTabId = tabId
        return splitActivePane(axis: axis, workingDirectory: tab.activeSession?.fullDirectory)
    }

    @discardableResult
    public func splitActivePane(axis: Axis, workingDirectory: String? = nil) -> SiqiTerminalSession {
        objectWillChange.send()
        let initialDir = DirectoryStore.resolvedInitialWorkingDirectory(
            explicit: workingDirectory ?? activeSession?.fullDirectory
        )
        let session = SiqiTerminalSession(workingDirectory: initialDir)
        attachSessionCallbacks(session)

        if let currentTab = activeTab {
            currentTab.objectWillChange.send()
            currentTab.splitActive(axis: axis, newSession: session)
        } else {
            let tab = SiqiTab(session: session)
            tabs.append(tab)
            activeTabId = tab.id
        }
        focusActiveSession()
        SiqiWindowManager.shared.scheduleSaveWindowState()
        return session
    }

    @discardableResult
    public func closeActiveSession() -> Bool {
        objectWillChange.send()
        guard let currentTab = activeTab else {
            onCloseWindowRequested?()
            return false
        }

        currentTab.objectWillChange.send()
        let currentSessionId = currentTab.activeSessionId
        let hasPanesRemaining = currentTab.closeSession(id: currentSessionId)

        if !hasPanesRemaining {
            return closeTab(id: currentTab.id)
        }
        focusActiveSession()
        SiqiWindowManager.shared.scheduleSaveWindowState()
        return true
    }

    public func tearDownAllSessions() {
        for tab in tabs {
            for session in tab.allSessions {
                session.tearDown()
            }
        }
        tabs.removeAll()
    }

    public static func needsCloseConfirmation(config: SiqiUserConfig, runningProcessNames: [String]) -> Bool {
        config.confirmCloseSurface && !runningProcessNames.isEmpty
    }

    public func closeSessionWithConfirmation(id: UUID, in window: NSWindow?) {
        guard let session = sessions.first(where: { $0.id == id }) else {
            _ = closeSession(id: id)
            return
        }

        let (config, _) = SiqiUserConfig.load()
        if config.confirmCloseSurface, session.hasActiveProcess, let proc = session.activeProcessName {
            let alert = NSAlert()
            alert.messageText = "Close session running '\(proc)'?"
            alert.informativeText = "Closing this session will terminate the running process."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Close")
            alert.addButton(withTitle: "Cancel")

            if let window {
                alert.beginSheetModal(for: window) { [weak self] response in
                    if response == .alertFirstButtonReturn {
                        _ = self?.closeSession(id: id)
                    }
                }
                return
            }
        }

        _ = closeSession(id: id)
    }

    public func closeActiveSessionWithConfirmation(in window: NSWindow?) {
        guard let session = activeSession else {
            _ = closeActiveSession()
            return
        }
        closeSessionWithConfirmation(id: session.id, in: window)
    }

    public func closeTabWithConfirmation(id: UUID, in window: NSWindow?) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }

        let (config, _) = SiqiUserConfig.load()
        if config.confirmCloseSurface {
            let running = tab.allSessions.filter { $0.hasActiveProcess }
            if let first = running.first, let proc = first.activeProcessName {
                let alert = NSAlert()
                alert.messageText = "Close tab running '\(proc)'?"
                alert.informativeText = "There are active processes running in this tab. Closing it will terminate them."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Close Tab")
                alert.addButton(withTitle: "Cancel")

                if let window {
                    alert.beginSheetModal(for: window) { [weak self] response in
                        if response == .alertFirstButtonReturn {
                            _ = self?.closeTab(id: id)
                        }
                    }
                    return
                }
            }
        }

        _ = closeTab(id: id)
    }

    public func closeOtherTabs(keeping tabId: UUID) {
        objectWillChange.send()
        let tabsToClose = tabs.filter { $0.id != tabId }
        tabs.removeAll { $0.id != tabId }
        for tab in tabsToClose {
            for session in tab.allSessions {
                session.tearDown()
            }
        }
        activeTabId = tabId
        focusActiveSession()
        SiqiWindowManager.shared.scheduleSaveWindowState()
    }

    public func closeOtherTabsWithConfirmation(keeping tabId: UUID, in window: NSWindow?) {
        let (config, _) = SiqiUserConfig.load()
        let otherTabs = tabs.filter { $0.id != tabId }
        if config.confirmCloseSurface {
            let running = otherTabs.flatMap { $0.allSessions }.filter { $0.hasActiveProcess }
            if let first = running.first, let proc = first.activeProcessName {
                let alert = NSAlert()
                alert.messageText = "Close other tabs running '\(proc)'?"
                alert.informativeText = "There are active processes running in other tabs. Closing them will terminate those processes."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Close Other Tabs")
                alert.addButton(withTitle: "Cancel")
                if let window {
                    alert.beginSheetModal(for: window) { [weak self] response in
                        if response == .alertFirstButtonReturn {
                            self?.closeOtherTabs(keeping: tabId)
                        }
                    }
                    return
                }
            }
        }
        closeOtherTabs(keeping: tabId)
    }

    @discardableResult
    public func closeTab(id: UUID) -> Bool {
        objectWillChange.send()
        guard tabs.count > 1 else {
            if let onlyTab = tabs.first {
                for session in onlyTab.allSessions {
                    _ = session.refreshWorkingDirectory()
                }
            }
            SiqiWindowManager.shared.saveWindowState()
            if let onlyTab = tabs.first {
                for session in onlyTab.allSessions {
                    session.tearDown()
                }
            }
            onCloseWindowRequested?()
            return false
        }

        if let index = tabs.firstIndex(where: { $0.id == id }) {
            let tab = tabs.remove(at: index)
            for session in tab.allSessions {
                session.tearDown()
            }
            if activeTabId == id {
                let newIndex = max(0, min(index, tabs.count - 1))
                activeTabId = tabs[newIndex].id
            }
            focusActiveSession()
            SiqiWindowManager.shared.scheduleSaveWindowState()
        }
        return true
    }

    public func selectTab(id: UUID) {
        if tabs.contains(where: { $0.id == id }) {
            activeTabId = id
            focusActiveSession()
            SiqiWindowManager.shared.scheduleSaveWindowState()
        }
    }

    public func selectTab(at index: Int) {
        guard index >= 0, index < tabs.count else { return }
        activeTabId = tabs[index].id
        focusActiveSession()
        SiqiWindowManager.shared.scheduleSaveWindowState()
    }

    public func selectSession(id: UUID) {
        for tab in tabs where tab.allSessions.contains(where: { $0.id == id }) {
            activeTabId = tab.id
            tab.activeSessionId = id
            focusActiveSession()
            return
        }
    }

    public func nextTab() {
        guard !tabs.isEmpty else { return }
        let next = (activeIndex + 1) % tabs.count
        activeTabId = tabs[next].id
        focusActiveSession()
    }

    public func previousTab() {
        guard !tabs.isEmpty else { return }
        let prev = (activeIndex - 1 + tabs.count) % tabs.count
        activeTabId = tabs[prev].id
        focusActiveSession()
    }

    public func nextPane() {
        guard let currentTab = activeTab else { return }
        let all = currentTab.allSessions
        guard all.count > 1, let idx = all.firstIndex(where: { $0.id == currentTab.activeSessionId }) else { return }
        currentTab.activeSessionId = all[(idx + 1) % all.count].id
        focusActiveSession()
    }

    public func previousPane() {
        guard let currentTab = activeTab else { return }
        let all = currentTab.allSessions
        guard all.count > 1, let idx = all.firstIndex(where: { $0.id == currentTab.activeSessionId }) else { return }
        currentTab.activeSessionId = all[(idx - 1 + all.count) % all.count].id
        focusActiveSession()
    }

    public func restartActiveSession() {
        activeSession?.restart()
    }

    public func clearActiveSession() {
        activeSession?.clearScreen()
    }

    public func reloadAllSessions() {
        for session in sessions {
            session.reloadConfiguration()
        }
    }

    public func updateSplitFraction(splitId: UUID, fraction: CGFloat) {
        activeTab?.updateSplitFraction(splitId: splitId, fraction: fraction)
    }

    public func equalizeSplits() {
        activeTab?.equalizeSplits()
    }

    public func toggleZoom() {
        activeTab?.toggleZoom()
        focusActiveSession()
    }

    public func focusPane(in direction: PaneDirection) {
        activeTab?.focusPane(in: direction)
        focusActiveSession()
    }

    public func moveTab(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex >= 0, sourceIndex < tabs.count,
              destinationIndex >= 0, destinationIndex < tabs.count,
              sourceIndex != destinationIndex else { return }
        objectWillChange.send()
        let tab = tabs.remove(at: sourceIndex)
        tabs.insert(tab, at: destinationIndex)
    }

    public func detachTabToNewWindow(id: UUID, at screenPoint: NSPoint? = nil) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        objectWillChange.send()
        let tab = tabs.remove(at: index)
        if activeTabId == id {
            activeTabId = tabs.first?.id
        }
        SiqiWindowManager.shared.createWindow(withTab: tab, at: screenPoint)
        if tabs.isEmpty {
            onCloseWindowRequested?()
        } else {
            focusActiveSession()
        }
    }

    @discardableResult
    public func removeTabWithoutClosingWindow(id: UUID) -> SiqiTab? {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return nil }
        objectWillChange.send()
        let tab = tabs.remove(at: index)
        if activeTabId == id {
            activeTabId = tabs.first?.id
        }
        if tabs.isEmpty {
            onCloseWindowRequested?()
        } else {
            focusActiveSession()
        }
        return tab
    }

    public func insertTab(_ tab: SiqiTab, at index: Int) {
        objectWillChange.send()
        let targetIndex = max(0, min(index, tabs.count))
        for session in tab.allSessions {
            attachSessionCallbacks(session)
        }
        tab.observeAllSessions()
        tabs.insert(tab, at: targetIndex)
        activeTabId = tab.id
        focusActiveSession()
    }

    // MARK: - Window Occlusion & Pinning

    public func pauseBackgroundRendering() {
        for session in sessions {
            session.terminalView.setSurfaceVisible(false)
            session.pauseCwdMonitor()
        }
    }

    public func resumeBackgroundRendering() {
        for session in sessions {
            session.terminalView.setSurfaceVisible(true)
        }
        synchronizeSessionTimers()
    }

    public func togglePin(in window: NSWindow? = nil) {
        objectWillChange.send()
        isPinned.toggle()
        let target = window ?? activeSession?.terminalView.window ?? NSApp.keyWindow
        if let target {
            target.level = isPinned ? .floating : .normal
            if isPinned {
                target.collectionBehavior.insert(.canJoinAllSpaces)
            } else {
                target.collectionBehavior.remove(.canJoinAllSpaces)
            }
        }
    }
}
