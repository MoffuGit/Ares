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
    private var app: Odyssey.App!

    @IBOutlet var window: NSWindow!

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Insert code here to initialize your application
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}
