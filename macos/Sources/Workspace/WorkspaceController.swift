//
//  WorkspaceController.swift
//  Odyssey
//
//  Created by Adrian Hess on 02/06/26.
//

import AppKit

private final class WorkspaceWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

final class WorkspaceController: NSWindowController, NSWindowDelegate {
    private let workspace: Odyssey.Workspace

    init(app: AppDelegate, project: Project) {
        self.workspace = Odyssey.Workspace(app: app.odysseyApp)

        let window = WorkspaceWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.title = project.name
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.contentView = WorkspaceView(project: project)
        window.titlebarAppearsTransparent = true

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
