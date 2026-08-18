//
//  AppDelegate.swift
//  Odyssey
//
//  Created by Adrian Hess on 18/08/26.
//

import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var app: Odyssey.App
    
    override init() {
        app = Odyssey.App()
        super.init()
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let controller = WindowController(appDelegate: self);
        controller.showWindow(nil);
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
