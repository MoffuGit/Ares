import AppKit
import Cocoa
import SwiftUI
import AresKit
import UserNotifications
import OSLog


class AppDelegate: NSObject, NSApplicationDelegate {
    let ares = Ares.App()

    private var applicationHasBecomeActive: Bool = false

    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: AppDelegate.self)
    )

    func applicationDidFinishLaunching(_ notification: Notification) {

    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if (!applicationHasBecomeActive) {
            applicationHasBecomeActive = true

            Ares.logger.info("application become active")

            // Define a simple SwiftUI View with a button
            let contentView = VStack {
                Button("Click Me") {
                    print("Button clicked!")
                }
                .padding()
            }
            .frame(width: 300, height: 200) // Set a size for the content

            // Create an NSHostingController to host the SwiftUI view
            let hostingController = NSHostingController(rootView: contentView)

            // Access the main application window
            if let mainWindow = NSApplication.shared.mainWindow {
                mainWindow.contentViewController = hostingController // Set the hosting controller as the main window's content
                mainWindow.title = "Ares Button Surface" // Optionally update the window title
                mainWindow.makeKeyAndOrderFront(nil) // Ensure the window is visible and frontmost
            } else {
                Ares.logger.error("Could not find the main application window.")
            }
        }

    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
