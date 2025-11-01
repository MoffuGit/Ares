import AppKit
import AresKit
import CoreText
import SwiftUI
import UserNotifications
import os

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
            config.scale_factor = NSScreen.main!.backingScaleFactor

            let surface = ares_surface_new(app, config)

            guard let surface = surface else {
                return
            }
            self.surfaceModel = Ares.Surface(cSurface: surface)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported for this view")
        }

        func sizeDidChange(_ newSize: CGSize) {
            let scaledSize = self.convertToBacking(newSize)
            setSurfaceSize(width: UInt32(scaledSize.width), height: UInt32(scaledSize.height))

        }

        private func setSurfaceSize(width: UInt32, height: UInt32) {
            guard let surface = self.surface else { return }

            ares_surface_set_size(surface, width, height)
        }

        override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()

            // The Core Animation compositing engine uses the layer's contentsScale property
            // to determine whether to scale its contents during compositing. When the window
            // moves between a high DPI display and a low DPI display, or the user modifies
            // the DPI scaling for a display in the system settings, this can result in the
            // layer being scaled inappropriately. Since we handle the adjustment of scale
            // and resolution ourselves below, we update the layer's contentsScale property
            // to match the window's backingScaleFactor, so as to ensure it is not scaled by
            // the compositor.
            //
            // Ref: High Resolution Guidelines for OS X
            // https://developer.apple.com/library/archive/documentation/GraphicsAnimation/Conceptual/HighResolutionOSX/CapturingScreenContents/CapturingScreenContents.html#//apple_ref/doc/uid/TP40012302-CH10-SW27
            if let window = window {
                CATransaction.begin()
                // Disable the implicit transition animation that Core Animation applies to
                // property changes. Otherwise it will apply a scale animation to the layer
                // contents which looks pretty janky.
                CATransaction.setDisableActions(true)
                layer?.contentsScale = window.backingScaleFactor
                CATransaction.commit()
            }

            guard let surface = self.surface else { return }

            // Detect our X/Y scale factor so we can update our surface
            let fbFrame = self.convertToBacking(self.frame)
            let xScale = fbFrame.size.width / self.frame.size.width
            let yScale = fbFrame.size.height / self.frame.size.height
            ares_surface_set_content_scale(surface, xScale, yScale)

            // When our scale factor changes, so does our fb size so we send that too
            setSurfaceSize(width: UInt32(fbFrame.size.width), height: UInt32(fbFrame.size.height))
        }

    }

    struct SurfaceWrapper: View {
        let surfaceView: SurfaceView
        @EnvironmentObject private var ghostty: Ares.App

        var body: some View {
            ZStack {
                GeometryReader { geo in
                    SurfaceRepresentable(view: self.surfaceView, size: geo.size)
                }
            }
        }
    }

    struct SurfaceRepresentable: NSViewRepresentable {
        let view: SurfaceView
        let size: CGSize

        func makeNSView(context: Context) -> SurfaceView {
            return view
        }

        func updateNSView(_ nsView: SurfaceView, context: Context) {
            nsView.sizeDidChange(size)
        }
    }
}
