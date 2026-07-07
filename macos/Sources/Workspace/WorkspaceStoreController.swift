//
//  WorkspaceListController.swift
//  Odyssey
//
//  Created by Adrian Hess on 03/07/26.
//

import AppKit

private final class WorkspaceStoreWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

class WorkspaceStoreController: NSWindowController,
    NSWindowDelegate
{
    private weak var app: AppDelegate?
    private var workspaceControllers: [WorkspaceController] = []
    private var toolbarAccessory: NSTitlebarAccessoryViewController?
    private let workspaces: Odyssey.SerializedWorkspaces

    init(app: AppDelegate, workspaces: Odyssey.SerializedWorkspaces) {
        self.app = app
        self.workspaces = workspaces

        let window = WorkspaceStoreWindow(
            contentRect: NSRect(x: 0, y: 0, width: 650, height: 550),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.titlebarAppearsTransparent = true

        super.init(window: window)
        window.delegate = self
        window.contentView = WorkspaceStoreContent(workspaces: workspaces) { [weak self] in
            self?.selectPathsForNewWorkspace()
        }
    }

    private func selectPathsForNewWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.prompt = "Create Workspace"

        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK else { return }
            self?.createWorkspace(paths: panel.urls.map(\.path))
        }
    }

    private func createWorkspace(paths: [String]) {
        guard let app else { return }

        let paths = Odyssey.Workspace.normalizedPaths(paths)
        guard !paths.isEmpty else { return }

        let controller = app.createWorkspaceController(paths: paths)
        workspaceControllers.append(controller)
        controller.showWindow(nil)
        controller.window?.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
