import AppKit
import SwiftUI

struct ProjectsToolbar: View {
    let app: AppDelegate

    var body: some View {
        VStack(alignment: .center) {
            UI.Button(
                variant: .destructive, size: .icon, icon: Image(systemName: "plus"),
                action: { app.selectNewProject() })
        }
        .padding(Padding.`6`)
    }
}
