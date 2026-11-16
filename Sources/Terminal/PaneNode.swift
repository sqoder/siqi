import SwiftUI

public enum PaneDirection {
    case left
    case right
    case up
    case down
}

/// Recursive binary split-pane layout tree inside a tab.
public enum PaneNode: Identifiable, Equatable {
    case terminal(SiqiTerminalSession)
    indirect case split(id: UUID, axis: Axis, fraction: CGFloat, first: PaneNode, second: PaneNode)

    public var id: UUID {
        switch self {
        case .terminal(let session):
            return session.id
        case .split(let id, _, _, _, _):
            return id
        }
    }

    public static func == (lhs: PaneNode, rhs: PaneNode) -> Bool {
        switch (lhs, rhs) {
        case (.terminal(let s1), .terminal(let s2)):
            return s1.id == s2.id
        case (.split(let id1, let axis1, let frac1, let f1, let s1),
              .split(let id2, let axis2, let frac2, let f2, let s2)):
            return id1 == id2 && axis1 == axis2 && abs(frac1 - frac2) < 0.0001 && f1 == f2 && s1 == s2
        default:
            return false
        }
    }

    public var allSessions: [SiqiTerminalSession] {
        switch self {
        case .terminal(let session):
            return [session]
        case .split(_, _, _, let first, let second):
            return first.allSessions + second.allSessions
        }
    }

    public func findSession(id: UUID) -> SiqiTerminalSession? {
        switch self {
        case .terminal(let s):
            return s.id == id ? s : nil
        case .split(_, _, _, let first, let second):
            return first.findSession(id: id) ?? second.findSession(id: id)
        }
    }

    public func split(targetSessionId: UUID, axis: Axis, newSession: SiqiTerminalSession) -> PaneNode {
        switch self {
        case .terminal(let s):
            if s.id == targetSessionId {
                return .split(id: UUID(), axis: axis, fraction: 0.5, first: .terminal(s), second: .terminal(newSession))
            }
            return self
        case .split(let id, let currentAxis, let fraction, let first, let second):
            let newFirst = first.split(targetSessionId: targetSessionId, axis: axis, newSession: newSession)
            let newSecond = second.split(targetSessionId: targetSessionId, axis: axis, newSession: newSession)
            if newFirst != first || newSecond != second {
                return .split(id: id, axis: currentAxis, fraction: fraction, first: newFirst, second: newSecond)
            }
            return self
        }
    }

    public func remove(sessionId: UUID) -> PaneNode? {
        switch self {
        case .terminal(let s):
            return s.id == sessionId ? nil : self
        case .split(let id, let axis, let fraction, let first, let second):
            let newFirst = first.remove(sessionId: sessionId)
            let newSecond = second.remove(sessionId: sessionId)
            if let newFirst, let newSecond {
                if newFirst != first || newSecond != second {
                    return .split(id: id, axis: axis, fraction: fraction, first: newFirst, second: newSecond)
                }
                return self
            }
            return newFirst ?? newSecond
        }
    }

    public func updatingFraction(splitId: UUID, fraction: CGFloat) -> PaneNode {
        guard !fraction.isNaN, fraction.isFinite else { return self }
        switch self {
        case .terminal:
            return self
        case .split(let id, let axis, let currentFraction, let first, let second):
            if id == splitId {
                let clamped = min(max(fraction, 0.05), 0.95)
                return .split(id: id, axis: axis, fraction: clamped, first: first, second: second)
            }
            let newFirst = first.updatingFraction(splitId: splitId, fraction: fraction)
            let newSecond = second.updatingFraction(splitId: splitId, fraction: fraction)
            if newFirst != first || newSecond != second {
                return .split(id: id, axis: axis, fraction: currentFraction, first: newFirst, second: newSecond)
            }
            return self
        }
    }

    public func equalized() -> PaneNode {
        switch self {
        case .terminal:
            return self
        case .split(let id, let axis, _, let first, let second):
            return .split(id: id, axis: axis, fraction: 0.5, first: first.equalized(), second: second.equalized())
        }
    }

    /// Computes normalized [0, 1] x [0, 1] rects for directional focus navigation.
    public func computeNormalizedFrames(in rect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)) -> [(UUID, CGRect)] {
        switch self {
        case .terminal(let s):
            return [(s.id, rect)]
        case .split(_, let axis, let fraction, let first, let second):
            if axis == .horizontal {
                let w1 = rect.width * fraction
                let r1 = CGRect(x: rect.minX, y: rect.minY, width: w1, height: rect.height)
                let r2 = CGRect(x: rect.minX + w1, y: rect.minY, width: max(0, rect.width - w1), height: rect.height)
                return first.computeNormalizedFrames(in: r1) + second.computeNormalizedFrames(in: r2)
            } else {
                let h1 = rect.height * fraction
                let r1 = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: h1)
                let r2 = CGRect(x: rect.minX, y: rect.minY + h1, width: rect.width, height: max(0, rect.height - h1))
                return first.computeNormalizedFrames(in: r1) + second.computeNormalizedFrames(in: r2)
            }
        }
    }
}
