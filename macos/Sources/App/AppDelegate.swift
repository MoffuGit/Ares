//
//  AppDelegate.swift
//  Odyssey
//
//  Created by Adrian Hess on 01/06/26.
//

import Cocoa
import OdysseyKit
import os

class AppDelegate: NSObject, NSApplicationDelegate {
    private var app: Odyssey.App!
    private var projectControllerState: ProjectsState = .uninitialized

    var projectsController: ProjectsController {
        switch projectControllerState {
        case .initialized(let controller):
            return controller

        case .uninitialized:
            let controller = ProjectsController()
            projectControllerState = .initialized(controller)
            return controller
        }
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        projectsController.showWindow(nil)
    }

    func applicationWillTerminate(_ aNotification: Notification) {
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

private enum ProjectsState {
    case uninitialized
    case initialized(ProjectsController)
}
