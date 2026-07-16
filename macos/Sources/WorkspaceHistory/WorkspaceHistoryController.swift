//
//  WorkspaceListController.swift
//  Odyssey
//
//  Created by Adrian Hess on 03/07/26.
//

import AppKit

private class WorkspaceHistoryWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

private class WorkspaceHistoryContainer: NSStackView {
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        super.updateLayer()
        let isDark = effectiveAppearance.bestMatch(
            from: [.aqua, .darkAqua]) == .darkAqua
        layer?.backgroundColor = (isDark ? NSColor.black : NSColor.white).cgColor
    }
}

class WorkspaceHistoryController: NSWindowController,
    NSWindowDelegate
{
    private let content: WorkspaceHistoryContent

    init(app: AppDelegate, historyManager: WorkspaceHistoryManager) {
        let window = WorkspaceHistoryWindow(
            contentRect: NSRect(x: 0, y: 0, width: 650, height: 550),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden

        let stackView = WorkspaceHistoryContainer()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        stackView.spacing = 0
        stackView.wantsLayer = true
        stackView.layer?.masksToBounds = true
        stackView.layer?.cornerRadius = 16
        stackView.needsDisplay = true
        let content = WorkspaceHistoryContent(app: app, manager: historyManager)
        self.content = content
        stackView.addArrangedSubview(WorkspaceHistoryToolbar(app: app))
        stackView.addArrangedSubview(content)

        super.init(window: window)

        window.delegate = self
        window.contentView = stackView
    }

    func reload() {
        content.reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

}
