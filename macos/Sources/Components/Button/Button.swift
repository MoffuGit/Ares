import SwiftUI

extension UI {
    public struct Button: View {
        private let title: String?
        private var variant: ButtonVariant = .primary
        private var size: ButtonSize = .md
        private let icon: Image?
        private let iconPosition: IconPosition
        private let action: () -> Void
        private let isEnabled: Bool

        @State private var isPressed = false

        public enum IconPosition {
            case leading, trailing
        }

        public init(
            _ title: String? = nil,
            _ icon: Image? = nil,
            action: @escaping () -> Void
        ) {
            self.title = title
            self.icon = icon
            self.iconPosition = .leading
            self.isEnabled = true
            self.action = action
        }

        public init(
            _ title: String? = nil,
            icon: Image? = nil,
            iconPosition: IconPosition = .leading,
            isEnabled: Bool = true,
            action: @escaping () -> Void
        ) {
            self.title = title
            self.icon = icon
            self.iconPosition = iconPosition
            self.isEnabled = isEnabled
            self.action = action
        }

        public func variant(_ variant: ButtonVariant) -> Self {
            var button = self
            button.variant = variant
            return button
        }

        public func size(_ size: ButtonSize) -> Self {
            var button = self
            button.size = size
            return button
        }

        public var body: some View {
            SwiftUI.Button(action: {
                if isEnabled {
                    action()
                }
            }) {
                HStack(spacing: Padding.`1`) {
                    if let icon = icon, iconPosition == .leading {
                        icon
                            .font(size.font)
                    }

                    if let title = title {
                        Text(title)
                            .font(size.font)
                    }

                    if let icon = icon, iconPosition == .trailing {
                        icon
                            .font(size.font)
                    }
                }
                .padding(size.padding)
                .background(
                    variant.getBackgroundColor(isPressed: isPressed, isEnabled: isEnabled)
                )
                .foregroundColor(variant.foregroundColor.opacity(isEnabled ? 1 : 0.5))
                .cornerRadius(size.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: size.cornerRadius)
                        .stroke(
                            variant.borderColor ?? .clear,
                            lineWidth: variant.borderColor != nil ? 0.5 : 0)
                )
                .contentShape(Rectangle())
            }
            .focusEffectDisabled(true)
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.08), value: isPressed)
            .buttonStyle(PlainButtonStyle())
            .disabled(!isEnabled)
            .pressAction(
                onPress: {
                    isPressed = true
                },
                onRelease: {
                    isPressed = false
                }
            )
            //.accessibilityLabel(title)
            //.accessibilityAddTraits(.isButton)
        }
    }
}

struct PressActionModifier: ViewModifier {
    var onPress: () -> Void
    var onRelease: () -> Void

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in onPress() }
                    .onEnded { _ in onRelease() }
            )
    }
}

extension View {
    func pressAction(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) -> some View {
        modifier(PressActionModifier(onPress: onPress, onRelease: onRelease))
    }
}
