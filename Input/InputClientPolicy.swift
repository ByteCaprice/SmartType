import Foundation

enum InputClientMode: Equatable, Sendable {
    case passthrough
    case inline
    case transparentPrediction
}

enum InputClientPolicy {
    static let extraTransparentPredictionBundleIDsKey = "transparentPredictionBundleIdentifiers"

    static let passthroughBundleIdentifiers: Set<String> = [
        "co.zeit.hyper",
        "com.apple.Terminal",
        "com.github.wez.wezterm",
        "com.googlecode.iterm2",
        "com.microsoft.VSCode",
        "com.mitchellh.ghostty",
        "com.termius-dmg.mac",
        "dev.warp.Warp-Preview",
        "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty",
        "org.alacritty",
    ]

    static func mode(
        forBundleIdentifier bundleIdentifier: String?,
        defaults: UserDefaults = .standard,
    ) -> InputClientMode {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return .inline }
        if bundleIdentifier == Bundle.main.bundleIdentifier {
            return .passthrough
        }
        if passthroughBundleIdentifiers.contains(bundleIdentifier) {
            return .passthrough
        }
        if usesTransparentPrediction(bundleIdentifier, defaults: defaults) {
            return .transparentPrediction
        }
        return .inline
    }

    static func usesTransparentPrediction(
        _ bundleIdentifier: String,
        defaults: UserDefaults = .standard,
    ) -> Bool {
        if extraTransparentPredictionIDs(from: defaults).contains(where: {
            bundleIdentifier == $0 || bundleIdentifier.hasPrefix($0)
        }) {
            return true
        }
        if transparentPredictionBundleIdentifiers.contains(bundleIdentifier) {
            return true
        }
        if transparentPredictionBundlePrefixes.contains(where: { bundleIdentifier.hasPrefix($0) }) {
            return true
        }
        return looksLikeChromiumFamily(bundleIdentifier)
    }

    private static let transparentPredictionBundleIdentifiers: Set<String> = [
        "com.microsoft.edgemac",
        "com.tencent.WeWorkMac",
        "com.google.Chrome",
        "org.chromium.Chromium",
        "com.brave.Browser",
        "company.thebrowser.Browser",
        "com.operasoftware.Opera",
        "com.vivaldi.Vivaldi",
    ]

    private static let transparentPredictionBundlePrefixes = [
        "88L2Q4487U.com.tencent.wework",
        "com.microsoft.edgemac",
        "com.google.Chrome",
        "com.brave.Browser",
    ]

    private static let chromiumFamilyMarkers = [
        "chrome",
        "chromium",
        "edgemac",
        "brave.browser",
        "vivaldi",
        "operasoftware.opera",
    ]

    private static func extraTransparentPredictionIDs(from defaults: UserDefaults) -> [String] {
        defaults.stringArray(forKey: extraTransparentPredictionBundleIDsKey) ?? []
    }

    private static func looksLikeChromiumFamily(_ bundleIdentifier: String) -> Bool {
        let id = bundleIdentifier.lowercased()
        return chromiumFamilyMarkers.contains { id.contains($0) }
    }
}
