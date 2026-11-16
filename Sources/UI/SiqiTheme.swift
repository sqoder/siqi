import AppKit
import GhosttyTheme
import SwiftUI

public typealias SiqiThemeCatalog = GhosttyThemeCatalog
public typealias SiqiThemeDefinition = GhosttyThemeDefinition

public enum SiqiTheme {
    public static let defaultBackgroundHex = "1E1E2E"

    public static func backgroundColor(for themeName: String, customBackground: String? = nil) -> Color {
        if let customBackground, !customBackground.trimmingCharacters(in: .whitespaces).isEmpty {
            return Color(hex: customBackground)
        }
        if let theme = SiqiThemeCatalog.theme(named: themeName) {
            return Color(hex: theme.background)
        }
        return Color(hex: defaultBackgroundHex)
    }

    public static func nsBackgroundColor(for themeName: String, customBackground: String? = nil) -> NSColor {
        if let customBackground, !customBackground.trimmingCharacters(in: .whitespaces).isEmpty {
            return NSColor(hex: customBackground)
        }
        if let theme = SiqiThemeCatalog.theme(named: themeName) {
            return NSColor(hex: theme.background)
        }
        return NSColor(hex: defaultBackgroundHex)
    }
}

public extension Color {
    init(hex: String, defaultColor: Color = Color(red: 30 / 255.0, green: 30 / 255.0, blue: 46 / 255.0)) {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        if Scanner(string: clean).scanHexInt64(&int) {
            let r, g, b: Double
            switch clean.count {
            case 3:
                r = Double(((int >> 8) & 0xF) * 17) / 255.0
                g = Double(((int >> 4) & 0xF) * 17) / 255.0
                b = Double((int & 0xF) * 17) / 255.0
                self.init(red: r, green: g, blue: b)
                return
            case 6:
                r = Double((int >> 16) & 0xFF) / 255.0
                g = Double((int >> 8) & 0xFF) / 255.0
                b = Double(int & 0xFF) / 255.0
                self.init(red: r, green: g, blue: b)
                return
            case 8:
                r = Double((int >> 24) & 0xFF) / 255.0
                g = Double((int >> 16) & 0xFF) / 255.0
                b = Double((int >> 8) & 0xFF) / 255.0
                let a = Double(int & 0xFF) / 255.0
                self.init(red: r, green: g, blue: b, opacity: a)
                return
            default:
                break
            }
        }
        self = defaultColor
    }
}

public extension NSColor {
    convenience init(
        hex: String,
        defaultColor: NSColor = NSColor(srgbRed: 30 / 255.0, green: 30 / 255.0, blue: 46 / 255.0, alpha: 1.0)
    ) {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        if Scanner(string: clean).scanHexInt64(&int) {
            let r, g, b: CGFloat
            switch clean.count {
            case 3:
                r = CGFloat(((int >> 8) & 0xF) * 17) / 255.0
                g = CGFloat(((int >> 4) & 0xF) * 17) / 255.0
                b = CGFloat((int & 0xF) * 17) / 255.0
                self.init(srgbRed: r, green: g, blue: b, alpha: 1.0)
                return
            case 6:
                r = CGFloat((int >> 16) & 0xFF) / 255.0
                g = CGFloat((int >> 8) & 0xFF) / 255.0
                b = CGFloat(int & 0xFF) / 255.0
                self.init(srgbRed: r, green: g, blue: b, alpha: 1.0)
                return
            case 8:
                r = CGFloat((int >> 24) & 0xFF) / 255.0
                g = CGFloat((int >> 16) & 0xFF) / 255.0
                b = CGFloat((int >> 8) & 0xFF) / 255.0
                let a = CGFloat(int & 0xFF) / 255.0
                self.init(srgbRed: r, green: g, blue: b, alpha: a)
                return
            default:
                break
            }
        }
        if let rgb = defaultColor.usingColorSpace(.sRGB) {
            self.init(srgbRed: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent, alpha: rgb.alphaComponent)
        } else {
            self.init(srgbRed: 30 / 255.0, green: 30 / 255.0, blue: 46 / 255.0, alpha: 1.0)
        }
    }
}
