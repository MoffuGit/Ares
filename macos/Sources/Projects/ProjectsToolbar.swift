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
