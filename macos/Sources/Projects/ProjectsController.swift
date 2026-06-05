//
//  ProjectsController.swift
//  Odyssey
//
//  Created by Adrian Hess on 01/06/26.
//

import AppKit
import Combine
import SwiftUI

private final class ProjectsWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

class ProjectsController: NSWindowController,
    NSWindowDelegate
{
    private var cancellables = Set<AnyCancellable>()
    private var toolbarAccessory: NSTitlebarAccessoryViewController?

    init(app: AppDelegate) {
        let window = ProjectsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 550, height: 450),
            styleMask: [.closable, .miniaturizable, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.isRestorable = false
        window.contentView = ProjectsView(app: app)
        window.backgroundColor = .clear
        window.isOpaque = false

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
