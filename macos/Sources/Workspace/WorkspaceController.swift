//
//  WorkspaceController.swift
//  Odyssey
//
//  Created by Adrian Hess on 02/06/26.
//

import AppKit

class WorkspaceController: NSWindowController, NSWindowDelegate, WorkspaceDelegate {
    let paths: [String]
    private let toolBar = WorkspaceToolBar()
    private let statusBar = WorkspaceStatusBar()
    private let content = NSView()
    private let docks: WorkspaceDocks
    internal let workspace: Odyssey.Workspace
    private weak var appDelegate: AppDelegate?
    
    convenience init(delegate: AppDelegate, session: Odyssey.Session, path: String, rect: NSRect? = nil) {
        self.init(delegate: delegate, session: session, paths: [path], rect: rect)
    }
    
    init(delegate: AppDelegate, session: Odyssey.Session, paths: [String], rect: NSRect? = nil) {
        self.paths = Odyssey.Workspace.normalizedPaths(paths)
        self.workspace = Odyssey.Workspace(app: delegate.app, session: session, paths: self.paths)
        self.appDelegate = delegate
        self.docks = WorkspaceDocks(center: content);
        
        super.init(window: WorkspaceWindow(rect ?? NSRect(x: 0, y: 0, width: 1200, height: 800)))
        
        let content = NSStackView()
        content.orientation = .vertical
        content.spacing = 0
        content.wantsLayer = true
        content.layer?.masksToBounds = true
        content.layer?.cornerRadius = 16
        content.layer?.backgroundColor = .white
        content.addArrangedSubview(toolBar)
        content.addArrangedSubview(docks)
        content.addArrangedSubview(statusBar)
        content.needsDisplay = true
        window?.contentView = content
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
            timestamp: Int64(Date().timeIntervalSince1970),
            rect: window!.frame
        )
    }
    
    func windowWillClose(_ notification: Notification) {
        appDelegate?.workspaceWindowWillClose(self)
    }
    
    func toggleLeftDock() {
        docks.toggleCollapsed(.left);
    }
    
    func toggleRightDock() {
        docks.toggleCollapsed(.right);
    }
    
    func markForRestoration() {
        workspace.markForRestoration()
    }
    
    func saveBounds() {
        workspace.setBounds(window: window!.frame, leftDock: 0.0, rightDock: 0.0)
    }
}

private class WorkspaceWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    
    init(_ rect: NSRect) {
        super.init(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        self.isReleasedWhenClosed = true
        self.isRestorable = false
        self.backgroundColor = .clear
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.contentMinSize = NSSize(width: 480, height: 300)
    }
}
