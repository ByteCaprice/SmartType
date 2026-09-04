@testable import SwiftType
import XCTest

/// Tests for custom `Notification.Name` extensions.
///
/// Verifies the theme notification used by the candidate window.
@MainActor final class NotificationNameTests: XCTestCase {
    func testThemeDidChangeRawValue() {
        XCTAssertEqual(Notification.Name.themeDidChange.rawValue, "themeDidChange")
    }
}
