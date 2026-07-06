//
//  OdysseyEntity.swift
//  Odyssey
//
//  Created by Adrian Hess on 05/07/26.
//

import OdysseyKit

extension Odyssey {
    @MainActor
    class Entity {
        let app: Odyssey.App
        var entity: odyssey_entity_s?

        init(app: Odyssey.App, entity: odyssey_entity_s?) {
            self.app = app
            self.entity = entity
        }

        deinit {
            if let entity {
                odyssey_drop_entity(entity)
            }
        }
    }
}
