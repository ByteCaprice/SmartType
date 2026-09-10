import AppKit
@testable import SwiftType
import XCTest

/// Tests for ThemeManager edge cases not covered by ThemeManagerTests or
/// ThemeManagerExtendedTests.
///
/// Focuses on:
///   - `gridCols` boundary values adjacent to the valid range (2 and 8)
///   - `highlightOpacity` clamping and malformed persisted values
///   - `setColor` rejection of syntactically invalid hex strings
@MainActor final class ThemeManagerEdgeCaseTests: XCTestCase {
    private var defaults: UserDefaults!
    private var manager: ThemeManager!
    private var suiteName: String!

    override func setUp() async throws {
        suiteName = "com.matthew.inputmethod.SwiftType.themeedge.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        manager = ThemeManager(defaults: defaults)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        manager = nil
    }

    // MARK: - gridCols boundary values

    // Valid range is [4, 5, 6].  Values immediately outside the range
    // (3 and 7) must fall back to the default just like 0, -1, and 99 do.

    func testGridColsThreeRetainsEffectiveDefault() {
        // Arrange: 3 is one below the minimum valid option (4).
        let before = manager.gridCols
        // Act.
        manager.setGridCols(3)
        // Assert: getter ignores the stored value and returns the default.
        XCTAssertEqual(manager.gridCols, before,
                       "setGridCols(3) must not change the effective gridCols (3 is not in gridColsOptions)")
    }

    func testGridColsSevenRetainsEffectiveDefault() {
        // Arrange: 7 is one above the maximum valid option (6).
        let before = manager.gridCols
        // Act.
        manager.setGridCols(7)
        // Assert.
        XCTAssertEqual(manager.gridCols, before,
                       "setGridCols(7) must not change the effective gridCols (7 is not in gridColsOptions)")
    }

    func testGridColsMinBoundaryIsAccepted() {
        // Arrange: 4 is the smallest valid option.
        manager.setGridCols(4)
        XCTAssertEqual(manager.gridCols, 4)
    }

    func testGridColsMaxBoundaryIsAccepted() {
        // Arrange: 6 is the largest valid option.
        manager.setGridCols(6)
        XCTAssertEqual(manager.gridCols, 6)
    }

    // MARK: - highlightOpacity validation

    func testHighlightOpacityAboveOneClampsToOne() {
        manager.setHighlightOpacity(1.5)
        XCTAssertEqual(manager.highlightOpacity, 1, accuracy: 0.001)
    }

    func testHighlightOpacityBelowZeroClampsToZero() {
        manager.setHighlightOpacity(-0.5)
        XCTAssertEqual(manager.highlightOpacity, 0, accuracy: 0.001)
    }

    func testLegacyOutOfRangeOpacityIsClampedWhenRead() {
        defaults.set(2.0, forKey: "theme.highlightTransparency")
        let fresh = ThemeManager(defaults: defaults)
        XCTAssertEqual(fresh.highlightOpacity, 1, accuracy: 0.001)
    }

    func testNonFiniteOpacityIsRejectedAtWriteBoundary() {
        manager.setHighlightOpacity(0.4)
        manager.setHighlightOpacity(.infinity)
        XCTAssertEqual(manager.highlightOpacity, 0.4, accuracy: 0.001)
    }

    func testMalformedPersistedOpacityFallsBackToDefault() {
        defaults.set(Double.nan, forKey: "theme.highlightTransparency")
        let fresh = ThemeManager(defaults: defaults)
        XCTAssertEqual(fresh.highlightOpacity, ThemeManager.defaultHighlightOpacity, accuracy: 0.001)
    }

    // MARK: - setColor with invalid hex string

    // `setColor` validates the hex string via `NSColor(hexString:)` and silently
    // rejects invalid values. The stored value and theme remain unchanged.

    func testSetColorWithInvalidHexIsRejected() {
        // Arrange: "notahex" is not a valid #RRGGBB string.
        manager.setColor("notahex", for: .normalTextColor)
        // Assert: the default is preserved — invalid input was rejected.
        XCTAssertEqual(manager.hexString(for: .normalTextColor), ThemeColorKey.normalTextColor.defaultHex)
    }

    func testSetColorWithInvalidHexDoesNotChangeTheme() {
        // Arrange: set a valid color first.
        manager.setColor("#FF0000", for: .backgroundColor)
        // Act: attempt to overwrite with invalid hex.
        manager.setColor("ZZZZZZ", for: .backgroundColor)
        // Assert: the previously valid color is still in effect.
        XCTAssertEqual(manager.hexString(for: .backgroundColor), "#FF0000")
    }

    // MARK: - gridRows validation

    // Valid range is [3, 4, 5]. `setGridRows` guards against out-of-range values
    // at write time (unlike `setGridCols`). The getter also falls back to the
    // default if an invalid value is somehow stored directly.

    func testSetGridRowsAcceptsAllValidOptions() {
        for count in ThemeManager.gridRowsOptions {
            manager.setGridRows(count)
            XCTAssertEqual(manager.gridRows, count,
                           "setGridRows(\(count)) must persist and return \(count)")
        }
    }

    func testSetGridRowsMinBoundaryIsAccepted() {
        manager.setGridRows(3)
        XCTAssertEqual(manager.gridRows, 3)
    }

    func testSetGridRowsMaxBoundaryIsAccepted() {
        manager.setGridRows(5)
        XCTAssertEqual(manager.gridRows, 5)
    }

    func testSetGridRowsBelowRangeIsRejected() {
        // 2 is one below the minimum valid option (3); the guard must reject it.
        let before = manager.gridRows
        manager.setGridRows(2)
        XCTAssertEqual(manager.gridRows, before,
                       "setGridRows(2) must be a no-op (2 is not in gridRowsOptions)")
    }

    func testSetGridRowsAboveRangeIsRejected() {
        // 6 is one above the maximum valid option (5); the guard must reject it.
        let before = manager.gridRows
        manager.setGridRows(6)
        XCTAssertEqual(manager.gridRows, before,
                       "setGridRows(6) must be a no-op (6 is not in gridRowsOptions)")
    }

    func testSetGridRowsZeroIsRejected() {
        let before = manager.gridRows
        manager.setGridRows(0)
        XCTAssertEqual(manager.gridRows, before)
    }

    func testSetGridRowsNegativeIsRejected() {
        let before = manager.gridRows
        manager.setGridRows(-1)
        XCTAssertEqual(manager.gridRows, before)
    }

    func testGridRowsFallsBackToDefaultForInvalidStoredValue() {
        // Simulate an older app version writing an invalid value directly to UserDefaults.
        defaults.set(99, forKey: "theme.gridRows")
        let freshManager = ThemeManager(defaults: defaults)
        XCTAssertEqual(freshManager.gridRows, ThemeManager.defaultGridRows,
                       "gridRows getter must fall back to the default when stored value is invalid")
    }

    func testGridRowsFallsBackToDefaultWhenKeyAbsent() {
        // No value stored — defaults.integer returns 0, which is not in gridRowsOptions.
        let freshManager = ThemeManager(defaults: defaults)
        XCTAssertEqual(freshManager.gridRows, ThemeManager.defaultGridRows,
                       "gridRows must default to defaultGridRows when key is absent")
    }

    func testGridRowsOptionsContainsDefaultGridRows() {
        XCTAssertTrue(ThemeManager.gridRowsOptions.contains(ThemeManager.defaultGridRows))
    }

    func testGridRowsOptionsAreSorted() {
        let options = ThemeManager.gridRowsOptions
        XCTAssertEqual(options, options.sorted())
    }

    func testGridRowsOptionsAreAllPositive() {
        for count in ThemeManager.gridRowsOptions {
            XCTAssertGreaterThan(count, 0)
        }
    }
}
