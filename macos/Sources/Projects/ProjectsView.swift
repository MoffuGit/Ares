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

    init(app: AppDelegate) {
        self.projectsList = ProjectsList(app: app)

        super.init(frame: .zero)

        self.translatesAutoresizingMaskIntoConstraints = false
        projectsList.translatesAutoresizingMaskIntoConstraints = false

        addSubview(projectsList)

        NSLayoutConstraint.activate([
            projectsList.leadingAnchor.constraint(equalTo: leadingAnchor),
            projectsList.trailingAnchor.constraint(equalTo: trailingAnchor),
            projectsList.topAnchor.constraint(equalTo: topAnchor),
            projectsList.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
