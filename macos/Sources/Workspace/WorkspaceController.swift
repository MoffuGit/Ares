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
    private weak var appDelegate: AppDelegate?

    init(delegate: AppDelegate, session: Odyssey.Session, path: String) {
        self.workspace = Odyssey.Workspace(app: delegate.app, session: session, path: path)
        self.appDelegate = delegate

        let window = WorkspaceWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.titlebarAppearsTransparent = true

        super.init(window: window)
        window.delegate = self
    }

    init(delegate: AppDelegate, session: Odyssey.Session, paths: [String]) {
        self.workspace = Odyssey.Workspace(app: delegate.app, session: session, paths: paths)
        self.appDelegate = delegate

        let window = WorkspaceWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.titlebarAppearsTransparent = true

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowWillClose(_ notification: Notification) {
        appDelegate?.workspaceWindowWillClose(self)
    }

    func markForRestoration() {
        workspace.markForRestoration()
    }
}
