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
                odyssey_workspace_free(app.app, old)
            }
        }

        init(app: Odyssey.App) {
            self.app = app
            guard let workspace = odyssey_workspace_new(app.app) else {
                logger.critical("odyssey_workspace_new failed")
                return
            }
            self.workspace = workspace
        }

        deinit {
            self.workspace = nil
        }
    }
}
