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
    private var session: Odyssey.Session
    private var workspaceStoreWorkspaces: Odyssey.SerializedWorkspaces
    private var workspaceStoreController: WorkspaceStoreController?

    override init() {
        app = Odyssey.App()
        session = Odyssey.Session(app: app)
        workspaceStoreWorkspaces = Odyssey.SerializedWorkspaces.getAllMetadataAndValidate()

        super.init()
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        workspaceStoreController = WorkspaceStoreController(
            app: self,
            workspaces: workspaceStoreWorkspaces
        )
        workspaceStoreController?.showWindow(nil)
        workspaceStoreController?.window?.center()
    }

    func createWorkspaceController(path: String) -> WorkspaceController {
        WorkspaceController(delegate: self, session: session, path: path)
    }

    func createWorkspaceController(paths: [String]) -> WorkspaceController {
        WorkspaceController(delegate: self, session: session, paths: paths)
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        odyssey_db_stop()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func selectPathsForNewWorkspace(window: NSWindow) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.prompt = "Create Workspace"

        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK else { return }
            self?.createWorkspace(paths: panel.urls.map(\.path))
        }
    }

    func createWorkspace(paths: [String]) {
        let paths = Odyssey.Workspace.normalizedPaths(paths)
        guard !paths.isEmpty else { return }

        let controller = createWorkspaceController(paths: paths)
        controller.showWindow(nil)
        controller.window?.center()
    }
}
