//
//  OdysseyApp.swift
//  Odyssey
//
//  Created by Adrian Hess on 28/05/26.
//

import Combine
import Foundation
import OdysseyKit
import os

extension Odyssey {
    final class App: ObservableObject {
        static let shared = App()

        private var app: odyssey_app_t?

        private init() {
            precondition(odyssey_init(CommandLine.argc, CommandLine.unsafeArgv) == 0)

            guard let app = odyssey_app_new() else {
                logger.error("Unable to create Odyssey app")
                return
            }

            self.app = app
        }

        deinit {
            if let app {
                odyssey_app_free(app)
            }

            odyssey_deinit()
        }

        func makeWorkspace() -> Workspace {
            Workspace(app: self)
        }

        fileprivate func newWorkspace() -> odyssey_workspace_t? {
            guard let app else { return nil }
            return odyssey_workspace_new(app)
        }

        fileprivate func freeWorkspace(_ workspace: odyssey_workspace_t) {
            guard let app else { return }
            odyssey_workspace_free(app, workspace)
        }
    }

    final class Workspace: ObservableObject {
        private weak var app: App?
        private var workspace: odyssey_workspace_t?

        fileprivate init(app: App) {
            self.app = app

            guard let workspace = app.newWorkspace() else {
                logger.error("Unable to create Odyssey workspace")
                return
            }

            self.workspace = workspace
        }

        deinit {
            if let app, let workspace {
                app.freeWorkspace(workspace)
            }
        }
    }
}
