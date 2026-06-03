//
//  AppDelegate.swift
//  Odyssey
//
//  Created by Adrian Hess on 01/06/26.
//

import Cocoa
import Combine
import OdysseyKit
import os

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private var app: Odyssey.App!
    private var projectControllerState: ProjectsState = .uninitialized
    @Published var projects: [Project] = []

    var projectsController: ProjectsController {
        switch projectControllerState {
        case .initialized(let controller):
            return controller

        case .uninitialized:
            let controller = ProjectsController(app: self)
            projectControllerState = .initialized(controller)
            return controller
        }
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        app = Odyssey.App()
        projectsController.showWindow(nil)
        projectsController.window?.center()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func addProject(project: Project) {
        projects.append(project)
    }
}

private enum ProjectsState {
    case uninitialized
    case initialized(ProjectsController)
}
