import AppKit
import Foundation
import GhosttyTheme
import SwiftUI

public typealias GhosttyUserConfig = SiqiUserConfig

public struct SiqiKeybinding: Equatable, Sendable {
    public let key: String
    public let modifiers: Set<String>
    public let action: String

    public init(key: String, modifiers: Set<String>, action: String) {
        self.key = key
        self.modifiers = modifiers
        self.action = action
    }
}

public struct SiqiExtraGhosttyOption: Equatable, Sendable {
    public let key: String
    public let value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

public struct SiqiUserConfig: Equatable, Sendable {
    public var themeName: String = "Catppuccin Mocha"
    public var fontFamily: String = "Maple Mono NF"
    public var fontSize: Double = 13.0
    public var fontThicken: Bool = true
    public var backgroundOpacity: Double = 0.85
    public var backgroundOpacityCells: Bool = false
    public var backgroundBlur: Int = 20
    public var windowPaddingX: Int = 12
    public var windowPaddingY: Int = 8
    public var windowCornerRadius: Double = 16.0
    public var cursorStyle: String = "bar"
    public var cursorBlink: Bool = true
    public var copyOnSelect: Bool = true
    public var adjustCellHeight: Int = 0
    public var macosTitlebarStyle: String = "tabs"
    public var shellIntegration: String = "zsh"
    public var windowSaveState: String = "always"
    public var windowWidth: Int? = nil
    public var windowHeight: Int? = nil
    public var background: String? = nil
    public var foreground: String? = nil
    public var workingDirectory: String? = nil
    public var restoreLastWorkingDirectory: Bool = true
    public var unfocusedSplitOpacity: Double = 1.0
    public var mouseScrollMultiplier: Double = 1.0
    public var command: String? = nil
    public var fontFeatures: [String] = []
    public var confirmCloseSurface: Bool = true
    public var keybindings: [SiqiKeybinding] = []
    public var quickTerminalPosition: String = "top"
    public var quickTerminalScreen: String = "mouse"
    public var quickTerminalAutohide: Bool = true
    public var quickTerminalAnimationDuration: Double = 0.2
    public var quickTerminalSize: String = "50%"
    public var extraGhosttyOptions: [SiqiExtraGhosttyOption] = []

    public static let defaultAiTools: [String] = [
        "agy", "claude", "codex", "opencode", "aider", "gemini", "chatgpt", "llm", "sgpt",
    ]
    public var aiTools: [String] = SiqiUserConfig.defaultAiTools

    /// Keys handled exclusively by Siqi that must be stripped before passing config text to libghostty.
    public static let siqiOnlyKeys: Set<String> = [
        "window-corner-radius",
        "restore-last-working-directory",
        "ai-tools",
        "ai-tool",
        "initial-working-directory",
    ]

    public init() {}

    /// Parses a Ghostty-style `keybind = cmd+shift+e=new_tab` value.
    public static func parseKeybinding(_ value: String) -> SiqiKeybinding? {
        guard let separator = value.lastIndex(of: "=") else { return nil }
        let trigger = value[..<separator]
        let action = value[value.index(after: separator)...].trimmingCharacters(in: .whitespaces)
        guard !trigger.isEmpty, !action.isEmpty else { return nil }

        var modifiers: Set<String> = []
        var key = ""
        for part in trigger.split(separator: "+") {
            switch part.lowercased() {
            case "cmd", "super", "command": modifiers.insert("cmd")
            case "ctrl", "control": modifiers.insert("ctrl")
            case "alt", "opt", "option": modifiers.insert("alt")
            case "shift": modifiers.insert("shift")
            default: key = part.lowercased()
            }
        }
        guard !key.isEmpty else { return nil }
        return SiqiKeybinding(key: key, modifiers: modifiers, action: action)
    }

    public static func parse(content: String, into cfg: inout SiqiUserConfig) {
        for rawLine in content.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            let key = parts[0].lowercased()
            let val = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

            switch key {
            case "theme":
                cfg.themeName = val
            case "font-family":
                cfg.fontFamily = val
            case "font-size":
                if let v = Double(val), v > 0 { cfg.fontSize = v }
            case "font-thicken":
                cfg.fontThicken = (val.lowercased() == "true")
            case "adjust-cell-height":
                if let v = Int(val) { cfg.adjustCellHeight = v }
            case "background-opacity":
                if let v = Double(val) { cfg.backgroundOpacity = max(0.05, min(1.0, v)) }
            case "background-opacity-cells":
                cfg.backgroundOpacityCells = (val.lowercased() == "true")
            case "background-blur":
                if let v = Int(val) { cfg.backgroundBlur = v }
                else if val.lowercased() == "true" { cfg.backgroundBlur = 20 }
            case "window-padding-x":
                let firstVal = val.split(separator: ",").first.map(String.init) ?? val
                if let v = Int(firstVal.trimmingCharacters(in: .whitespaces)) { cfg.windowPaddingX = v }
            case "window-padding-y":
                let firstVal = val.split(separator: ",").first.map(String.init) ?? val
                if let v = Int(firstVal.trimmingCharacters(in: .whitespaces)) { cfg.windowPaddingY = v }
            case "window-corner-radius":
                if let v = Double(val) { cfg.windowCornerRadius = Double(Int(max(0, v).rounded())) }
            case "macos-titlebar-style":
                let normalized = val.lowercased()
                if ["native", "transparent", "tabs", "hidden"].contains(normalized) {
                    cfg.macosTitlebarStyle = normalized
                }
            case "window-save-state":
                cfg.windowSaveState = val
            case "window-width":
                if let v = Int(val) { cfg.windowWidth = v }
            case "window-height":
                if let v = Int(val) { cfg.windowHeight = v }
            case "cursor-style":
                cfg.cursorStyle = val.lowercased()
            case "cursor-style-blink":
                cfg.cursorBlink = (val.lowercased() == "true")
            case "copy-on-select":
                cfg.copyOnSelect = (val.lowercased() == "clipboard" || val.lowercased() == "true")
            case "shell-integration":
                cfg.shellIntegration = val
            case "working-directory", "initial-working-directory":
                cfg.workingDirectory = val.isEmpty ? nil : val
            case "restore-last-working-directory":
                cfg.restoreLastWorkingDirectory = (val.lowercased() == "true")
            case "background":
                let cleaned = val.trimmingCharacters(in: CharacterSet(charactersIn: "#\"' "))
                cfg.background = cleaned.isEmpty ? nil : cleaned
            case "foreground":
                let cleaned = val.trimmingCharacters(in: CharacterSet(charactersIn: "#\"' "))
                cfg.foreground = cleaned.isEmpty ? nil : cleaned
            case "unfocused-split-opacity":
                if let v = Double(val) { cfg.unfocusedSplitOpacity = max(0.0, min(1.0, v)) }
            case "mouse-scroll-multiplier":
                if let v = Double(val) { cfg.mouseScrollMultiplier = max(0.1, min(10.0, v)) }
            case "command":
                let trimmedCmd = val.trimmingCharacters(in: .whitespaces)
                cfg.command = trimmedCmd.isEmpty ? nil : trimmedCmd
            case "font-feature":
                let features = val.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                for f in features where !f.isEmpty {
                    cfg.fontFeatures.append(f)
                }
            case "confirm-close-surface":
                cfg.confirmCloseSurface = (val.lowercased() == "true")
            case "keybind":
                if let binding = Self.parseKeybinding(val) {
                    cfg.keybindings.append(binding)
                }
            case "ai-tools":
                let tools = val.split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                    .filter { !$0.isEmpty }
                if !tools.isEmpty {
                    cfg.aiTools = tools
                }
            case "ai-tool":
                let tool = val.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !tool.isEmpty && !cfg.aiTools.contains(tool) {
                    cfg.aiTools.append(tool)
                }
            case "quick-terminal-position":
                cfg.quickTerminalPosition = val.lowercased()
            case "quick-terminal-screen":
                cfg.quickTerminalScreen = val.lowercased()
            case "quick-terminal-autohide":
                cfg.quickTerminalAutohide = (val.lowercased() == "true")
            case "quick-terminal-animation-duration":
                if let v = Double(val) { cfg.quickTerminalAnimationDuration = max(0, v) }
            case "quick-terminal-size":
                cfg.quickTerminalSize = val
            default:
                if !key.isEmpty && !siqiOnlyKeys.contains(key) {
                    cfg.extraGhosttyOptions.append(SiqiExtraGhosttyOption(key: key, value: val))
                }
            }
        }
    }

    public static func load(from content: String) -> (config: SiqiUserConfig, filePath: String?) {
        var cfg = SiqiUserConfig()
        parse(content: content, into: &cfg)
        return (cfg, nil)
    }

    public static func load(at url: URL = SiqiConfigStore.configFileURL) -> (config: SiqiUserConfig, filePath: String?) {
        SiqiConfigStore.load(from: url)
    }

    public static func saveValues(_ updates: [String: String], at url: URL = SiqiConfigStore.configFileURL) {
        let converted = updates.mapValues { Optional($0) }
        SiqiConfigStore.saveValues(converted, at: url)
    }

    /// Strips Siqi-only extension keys before feeding raw config text to libghostty.
    public static func ghosttyCompatibleContent(from raw: String) -> String {
        var kept: [String] = []
        for rawLine in raw.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !trimmed.hasPrefix("#"),
               let eqIdx = trimmed.firstIndex(of: "=") {
                let key = trimmed[..<eqIdx].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if siqiOnlyKeys.contains(key) {
                    continue
                }
            }
            kept.append(rawLine)
        }
        return kept.joined(separator: "\n")
    }
}

public enum SiqiConfigStore {
    public static var configDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("siqi", isDirectory: true)
    }

    public static var configFileURL: URL {
        configDirectoryURL.appendingPathComponent("config")
    }

    public static var ghosttyFallbackConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("ghostty", isDirectory: true)
            .appendingPathComponent("config")
    }

    public static var configPath: String {
        configFileURL.path
    }

    private static var cache: (config: SiqiUserConfig, filePath: String, mtime: Date, size: UInt64)?
    private static let cacheLock = NSLock()

    public static func invalidateCache() {
        cacheLock.lock()
        cache = nil
        cacheLock.unlock()
    }

    public static func load(from url: URL = configFileURL, fallbackURL: URL? = nil) -> (config: SiqiUserConfig, filePath: String?) {
        var cfg = SiqiUserConfig()
        let resolvedFallback = fallbackURL ?? (url == configFileURL ? ghosttyFallbackConfigURL : nil)
        let effectiveURL: URL
        if FileManager.default.fileExists(atPath: url.path) {
            effectiveURL = url
        } else if let resolvedFallback, FileManager.default.fileExists(atPath: resolvedFallback.path) {
            effectiveURL = resolvedFallback
        } else {
            return (cfg, nil)
        }

        let path = effectiveURL.path
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let mtime = attrs[.modificationDate] as? Date,
              let size = attrs[.size] as? UInt64 else {
            return (cfg, nil)
        }

        cacheLock.lock()
        let cached = Self.cache
        cacheLock.unlock()
        if let cached, cached.filePath == path, cached.mtime == mtime, cached.size == size {
            return (cached.config, path)
        }

        guard let content = try? String(contentsOf: effectiveURL, encoding: .utf8) else {
            return (cfg, nil)
        }

        SiqiUserConfig.parse(content: content, into: &cfg)

        cacheLock.lock()
        Self.cache = (cfg, path, mtime, size)
        cacheLock.unlock()
        return (cfg, path)
    }

    public static func rawGhosttyCompatibleContent(from url: URL = configFileURL) -> String? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let base = SiqiUserConfig.ghosttyCompatibleContent(from: content)
        return base
            .components(separatedBy: .newlines)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#"),
                      let eqIdx = trimmed.firstIndex(of: "=") else {
                    return true
                }
                let key = trimmed[..<eqIdx].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return key != "theme"
            }
            .joined(separator: "\n")
    }

    @discardableResult
    public static func ensureConfigFileExists(at url: URL = configFileURL) -> URL {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        if !fm.fileExists(atPath: url.path) {
            if url == configFileURL,
               fm.fileExists(atPath: ghosttyFallbackConfigURL.path),
               let ghosttyContent = try? String(contentsOf: ghosttyFallbackConfigURL, encoding: .utf8) {
                try? ghosttyContent.write(to: url, atomically: true, encoding: .utf8)
            } else {
                let starter = """
                # Siqi Terminal Configuration
                # Uses Ghostty key = value syntax.

                theme = Catppuccin Mocha
                font-family = Maple Mono NF
                font-size = 13
                macos-titlebar-style = tabs
                window-corner-radius = 16
                """
                try? starter.write(to: url, atomically: true, encoding: .utf8)
            }
            invalidateCache()
        }
        return url
    }

    /// Updates or removes (`nil` value) keys in ~/.config/siqi/config.
    public static func saveValues(_ updates: [String: String?], at url: URL = configFileURL) {
        ensureConfigFileExists(at: url)

        var lines: [String] = []
        if let content = try? String(contentsOf: url, encoding: .utf8) {
            lines = content.components(separatedBy: .newlines)
        }

        var normalizedUpdates: [String: (originalKey: String, value: String?)] = [:]
        for (key, value) in updates {
            normalizedUpdates[key.lowercased()] = (key, value)
        }

        var handled: Set<String> = []
        var resultLines: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty && !trimmed.hasPrefix("#"),
               let eqIdx = trimmed.firstIndex(of: "=") {
                let lineKey = trimmed[..<eqIdx].trimmingCharacters(in: .whitespaces).lowercased()
                if let entry = normalizedUpdates[lineKey] {
                    if let value = entry.value, !handled.contains(lineKey) {
                        resultLines.append("\(entry.originalKey) = \(value)")
                        handled.insert(lineKey)
                    }
                    // Skip old duplicate / deleted lines
                    continue
                }
            }
            resultLines.append(line)
        }

        for (lowerKey, entry) in normalizedUpdates.sorted(by: { $0.key < $1.key }) {
            guard !handled.contains(lowerKey), let value = entry.value else { continue }
            if let last = resultLines.last, !last.isEmpty {
                resultLines.append("")
            }
            resultLines.append("\(entry.originalKey) = \(value)")
        }

        let output = resultLines.joined(separator: "\n")
        try? output.write(to: url, atomically: true, encoding: .utf8)
        invalidateCache()
    }
}

public enum SiqiColorParser {
    public static func rgbComponents(hex: String) -> (r: Double, g: Double, b: Double)? {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return (r, g, b)
    }

    public static func color(hex: String) -> Color? {
        guard let rgb = rgbComponents(hex: hex) else { return nil }
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    public static func nsColor(hex: String, alpha: CGFloat = 1.0) -> NSColor? {
        guard let rgb = rgbComponents(hex: hex) else { return nil }
        return NSColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: alpha)
    }

    public static func isLight(hex: String) -> Bool {
        guard let rgb = rgbComponents(hex: hex) else { return false }
        let luminance = 0.2126 * rgb.r + 0.7152 * rgb.g + 0.0722 * rgb.b
        return luminance > 0.55
    }
}
