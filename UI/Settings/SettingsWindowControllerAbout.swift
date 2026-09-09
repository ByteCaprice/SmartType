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
        alert.informativeText = "This removes the SwiftType app, but does not change your configured input sources or preferences. "
            + "Switch to another input source first; afterward, remove SwiftType in System Settings and log out if it still appears."

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
            alert.messageText = "SwiftType Removed"
            alert.informativeText = "Switch to another input source, remove SwiftType from System Settings → Keyboard → Text Input, "
                + "then log out if it still appears. Your preferences were preserved."
            alert.addButton(withTitle: "Quit SwiftType")
            alert.runModal()
            NSApp.terminate(nil)
        } else {
            Log.settings.error("Uninstall finished with removal failures")
            alert.alertStyle = .critical
            alert.messageText = "SwiftType Couldn’t Be Completely Removed"
            alert.informativeText = result.failures.joined(separator: "\n")
                + "\n\nSwiftType will remain open so you can retry or remove the listed item manually."
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    static func removeInstallation(
        appBundle: URL,
        applicationsSymlink: URL,
        fileManager: any UninstallFileManaging = FileManager.default
    ) -> UninstallResult {
        var result = UninstallResult()

        if fileManager.fileExists(atPath: appBundle.path) {
            do {
                try fileManager.removeItem(at: appBundle)
                result.removedAppBundle = true
            } catch {
                result.failures.append("Could not remove \(appBundle.path). Check its permissions.")
            }
        }

        if (try? fileManager.destinationOfSymbolicLink(atPath: applicationsSymlink.path)) != nil {
            do {
                try fileManager.removeItem(at: applicationsSymlink)
                result.removedApplicationsLink = true
            } catch {
                result.failures.append("Could not remove \(applicationsSymlink.path). Administrator permission may be required.")
            }
        }

        return result
    }
}
