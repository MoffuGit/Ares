import SwiftUI

struct ProjectEmptyView: View {
    let app: AppDelegate

    @State private var showingOpenPanel = false

    var body: some View {
        VStack(spacing: 18) {
            Text("Odyssey")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(.white)
            UI.Button("Add Project", icon: Image(systemName:"folder"), action: {selectNewProject()})
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func selectNewProject() {
        let panel = NSOpenPanel()
        panel.title = "Add Project"
        panel.prompt = "Add Project"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        app.addProject(project: Project(abs_path: url.path))
    }
}
