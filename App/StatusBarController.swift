import AppKit

@MainActor final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        if let button = statusItem.button {
            button.title = "EN"
            button.toolTip = "SwiftType"
        }
        statusItem.menu = buildMenu()
    }

    // MARK: - Menu

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let aboutItem = NSMenuItem(title: "About SwiftType", action: #selector(openAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let settingsItem = NSMenuItem(title: "Settings\u{2026}", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let helpItem = NSMenuItem(title: "Setup & Shortcuts\u{2026}", action: #selector(openHelp), keyEquivalent: "")
        helpItem.target = self
        menu.addItem(helpItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit SwiftType", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        return menu
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.showWindow()
    }

    @objc private func openAbout() {
        SettingsWindowController.shared.showWindow(tab: .about)
    }

    @objc private func openHelp() {
        let alert = NSAlert()
        alert.messageText = "SwiftType Setup & Shortcuts"
        alert.informativeText = "Enable SwiftType in System Settings → Keyboard → Text Input, then select it from the input menu.\n\n"
            + "Vertical List: press the number shown beside a candidate to choose it. Arrow keys activate and move the selection. Space accepts the item marked with the spacebar icon; ✓ Exact match keeps a completed word; ✓ Keep typed marks other literal fallbacks.\n\n"
            + "Grid: ↓ expands the grid, arrows or Tab move the selection, and number keys choose from the active row. Return keeps the original letters unless you explicitly selected a candidate.\n\n"
            + "Chrome and compatible CEF apps show Smart Space predictions without capturing arrow keys. Return remains the app's normal submit or newline key. Native terminals use passthrough; VS Code uses direct compatibility input without suggestions. "
            + "If applications cannot connect after an update, log out and back in."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
