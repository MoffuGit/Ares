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
    let workspaceHistoryManager: WorkspaceHistoryManager
    private var workspaceHistoryController: WorkspaceHistoryController?

    override init() {
        app = Odyssey.App()
        session = Odyssey.Session(app: app)
        workspaceHistoryManager = WorkspaceHistoryManager()

        super.init()

        workspaceHistoryManager.delegate = self
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let restored = Odyssey.SerializedWorkspaces.getBySession(app: app, session: session)
        let controller = WorkspaceHistoryController(
            app: self,
            historyManager: workspaceHistoryManager
        )
        workspaceHistoryController = controller
        controller.showWindow(nil)
        controller.window?.center()

        for workspace in restored.workspaces {
            openWorkspace(workspace)
        }
    }

    func openWorkspace(_ workspace: Odyssey.SerializedWorkspace) {
        openWorkspace(workspace.paths)
    }

    public func openWorkspace(_ path: String) {
        openWorkspace([path])
    }

    public func openWorkspace(_ paths: [String]) {
        let paths = Odyssey.Workspace.normalizedPaths(paths)
        guard !paths.isEmpty else { return }

        let controller = WorkspaceController(
            delegate: self, session: session, paths: paths)
        register(controller)
        controller.showWindow(nil)
        controller.window?.center()

        if let metadata = controller.serializedMetadata() {
            workspaceHistoryManager.upsert(metadata)
        }
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

extension AppDelegate: WorkspaceHistoryManagerDelegate {
    func workspaceHistoryManager(
        _ manager: WorkspaceHistoryManager,
        didChange workspaces: [Odyssey.SerializedWorkspace],
        removedWorkspace: Odyssey.SerializedWorkspace?
    ) {
        if let workspace = removedWorkspace {
            let normalized = Odyssey.Workspace.normalizedPaths(workspace.paths)
            let matching = workspaceControllers.filter { $0.paths == normalized }
            let matchingIDs = Set(matching.map(ObjectIdentifier.init))

            workspaceControllers.removeAll {
                matchingIDs.contains(ObjectIdentifier($0))
            }

            for controller in matching {
                controller.close()
            }
        }

        workspaceHistoryController?.reload()
    }
}
