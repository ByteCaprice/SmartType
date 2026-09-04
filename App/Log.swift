import Foundation
import os

enum Log {
    static let appDelegate = Logger(subsystem: subsystem, category: "AppDelegate")
    static let inputController = Logger(subsystem: subsystem, category: "InputController")
    static let nsManualApp = Logger(subsystem: subsystem, category: "NSManualApplication")
    static let settings = Logger(subsystem: subsystem, category: "Settings")
    static let startup = Logger(subsystem: subsystem, category: "startup")

    private static let subsystem = Bundle.main.bundleIdentifier!
}
