//
//  OdysseyPackage.swift
//  Odyssey
//
//  Created by Adrian Hess on 01/06/26.
//

import Foundation
import os

enum Odyssey {
    nonisolated static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "odyssey"
    )

    struct Notification {}
}
