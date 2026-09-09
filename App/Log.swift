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

enum PerformanceTrace {
    static let signposter = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "com.matthew.inputmethod.SwiftType",
        category: "Performance"
    )

    static func measure<T>(_ name: StaticString, operation: () throws -> T) rethrows -> T {
        let interval = signposter.beginInterval(name)
        defer { signposter.endInterval(name, interval) }
        return try operation()
    }
}
