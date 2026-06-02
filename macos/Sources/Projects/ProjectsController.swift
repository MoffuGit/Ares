//
//  ProjectsController.swift
//  Odyssey
//
//  Created by Adrian Hess on 01/06/26.
//

import AppKit

class ProjectsController: NSWindowController,
    NSWindowDelegate
{

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Projects"
        window.center()

        super.init(window: window)

        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
