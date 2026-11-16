import Darwin
import Foundation

public struct ChildProcessInfo {
    public let name: String?
    public let cwd: String?

    public init(name: String?, cwd: String?) {
        self.name = name
        self.cwd = cwd
    }
}

/// Direct kernel inspection of foreground processes and working directories.
public enum ProcessInspector {
    private static let shellProcessNames: Set<String> = [
        "zsh", "bash", "fish", "sh", "tcsh", "csh", "ksh", "login",
        "-zsh", "-bash", "-fish", "siqi", "ghostty",
    ]

    private static func directWorkingDirectory(for pid: pid_t) -> String? {
        guard pid > 0 else { return nil }
        var vpi = proc_vnodepathinfo()
        let size = MemoryLayout<proc_vnodepathinfo>.stride
        let result = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vpi, Int32(size))
        guard result == size else { return nil }
        return withUnsafePointer(to: &vpi.pvi_cdir.vip_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { cStr in
                let path = String(cString: cStr).trimmingCharacters(in: .whitespacesAndNewlines)
                return path.isEmpty ? nil : path
            }
        }
    }

    public static func currentWorkingDirectory(for pid: pid_t, maxDepth: Int = 4) -> String? {
        if let direct = directWorkingDirectory(for: pid) {
            return direct
        }
        guard pid > 0, maxDepth > 0 else { return nil }
        for child in childPids(for: pid).reversed() {
            if let childDir = currentWorkingDirectory(for: child, maxDepth: maxDepth - 1) {
                return childDir
            }
        }
        return nil
    }

    public static func childPids(for parentPid: pid_t) -> [pid_t] {
        let count = proc_listchildpids(parentPid, nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count))
        let actual = proc_listchildpids(parentPid, &pids, count * Int32(MemoryLayout<pid_t>.stride))
        guard actual > 0 else { return [] }
        return Array(pids.prefix(Int(actual)))
    }

    public static func processName(for pid: pid_t) -> String? {
        guard pid > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: 256)
        let ret = proc_name(pid, &buf, 256)
        guard ret > 0 else { return nil }
        let name = String(cString: buf).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    public static func findLatestChildInfo(for parentPid: pid_t = getpid(), maxDepth: Int = 6) -> ChildProcessInfo? {
        var name: String?
        var cwd: String?

        func search(pid: pid_t, depth: Int) -> Bool {
            guard depth <= maxDepth else { return false }
            for child in childPids(for: pid).reversed() {
                if name == nil, let rawName = processName(for: child) {
                    let clean = rawName.lowercased()
                    if !clean.isEmpty && !shellProcessNames.contains(clean) {
                        name = rawName
                    }
                }
                if cwd == nil, let found = currentWorkingDirectory(for: child), !found.isEmpty {
                    cwd = found
                }
                if name != nil && cwd != nil { return true }
                if search(pid: child, depth: depth + 1) { return true }
            }
            return false
        }

        _ = search(pid: parentPid, depth: 1)
        guard name != nil || cwd != nil else { return nil }
        return ChildProcessInfo(name: name, cwd: cwd)
    }

    public static func hasDescendantProcess(
        for parentPid: pid_t = getpid(),
        matching keywords: Set<String>,
        maxDepth: Int = 6
    ) -> Bool {
        func search(pid: pid_t, depth: Int) -> Bool {
            guard depth <= maxDepth else { return false }
            for child in childPids(for: pid) {
                if let rawName = processName(for: child)?.lowercased(),
                   keywords.contains(where: { rawName.contains($0) }) {
                    return true
                }
                if search(pid: child, depth: depth + 1) {
                    return true
                }
            }
            return false
        }
        return search(pid: parentPid, depth: 1)
    }

    public static func hasRunningNonShellChild(for foregroundPid: pid_t?) -> Bool {
        if let pid = foregroundPid, pid > 0 {
            if let name = processName(for: pid)?.lowercased(),
               !name.isEmpty,
               !shellProcessNames.contains(name) {
                return true
            }
            if !childPids(for: pid).isEmpty {
                return true
            }
        }
        return false
    }
}
