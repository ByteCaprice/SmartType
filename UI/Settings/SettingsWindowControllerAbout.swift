import AppKit

// MARK: - About Tab

extension SettingsWindowController {
    func makeAboutTab() -> NSView {
        let container = NSView()

        let stack = makeContentStack()
        stack.alignment = .centerX

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"

        let iconView = NSImageView(image: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.widthAnchor.constraint(equalToConstant: 72).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 72).isActive = true
        stack.addArrangedSubview(iconView)

        let titleLabel = NSTextField(labelWithString: "SwiftType")
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        stack.addArrangedSubview(titleLabel)

        let versionLabel = NSTextField(labelWithString: "Version \(version)")
        versionLabel.font = .systemFont(ofSize: Layout.headerFontSize)
        versionLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(versionLabel)

        container.addSubview(stack)

        let uninstallButton = NSButton(title: "Uninstall SwiftType\u{2026}", target: self, action: #selector(uninstallButtonClicked))
        uninstallButton.bezelStyle = .push
        uninstallButton.contentTintColor = .systemRed
        uninstallButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(uninstallButton)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: Layout.edgeInset),
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),

            uninstallButton.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: Layout.edgeInset),
            uninstallButton.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            uninstallButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Layout.edgeInset),
        ])

        return container
    }

    // MARK: - Uninstall

    @objc private func uninstallButtonClicked() {
        guard let window else { return }

        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Uninstall SwiftType?"
        alert.informativeText = "This will remove SwiftType from Input Methods and the Applications folder. You may need to log out for the change to take full effect."

        let uninstallButton = alert.addButton(withTitle: "Uninstall")
        uninstallButton.hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")

        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.performUninstall()
        }
    }

    private func performUninstall() {
        let appBundle = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Input Methods/SwiftType.app")
        let applicationsSymlink = URL(fileURLWithPath: "/Applications/SwiftType.app")

        removeItem(at: appBundle)

        if (try? FileManager.default.destinationOfSymbolicLink(atPath: applicationsSymlink.path)) != nil {
            removeItem(at: applicationsSymlink)
        }

        Log.settings.info("Uninstall complete; terminating")
        NSApp.terminate(nil)
    }

    private func removeItem(at url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
            Log.settings.info("Removed uninstall item")
        } catch {
            Log.settings.error("Failed to remove uninstall item")
        }
    }
}
