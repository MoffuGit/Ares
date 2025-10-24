import os
import SwiftUI
import AresKit

struct Ares {
    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "ares"
    )
}
