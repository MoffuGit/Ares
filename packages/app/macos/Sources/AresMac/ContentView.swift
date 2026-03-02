import SwiftUI
import AresKit

struct ContentView: View {
    @State private var themeInfo: String = "No theme loaded"

    var body: some View {
        VStack(spacing: 16) {
            Text("Ares")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Core library linked successfully")
                .foregroundStyle(.secondary)

            Divider()

            Text(themeInfo)
                .font(.system(.body, design: .monospaced))
        }
        .padding(40)
        .frame(minWidth: 400, minHeight: 300)
        .onAppear {
            loadThemeInfo()
        }
    }

    private func loadThemeInfo() {
        guard let settings = createSettings() else {
            themeInfo = "Failed to create settings"
            return
        }
        defer { destroySettings(settings) }

        var ext = ExternTheme()
        readTheme(settings, &ext)

        let bg = ext.bg
        themeInfo = "BG: \(bg.0),\(bg.1),\(bg.2),\(bg.3)"
    }
}
