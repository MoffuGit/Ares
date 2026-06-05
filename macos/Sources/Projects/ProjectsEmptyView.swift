import SwiftUI

struct ProjectEmptyView: View {
    let app: AppDelegate

    @State private var showingOpenPanel = false

    var body: some View {
        Text("You don't have any project yet.\nOpen a new project (+)")
            .font(Theme.Fonts.sm)
            .foregroundStyle(Color(Theme.Colors.mutedForeground))
            .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
