import AppKit
import Cocoa
import OdysseyKit
import os

guard odyssey_init(CommandLine.argc, CommandLine.unsafeArgv) == 0 else {
    Odyssey.logger.critical("odyssey_init failed")
    exit(1)
}

_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
