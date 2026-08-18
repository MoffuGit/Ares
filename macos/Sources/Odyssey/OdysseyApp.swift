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

        init() {
            guard let app = odyssey_app_new() else {
                logger.critical("odyssey_app_new failed")
                return
            }

            self.app = app
        }

        deinit {
            self.app = nil
        }
    }
}
