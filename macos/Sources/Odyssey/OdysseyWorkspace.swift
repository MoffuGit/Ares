//
//  OdysseyWorkspace.swift
//  Odyssey
//
//  Created by Adrian Hess on 02/06/26.
//
import OdysseyKit
import os

extension Odyssey {
    class Workspace {
        var app: Odyssey.App
        var workspace: odyssey_workspace_t? {
            didSet {
                guard let old = oldValue else { return }
                odyssey_drop_entity(old)
            }
        }

        init(app: Odyssey.App) {
            self.app = app

            guard let app = app.app else {
                logger.critical("odyssey_workspace_new failed: app is nil")
                return
            }

            let creation = odyssey_workspace_new(app)
            guard creation.valid else {
                logger.critical("odyssey_workspace_new failed")
                return
            }

            self.workspace = creation.entity
        }

        deinit {
            self.workspace = nil
        }
    }
}
