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

guard odyssey_init(CommandLine.argc, CommandLine.unsafeArgv) == 0 else {
    Odyssey.logger.critical("odyssey_init failed")
    exit(1)
}

guard odyssey_db_start() == 0 else {
    Odyssey.logger.critical("odyssey_db_start failed")
    exit(1)
}

_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
