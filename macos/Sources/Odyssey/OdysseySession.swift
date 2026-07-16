//
//  OdysseySession.swift
//  Odyssey
//
//  Created by Adrian Hess on 05/07/26.
//

import OdysseyKit
import os

extension Odyssey {
    class Session: Entity {
        init(app: Odyssey.App) {
            guard let odysseyApp = app.app else {
                logger.critical("odyssey_session_new failed: app is nil")
                super.init(app: app, entity: nil)
                return
            }

            let maybe_entity = odyssey_session_new(odysseyApp)
            guard maybe_entity.valid else {
                logger.critical("odyssey_session_new failed")
                super.init(app: app, entity: nil)
                return
            }

            super.init(app: app, entity: maybe_entity.entity)
        }
    }
}
