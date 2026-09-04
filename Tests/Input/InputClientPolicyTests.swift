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
            "com.microsoft.edgemac",
            "com.microsoft.edgemac.dev",
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
