import AppKit
import Foundation

struct Project: Identifiable {
    let id: String
    var abs_path: String
    var name: String

    init(abs_path: String) {
        self.abs_path = abs_path
        self.id = abs_path
        self.name = URL(fileURLWithPath: abs_path).lastPathComponent
    }
}

class ProjectsView: NSView {
    private let projectsList: NSView
    private let projectsToolbar: NSView

    init(app: AppDelegate) {
        self.projectsList = ProjectsList(app: app)
        self.projectsToolbar = ProjectsToolbar(app: app)

        super.init(frame: .zero)

        self.translatesAutoresizingMaskIntoConstraints = false
        projectsList.translatesAutoresizingMaskIntoConstraints = false
        projectsToolbar.translatesAutoresizingMaskIntoConstraints = false

        addSubview(projectsToolbar)
        addSubview(projectsList)

        NSLayoutConstraint.activate([
            projectsList.leadingAnchor.constraint(equalTo: leadingAnchor),
            projectsList.trailingAnchor.constraint(equalTo: trailingAnchor),
            projectsList.topAnchor.constraint(equalTo: topAnchor),
            projectsList.bottomAnchor.constraint(equalTo: bottomAnchor),

            projectsToolbar.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            projectsToolbar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            projectsToolbar.widthAnchor.constraint(equalToConstant: 24),
            projectsToolbar.heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
