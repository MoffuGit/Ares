import AppKit
import SwiftUI
import CoreText
import UserNotifications
import AresKit

extension Ares {
    /// The NSView implementation for a terminal surface.
    class SurfaceView: NSView, Identifiable {

        typealias ID = UUID

        /// Unique ID per surface
        let id: UUID

        /// Returns the data model for this surface.
        ///
        /// Note: eventually, all surface access will be through this, but presently its in a transition
        /// state so we're mixing this with direct surface access.
        private(set) var surfaceModel: Ares.Surface?

        /// Returns the underlying C value for the surface. See "note" on surfaceModel.
        var surface: ares_surface_t? {
            surfaceModel?.unsafeCValue
        }

        init(_ app: ares_app_t, uuid: UUID? = nil) {
            self.id = uuid ?? .init()

            // Initialize with some default frame size. The important thing is that this
            // is non-zero so that our layer bounds are non-zero so that our renderer
            // can do SOMETHING.
            super.init(frame: NSMakeRect(0, 0, 800, 600))

            // Setup our surface. This will also initialize all the terminal IO.
            var config = ares_surface_config_s()
            config.platform.macos.nsview = Unmanaged.passUnretained(self).toOpaque()

            let surface = ares_surface_new(app, config)


            guard let surface = surface else {
                return
            }
            self.surfaceModel = Ares.Surface(cSurface: surface)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported for this view")
        }

        deinit {
        }

        func sizeDidChange(_ newSize: CGSize) {
            print("Ares.SurfaceView size changed to: \(newSize)")
        }

    }
}
