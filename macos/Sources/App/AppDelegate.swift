//
//  AppDelegate.swift
//  Odyssey
//
//  Created by Adrian Hess on 18/08/26.
//

import AppKit
import OdysseyKit
import os

@main
class Application: NSApplication {
    static func main() {
        guard odyssey_init(CommandLine.argc, CommandLine.unsafeArgv) == 0 else {
            Odyssey.logger.critical("odyssey_init failed")
            exit(1)
        }

        let application = Application.shared
        
        var runtime = odyssey_runtime_s(
            userdata: Unmanaged.passUnretained(application).toOpaque(),
            event_callback: { userdata in Application.events(userdata) })
        let app = Odyssey.App(runtime: &runtime)
        let delegate = AppDelegate(app: app)
        application.delegate = delegate
        
        Bundle.main.loadNibNamed("MainMenu", owner: NSApp, topLevelObjects: nil)
        
        app.run();
    }

    static func events(_ userdata: UnsafeMutableRawPointer?) {
        let application = Unmanaged<Application>.fromOpaque(userdata!).takeUnretainedValue()
        while let event = application.nextEvent(
            matching: .any, until: nil, inMode: .default, dequeue: true)
        {
            application.sendEvent(event)
        }
        application.updateWindows()

    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var app: Odyssey.App

    init(app: Odyssey.App) {
        self.app = app
        super.init()
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let controller = WindowController(appDelegate: self)
        controller.showWindow(nil)
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}
