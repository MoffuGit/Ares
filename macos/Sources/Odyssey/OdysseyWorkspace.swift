//
//  OdysseyWorkspace.swift
//  Odyssey
//
//  Created by Adrian Hess on 02/06/26.

import AppKit
import Combine
import OdysseyKit
import os

extension Odyssey {
    @MainActor
    class Workspace: NSObject, ObservableObject {
        private var app: Odyssey.App
        @Published var workspace: odyssey_workspace_s
        var entity: odyssey_entity_s? {
            didSet {
                guard let old = oldValue else { return }
                odyssey_drop_entity(old)
            }
        }

        init(app: Odyssey.App) {
            self.app = app
            self.entity = nil
            self.workspace = odyssey_workspace_s(count: 0)

            super.init()

            guard let app = app.app else {
                logger.critical("odyssey_workspace_new failed: app is nil")
                return
            }

            let maybe_entity = odyssey_workspace_new(app)
            guard maybe_entity.valid else {
                logger.critical("odyssey_workspace_new failed")
                return
            }

            self.entity = maybe_entity.entity

            withUnsafeMutablePointer(to: &self.workspace) { ptr in
                odyssey_workspace_set(app, self.entity!, ptr)
            }

        }

        deinit {
            self.entity = nil
        }
    }
}
