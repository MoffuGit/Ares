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
            return Color(NSColor(hex: "#117DFE"))
        case .secondary:
            return Color(NSColor(hex: "#141414"))
        case .outline, .ghost, .link:
            return .clear
        case .destructive:
            return Color.red
        }
    }
    
    var foregroundColor: Color {
        switch self {
        case .primary:
            return Color.white
        case .secondary:
            return Color(NSColor(hex: "#828282"))
        case .outline:
            return Color.white.opacity(0.6)
        case .ghost:
            return Color.white
        case .link:
            return Color.white
        case .destructive:
            return Color.white
        }
    }
    
    var borderColor: Color? {
        switch self {
        case .outline:
            return Color(NSColor(hex:"#393939"))
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
                return Color(NSColor(hex: "#117DFE")).opacity(0.8)
            case .secondary:
                return Color(NSColor(hex: "#141414")).opacity(0.8)
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
    
    var font: Typography {
        switch self{
        case .xs, .iconXs:
                .xs
        default:
                .sm
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
