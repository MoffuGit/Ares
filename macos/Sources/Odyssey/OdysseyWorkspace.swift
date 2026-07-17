//
//  OdysseyWorkspace.swift
//  Odyssey
//
//  Created by Adrian Hess on 02/06/26.

import Foundation
import OdysseyKit
import os

extension Odyssey {
    struct SerializedWindowBounds {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
        
        init(_ bounds: odyssey_workspace_window_bounds_s) {
            self.height = bounds.height
            self.width = bounds.width
            self.x  = bounds.x
            self.y = bounds.y
        }
    }
    
    struct SerializedWorkspace {
        let id: Int64
        let windowBounds: SerializedWindowBounds?
        let leftDock: Double?
        let rightDock: Double?
        let paths: [String]
        let timestamp: Int64
        
        init(id: Int64, paths: [String], timestamp: Int64) {
            self.id = id
            self.paths = paths
            self.timestamp = timestamp
            self.windowBounds = nil
            self.leftDock = nil
            self.rightDock = nil
        }
        
        init(_ workspace: odyssey_serialized_workspace_s) {
            id = workspace.id
            timestamp = workspace.timestamp
            
            if(workspace.window.valid) {
                windowBounds = SerializedWindowBounds(workspace.window.value)
            } else {
                windowBounds = nil
            }
            
            if(workspace.left_dock.valid) {
                leftDock = workspace.left_dock.width
            } else {
                leftDock = nil
            }
            
            if(workspace.right_dock.valid) {
                rightDock = workspace.right_dock.width
            } else {
                rightDock = nil
            }
            
            guard let pathsPointer = workspace.paths.ptr else {
                paths = []
                return
            }
            
            paths = (0..<workspace.paths.len).map { index in
                let path = pathsPointer[index]
                guard let bytes = path.ptr else { return "" }
                return String(
                    decoding: UnsafeBufferPointer(start: bytes, count: path.len), as: UTF8.self)
            }
        }
        
        var displayPath: String {
            paths.first ?? "No path"
        }
    }
    
    class SerializedWorkspaces {
        let list: odyssey_workspace_list_s
        let workspaces: [SerializedWorkspace]
        
        init(_ list: odyssey_workspace_list_s) {
            self.list = list
            
            guard let workspacePointer = list.ptr else {
                workspaces = []
                return
            }
            
            workspaces = (0..<list.len).map { index in
                SerializedWorkspace(workspacePointer[index])
            }
        }
        
        static func getAllMetadataAndValidate() -> SerializedWorkspaces {
            SerializedWorkspaces(odyssey_workspace_get_all_metadata_and_validate())
        }
        
        static func deleteByID(_ id: Int64) -> Bool {
            odyssey_workspace_delete_by_id(id) == 0
        }
        
        static func getBySession(app: Odyssey.App, session: Odyssey.Session) -> SerializedWorkspaces
        {
            guard let odysseyApp = app.app, let sessionEntity = session.entity else {
                logger.critical("odyssey_workspace_get_by_session failed: app or session is nil")
                return SerializedWorkspaces(odyssey_workspace_list_s(ptr: nil, len: 0))
            }
            
            return SerializedWorkspaces(odyssey_workspace_get_by_session(odysseyApp, sessionEntity))
        }
        
        deinit {
            odyssey_workspace_list_free(list)
        }
    }
    
    class Workspace: Entity {
        convenience init(app: Odyssey.App, session: Odyssey.Session, path: String) {
            self.init(app: app, session: session, paths: [path])
        }
        
        init(app: Odyssey.App, session: Odyssey.Session, paths: [String]) {
            guard let odysseyApp = app.app else {
                logger.critical("odyssey_workspace_new failed: app is nil")
                super.init(app: app, entity: nil)
                return
            }
            
            let paths = Self.normalizedPaths(paths)
            
            guard !paths.isEmpty else {
                logger.critical("odyssey_workspace_new failed: paths is empty")
                super.init(app: app, entity: nil)
                return
            }
            
            let pathStorage = paths.map { Array($0.utf8) }
            var pathStrings = pathStorage.indices.map { index in
                pathStorage[index].withUnsafeBufferPointer { buffer in
                    odyssey_string_s(ptr: buffer.baseAddress, len: buffer.count)
                }
            }
            
            let maybe_entity = pathStrings.withUnsafeMutableBufferPointer { buffer in
                odyssey_workspace_new(
                    odysseyApp,
                    session.entity!,
                    odyssey_workspace_paths_s(ptr: buffer.baseAddress, len: buffer.count)
                )
            }
            guard maybe_entity.valid else {
                logger.critical("odyssey_workspace_new failed")
                super.init(app: app, entity: nil)
                return
            }
            
            super.init(app: app, entity: maybe_entity.entity)
        }
        
        func markForRestoration() {
            guard let odysseyApp = app.app, let entity = entity else {
                logger.critical("odyssey_workspace_mark_for_restoration failed: app or entity is nil")
                return
            }
            
            odyssey_workspace_mark_for_restoration(odysseyApp, entity)
            app.enqueueFlush()
        }
        
        var Id: Int64 {
            guard let odysseyApp = app.app, let entity = entity else { return -1 }
            return odyssey_workspace_get_id(odysseyApp, entity)
        }
        
        static func normalizedPaths(_ paths: [String]) -> [String] {
            Array(Set(paths.map { URL(fileURLWithPath: $0).standardizedFileURL.path })).sorted()
        }
    }
}
