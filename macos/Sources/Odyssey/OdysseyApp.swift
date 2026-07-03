//
//  OdysseyApp.swift
//  Odyssey
//
//  Created by Adrian Hess on 01/06/26.
//
import OdysseyKit
import os

extension Odyssey {
    class App {
        var app: odyssey_app_t? {
            didSet {
                guard let old = oldValue else { return }
                odyssey_app_free(old)
            }
        }

        init() {
            var options = odyssey_options_s(
                userdata: Unmanaged.passUnretained(self).toOpaque(),
                wakeup_cb: { userdata in App.wakeup(userdata)
                }
            )
            guard let app = odyssey_app_new(&options) else {
                logger.critical("odyssey_app_new failed")
                return
            }
            self.app = app
        }

        deinit {
            self.app = nil
        }

        static func wakeup(_ userdata: UnsafeMutableRawPointer?) {
            let state = Unmanaged<App>.fromOpaque(userdata!)
                .takeUnretainedValue()

            DispatchQueue.main.async {
                odyssey_app_flush(state.app)
            }
        }
    }
}
