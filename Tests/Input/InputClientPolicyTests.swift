@testable import SwiftType
import XCTest

final class InputClientPolicyTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "InputClientPolicyTests.\(UUID().uuidString)"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testTerminalsArePassthrough() {
        for bundleIdentifier in InputClientPolicy.passthroughBundleIdentifiers {
            XCTAssertEqual(
                InputClientPolicy.mode(forBundleIdentifier: bundleIdentifier, defaults: defaults),
                .passthrough,
                bundleIdentifier
            )
        }
    }

    func testNativeEditorsStayInline() {
        XCTAssertEqual(InputClientPolicy.mode(forBundleIdentifier: "com.apple.TextEdit", defaults: defaults), .inline)
        XCTAssertEqual(InputClientPolicy.mode(forBundleIdentifier: "com.apple.dt.Xcode", defaults: defaults), .inline)
        XCTAssertEqual(InputClientPolicy.mode(forBundleIdentifier: "com.apple.Safari", defaults: defaults), .inline)
        XCTAssertEqual(InputClientPolicy.mode(forBundleIdentifier: nil, defaults: defaults), .inline)
        XCTAssertEqual(InputClientPolicy.mode(forBundleIdentifier: "", defaults: defaults), .inline)
    }

    func testChromiumFamilyIsTransparentWithoutListingEveryVariant() {
        let chromiumIDs = [
            "com.google.Chrome",
            "com.google.Chrome.canary",
            "org.chromium.Chromium",
            "com.brave.Browser",
            "com.vivaldi.Vivaldi",
            "com.operasoftware.Opera",
        ]
        for bundleIdentifier in chromiumIDs {
            XCTAssertEqual(
                InputClientPolicy.mode(forBundleIdentifier: bundleIdentifier, defaults: defaults),
                .transparentPrediction,
                bundleIdentifier
            )
        }
    }

    func testEdgeFamilyUsesInlineComposition() {
        let edgeIDs = [
            "com.microsoft.edgemac",
            "com.microsoft.edgemac.beta",
            "com.microsoft.edgemac.dev",
            "com.microsoft.edgemac.canary",
            "com.microsoft.edgemac.Beta",
            "com.microsoft.edgemac.Canary",
            "com.microsoft.edgemac.app.mjoklplbddabcmpepnokjaffbmgbkkgg",
        ]
        for bundleIdentifier in edgeIDs {
            XCTAssertEqual(
                InputClientPolicy.mode(forBundleIdentifier: bundleIdentifier, defaults: defaults),
                .inline,
                bundleIdentifier
            )
        }
    }

    func testEdgeFamilyStaysInlineEvenWhenTransparentPredictionOverrideIsConfigured() {
        // The documented defaults escape hatch must never be able to flip the Edge
        // family back to transparent prediction: Edge text fields drop modeless
        // input, so an override would silently reintroduce the no-input failure.
        defaults.set(
            [
                "com.future.BrokenApp",
                "com.microsoft.edgemac",
                "com.microsoft.edgemac.app.somepwa",
            ],
            forKey: InputClientPolicy.extraTransparentPredictionBundleIDsKey
        )

        XCTAssertEqual(
            InputClientPolicy.mode(forBundleIdentifier: "com.microsoft.edgemac", defaults: defaults),
            .inline
        )
        XCTAssertEqual(
            InputClientPolicy.mode(
                forBundleIdentifier: "com.microsoft.edgemac.app.somepwa",
                defaults: defaults
            ),
            .inline
        )
        // The override must keep working for non-Edge apps.
        XCTAssertEqual(
            InputClientPolicy.mode(forBundleIdentifier: "com.future.BrokenApp", defaults: defaults),
            .transparentPrediction
        )
    }

    func testAuditedCustomTextClientsUseStandardInlineComposition() {
        let bundleIdentifiers = [
            "com.openai.codex",
            "com.kangfenmao.CherryStudio",
            "com.anthropic.claudefordesktop",
            "com.electron.lark",
            "notion.id",
            "dev.openchamber.desktop",
            "com.youku.mac",
            "com.netease.163music",
            "com.anaconda.io",
            "com.alibaba.DingTalkMac",
            "com.follow.clash",
            "io.github.clash-verge-rev.clash-verge-rev",
            "com.google.GeminiMacOS",
            "com.tdesktop.Telegram",
            "com.tencent.xinWeChat",
            "com.tencent.meeting",
            "com.microsoft.Word",
            "com.microsoft.Excel",
            "com.microsoft.Powerpoint",
        ]
        for bundleIdentifier in bundleIdentifiers {
            XCTAssertEqual(
                InputClientPolicy.mode(forBundleIdentifier: bundleIdentifier, defaults: defaults),
                .inline,
                bundleIdentifier
            )
        }
    }

    func testKnownCEFAppsAndHelpersAreTransparent() {
        XCTAssertEqual(
            InputClientPolicy.mode(forBundleIdentifier: "com.tencent.WeWorkMac", defaults: defaults),
            .transparentPrediction
        )
        XCTAssertEqual(
            InputClientPolicy.mode(
                forBundleIdentifier: "88L2Q4487U.com.tencent.wework.helper.gpu",
                defaults: defaults
            ),
            .transparentPrediction
        )
    }

    func testPassthroughWinsOverChromiumHeuristic() {
        XCTAssertEqual(
            InputClientPolicy.mode(forBundleIdentifier: "com.microsoft.VSCode", defaults: defaults),
            .passthrough
        )
    }

    func testUserDefaultsCanAddAFutureBrokenAppWithoutCodeChanges() {
        XCTAssertEqual(InputClientPolicy.mode(forBundleIdentifier: "com.future.BrokenApp", defaults: defaults), .inline)

        defaults.set(["com.future.BrokenApp"], forKey: InputClientPolicy.extraTransparentPredictionBundleIDsKey)

        XCTAssertEqual(
            InputClientPolicy.mode(forBundleIdentifier: "com.future.BrokenApp", defaults: defaults),
            .transparentPrediction
        )
        XCTAssertEqual(
            InputClientPolicy.mode(forBundleIdentifier: "com.future.BrokenApp.helper", defaults: defaults),
            .transparentPrediction
        )
        XCTAssertEqual(InputClientPolicy.mode(forBundleIdentifier: "com.apple.TextEdit", defaults: defaults), .inline)
    }
}
