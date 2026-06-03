//
//  ProjectsController.swift
//  Odyssey
//
//  Created by Adrian Hess on 01/06/26.
//

import AppKit
import Combine

class ProjectsController: NSWindowController,
    NSWindowDelegate
{
    private var cancellables = Set<AnyCancellable>()

    init(app: AppDelegate) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.closable, .miniaturizable, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isRestorable = false
        window.contentView = ProjectsView(app: app)
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        super.init(window: window)

        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
