//
//  WorkspaceListController.swift
//  Odyssey
//
//  Created by Adrian Hess on 03/07/26.
//

import AppKit

private final class WorkspaceHistoryWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

class WorkspaceHistoryController: NSWindowController,
    NSWindowDelegate
{
    init(app: AppDelegate, workspaces: Odyssey.SerializedWorkspaces) {
        let window = WorkspaceHistoryWindow(
            contentRect: NSRect(x: 0, y: 0, width: 650, height: 550),
            styleMask: [.closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear

        let stackView = NSStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        stackView.spacing = 0
        stackView.wantsLayer = true
        stackView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        stackView.layer?.masksToBounds = true
        stackView.layer?.cornerRadius = 16
        let content = WorkspaceHistoryContent(app: app, workspaces: workspaces)
        stackView.addArrangedSubview(WorkspaceHistoryToolbar(app: app))
        stackView.addArrangedSubview(content)

        super.init(window: window)

        window.delegate = self
        window.contentView = stackView
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

}
