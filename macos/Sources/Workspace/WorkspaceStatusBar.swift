//
//  WorkspaceStatusBar.swift
//  Odyssey
//
//  Created by Adrian Hess on 15/07/26.
//

import AppKit

class WorkspaceStatusBar: NSView {
    fileprivate enum Metrics {
        static let height: CGFloat = 32
    }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Metrics.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.separatorColor.setFill()
        NSRect(x: bounds.minX, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
