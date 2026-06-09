import AppKit
import SwiftUI

public enum Theme {
    public enum Colors {
        public static let background = ThemeColor(hex: "#000000")
        public static let foreground = ThemeColor(nsColor: .white)
        public static let card = ThemeColor(hex: "#141414")
        public static let cardForeground = ThemeColor(nsColor: .white)
        public static let popover = ThemeColor(hex: "#141414")
        public static let popoverForeground = ThemeColor(nsColor: .white)
        public static let primary = ThemeColor(hex: "#117DFE")
        public static let primaryForeground = ThemeColor(nsColor: .white)
        public static let secondary = ThemeColor(hex: "#141414")
        public static let secondaryForeground = ThemeColor(hex: "#828282")
        public static let muted = ThemeColor(hex: "#141414")
        public static let mutedForeground = ThemeColor(hex: "#828282")
        public static let accent = ThemeColor(hex: "#117DFE")
        public static let accentForeground = ThemeColor(nsColor: .white)
        public static let destructive = ThemeColor(nsColor: .systemRed)
        public static let destructiveForeground = ThemeColor(nsColor: .white)
        public static let border = ThemeColor(hex: "#393939")
        public static let input = ThemeColor(hex: "#393939")
        public static let ring = ThemeColor(hex: "#117DFE")
        public static let clear = ThemeColor(nsColor: .clear)
    }

    public enum Fonts {
        public static let xs = ThemeFont(size: 12)
        public static let sm = ThemeFont(size: 14)
        public static let base = ThemeFont(size: 16)
        public static let lg = ThemeFont(size: 18)
        public static let xl = ThemeFont(size: 20)
        public static let `2xl` = ThemeFont(size: 24)
        public static let `3xl` = ThemeFont(size: 30)
        public static let `4xl` = ThemeFont(size: 36)
        public static let `5xl` = ThemeFont(size: 48)
    }

    public enum Radius {
        public static let xs: CGFloat = 2
        public static let sm: CGFloat = 4
        public static let md: CGFloat = 6
        public static let lg: CGFloat = 8
        public static let xl: CGFloat = 12
    }
}

public struct ThemeFont {
    public let size: CGFloat
    public let nsWeight: NSFont.Weight
    public let swiftUIWeight: Font.Weight

    public init(size: CGFloat, nsWeight: NSFont.Weight = .regular, swiftUIWeight: Font.Weight = .regular) {
        self.size = size
        self.nsWeight = nsWeight
        self.swiftUIWeight = swiftUIWeight
    }

    public var font: Font {
        .system(size: size, weight: swiftUIWeight)
    }

    public var nsFont: NSFont {
        .systemFont(ofSize: size, weight: nsWeight)
    }
}

public struct ThemeColor {
    public let nsColor: NSColor

    public init(nsColor: NSColor) {
        self.nsColor = nsColor
    }

    public init(hex: String, alpha: CGFloat = 1) {
        self.nsColor = NSColor(hex: hex, alpha: alpha)
    }

    public var cgColor: CGColor {
        nsColor.cgColor
    }
}

public extension Color {
    init(_ themeColor: ThemeColor) {
        self.init(nsColor: themeColor.nsColor)
    }
}

public extension ShapeStyle where Self == Color {
    static func theme(_ color: ThemeColor) -> Color {
        Color(color)
    }
}

public extension NSColor {
    convenience init(_ themeColor: ThemeColor) {
        self.init(cgColor: themeColor.cgColor)!
    }
}

public extension CALayer {
    func setBackgroundColor(_ color: ThemeColor) {
        backgroundColor = color.cgColor
    }

    func setBorderColor(_ color: ThemeColor) {
        borderColor = color.cgColor
    }
}

public extension Font {
    init(_ themeFont: ThemeFont) {
        self = themeFont.font
    }
}

public extension NSFont {
    static func theme(_ font: ThemeFont) -> NSFont {
        font.nsFont
    }
}

public extension View {
    func font(_ themeFont: ThemeFont) -> some View {
        font(themeFont.font)
    }
}
