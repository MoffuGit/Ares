//
//  WorkspaceHistoryManager.swift
//  Odyssey
//
//  Created by Adrian Hess on 10/07/26.
//

import Foundation

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
