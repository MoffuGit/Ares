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
    class App: ObservableObject {
        private var app: odyssey_app_t?

        init() {
            precondition(odyssey_init(CommandLine.argc, CommandLine.unsafeArgv) == 0)

            guard let app = odyssey_app_new() else {
                logger.error("Unable to create Odyssey app")
                return;
            }

            self.app = app
        }

        deinit {
            if let app {
                odyssey_app_free(app)
            }

            odyssey_deinit()
        }
    }
}
