import SwiftUI
import Combine
import AresKit
import os

extension Ares {
    class App: ObservableObject {
        @Published var app: ares_app_t? = nil

        init() {
            guard let app = ares_app_new() else {
                logger.critical("ares_app_new failed")
                return
            }
            self.app = app
        }

        deinit {
            self.app = nil
        }
    }
}
