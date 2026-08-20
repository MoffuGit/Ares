//
//  OdysseyApp.swift
//  Odyssey
//
//  Created by Adrian Hess on 18/08/26.
//
import OdysseyKit
import os

extension Odyssey {
    class App {
        var app: odyssey_app_t? = nil {
            didSet {
                guard let old = oldValue else { return }
                odyssey_app_free(old)
            }
        }

        init(runtime: inout odyssey_runtime_s) {
            guard let app = odyssey_app_new(&runtime) else {
                logger.critical("odyssey_app_new failed")
                return
            }

            self.app = app
        }
        
        func run() {
            guard let app = self.app else {return}
            odyssey_app_run(app)
        }

        deinit {
            self.app = nil
        }
    }
}
