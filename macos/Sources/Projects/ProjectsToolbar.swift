import AppKit
import SwiftUI

struct ProjectsToolbar: View {
    let app: AppDelegate
    
    var body: some View {
        UI.Button( variant: .destructive, size: .icon, icon: Image(systemName: "plus"), action: {app.selectNewProject()})
            .padding(Padding.`1`)
            .background(Color(nsColor: .systemBlue))
            .cornerRadius(BorderRadius.lg)
            .fixedSize()
    }
}
