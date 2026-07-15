//
//  WorkspaceSplitViewController.swift
//  Odyssey
//
//  Created by Adrian Hess on 14/07/26.
//


import AppKit

class WorkspaceSplitViewController: NSSplitViewController {
    let sidebar = SidebarViewController()
    let content = ContentViewController()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        splitView.isVertical = true
        
        let sidebarItem = NSSplitViewItem(viewController: sidebar)
        let contentItem = NSSplitViewItem(viewController: content)
        
        addSplitViewItem(sidebarItem)
        addSplitViewItem(contentItem)
    }
}

class SidebarViewController: NSViewController {
    override func loadView() {
        view = NSView()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.white.cgColor
    }
}

class ContentViewController: NSViewController {
    override func loadView() {
        view = NSView()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.systemBlue.cgColor
    }
}
