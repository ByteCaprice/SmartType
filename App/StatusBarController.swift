import AppKit

@MainActor final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        if let button = statusItem.button {
            button.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
            button.title = "EN"
        }
        statusItem.menu = buildMenu()
    }

    // MARK: - Menu

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)
        return menu
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.showWindow()
    }
}
