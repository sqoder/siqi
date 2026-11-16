import SwiftUI

public indirect enum SiqiPersistedPane: Codable, Equatable {
    case leaf(cwd: String)
    case split(axis: String, fraction: Double, first: SiqiPersistedPane, second: SiqiPersistedPane)
}

public struct SiqiPersistedTab: Codable, Equatable {
    public var activePaneIndex: Int
    public var root: SiqiPersistedPane

    public init(activePaneIndex: Int, root: SiqiPersistedPane) {
        self.activePaneIndex = activePaneIndex
        self.root = root
    }
}

public struct SiqiPersistedWindow: Codable, Equatable {
    public var frame: [Double]
    public var activeTabIndex: Int
    public var tabs: [SiqiPersistedTab]

    public init(frame: [Double], activeTabIndex: Int, tabs: [SiqiPersistedTab]) {
        self.frame = frame
        self.activeTabIndex = activeTabIndex
        self.tabs = tabs
    }
}

public struct SiqiPersistedState: Codable, Equatable {
    public var windows: [SiqiPersistedWindow]

    public init(windows: [SiqiPersistedWindow]) {
        self.windows = windows
    }
}

public enum SiqiWindowStateStore {
    public static var filePath: String {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return (NSTemporaryDirectory() as NSString).appendingPathComponent("siqi-test-window-state.json")
        }
        return NSString(string: "~/.cache/siqi/window-state.json").expandingTildeInPath
    }

    public static func save(_ state: SiqiPersistedState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        let dir = (filePath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? data.write(to: URL(fileURLWithPath: filePath), options: .atomic)
    }

    public static func clear() {
        try? FileManager.default.removeItem(atPath: filePath)
    }

    public static func load() -> SiqiPersistedState? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)) else { return nil }
        return try? JSONDecoder().decode(SiqiPersistedState.self, from: data)
    }

    public static func usableDirectory(_ path: String) -> String {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return NSHomeDirectory()
        }
        return path
    }
}

@MainActor
extension SiqiPersistedPane {
    init(node: PaneNode) {
        switch node {
        case .terminal(let session):
            self = .leaf(cwd: session.refreshWorkingDirectory())
        case .split(_, let axis, let fraction, let first, let second):
            self = .split(
                axis: axis == .horizontal ? "horizontal" : "vertical",
                fraction: Double(fraction),
                first: SiqiPersistedPane(node: first),
                second: SiqiPersistedPane(node: second)
            )
        }
    }

    func buildNode() -> PaneNode {
        switch self {
        case .leaf(let cwd):
            return .terminal(SiqiTerminalSession(workingDirectory: SiqiWindowStateStore.usableDirectory(cwd)))
        case .split(let axis, let fraction, let first, let second):
            return .split(
                id: UUID(),
                axis: axis == "vertical" ? .vertical : .horizontal,
                fraction: CGFloat(fraction),
                first: first.buildNode(),
                second: second.buildNode()
            )
        }
    }
}
