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
            styleMask: [.closable, .miniaturizable, .resizable, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.titleVisibility = .hidden;
        window.titlebarAppearsTransparent = true;
        window.isRestorable = false;
        window.contentView = ProjectsContainer()

        super.init(window: window)
        
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
