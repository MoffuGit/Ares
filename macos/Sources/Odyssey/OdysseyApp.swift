//
//  OdysseyApp.swift
//  Odyssey
//
//  Created by Adrian Hess on 01/06/26.

import Foundation
import OdysseyKit
import os

private final class OdysseyWakeContext: @unchecked Sendable {
    weak var app: Odyssey.App?

    init(app: Odyssey.App) {
        self.app = app
    }

    nonisolated func wake() {
        Task { @MainActor [weak self] in
            self?.app?.flush()
        }
    }
}

extension Odyssey {
    class App {
        var app: odyssey_app_t? = nil {
            didSet {
                guard let old = oldValue else { return }
                odyssey_app_free(old)
            }
        }

        private var wakeContext: UnsafeMutableRawPointer? = nil

        init() {
            wakeContext = Unmanaged.passRetained(OdysseyWakeContext(app: self)).toOpaque()
            var options = odyssey_options_s(
                userdata: wakeContext,
                wakeup_cb: { userdata in
                    App.wakeup(userdata)
                }
            )

            guard let app = odyssey_app_new(&options) else {
                Unmanaged<OdysseyWakeContext>.fromOpaque(wakeContext!).release()
                wakeContext = nil
                logger.critical("odyssey_app_new failed")
                return
            }

            self.app = app
        }

        deinit {
            self.app = nil
            if let wakeContext {
                Unmanaged<OdysseyWakeContext>.fromOpaque(wakeContext).release()
            }
        }

        fileprivate func flush() {
            odyssey_app_flush(app)
        }

        nonisolated static func wakeup(_ userdata: UnsafeMutableRawPointer?) {
            let state = Unmanaged<OdysseyWakeContext>.fromOpaque(userdata!)
                .takeUnretainedValue()

            state.wake()
        }
    }
}
