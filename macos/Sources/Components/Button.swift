import SwiftUI

extension Components {
    struct Button: View {
        let title: String
        let symbolName: String
        var bg: Color = .blue
        var hoverBg: Color = .blue.opacity(0.6)
        var fg: Color = .white
        let action: () -> Void
        let scale: CGFloat = 0.97

        @State private var isHovered = false
        @GestureState private var isPressed = false

        var body: some View {
            HStack(spacing: 6) {
                Image(systemName: symbolName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(fg)

                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(fg)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minWidth: 44, minHeight: 32)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered ? hoverBg : bg)
            )
            .scaleEffect(isPressed ? scale : 1.0)
            .animation(.easeOut(duration: 0.08), value: isPressed)
            .onHover { hovered in
                isHovered = hovered
            }
            .onTapGesture(perform: action)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressed) { _, state, _ in
                        state = true
                    }
            )
        }
    }
}
