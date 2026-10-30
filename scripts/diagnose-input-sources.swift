// Read-only developer diagnostic. Run with: xcrun swift scripts/diagnose-input-sources.swift
// Requires the Xcode command-line tools. No key events or document text are observed.
import Carbon
import Foundation

func property(_ source: TISInputSource, _ key: CFString) -> AnyObject? {
    guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
    return Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue()
}

func describe(_ source: TISInputSource?) -> String {
    guard let source else { return "unavailable" }
    let identifier = property(source, kTISPropertyInputSourceID) as? String ?? "unknown"
    let enabled = property(source, kTISPropertyInputSourceIsEnabled) as? Bool ?? false
    let ascii = property(source, kTISPropertyInputSourceIsASCIICapable) as? Bool ?? false
    return "\(identifier) [enabled=\(enabled), ASCII-capable=\(ascii)]"
}

func snapshot() {
    print("Current source: \(describe(TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()))")
    print("Last-used ASCII source: \(describe(TISCopyCurrentASCIICapableKeyboardInputSource()?.takeRetainedValue()))")
    print("Underlying keyboard layout: \(describe(TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue()))")
    print("English-language lookup: \(describe(TISCopyInputSourceForLanguage("en" as CFString)?.takeRetainedValue()))")
}

let usage = "Usage: xcrun swift scripts/diagnose-input-sources.swift [--watch SECONDS | --help]\nSECONDS must be an integer from 1 to 300."
let arguments = Array(CommandLine.arguments.dropFirst())
let watchSeconds: Int
if arguments == ["--help"] {
    print(usage)
    exit(0)
} else if arguments.isEmpty {
    watchSeconds = 0
} else if arguments.count == 2, arguments[0] == "--watch",
          let seconds = Int(arguments[1]), (1 ... 300).contains(seconds) {
    watchSeconds = seconds
} else {
    FileHandle.standardError.write(Data((usage + "\n").utf8))
    exit(2)
}

print("SmartType read-only input-source diagnostic")
print("No input sources, preferences, registrations, or services are changed.")
print("Only source identifiers, capabilities, and notification times are reported; no keystrokes or text.")
print("The English-language lookup is NOT a guaranteed Caps Lock destination.")
print("An underlying US/ABC keyboard layout does not mean SmartType was deselected.\n")

let filter = [kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource!,
              kTISPropertyInputSourceIsSelectCapable as String: kCFBooleanTrue!] as CFDictionary
if let sources = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] {
    print("Selectable keyboard sources (enabled state shown):")
    for source in sources {
        print("  \(describe(source))")
    }
}

if watchSeconds == 0 {
    snapshot()
} else {
    let start = ProcessInfo.processInfo.systemUptime
    let center = DistributedNotificationCenter.default()
    let token = center.addObserver(
        forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
        object: nil,
        queue: nil
    ) { _ in
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        print(String(format: "\n[+%.3fs] System source-change notification (trigger unknown)", elapsed))
        snapshot()
        fflush(stdout)
    }
    print("\nWatching for \(watchSeconds) seconds. Reproduce manually in a non-sensitive field; Ctrl-C stops early.")
    snapshot()
    fflush(stdout)
    RunLoop.current.run(until: Date(timeIntervalSinceNow: TimeInterval(watchSeconds)))
    center.removeObserver(token)
    print("\nWatch finished. This reports source changes, not physical Caps Lock presses or their latency.")
}
