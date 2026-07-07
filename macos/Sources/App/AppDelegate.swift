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
        WorkspaceController(delegate: self, session:session, path: path)
    }

    func createWorkspaceController(paths: [String]) -> WorkspaceController {
        WorkspaceController(delegate: self, session:session, paths: paths)
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
}
