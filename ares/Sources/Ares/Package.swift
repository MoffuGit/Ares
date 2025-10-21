import os
import SwiftUI
import AresKit

extension ares_surface_t: @unchecked @retroactive Sendable {}

struct Ares {
    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "ares"
    )
}
