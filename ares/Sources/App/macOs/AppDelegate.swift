import AppKit
import Cocoa
import SwiftUI
import AresKit
import UserNotifications
import OSLog


class AppDelegate: NSObject, NSApplicationDelegate {
    let ares = Ares.App()
    var window: NSWindow?


    private var applicationHasBecomeActive: Bool = false

    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: AppDelegate.self)
    )

    func applicationDidFinishLaunching(_ notification: Notification) {

    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Create the window only once when the application first becomes active
        guard self.window == nil else {
            return
        }

        Ares.logger.info("application become active")

        // Use the 'app' property from your 'ares' instance
        guard let aresCValue = ares.app else { // Changed from ares.unsafeCValue to ares.app
            Ares.logger.error("Failed to get ares_app_t from Ares.App instance.")
            return
        }

        // Define the initial window size and style
        let contentRect = NSMakeRect(100, 100, 800, 600)
        let styleMask: NSWindow.StyleMask = [.titled, .closable, .resizable, .miniaturizable]
        let newWindow = NSWindow(contentRect: contentRect, styleMask: styleMask, backing: .buffered, defer: false)
        newWindow.title = "Ares Terminal Window"
        newWindow.center() // Center the window on the screen

        // Create the SurfaceView, passing the ares_app_t instance
        let surfaceView = Ares.SurfaceView(aresCValue)
        surfaceView.translatesAutoresizingMaskIntoConstraints = false

        // Create a button
        let button = NSButton(title: "Do Something", target: nil, action: nil)
        button.translatesAutoresizingMaskIntoConstraints = false

        // Create a vertical stack view to arrange the surface view and the button
        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .centerX // Center horizontally
        stackView.distribution = .fill // Allow views to fill available space
        stackView.spacing = 10 // Space between views
        stackView.translatesAutoresizingMaskIntoConstraints = false

        stackView.addView(surfaceView, in: .center)
        stackView.addView(button, in: .center)

        // Set the stack view as the window's content view
        newWindow.contentView = stackView

        // Add constraints for the stack view to fill the content view
        if let contentView = newWindow.contentView {
            NSLayoutConstraint.activate([
                stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                stackView.topAnchor.constraint(equalTo: contentView.topAnchor),
                stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            ])
        }

        // Make the window visible
        newWindow.makeKeyAndOrderFront(nil)
        self.window = newWindow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
