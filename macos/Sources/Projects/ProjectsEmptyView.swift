import SwiftUI

struct ProjectEmptyView: View {
    let app: AppDelegate

    @State private var showingOpenPanel = false

    var body: some View {
        VStack(spacing: 18) {
            Text("Odyssey")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(.white)
            UI.Button(
                "Add Project", icon: Image(systemName: "folder"), action: { app.selectNewProject() }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
