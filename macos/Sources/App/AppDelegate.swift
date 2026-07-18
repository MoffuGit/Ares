//
//  AppDelegate.swift
//  Odyssey
//
//  Created by Adrian Hess on 02/07/26.
//

import Cocoa
import Foundation
import OdysseyKit
import os

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, WorkspaceHistoryManagerDelegate {
    var app: Odyssey.App
    var session: Odyssey.Session
    let workspaceHistoryManager: WorkspaceHistoryManager

    private var workspaceControllers: [WorkspaceController] = []
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
        if let bound = workspace.windowBounds {
            openWorkspace(
                workspace.paths,
                rect: NSRect(x: bound.x, y: bound.y, width: bound.width, height: bound.height),
                leftDock: workspace.leftDock,
                rightDock: workspace.rightDock
            )
        } else {
            openWorkspace(
                workspace.paths,
                leftDock: workspace.leftDock,
                rightDock: workspace.rightDock
            )
        }
    }

    public func openWorkspace(_ path: String) {
        openWorkspace([path])
    }

    public func openWorkspace(
        _ paths: [String],
        rect: NSRect? = nil,
        leftDock: Double? = nil,
        rightDock: Double? = nil
    ) {
        let paths = Odyssey.Workspace.normalizedPaths(paths)
        guard !paths.isEmpty else { return }

        let controller = WorkspaceController(
            delegate: self,
            session: session,
            paths: paths,
            rect: rect,
            leftDock: leftDock,
            rightDock: rightDock
        )
        workspaceControllers.append(controller)

        controller.showWindow(nil)
        if(rect == nil) {
            controller.window?.center()
        }
        
        if let metadata = controller.serializedMetadata() {
            workspaceHistoryManager.upsert(metadata)
        }
    }

    func workspaceWindowWillClose(_ controller: WorkspaceController) {
        let isLastWorkspaceWindow =
            workspaceControllers.count == 1 && workspaceControllers.first === controller
        if isLastWorkspaceWindow {
            controller.markForRestoration()
        }
        
        if let metadata = controller.serializedMetadata() {
            workspaceHistoryManager.upsert(metadata)
        }

        controller.saveBounds();
        workspaceControllers.removeAll { $0 === controller }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        for controller in workspaceControllers {
            controller.markForRestoration()
            controller.saveBounds();
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

@MainActor
protocol WorkspaceHistoryManagerDelegate: AnyObject {
    func workspaceHistoryManager(
        _ manager: WorkspaceHistoryManager,
        didChange workspaces: [Odyssey.SerializedWorkspace],
        removedWorkspace: Odyssey.SerializedWorkspace?
    )
}

@MainActor
final class WorkspaceHistoryManager {
    enum RemovalError: Error {
        case notFound(Int64)
        case persistenceFailed(Int64)
    }

    private(set) var workspaces: [Odyssey.SerializedWorkspace]
    weak var delegate: WorkspaceHistoryManagerDelegate?

    init(workspaces: [Odyssey.SerializedWorkspace]) {
        self.workspaces = workspaces
    }

    convenience init() {
        self.init(
            workspaces: Odyssey.SerializedWorkspaces.getAllMetadataAndValidate().workspaces
        )
    }

    /// Adds a new workspace, or updates an existing one matched by id.
    func upsert(_ workspace: Odyssey.SerializedWorkspace) {
        if let index = workspaces.firstIndex(where: { $0.id == workspace.id }) {
            workspaces[index] = workspace
        } else {
            workspaces.append(workspace)
        }
        delegate?.workspaceHistoryManager(self, didChange: workspaces, removedWorkspace: nil)
    }

    /// Deletes from the database, removes from the list, and notifies the delegate.
    func remove(id: Int64) throws {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else {
            throw RemovalError.notFound(id)
        }

        let workspace = workspaces[index]

        guard Odyssey.SerializedWorkspaces.deleteByID(id) else {
            throw RemovalError.persistenceFailed(id)
        }

        workspaces.remove(at: index)
        delegate?.workspaceHistoryManager(self, didChange: workspaces, removedWorkspace: workspace)
    }
}
