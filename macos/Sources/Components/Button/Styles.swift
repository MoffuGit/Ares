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
            return Color.blue
        case .secondary:
            return Color.secondary
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
            return Color.gray
        case .outline:
            return Color.white
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
            return Color.gray
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
                return Color.blue.opacity(0.9)
            case .secondary:
                return Color.secondary.opacity(0.9)
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
    case sm, md, lg
    
    var padding: EdgeInsets {
        EdgeInsets(
            top: Padding.`1.5`, leading: Padding.`2`, bottom: Padding.`1.5`, trailing: Padding.`2`)
    }
    
    var font: Typography {
        return .sm
    }
    
    var cornerRadius: CGFloat {
        switch self {
        case .sm:
            return 6
        case .md, .lg:
            return 8
        }
    }
}
