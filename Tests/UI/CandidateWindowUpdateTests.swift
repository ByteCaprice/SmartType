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
