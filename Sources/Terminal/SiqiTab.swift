import Combine
import SwiftUI

@MainActor
public final class SiqiTab: ObservableObject, Identifiable {
    public let id: UUID
    @Published public var rootPane: PaneNode
    @Published public var activeSessionId: UUID
    @Published public var isZoomed: Bool = false
    @Published public var paneVersion: Int = 0
    private var sessionObservers: [UUID: AnyCancellable] = [:]

    public init(session: SiqiTerminalSession) {
        self.id = UUID()
        self.rootPane = .terminal(session)
        self.activeSessionId = session.id
        observeSession(session)
    }

    public init(rootPane: PaneNode, activeSessionId: UUID) {
        self.id = UUID()
        self.rootPane = rootPane
        self.activeSessionId = activeSessionId
        observeAllSessions()
    }

    public var title: String {
        activeSession?.title ?? "zsh"
    }

    public var displayDirectory: String {
        activeSession?.displayDirectory ?? "~"
    }

    public var displayPathFormatted: String {
        activeSession?.displayPathFormatted ?? "~"
    }

    public var tabDisplayTitle: String {
        activeSession?.tabDisplayTitle ?? displayDirectory
    }

    public var hasActiveProcess: Bool {
        allSessions.contains { $0.hasActiveProcess }
    }

    public var activeSession: SiqiTerminalSession? {
        rootPane.findSession(id: activeSessionId) ?? rootPane.allSessions.first
    }

    public var allSessions: [SiqiTerminalSession] {
        rootPane.allSessions
    }

    public func splitActive(axis: Axis, newSession: SiqiTerminalSession) {
        let targetId = (rootPane.findSession(id: activeSessionId) != nil)
            ? activeSessionId
            : (rootPane.allSessions.first?.id ?? activeSessionId)
        rootPane = rootPane.split(targetSessionId: targetId, axis: axis, newSession: newSession)
        activeSessionId = newSession.id
        isZoomed = false
        paneVersion += 1
        observeSession(newSession)
    }

    private func observeSession(_ session: SiqiTerminalSession) {
        guard sessionObservers[session.id] == nil else { return }
        sessionObservers[session.id] = session.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    public func observeAllSessions() {
        for session in allSessions {
            observeSession(session)
        }
    }

    public func closeSession(id: UUID) -> Bool {
        sessionObservers.removeValue(forKey: id)
        guard let session = rootPane.findSession(id: id) else {
            return !rootPane.allSessions.isEmpty
        }
        session.tearDown()
        guard let newRoot = rootPane.remove(sessionId: id) else { return false }
        rootPane = newRoot
        if activeSessionId == id {
            activeSessionId = rootPane.allSessions.first?.id ?? UUID()
        }
        if rootPane.allSessions.count <= 1 {
            isZoomed = false
        }
        paneVersion += 1
        return true
    }

    public func updateSplitFraction(splitId: UUID, fraction: CGFloat) {
        rootPane = rootPane.updatingFraction(splitId: splitId, fraction: fraction)
    }

    public func equalizeSplits() {
        rootPane = rootPane.equalized()
        isZoomed = false
        paneVersion += 1
    }

    public func toggleZoom() {
        if isZoomed {
            isZoomed = false
        } else if rootPane.allSessions.count > 1 {
            isZoomed = true
        }
    }

    public func focusPane(in direction: PaneDirection) {
        if isZoomed { isZoomed = false }
        let frames = rootPane.computeNormalizedFrames()
        guard let current = frames.first(where: { $0.0 == activeSessionId }) else { return }
        let curFrame = current.1

        var bestTarget: UUID?
        var bestScore: CGFloat = .greatestFiniteMagnitude

        for (id, frame) in frames where id != activeSessionId {
            let primaryGap: CGFloat
            let perpOverlap: CGFloat
            let centerDist: CGFloat

            switch direction {
            case .left:
                guard frame.maxX <= curFrame.minX + 0.001 else { continue }
                primaryGap = curFrame.minX - frame.maxX
                perpOverlap = max(0, min(curFrame.maxY, frame.maxY) - max(curFrame.minY, frame.minY))
                centerDist = abs(frame.midY - curFrame.midY)
            case .right:
                guard frame.minX >= curFrame.maxX - 0.001 else { continue }
                primaryGap = frame.minX - curFrame.maxX
                perpOverlap = max(0, min(curFrame.maxY, frame.maxY) - max(curFrame.minY, frame.minY))
                centerDist = abs(frame.midY - curFrame.midY)
            case .up:
                guard frame.maxY <= curFrame.minY + 0.001 else { continue }
                primaryGap = curFrame.minY - frame.maxY
                perpOverlap = max(0, min(curFrame.maxX, frame.maxX) - max(curFrame.minX, frame.minX))
                centerDist = abs(frame.midX - curFrame.midX)
            case .down:
                guard frame.minY >= curFrame.maxY - 0.001 else { continue }
                primaryGap = frame.minY - curFrame.maxY
                perpOverlap = max(0, min(curFrame.maxX, frame.maxX) - max(curFrame.minX, frame.minX))
                centerDist = abs(frame.midX - curFrame.midX)
            }

            let score = primaryGap * 10 - perpOverlap * 5 + centerDist
            if score < bestScore {
                bestScore = score
                bestTarget = id
            }
        }

        if let target = bestTarget {
            activeSessionId = target
        }
    }
}
