import AppKit
import Foundation
import SwiftUI

struct Project: Identifiable {
    let id: String
    var abs_path: String
    var displayPath: String
    var name: String
    var lastOpened: String
    var fileCount: Int
    var directoryCount: Int
    var totalBytes: Int
    
    init(abs_path: String) {
        self.abs_path = abs_path
        self.id = abs_path
        self.displayPath = Project.relativeDisplayPath(for: abs_path)
        self.name = URL(fileURLWithPath: abs_path).lastPathComponent
        self.lastOpened = "Today"
        self.fileCount = 128
        self.directoryCount = 24
        self.totalBytes = 42_000_000
    }

    private static func relativeDisplayPath(for path: String) -> String {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let components = url.pathComponents
        let maxVisibleComponents = 4

        if components.count <= maxVisibleComponents {
            return url.path
        }

        return "~/" + components.suffix(maxVisibleComponents - 1).joined(separator: "/")
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
            titlebar.heightAnchor.constraint(equalToConstant: 36),
            
            closeButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 15),
            closeButton.topAnchor.constraint(equalTo: topAnchor, constant: 15),
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
        HStack(alignment: .center, spacing: 0) {
            Spacer()
            
            Text("Projects")
                .font(Theme.Fonts.xs.font.leading(.tight))
                .fontWeight(.light)
                .foregroundStyle(Color(Theme.Colors.foreground))
            
            Spacer()
            
            UI.Button(
                nil, Image(systemName: "plus"), action: { app.selectNewProject() }
            )
            .variant(.ghost)
            .size(.iconXs)
        }
        .padding(.trailing, Padding.`1.5`)
        .padding(.leading, Padding.`9`)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(Theme.Colors.background))
        .gesture(WindowDragGesture())
        .allowsWindowActivationEvents()
    }
}
