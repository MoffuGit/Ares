//
//  AppDelegate.swift
//  Odyssey
//
//  Created by Adrian Hess on 01/06/26.
//

import Cocoa
import OdysseyKit
import os

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    @IBOutlet var window: NSWindow!
    private var app: Odyssey.App!

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let result = odyssey_init(0, nil)

        guard result == 0 else {
            Odyssey.logger.critical("odyssey_init failed: \(result)")
            NSApp.terminate(self)
            return
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        app = nil
        odyssey_deinit()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
