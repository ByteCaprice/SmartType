import AppKit
@testable import SwiftType
import XCTest

/// Tests for `ThemeManager` grid column/row validation at both read and write boundaries.
@MainActor final class ThemeManagerGridValidationTests: XCTestCase {
    private var defaults: UserDefaults!
    private var manager: ThemeManager!
    private var suiteName: String!

    override func setUp() async throws {
        suiteName = "com.matthew.inputmethod.SwiftType.gridvalidation.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        manager = ThemeManager(defaults: defaults)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - gridCols validation

    func testGridColsDefaultIs5() {
        XCTAssertEqual(manager.gridCols, ThemeManager.defaultGridCols)
    }

    func testGridColsAcceptsAllValidOptions() {
        for option in ThemeManager.gridColsOptions {
            manager.setGridCols(option)
            XCTAssertEqual(manager.gridCols, option)
        }
    }

    func testGridColsFallsBackToDefaultForOutOfRange() {
        manager.setGridCols(999)
        XCTAssertEqual(manager.gridCols, ThemeManager.defaultGridCols,
                       "Out-of-range gridCols should fall back to default on read")
    }

    func testGridColsFallsBackToDefaultForZero() {
        manager.setGridCols(0)
        XCTAssertEqual(manager.gridCols, ThemeManager.defaultGridCols)
    }

    func testGridColsFallsBackToDefaultForNegative() {
        manager.setGridCols(-1)
        XCTAssertEqual(manager.gridCols, ThemeManager.defaultGridCols)
    }

    func testSetGridColsRejectsOutOfRangeValue() {
        manager.setGridCols(4)
        manager.setGridCols(99)
        XCTAssertEqual(manager.gridCols, 4)
        XCTAssertEqual(defaults.integer(forKey: "theme.gridCols"), 4)
    }

    // MARK: - gridRows validation (write-time guard)

    func testGridRowsDefault() {
        XCTAssertEqual(manager.gridRows, ThemeManager.defaultGridRows)
    }

    func testGridRowsAcceptsAllValidOptions() {
        for option in ThemeManager.gridRowsOptions {
            manager.setGridRows(option)
            XCTAssertEqual(manager.gridRows, option)
        }
    }

    func testSetGridRowsRejectsOutOfRange() {
        manager.setGridRows(3) // set a valid value first
        manager.setGridRows(99) // should be rejected
        XCTAssertEqual(manager.gridRows, 3,
                       "setGridRows guards at write time; invalid value should not change the stored value")
    }

    func testSetGridRowsRejectsZero() {
        manager.setGridRows(0)
        XCTAssertEqual(manager.gridRows, ThemeManager.defaultGridRows)
    }

    func testGridRowsFallsBackToDefaultForCorruptedStorage() {
        defaults.set(99, forKey: "theme.gridRows")
        let freshManager = ThemeManager(defaults: defaults)
        XCTAssertEqual(freshManager.gridRows, ThemeManager.defaultGridRows)
    }

    // MARK: - themeDidChange notification

    func testSetGridColsPostsThemeDidChange() {
        let counter = NotificationCounter()
        let token = NotificationCenter.default.addObserver(
            forName: .themeDidChange, object: nil, queue: nil,
        ) { _ in counter.increment() }
        manager.setGridCols(6)
        NotificationCenter.default.removeObserver(token)
        XCTAssertEqual(counter.count, 1)
    }

    func testSetGridRowsPostsThemeDidChangeOnlyForValidValue() {
        let counter = NotificationCounter()
        let token = NotificationCenter.default.addObserver(
            forName: .themeDidChange, object: nil, queue: nil,
        ) { _ in counter.increment() }
        manager.setGridRows(4) // valid
        manager.setGridRows(99) // invalid — should NOT post
        NotificationCenter.default.removeObserver(token)
        XCTAssertEqual(counter.count, 1)
    }

    func testSetGridColsDoesNotNotifyForOutOfRangeValue() {
        let counter = NotificationCounter()
        let token = NotificationCenter.default.addObserver(
            forName: .themeDidChange, object: nil, queue: nil,
        ) { _ in counter.increment() }
        manager.setGridCols(999)
        NotificationCenter.default.removeObserver(token)
        XCTAssertEqual(counter.count, 0)
    }
}
