import AppKit
import AresKit
import Combine
import CoreText
import SwiftUI
import UserNotifications
import os

extension Ares {
    /// The NSView implementation for a terminal surface.
    class SurfaceView: NSView, Identifiable, ObservableObject {

        typealias ID = UUID

        /// Unique ID per surface
        let id: UUID

        @Published var pwd: String? = nil

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

        func setFile(pwd: String) {
            let len = pwd.utf8CString.count
            if len == 0 { return }

            self.pwd = pwd
            pwd.withCString { ptr in
                ares_surface_set_file(surface, ptr)
            }

        }
    }

    struct SurfaceWrapper: View {
        let surfaceView: SurfaceView
        @EnvironmentObject private var ghostty: Ares.App

        private func presentFilePicker() {
            let panel = NSOpenPanel()
            panel.canChooseFiles = true  // Allow selecting files
            panel.canChooseDirectories = false  // Disallow selecting directories
            panel.allowsMultipleSelection = false  // Only allow single file selection
            panel.prompt = "Select File"  // Custom prompt for the panel

            // Present the panel modally.
            // The completion handler will be called when the user makes a selection or cancels.
            panel.begin(completionHandler: { response in
                if response == .OK {
                    if let url = panel.url {
                        let filePath = url.path  // Get the file path from the URL
                        self.surfaceView.setFile(pwd: filePath)  // Call setFile on the SurfaceView
                    }
                }
            })
        }

        var body: some View {
            ZStack {
                // The existing SurfaceRepresentable, filling the available space
                GeometryReader { geo in
                    SurfaceRepresentable(view: self.surfaceView, size: geo.size)
                }

                // File selector UI overlay positioned top-right
                VStack {
                    HStack {
                        Spacer()  // Pushes the button to the right
                        Button(action: {
                            self.presentFilePicker()
                        }) {
                            Label("Open File", systemImage: "doc.fill")  // Using SF Symbol for a modern look
                                .font(.caption)  // Make the text/icon slightly smaller
                                .padding(8)
                                .background(Color.primary.opacity(0.1))  // Subtle background for the button
                                .cornerRadius(5)
                        }
                        .buttonStyle(PlainButtonStyle())  // Makes the button appear as a styled label, not a standard macOS button
                        .padding([.top, .trailing], 10)  // Padding from the top and right edges of the view
                    }
                    Spacer()  // Pushes the HStack (and thus the button) to the top
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
