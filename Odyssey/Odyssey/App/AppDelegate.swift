//
//  AppDelegate.swift
//  Odyssey
//
//  Created by Adrian Hess on 28/05/26.
//

import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    let odyssey = Odyssey.App.shared

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
