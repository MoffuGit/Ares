//
//  WorkspaceContent.swift
//  Odyssey
//
//  Created by Adrian Hess on 15/07/26.
//

import AppKit

class WorkspaceContent: NSView {
    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
