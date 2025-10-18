import AppKit
import Cocoa
import SwiftUI
import AresKit
import UserNotifications
import OSLog


class AppDelegate: NSObject, NSApplicationDelegate {
    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: AppDelegate.self)
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.logger.info("this run (from OSLog)")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
