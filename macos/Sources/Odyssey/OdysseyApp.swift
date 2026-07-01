//
//  OdysseyApp.swift
//  Odyssey
//
//  Created by Adrian Hess on 01/06/26.
//
import OdysseyKit
import os

extension Odyssey {
    class App  {
        var app: odyssey_app_t? {
            didSet {
                guard let old = oldValue else { return }
                odyssey_app_free(old)
            }
        }
        private var options: odyssey_options_s
        
        init() {
            self.options = odyssey_options_s(
                userdata: nil,
                wakeup_cb: { userdata in
                    DispatchQueue.main.async {
                        guard let userdata else { return }
                        odyssey_app_flush(userdata)
                    }
                }
            )
            guard let app = odyssey_app_new(&self.options) else {
                logger.critical("odyssey_app_new failed")
                return
            }
            self.app = app
            self.options.userdata = app
        }
        
        deinit {
            self.app = nil;
        }
    }
}
