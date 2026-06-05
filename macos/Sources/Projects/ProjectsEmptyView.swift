import SwiftUI

struct ProjectEmptyView: View {
    let app: AppDelegate

    @State private var showingOpenPanel = false

    var body: some View {
        Text("Odyssey")
            .font(.system(size: 38, weight: .semibold))
            .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
