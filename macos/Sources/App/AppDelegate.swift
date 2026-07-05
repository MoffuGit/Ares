//
//  AppDelegate.swift
//  Odyssey
//
//  Created by Adrian Hess on 02/07/26.
//

import Cocoa
import OdysseyKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var app: Odyssey.App!

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        app = Odyssey.App()
        let controller = WorkspaceController(delegate: self)
        controller.showWindow(nil)
        controller.window?.center()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        odyssey_db_stop()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
