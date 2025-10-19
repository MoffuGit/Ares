import SwiftUI
internal import Combine

extension Ares {
    class App: ObservableObject {
        @Published var isLoggedIn: Bool = false
        @Published var username: String = ""

        init() {
            print("Ares.App initialized.")
        }

        func login(user: String) {
            self.isLoggedIn = true
            self.username = user
            print("\(user) logged in.")
        }

        func logout() {
            self.isLoggedIn = false
            self.username = ""
            print("Logged out.")
        }
    }
}
