import SwiftUI

public enum ButtonVariant {
    case primary
    case secondary
    case outline
    case ghost
    case link
    case destructive
    
    var backgroundColor: Color {
        switch self {
        case .primary:
            return Color(Theme.Colors.primary)
        case .secondary:
            return Color(Theme.Colors.secondary)
        case .outline:
            return Color(Theme.Colors.background)
        case .ghost, .link:
            return .clear
        case .destructive:
            return Color.red
        }
    }
    
    var foregroundColor: Color {
        switch self {
        case .primary:
            return Color(Theme.Colors.primaryForeground)
        case .secondary:
            return Color(Theme.Colors.secondaryForeground)
        case .outline:
            return Color(Theme.Colors.foreground)
        case .ghost:
            return Color(Theme.Colors.foreground)
        case .link:
            return Color(Theme.Colors.foreground)
        case .destructive:
            return Color(Theme.Colors.destructiveForeground)
        }
    }
    
    var borderColor: Color? {
        switch self {
        case .outline:
            return Color(Theme.Colors.border)
        default:
            return nil
        }
    }
    
    func getBackgroundColor(isPressed: Bool, isEnabled: Bool) -> Color {
        guard isEnabled else {
            return backgroundColor.opacity(0.5)
        }
        
        if isPressed {
            switch self {
            case .primary:
                return Color(Theme.Colors.primary).opacity(0.8)
            case .secondary:
                return Color(Theme.Colors.secondary).opacity(0.8)
            case .outline:
                return Color.gray.opacity(0.2)
            case .ghost:
                return Color.gray.opacity(0.2)
            case .link:
                return .clear
            case .destructive:
                return Color.red.opacity(0.9)
            }
        }
        
        return backgroundColor
    }
}

public enum ButtonSize {
    case xs, sm, md, lg, icon, iconXs
    
    var padding: EdgeInsets {
        switch self {
        case .iconXs:
            EdgeInsets(
                top: Padding.`1.5`, leading: Padding.`1.5`, bottom: Padding.`1.5`, trailing: Padding.`1.5`)
        case .icon, .sm :
            EdgeInsets(
                top: Padding.`1`, leading: Padding.`1`, bottom: Padding.`1`, trailing: Padding.`1`)
        default:
            EdgeInsets(
                top: Padding.`1.5`, leading: Padding.`2`, bottom: Padding.`1.5`, trailing: Padding.`2`)
        }
    }
    
    var font: ThemeFont {
        switch self{
        case .xs, .iconXs:
            Theme.Fonts.xs
        default:
            Theme.Fonts.sm
        }
    }
    
    var cornerRadius: CGFloat {
        switch self {
        case .sm, .icon, .xs, .iconXs:
            return BorderRadius.md
        case .md, .lg:
            return BorderRadius.lg
        }
    }
}
