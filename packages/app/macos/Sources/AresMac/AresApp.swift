import SwiftUI
import AresKit

@main
struct AresApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        initState(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        deinitState()
    }
}
