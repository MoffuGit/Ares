//
//  ProjectsController.swift
//  Odyssey
//
//  Created by Adrian Hess on 01/06/26.
//

import AppKit
import Combine
import SwiftUI

class ProjectsController: NSWindowController,
    NSWindowDelegate
{
    private var cancellables = Set<AnyCancellable>()
    private var toolbarAccessory: NSTitlebarAccessoryViewController?

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

        let toolbarHostingView = NSHostingView(rootView: ProjectsToolbar(app: app).fixedSize())
        toolbarHostingView.setContentHuggingPriority(.required, for: .horizontal)
        toolbarHostingView.setContentHuggingPriority(.required, for: .vertical)
        toolbarHostingView.setContentCompressionResistancePriority(.required, for: .horizontal)
        toolbarHostingView.setContentCompressionResistancePriority(.required, for: .vertical)
        toolbarHostingView.setFrameSize(toolbarHostingView.fittingSize)

        let toolbarAccessory = NSTitlebarAccessoryViewController()
        toolbarAccessory.view = toolbarHostingView
        toolbarAccessory.layoutAttribute = .right

        window.addTitlebarAccessoryViewController(toolbarAccessory)

        super.init(window: window)

        self.toolbarAccessory = toolbarAccessory
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
