import os
import SwiftUI

struct Ares {
    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "ares"
    )
}
