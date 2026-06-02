//
//  ProjectsContainer.swift
//  Odyssey
//
//  Created by Adrian Hess on 01/06/26.
//
import AppKit
import SwiftUI

class ProjectsContainer: NSView {
    private let hostingView: NSHostingView<ProjectsView>
    private let padding: CGFloat = 35.0
    private let lineColor: NSColor = NSColor(hex: "#A8A8A8")
    private let lineWidth: CGFloat = if let scale_factor = NSScreen.main?.backingScaleFactor {
        0.5 / scale_factor
    } else {
        0.5
    };

    init(app: Odyssey.App) {
        self.hostingView = NSHostingView(rootView: ProjectsView(app: app))
        
        super.init(frame: .zero)
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor(hex: "#ffffff").cgColor
        
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)
        
        let offset = (padding + lineWidth)
        
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: offset),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -offset),
            hostingView.topAnchor.constraint(equalTo: topAnchor, constant: offset),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -offset),
        ])
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        let bounds = self.bounds
        let path = NSBezierPath()
        path.lineWidth = lineWidth
        lineColor.setStroke()
        
        let lx =  padding - lineWidth
        let rx = bounds.width - lx
        
        path.move(to: NSPoint(x: lx, y: 0))
        path.line(to: NSPoint(x: lx, y: bounds.height))
        
        path.move(to: NSPoint(x: rx, y: 0))
        path.line(to: NSPoint(x: rx, y: bounds.height))
        
        let ty = padding - lineWidth
        let by = bounds.height - ty;
        
        path.move(to: NSPoint(x: 0, y: ty))
        path.line(to: NSPoint(x: bounds.width, y: ty))
        
        path.move(to: NSPoint(x: 0, y: by))
        path.line(to: NSPoint(x: bounds.width, y: by))

        path.stroke()
    }
}
