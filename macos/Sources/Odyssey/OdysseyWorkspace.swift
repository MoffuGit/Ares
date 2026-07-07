//
//  OdysseyWorkspace.swift
//  Odyssey
//
//  Created by Adrian Hess on 02/06/26.

import OdysseyKit
import os

extension Odyssey {
    final class SerializedWorkspaces {
        let list: odyssey_workspace_list_s

        init(_ list: odyssey_workspace_list_s) {
            self.list = list
        }

        static func getAllMetadataAndValidate() -> SerializedWorkspaces {
            SerializedWorkspaces(odyssey_workspace_get_all_metadata_and_validate())
        }

        static func getBySession(app: Odyssey.App, session: Odyssey.Session) -> SerializedWorkspaces
        {
            guard let odysseyApp = app.app, let sessionEntity = session.entity else {
                logger.critical("odyssey_workspace_get_by_session failed: app or session is nil")
                return SerializedWorkspaces(odyssey_workspace_list_s(ptr: nil, len: 0))
            }

            return SerializedWorkspaces(odyssey_workspace_get_by_session(odysseyApp, sessionEntity))
        }

        deinit {
            odyssey_workspace_list_free(list)
        }
    }

    final class Workspace: Entity {
        init(app: Odyssey.App) {
            guard let odysseyApp = app.app else {
                logger.critical("odyssey_workspace_new failed: app is nil")
                super.init(app: app, entity: nil)
                return
            }

            let maybe_entity = odyssey_workspace_new(odysseyApp)
            guard maybe_entity.valid else {
                logger.critical("odyssey_workspace_new failed")
                super.init(app: app, entity: nil)
                return
            }

            super.init(app: app, entity: maybe_entity.entity)
        }
    }
}
