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
        var onChange: ((UInt) -> Void)?
        private(set) var count: UInt = 0
        var workspace: odyssey_entity_s? {
            didSet {
                guard let old = oldValue else { return }
                odyssey_drop_entity(old)
            }
        }
        private var subscription: odyssey_observer_s?

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
            let subscription = odyssey_workspace_observe(
                app,
                creation.entity,
                { userdata, data in
                    guard let userdata else { return false }
                    let workspace = Unmanaged<Odyssey.Workspace>
                        .fromOpaque(userdata)
                        .takeUnretainedValue()
                    workspace.count = UInt(data.count)
                    workspace.onChange?(workspace.count)
                    return true
                },
                Unmanaged.passUnretained(self).toOpaque()
            )
            guard subscription.valid else {
                logger.critical("odyssey_workspace_observe failed")
                return
            }
            self.subscription = subscription.observer
        }

        deinit {
            if let subscription {
                odyssey_workspace_unobserve(subscription)
            }
            self.workspace = nil
        }
    }
}
