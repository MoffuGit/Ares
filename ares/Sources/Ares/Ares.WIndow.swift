import AresKit
//
//  Ares.WIndow.swift
//  ares
//
//  Created by Adrian Hess on 23/10/25.
//
import Cocoa
import Combine
import SwiftUI
import os

class BaseWindowController: NSWindowController, NSWindowDelegate {
    let ares: Ares.App
    let surface: Ares.SurfaceView

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported for this view")
    }

    init(_ ares: Ares.App) {
        self.ares = ares

        guard let ares = ares.app else { preconditionFailure("app must be loaded") }
        self.surface = .init(ares)

        let newWindow = NSWindow(
            contentRect: NSMakeRect(0, 0, 800, 600),
            styleMask: [.closable, .miniaturizable, .resizable, .titled],
            backing: .buffered, defer: false)
        newWindow.center()
        newWindow.title = "Ares"

        newWindow.contentView = NSHostingView(
            rootView: Ares.SurfaceWrapper(surfaceView: self.surface))

        super.init(window: newWindow)
    }
}

class WindowController: BaseWindowController {
    static func newWindow(_ ares: Ares.App) -> WindowController {
        let controller = WindowController.init(ares)
        DispatchQueue.main.async {

            controller.showWindow(self)
            NSApp.activate(ignoringOtherApps: true)
        }

        return controller
    }
}
