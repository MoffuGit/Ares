//
//  OdysseyApplication.swift
//  Odyssey
//
//  Created by Adrian Hess on 26/05/26.
//

import SwiftUI

@main
struct MainApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appDelegate.odyssey)
        }
        .windowStyle(.hiddenTitleBar)
    }
}
