@testable import SwiftType
import XCTest

/// Tests for the visual treatment of English composition text.
@MainActor final class LatinKeyHandlerTests: XCTestCase {
    func testMarkedTextIsNotUnderlined() {
        XCTAssertNil(InputController.markedTextAttributes[.underlineStyle])
    }
}
