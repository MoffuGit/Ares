//
//  OdysseyPackageMeta.swift
//  Odyssey
//
//  Created by Adrian Hess on 28/05/26.
//

import Foundation
import os

enum Odyssey {
    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "odyssey"
    )

    struct Notification {}
}
