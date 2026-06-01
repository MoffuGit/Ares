//
//  main.swift
//  Odyssey
//
//  Created by Adrian Hess on 01/06/26.
//

import AppKit
import Cocoa
import OdysseyKit
import os

let result = odyssey_init(CommandLine.argc, CommandLine.unsafeArgv)

guard result == 0 else {
    Odyssey.logger.critical("odyssey_init failed: \(result)")
    exit(1)
}

_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
