//
//  OdysseyWorkspace.swift
//  Odyssey
//
//  Created by Adrian Hess on 02/06/26.

import Observation
import OdysseyKit
import os

extension Odyssey {
    @Observable @MainActor
    final class Workspace {
        var count: Int {
            guard let app = app.app, let entity else { return 0 }

            return Int(odyssey_workspace_read(app, entity).count)
        }

        @ObservationIgnored private let app: Odyssey.App
        @ObservationIgnored private var entity: odyssey_entity_s?
        @ObservationIgnored private var observer: odyssey_observer_s?
        private(set) var updateGeneration: UInt64 = 0

        init(app: Odyssey.App) {
            self.app = app

            guard let app = app.app else {
                logger.critical("odyssey_workspace_new failed: app is nil")
                return
            }

            let maybe_entity = odyssey_workspace_new(app)
            guard maybe_entity.valid else {
                logger.critical("odyssey_workspace_new failed")
                return
            }

            self.entity = maybe_entity.entity
            startObserving(app)
        }

        private func startObserving(_ app: odyssey_app_t) {
            guard let entity else { return }

            let maybe_observer = odyssey_workspace_observe(app, entity, { userdata, snapshot in
                guard let userdata else { return false }
                let workspace = Unmanaged<Workspace>.fromOpaque(userdata).takeUnretainedValue()

                MainActor.assumeIsolated {
                    workspace.updateGeneration &+= 1
                }

                return true
            }, Unmanaged.passUnretained(self).toOpaque())

            guard maybe_observer.valid else {
                logger.critical("odyssey_workspace_observe failed")
                return
            }

            self.observer = maybe_observer.observer
        }

        deinit {
            if let observer {
                odyssey_workspace_unobserve(observer)
            }
            if let entity {
                odyssey_drop_entity(entity)
            }
        }
    }
}
