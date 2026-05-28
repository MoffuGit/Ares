//
//  OdysseyApp.swift
//  Odyssey
//
//  Created by Adrian Hess on 26/05/26.
//

import SwiftUI
import OdysseyKit

@main
struct OdysseyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    
     var app: odyssey_app_t? {
        didSet {
            guard let old = oldValue else { return }
            odyssey_app_free(old)
        }
    }


    init() {
        precondition(odyssey_init(CommandLine.argc, CommandLine.unsafeArgv) == 0)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
    }
}

extension OdysseyApp {
    final class AppDelegate: NSObject, NSApplicationDelegate {
        func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
            true
        }

        func applicationWillTerminate(_ notification: Notification) {
            odyssey_deinit()
        }
    }
}
