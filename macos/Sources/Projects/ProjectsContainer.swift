//
//  ProjectsContainer.swift
//  Odyssey
//
//  Created by Adrian Hess on 01/06/26.
//
import AppKit

class ProjectsContainer: NSView {
    init() {
        super.init(frame: .zero)
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor(hex: "#f8f8f8").cgColor
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
