//
//  main.swift
//  ares
//
//  Created by Adrian Hess on 16/10/25.
//

import Cocoa
import AresKit

if ares_init(UInt(CommandLine.argc), CommandLine.unsafeArgv) != 0 {
    exit(1)
}

_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
