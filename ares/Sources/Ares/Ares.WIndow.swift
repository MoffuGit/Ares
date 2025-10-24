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

class WindowController: NSWindowController, NSWindowDelegate {
    let ares: Ares.App
    @Published var surface: Ares.SurfaceView? = nil

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

        super.init(window: newWindow)

        if let surface = self.surface {
            surface.autoresizingMask = [.width, .height]
            newWindow.contentView = surface
        }

        self.windowDidLoad()
    }
}
