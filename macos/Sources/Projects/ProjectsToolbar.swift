import AppKit

class ProjectsToolbar: NSView {
    private let app: AppDelegate

    init(app: AppDelegate) {
        self.app = app

        super.init(frame: .zero)
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.systemBlue.cgColor
        self.layer?.cornerRadius = 4
        self.layer?.zPosition = 100
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func selectNewProject() {
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

// self.addProjectButton = NSButton(
//     image: NSImage(systemSymbolName: "plus", accessibilityDescription: "Add Project")!,
//     target: nil, action: nil)
//
// addProjectButton.translatesAutoresizingMaskIntoConstraints = false
// addProjectButton.bezelStyle = .roundRect
// addProjectButton.imagePosition = .imageOnly
// addProjectButton.target = self
// addProjectButton.action = #selector(addProject)
// addSubview(addProjectButton)
// struct ProjectsView: View {
//     @ObservedObject var app: AppDelegate
//     @State private var projects: [Project] = []
//
//     var body: some View {
//         VStack(alignment: .leading, spacing: 16) {
//             if projects.isEmpty {
//                 Spacer()
//                 VStack(spacing: 8) {
//                     RoundedRectangle(cornerRadius: 8)
//                         .fill(Color(NSColor(hex: "#A8A8A8", alpha: 0.4)))
//                         .frame(width: 28, height: 28)
//                         .overlay {
//                             Image(systemName: "folder")
//                                 .font(.system(size: 16))
//                         }
//                     Text("No project's open yet")
//                 }
//                 .frame(maxWidth: .infinity)
//                 .opacity(0.6)
//                 Spacer()
//             } else {
//                 List(projects) { project in
//                     VStack(alignment: .leading) {
//                         Text(project.name)
//                             .font(.title2)
//                             .fontWeight(.medium)
//
//                         Text(project.abs_path)
//                             .font(.caption)
//                             .foregroundStyle(.secondary)
//                             .lineLimit(1)
//                     }
//                 }
//                 .listStyle(.inset)
//             }
//         }
//         .frame(maxWidth: .infinity, maxHeight: .infinity)
//     }
//
// }
