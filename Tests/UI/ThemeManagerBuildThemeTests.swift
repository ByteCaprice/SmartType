@testable import SwiftType
import XCTest

/// Tests for `ThemeManager.buildTheme()` and related static construction logic.
///
/// `buildTheme` reads from UserDefaults and produces an immutable Theme. These tests
/// verify colour resolution, invalid-hex handling, and border settings.
@MainActor final class ThemeManagerBuildThemeTests: XCTestCase {
    private var defaults: UserDefaults!
    private var manager: ThemeManager!
    private var suiteName: String!

    override func setUp() async throws {
        suiteName = "com.matthew.inputmethod.SwiftType.buildtheme.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        manager = ThemeManager(defaults: defaults)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        manager = nil
    }

    // MARK: - Default theme

    func testDefaultThemeHasStandardBorderWidth() {
        XCTAssertEqual(manager.current.border.width, ThemeBorder.standardWidth)
    }

    func testDefaultHighlightOpacityUsesNativeSelectionFill() {
        XCTAssertEqual(manager.highlightOpacity, 0.82, accuracy: 0.001)
    }

    // MARK: - Border always has standard width

    func testBorderAlwaysHasStandardWidth() {
        XCTAssertEqual(manager.current.border.width, ThemeBorder.standardWidth)
    }

    // MARK: - Border color

    func testBorderColorDefault() {
        XCTAssertEqual(manager.hexString(for: .borderColor), ThemeColorKey.borderColor.defaultHex)
    }

    func testExplicitBorderColor() {
        manager.setColor("#112233", for: .borderColor)
        XCTAssertEqual(manager.hexString(for: .borderColor), "#112233")
    }

    func testColorCustomizationTracksExplicitOverridesAndReset() {
        XCTAssertFalse(manager.isColorCustomized(.backgroundColor))

        manager.setColor("#112233", for: .backgroundColor)
        XCTAssertTrue(manager.isColorCustomized(.backgroundColor))

        manager.resetToDefaults()
        XCTAssertFalse(manager.isColorCustomized(.backgroundColor))
    }

    func testInvalidStoredColorIsNotTreatedAsCustomization() {
        defaults.set("not-a-color", forKey: ThemeColorKey.backgroundColor.rawValue)

        XCTAssertFalse(manager.isColorCustomized(.backgroundColor))
    }

    // MARK: - Invalid hex handling

    func testInvalidHexIsRejectedAndDefaultPreserved() throws {
        manager.setColor("not-a-hex", for: .backgroundColor)
        // setColor rejects invalid hex — the default colour remains.
        XCTAssertEqual(manager.current.backgroundColor, Theme.defaultTheme.backgroundColor)
    }

    func testValidHexIsApplied() throws {
        manager.setColor("#FF0000", for: .backgroundColor)
        let expected = try XCTUnwrap(NSColor(hexString: "#FF0000"))
        XCTAssertEqual(manager.current.backgroundColor, expected)
    }

    // MARK: - Grid cols/rows validation

    func testGridColsOutOfRangeReturnsDefault() {
        manager.setGridCols(99)
        XCTAssertEqual(manager.gridCols, ThemeManager.defaultGridCols)
    }

    func testGridColsValidValueIsPersisted() {
        manager.setGridCols(6)
        XCTAssertEqual(manager.gridCols, 6)
    }

    func testGridRowsOutOfRangeIsRejected() {
        manager.setGridRows(99)
        XCTAssertEqual(manager.gridRows, ThemeManager.defaultGridRows)
    }

    func testGridRowsValidValueIsPersisted() {
        manager.setGridRows(5)
        XCTAssertEqual(manager.gridRows, 5)
    }

    func testGridColsAllValidValues() {
        for value in ThemeManager.gridColsOptions {
            manager.setGridCols(value)
            XCTAssertEqual(manager.gridCols, value)
        }
    }

    func testGridRowsAllValidValues() {
        for value in ThemeManager.gridRowsOptions {
            manager.setGridRows(value)
            XCTAssertEqual(manager.gridRows, value)
        }
    }

    // MARK: - Highlight opacity

    func testHighlightOpacityIsPersisted() {
        manager.setHighlightOpacity(0.75)
        // Rebuild manager from same defaults to verify persistence.
        let fresh = ThemeManager(defaults: defaults)
        XCTAssertEqual(fresh.highlightOpacity, 0.75, accuracy: 0.01)
    }

    func testHighlightOpacityZeroIsPersisted() {
        manager.setHighlightOpacity(0)
        let fresh = ThemeManager(defaults: defaults)
        XCTAssertEqual(fresh.highlightOpacity, 0, accuracy: 0.001)
    }

    // MARK: - Reset to defaults

    func testResetToDefaultsRestoresAllSettings() {
        manager.setColor("#FF0000", for: .backgroundColor)
        manager.setColor("#00FF00", for: .borderColor)
        manager.setHighlightOpacity(0.5)
        manager.setGridCols(6)
        manager.setGridRows(5)

        manager.resetToDefaults()

        XCTAssertEqual(manager.gridCols, ThemeManager.defaultGridCols)
        XCTAssertEqual(manager.gridRows, ThemeManager.defaultGridRows)
        XCTAssertEqual(manager.highlightOpacity, ThemeManager.defaultHighlightOpacity)
        XCTAssertEqual(manager.hexString(for: .borderColor), ThemeColorKey.borderColor.defaultHex)
        XCTAssertEqual(manager.current.border.width, ThemeBorder.standardWidth)
    }

    // MARK: - Theme is rebuilt on every change

    func testThemeIsRebuiltAfterColorChange() {
        let before = manager.current
        manager.setColor("#FF0000", for: .backgroundColor)
        let after = manager.current
        XCTAssertNotEqual(before.backgroundColor, after.backgroundColor)
    }

    func testThemeIsRebuiltAfterBorderColorChange() {
        let before = manager.current.border.color
        manager.setColor("#FF0000", for: .borderColor)
        let after = manager.current.border.color
        XCTAssertNotEqual(before, after)
    }

    // MARK: - Stored values vs. semantic defaults

    // `buildTheme` reads stored hex directly from UserDefaults, so values written
    // by anything other than `setColor` (older app versions, synced or hand-edited
    // defaults) also reach the fallback paths.

    func testStoredValidHexOverridesSemanticDefaultForEveryKey() throws {
        // A valid stored hex must win over the semantic default for every key —
        // custom stored colours override the macOS-coordinated defaults.
        for key in ThemeColorKey.allCases {
            defaults.set("#010203", forKey: key.rawValue)
        }
        let stored = try XCTUnwrap(NSColor(hexString: "#010203"))

        let m = ThemeManager(defaults: defaults)
        for key in ThemeColorKey.allCases {
            XCTAssertEqual(m.current.color(for: key), stored,
                           "\(key.rawValue): stored hex must override the semantic default")
        }
    }

    func testStoredInvalidHexFallsBackToSemanticDefaultForEveryKey() {
        // An unparseable hex stored directly in UserDefaults (bypassing setColor's
        // validation) must fall back to the semantic default — not the legacy
        // defaultHex palette and not a crash.
        for key in ThemeColorKey.allCases {
            defaults.set("not-a-hex", forKey: key.rawValue)
        }

        let m = ThemeManager(defaults: defaults)
        for key in ThemeColorKey.allCases {
            XCTAssertEqual(m.current.color(for: key), Theme.defaultTheme.color(for: key),
                           "\(key.rawValue): invalid stored hex must fall back to the semantic default")
        }
    }
}
