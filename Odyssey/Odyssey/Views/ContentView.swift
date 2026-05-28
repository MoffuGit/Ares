//
//  ContentView.swift
//  Odyssey
//
//  Created by Adrian Hess on 26/05/26.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var app: Odyssey.App
    @StateObject private var workspace: Odyssey.Workspace

    init(app: Odyssey.App = .shared) {
        _workspace = StateObject(wrappedValue: app.makeWorkspace())
    }

    var body: some View {}
}

#Preview {
    ContentView()
}
