@testable import SwiftType
import XCTest

/// Tests for `CandidateWindow` show/hide and literal-slot edge cases.
@MainActor final class CandidateWindowUpdateTests: XCTestCase {
    override func setUp() async throws {
        CandidateWindow.shared.hide()
    }

    override func tearDown() async throws {
        CandidateWindow.shared.hide()
    }

    // MARK: - show() guard: empty candidates + nil literal hides

    func testShowWithEmptyCandidatesAndNilLiteralHides() {
        // First show something
        CandidateWindow.shared.show(candidates: ["alpha"], client: nil)
        XCTAssertTrue(CandidateWindow.shared.isVisible)

        // Then show empty
        CandidateWindow.shared.show(candidates: [], client: nil)
        XCTAssertFalse(CandidateWindow.shared.isVisible)
    }

    func testShowWithEmptyCandidatesButLiteralTextStaysVisible() {
        CandidateWindow.shared.show(candidates: [], literalText: "hel", client: nil)
        XCTAssertTrue(CandidateWindow.shared.isVisible)
    }

    // MARK: - Accessibility

    func testVisibleCandidatesExposeOrderedAccessibilityLabels() {
        CandidateWindow.shared.show(candidates: ["hello", "help"], layout: .vertical, client: nil)

        XCTAssertEqual(CandidateWindow.shared.accessibilityCandidateLabels, ["1, hello", "2, help"])
    }

    func testNavigationUpdatesAccessibleSelection() {
        CandidateWindow.shared.show(candidates: ["hello", "help"], layout: .vertical, client: nil)
        XCTAssertNil(CandidateWindow.shared.accessibilitySelectedCandidateLabel)

        CandidateWindow.shared.moveActiveRowDown()

        XCTAssertEqual(CandidateWindow.shared.accessibilitySelectedCandidateLabel, "1, hello")
    }

    func testAccessibilityPressSelectsPredictionByIndex() {
        var selectedIndex: Int?
        CandidateWindow.shared.show(
            candidates: ["hello", "help"],
            layout: .vertical,
            client: nil,
            candidateSelectionHandler: { selectedIndex = $0 }
        )

        XCTAssertTrue(CandidateWindow.shared.performAccessibilityCandidateSelection(at: 1))
        XCTAssertEqual(selectedIndex, 1)
    }

    func testAccessibilityPressAccountsForLiteralSlot() {
        var selectedIndex: Int?
        CandidateWindow.shared.show(
            candidates: ["hello"],
            literalText: "hel",
            layout: .vertical,
            client: nil,
            candidateSelectionHandler: { selectedIndex = $0 }
        )

        XCTAssertFalse(CandidateWindow.shared.performAccessibilityCandidateSelection(at: 0))
        XCTAssertTrue(CandidateWindow.shared.performAccessibilityCandidateSelection(at: 1))
        XCTAssertEqual(selectedIndex, 0)
    }

    func testHideRemovesAccessibilityCandidates() {
        CandidateWindow.shared.show(candidates: ["hello"], layout: .vertical, client: nil)
        CandidateWindow.shared.hide()

        XCTAssertTrue(CandidateWindow.shared.accessibilityCandidateLabels.isEmpty)
    }

    // MARK: - Cursor geometry

    func testZeroAndNonFiniteCursorRectsAreRejected() {
        XCTAssertNil(CandidateWindow.usableCursorRect(.zero))
        XCTAssertNil(CandidateWindow.usableCursorRect(NSRect(x: CGFloat.infinity, y: 2, width: 1, height: 20)))
    }

    func testNegativeCursorDimensionsAreStandardized() {
        let rect = CandidateWindow.usableCursorRect(NSRect(x: 30, y: 40, width: -2, height: -20))

        XCTAssertEqual(rect, NSRect(x: 28, y: 20, width: 2, height: 20))
    }

    // MARK: - hide() resets grid state

    func testHideResetsIsLiteralSelected() {
        CandidateWindow.shared.show(candidates: ["a"], literalText: "x", client: nil)
        XCTAssertTrue(CandidateWindow.shared.isLiteralSelected)
        CandidateWindow.shared.hide()
        XCTAssertFalse(CandidateWindow.shared.isLiteralSelected)
    }

    func testHideResetsSelectedCandidate() {
        CandidateWindow.shared.show(candidates: ["a", "b"], client: nil)
        XCTAssertNil(CandidateWindow.shared.selectedCandidate())
        CandidateWindow.shared.moveActiveColumnRight()
        XCTAssertNotNil(CandidateWindow.shared.selectedCandidate())
        CandidateWindow.shared.hide()
        XCTAssertNil(CandidateWindow.shared.selectedCandidate())
    }

    func testHideResetsPredictionIndexAt() {
        CandidateWindow.shared.show(candidates: ["a"], client: nil)
        XCTAssertNotNil(CandidateWindow.shared.predictionIndexAt(gridColumn: 0))
        CandidateWindow.shared.hide()
        XCTAssertNil(CandidateWindow.shared.predictionIndexAt(gridColumn: 0))
    }

    // MARK: - isLiteralAt edge cases

    func testIsLiteralAtCol0WhenNoLiteralIsFalse() {
        CandidateWindow.shared.show(candidates: ["a", "b"], client: nil)
        XCTAssertFalse(CandidateWindow.shared.isLiteralAt(gridColumn: 0))
    }

    func testIsLiteralAtCol1WithLiteralIsFalse() {
        CandidateWindow.shared.show(candidates: ["a"], literalText: "x", client: nil)
        XCTAssertFalse(CandidateWindow.shared.isLiteralAt(gridColumn: 1))
    }

    func testIsLiteralAtWhenHiddenIsFalse() {
        XCTAssertFalse(CandidateWindow.shared.isLiteralAt(gridColumn: 0))
    }

    // MARK: - show() replaces previous state

    func testShowReplacesGridState() {
        CandidateWindow.shared.show(candidates: ["a"], literalText: "x", client: nil)
        XCTAssertTrue(CandidateWindow.shared.isLiteralSelected)

        // Show without literal replaces the state
        CandidateWindow.shared.show(candidates: ["b", "c"], client: nil)
        XCTAssertFalse(CandidateWindow.shared.isLiteralSelected)
        XCTAssertNil(CandidateWindow.shared.selectedCandidate())
    }

}
