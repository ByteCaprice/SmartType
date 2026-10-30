import AppKit

protocol UninstallFileManaging {
    func fileExists(atPath path: String) -> Bool
    func destinationOfSymbolicLink(atPath path: String) throws -> String
    func removeItem(at URL: URL) throws
}

extension FileManager: UninstallFileManaging {}

struct UninstallResult {
    var removedAppBundle = false
    var removedApplicationsLink = false
    var appBundleRemovalAttempted = false
    var failures: [String] = []

    var succeeded: Bool { failures.isEmpty }
}

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

        let titleLabel = NSTextField(labelWithString: "SmartType")
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        stack.addArrangedSubview(titleLabel)

        let versionLabel = NSTextField(labelWithString: "Version \(version)")
        versionLabel.font = .systemFont(ofSize: Layout.headerFontSize)
        versionLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(versionLabel)

        container.addSubview(stack)

        let uninstallButton = NSButton(title: "Uninstall SmartType\u{2026}", target: self, action: #selector(uninstallButtonClicked))
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
        alert.messageText = "Uninstall SmartType?"
        alert.informativeText = "This removes the SmartType app, but does not change your configured input sources or preferences. "
            + "Switch to another input source first; afterward, remove SmartType in System Settings and log out if it still appears."

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
        let result = Self.removeInstallation(
            appBundle: appBundle,
            applicationsSymlink: applicationsSymlink
        )

        let alert = NSAlert()
        if result.succeeded {
            Log.settings.info("Uninstall completed successfully")
            alert.alertStyle = .informational
            alert.messageText = "SmartType Removed"
            alert.informativeText = "Switch to another input source, remove SmartType from System Settings → Keyboard → Text Input, "
                + "then log out if it still appears. Your preferences were preserved."
            alert.addButton(withTitle: "Quit SmartType")
            alert.runModal()
            NSApp.terminate(nil)
        } else {
            Log.settings.error("Uninstall finished with removal failures")
            alert.alertStyle = .critical
            alert.messageText = "SmartType Couldn’t Be Completely Removed"
            if result.appBundleRemovalAttempted {
                alert.informativeText = result.failures.joined(separator: "\n")
                    + "\n\nSmartType will quit so it cannot continue running from a partially removed bundle."
                alert.addButton(withTitle: "Quit SmartType")
            } else {
                alert.informativeText = result.failures.joined(separator: "\n")
                    + "\n\nSmartType will remain open so you can retry or remove the listed item manually."
                alert.addButton(withTitle: "OK")
            }
            alert.runModal()
            if result.appBundleRemovalAttempted {
                NSApp.terminate(nil)
            }
        }
    }

    static func removeInstallation(
        appBundle: URL,
        applicationsSymlink: URL,
        fileManager: any UninstallFileManaging = FileManager.default
    ) -> UninstallResult {
        var result = UninstallResult()

        if (try? fileManager.destinationOfSymbolicLink(atPath: applicationsSymlink.path)) != nil {
            do {
                try fileManager.removeItem(at: applicationsSymlink)
                result.removedApplicationsLink = true
            } catch {
                result.failures.append("Could not remove \(applicationsSymlink.path). Administrator permission may be required.")
                return result
            }
        }

        if fileManager.fileExists(atPath: appBundle.path) {
            result.appBundleRemovalAttempted = true
            do {
                try fileManager.removeItem(at: appBundle)
                result.removedAppBundle = true
            } catch {
                result.failures.append("Could not remove \(appBundle.path). Check its permissions.")
            }
        }

        return result
    }
}
