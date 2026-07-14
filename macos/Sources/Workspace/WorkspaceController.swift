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
    let paths: [String]
    private let workspace: Odyssey.Workspace
    private weak var appDelegate: AppDelegate?

    convenience init(delegate: AppDelegate, session: Odyssey.Session, path: String) {
        self.init(delegate: delegate, session: session, paths: [path])
    }

    init(delegate: AppDelegate, session: Odyssey.Session, paths: [String]) {
        let normalized = Odyssey.Workspace.normalizedPaths(paths)
        self.paths = normalized
        self.workspace = Odyssey.Workspace(app: delegate.app, session: session, paths: normalized)
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

    func serializedMetadata() -> Odyssey.SerializedWorkspace? {
        let id = workspace.Id
        guard id >= 0 else { return nil }
        return Odyssey.SerializedWorkspace(
            id: id,
            paths: paths,
            timestamp: Int64(Date().timeIntervalSince1970)
        )
    }

    func windowWillClose(_ notification: Notification) {
        appDelegate?.workspaceWindowWillClose(self)
    }

    func markForRestoration() {
        workspace.markForRestoration()
    }
}
