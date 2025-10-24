import AppKit
import AresKit
import Cocoa
import OSLog
import SwiftUI
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate {
    let ares = Ares.App()

    private var applicationHasBecomeActive: Bool = false

    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: AppDelegate.self)
    )

    func applicationDidBecomeActive(_ notification: Notification) {
        _ = WindowController.newWindow(ares)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
