//
//  main.swift
//  ares
//
//  Created by Adrian Hess on 16/10/25.
//

import AppKit
import Cocoa
import SwiftUI
import AresKit

if ares_init(UInt(CommandLine.argc), CommandLine.unsafeArgv) != 0 {
    exit(1)
}

let app = NSApplication.shared
let appDelegate = AppDelegate()
app.delegate = appDelegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
