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
        // Create the window only once when the application first becomes active

        // Define the initial window size and style
        let controller = WindowController.init(ares)
        DispatchQueue.main.async {
            controller.showWindow(self)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
