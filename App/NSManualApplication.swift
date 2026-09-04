import AppKit
import os

@MainActor @objc(NSManualApplication)
class NSManualApplication: NSApplication {
    private let appDelegate = AppDelegate()

    override init() {
        super.init()
        delegate = appDelegate
        Log.nsManualApp.info("NSManualApplication initialized")
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
