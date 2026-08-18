//
//  WindowController.swift
//  Odyssey
//
//  Created by Adrian Hess on 18/08/26.
//

import AppKit

class WindowController: NSWindowController, NSWindowDelegate {
    private weak var appDelegate: AppDelegate?
    
    init(appDelegate: AppDelegate? = nil) {
        self.appDelegate = appDelegate
        
        let window = NSWindow(contentRect: NSMakeRect(0,0,800,600), styleMask: [.closable, .miniaturizable, .resizable, .titled], backing: .buffered, defer: false);
        super.init(window: window);
        window.delegate = self
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
