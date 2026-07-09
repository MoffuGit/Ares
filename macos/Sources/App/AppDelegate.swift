//
//  AppDelegate.swift
//  Odyssey
//
//  Created by Adrian Hess on 02/07/26.
//

import Cocoa
import OdysseyKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var app: Odyssey.App
    var session: Odyssey.Session
    private var workspaceControllers: [WorkspaceController] = []

    override init() {
        app = Odyssey.App()
        session = Odyssey.Session(app: app)

        super.init()
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let restored = Odyssey.SerializedWorkspaces.getBySession(app: app, session: session)
        let controller = WorkspaceHistoryController(
            app: self,
            workspaces: Odyssey.SerializedWorkspaces.getAllMetadataAndValidate()
        )
        controller.showWindow(nil)
        controller.window?.center()

        for workspace in restored.workspaces {
            openWorkspace(workspace)
        }
    }

    func openWorkspace(_ workspace: Odyssey.SerializedWorkspace) {
        openWorkspace(workspace.paths)
    }

    public func openWorkspace(_ paths: [String]) {
        let paths = Odyssey.Workspace.normalizedPaths(paths)
        guard !paths.isEmpty else { return }

        let controller = WorkspaceController(
            delegate: self, session: session, paths: paths)
        register(controller)
        controller.showWindow(nil)
        controller.window?.center()
    }

    public func openWorkspace(_ path: String) {
        let controller = WorkspaceController(
            delegate: self, session: session, path: path)
        register(controller)
        controller.showWindow(nil)
        controller.window?.center()
    }

    private func register(_ controller: WorkspaceController) {
        workspaceControllers.append(controller)
    }

    func workspaceWindowWillClose(_ controller: WorkspaceController) {
        let isLastWorkspaceWindow =
            workspaceControllers.count == 1 && workspaceControllers.first === controller
        if isLastWorkspaceWindow {
            controller.markForRestoration()
        }
        workspaceControllers.removeAll { $0 === controller }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        for controller in workspaceControllers {
            controller.markForRestoration()
        }
        odyssey_db_stop()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func selectNewWorkspace(window: NSWindow) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.prompt = "Create Workspace"

        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK else { return }
            self?.openWorkspace(panel.urls.map(\.path))
        }
    }
}
