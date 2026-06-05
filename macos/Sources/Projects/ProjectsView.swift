import AppKit
import Foundation
import SwiftUI

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
    private let titlebar: NSHostingView<ProjectsTitlebar>
    private let projectsList: NSView
    private let closeButton: NSView

    init(app: AppDelegate) {
        self.titlebar = NSHostingView(rootView: ProjectsTitlebar(app: app))
        self.projectsList = ProjectsList(app: app)
        self.closeButton = NSWindow.standardWindowButton(.closeButton, for: .titled) ?? NSButton()

        super.init(frame: .zero)

        self.translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.setBackgroundColor(Theme.Colors.background)
        layer?.cornerRadius = Theme.Radius.xl
        layer?.masksToBounds = true

        titlebar.translatesAutoresizingMaskIntoConstraints = false
        projectsList.translatesAutoresizingMaskIntoConstraints = false
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titlebar)
        addSubview(projectsList)
        addSubview(closeButton)

        NSLayoutConstraint.activate([
            projectsList.leadingAnchor.constraint(equalTo: leadingAnchor),
            projectsList.trailingAnchor.constraint(equalTo: trailingAnchor),
            projectsList.topAnchor.constraint(equalTo: titlebar.bottomAnchor),
            projectsList.bottomAnchor.constraint(equalTo: bottomAnchor),

            titlebar.leadingAnchor.constraint(equalTo: leadingAnchor),
            titlebar.trailingAnchor.constraint(equalTo: trailingAnchor),
            titlebar.topAnchor.constraint(equalTo: topAnchor),
            titlebar.heightAnchor.constraint(equalToConstant: 44),

            closeButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            closeButton.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            closeButton.widthAnchor.constraint(equalToConstant: 6),
            closeButton.heightAnchor.constraint(equalToConstant: 6),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct ProjectsTitlebar: View {
    let app: AppDelegate

    var body: some View {
        HStack(alignment: .center) {
            Spacer()
            Text("Projects")
            Spacer()
            UI.Button(
                nil, Image(systemName: "folder"), action: { app.selectNewProject() }
            )
            .variant(.outline)
            .size(.iconXs)
        }
        .padding(.horizontal, Padding.`2.5`)
        .frame(maxWidth: .infinity, maxHeight: 44)
        .background(Color(Theme.Colors.background))
        .gesture(WindowDragGesture())
        .allowsWindowActivationEvents()
    }
}
