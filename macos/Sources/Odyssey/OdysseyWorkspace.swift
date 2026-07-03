//
//  OdysseyWorkspace.swift
//  Odyssey
//
//  Created by Adrian Hess on 02/06/26.

import OdysseyKit
import os

extension Odyssey {
    @MainActor
    final class Workspace {
        private let app: Odyssey.App
        private var entity: odyssey_entity_s?

        init(app: Odyssey.App) {
            self.app = app

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
        }

        deinit {
            if let entity {
                odyssey_drop_entity(entity)
            }
        }
    }
}
