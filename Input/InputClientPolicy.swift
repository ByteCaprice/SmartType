import Foundation

enum InputClientMode: Equatable, Sendable {
    case passthrough
    case directInput
    case inline
    case transparentPrediction
}

enum InputClientPolicy {
    static let extraTransparentPredictionBundleIDsKey = "transparentPredictionBundleIdentifiers"
    static let extraDirectInputBundleIDsKey = "directInputBundleIdentifiers"
    static let extraMarkedTextPrimingBundleIDsKey = "markedTextPrimingBundleIdentifiers"

    static let passthroughBundleIdentifiers: Set<String> = [
        "co.zeit.hyper",
        "com.apple.Terminal",
        "com.github.wez.wezterm",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "com.termius-dmg.mac",
        "dev.warp.Warp-Preview",
        "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty",
        "org.alacritty",
    ]

    static let directInputBundleIdentifiers: Set<String> = [
        "com.microsoft.VSCode",
    ]

    static func mode(
        forBundleIdentifier bundleIdentifier: String?,
        defaults: UserDefaults = .standard,
    ) -> InputClientMode {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return .inline }
        if bundleIdentifier == Bundle.main.bundleIdentifier {
            return .passthrough
        }
        if bundleIdentifier == "com.microsoft.edgemac"
            || bundleIdentifier.hasPrefix("com.microsoft.edgemac.")
        {
            return .inline
        }
        if matchesConfiguredBundleIdentifier(
            bundleIdentifier,
            entries: Array(directInputBundleIdentifiers)
        ) || matchesConfiguredBundleIdentifier(
            bundleIdentifier,
            entries: defaults.stringArray(forKey: extraDirectInputBundleIDsKey) ?? []
        )
        {
            return .directInput
        }
        if passthroughBundleIdentifiers.contains(bundleIdentifier) {
            return .passthrough
        }
        if usesTransparentPrediction(bundleIdentifier, defaults: defaults) {
            return .transparentPrediction
        }
        return .inline
    }

    static func requiresMarkedTextForDirectCommit(
        _ bundleIdentifier: String?,
        defaults: UserDefaults = .standard,
    ) -> Bool {
        guard let bundleIdentifier else { return false }
        let configuredEntries = (defaults.stringArray(
            forKey: extraMarkedTextPrimingBundleIDsKey
        ) ?? []) + extraTransparentPredictionIDs(from: defaults)
            + (defaults.stringArray(forKey: extraDirectInputBundleIDsKey) ?? [])
        return matchesConfiguredBundleIdentifier(
            bundleIdentifier,
            entries: markedTextPrimingBundlePrefixes + configuredEntries
        )
    }

    static func usesTransparentPrediction(
        _ bundleIdentifier: String,
        defaults: UserDefaults = .standard,
    ) -> Bool {
        if matchesConfiguredBundleIdentifier(
            bundleIdentifier,
            entries: extraTransparentPredictionIDs(from: defaults)
        ) {
            return true
        }
        if transparentPredictionBundleIdentifiers.contains(bundleIdentifier) {
            return true
        }
        if matchesConfiguredBundleIdentifier(
            bundleIdentifier,
            entries: transparentPredictionBundlePrefixes
        ) {
            return true
        }
        return looksLikeChromiumFamily(bundleIdentifier)
    }

    private static let transparentPredictionBundleIdentifiers: Set<String> = [
        "com.tencent.WeWorkMac",
        "com.alibaba.DingTalkMac",
        "com.google.Chrome",
        "org.chromium.Chromium",
        "com.brave.Browser",
        "company.thebrowser.Browser",
        "com.operasoftware.Opera",
        "com.vivaldi.Vivaldi",
    ]

    private static let transparentPredictionBundlePrefixes = [
        "88L2Q4487U.com.tencent.wework",
        "com.alibaba.DingTalkMac",
        "com.google.Chrome",
        "com.brave.Browser",
    ]

    private static let markedTextPrimingBundlePrefixes = [
        "com.microsoft.VSCode",
        "com.tencent.WeWorkMac",
        "88L2Q4487U.com.tencent.wework",
        "com.alibaba.DingTalkMac",
    ]

    private static let chromiumFamilyMarkers = [
        "chrome",
        "chromium",
        "brave.browser",
        "vivaldi",
        "operasoftware.opera",
    ]

    private static func extraTransparentPredictionIDs(from defaults: UserDefaults) -> [String] {
        defaults.stringArray(forKey: extraTransparentPredictionBundleIDsKey) ?? []
    }

    private static func matchesConfiguredBundleIdentifier(
        _ bundleIdentifier: String,
        entries: [String],
    ) -> Bool {
        entries.contains(where: {
            !$0.isEmpty && (bundleIdentifier == $0 || bundleIdentifier.hasPrefix($0 + "."))
        })
    }

    private static func looksLikeChromiumFamily(_ bundleIdentifier: String) -> Bool {
        let id = bundleIdentifier.lowercased()
        return chromiumFamilyMarkers.contains { id.contains($0) }
    }
}
