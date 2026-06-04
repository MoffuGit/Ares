import AppKit
import SwiftUI

class ProjectsToolbar: NSView {
    private let app: AppDelegate
    private let hosting: NSView

    init(app: AppDelegate) {
        self.hosting = NSHostingView(rootView:Tools(app: app))
        self.app = app
        

        super.init(frame: .zero)
        
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.systemBlue.cgColor
        self.layer?.cornerRadius = BorderRadius.lg
        self.layer?.zPosition = 100
        
        hosting.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hosting)
        
        NSLayoutConstraint.activate([
            hosting.trailingAnchor.constraint(equalTo: trailingAnchor),
            hosting.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct Tools: View {
    let app: AppDelegate
    
    var body: some View {
        UI.Button( variant: .destructive, size: .icon, icon: Image(systemName: "plus"), action: {app.selectNewProject()})
    }
}
