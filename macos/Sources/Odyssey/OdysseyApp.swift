//
//  OdysseyApp.swift
//  Odyssey
//
//  Created by Adrian Hess on 01/06/26.

import Foundation
import OdysseyKit
import os

extension Odyssey {
    actor FlushQueueState {
        private var isQueued = false
        
        func markQueued() -> Bool {
            guard !isQueued else { return false }
            isQueued = true
            return true
        }
        
        func markFinished() {
            isQueued = false
        }
    }
    
    class App {
        private let flushQueueState = FlushQueueState()
        
        var app: odyssey_app_t? {
            didSet {
                guard let old = oldValue else { return }
                odyssey_app_free(old)
            }
        }
        
        init() {
            var options = odyssey_options_s(
                userdata: Unmanaged.passUnretained(self).toOpaque(),
                wakeup_cb: { userdata in
                    App.wakeup(userdata)
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
        
        func enqueueFlush() {
            Task { [weak self] in
                guard let self else { return }
                
                let shouldFlush = await flushQueueState.markQueued() 
                guard shouldFlush else { return }
                
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    
                    Task {
                        await self.flushQueueState.markFinished()
                    }
                    
                    odyssey_app_flush(self.app)
                }
            }
        }
        
        static func wakeup(_ userdata: UnsafeMutableRawPointer?) {
            let state = Unmanaged<App>.fromOpaque(userdata!)
                .takeUnretainedValue()
            
            state.enqueueFlush()
        }
    }
}
