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

    override init() {
        app = Odyssey.App()
        session = Odyssey.Session(app: app)

        super.init()
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let controller = WorkspaceHistoryController(
            app: self,
            workspaces: Odyssey.SerializedWorkspaces.getAllMetadataAndValidate()
        )
        controller.showWindow(nil)
        controller.window?.center()
    }

    func openWorkspace(_ workspace: Odyssey.SerializedWorkspace) {
        let controller = WorkspaceController(
            delegate: self, session: session, paths: workspace.paths)
        controller.showWindow(nil)
        controller.window?.center()
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

    func selectNewWorkspace(window: NSWindow) {
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

    public func createWorkspace(paths: [String]) {
        let paths = Odyssey.Workspace.normalizedPaths(paths)
        guard !paths.isEmpty else { return }

        let controller = WorkspaceController(
            delegate: self, session: session, paths: paths)
        controller.showWindow(nil)
        controller.window?.center()
    }
}
