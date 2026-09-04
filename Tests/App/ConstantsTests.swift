@testable import SwiftType
import XCTest

/// Tests for `Constants` computed properties and static values.
@MainActor final class ConstantsTests: XCTestCase {
    // MARK: - Static bounds

    func testMaxSupportedGridColsIsAtLeastSeven() {
        XCTAssertGreaterThanOrEqual(Constants.maxSupportedGridCols, 7)
    }

    func testMaxSupportedGridRowsIsAtLeastFive() {
        XCTAssertGreaterThanOrEqual(Constants.maxSupportedGridRows, 5)
    }

    func testReplacementNotFoundLocationIsNSNotFound() {
        XCTAssertEqual(Constants.replacementNotFound.location, NSNotFound)
    }

    func testReplacementNotFoundLengthIsZero() {
        XCTAssertEqual(Constants.replacementNotFound.length, 0)
    }

    func testSpellCompletionLimitIsFive() {
        // Product requirement: at most five spell suggestions may be offered.
        XCTAssertEqual(Constants.spellCompletionLimit, 5)
    }

    func testInputMethodSupportsCapsLockLanguageSwitching() {
        let bundle = Bundle(for: InputController.self)

        XCTAssertEqual(
            bundle.object(forInfoDictionaryKey: "TICapsLockLanguageSwitchCapable") as? Bool,
            true
        )
        XCTAssertEqual(
            bundle.object(forInfoDictionaryKey: "TISInputSourceID") as? String,
            "com.matthew.inputmethod.SwiftType"
        )
        XCTAssertEqual(
            bundle.object(forInfoDictionaryKey: "TISIntendedLanguage") as? String,
            "en"
        )
        XCTAssertEqual(
            bundle.object(forInfoDictionaryKey: "tsInputMethodIconFileKey") as? String,
            "SwiftTypeInputSourceIcon.png"
        )
        XCTAssertEqual(
            bundle.object(forInfoDictionaryKey: "TISIconIsTemplate") as? Bool,
            true
        )
        XCTAssertNotNil(bundle.url(forResource: "SwiftTypeInputSourceIcon", withExtension: "png"))
    }

    // MARK: - Computed properties

    func testGridMaxVisibleColsMatchesThemeManager() {
        XCTAssertEqual(Constants.gridMaxVisibleCols, ThemeManager.shared.gridCols)
    }

    func testGridMaxVisibleRowsMatchesThemeManager() {
        XCTAssertEqual(Constants.gridMaxVisibleRows, ThemeManager.shared.gridRows)
    }

    // MARK: - Consistency with ThemeManager options

    func testMaxSupportedGridColsCoversAllThemeOptions() {
        for option in ThemeManager.gridColsOptions {
            XCTAssertLessThanOrEqual(option, Constants.maxSupportedGridCols,
                                     "gridColsOption \(option) exceeds maxSupportedGridCols")
        }
    }

    func testMaxSupportedGridRowsCoversAllThemeRowOptions() {
        for option in ThemeManager.gridRowsOptions {
            XCTAssertLessThanOrEqual(option, Constants.maxSupportedGridRows,
                                     "gridRowsOption \(option) exceeds maxSupportedGridRows")
        }
    }
}
