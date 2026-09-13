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

        XCTAssertEqual(
            CandidateWindow.shared.accessibilitySelectedCandidateLabel,
            "1, hello, Space accepts hello"
        )
    }

    func testDefaultCandidateExposesSpaceActionWithoutSelectingIt() throws {
        CandidateWindow.shared.show(
            candidates: ["apply", "apple"],
            defaultSpaceAction: .prediction(index: 0),
            literalSpaceText: "appl",
            layout: .vertical,
            client: nil
        )

        XCTAssertEqual(
            CandidateWindow.shared.accessibilityCandidateLabels,
            ["1, apply, Space accepts apply", "2, apple"]
        )
        XCTAssertNil(CandidateWindow.shared.accessibilitySelectedCandidateLabel)
        XCTAssertNil(CandidateWindow.shared.selectedCandidate())
        XCTAssertNil(CandidateWindow.shared.spaceHintText)
        let visualLabel = try XCTUnwrap(CandidateWindow.shared.visualCandidateLabels.first)
        XCTAssertFalse(visualLabel.contains("Space"))
        XCTAssertTrue(
            visualLabel.contains("\u{FFFC}") || visualLabel.contains("␣"),
            "the visual default marker must be an icon rather than the word Space"
        )
    }

    func testExplicitNavigationMovesSpaceIndicatorToSelection() {
        CandidateWindow.shared.show(
            candidates: ["apply", "apple"],
            defaultSpaceAction: .prediction(index: 0),
            literalSpaceText: "appl",
            layout: .vertical,
            client: nil
        )

        CandidateWindow.shared.moveActiveRowDown()
        CandidateWindow.shared.moveActiveRowDown()

        XCTAssertEqual(CandidateWindow.shared.selectedCandidate(), "apple")
        XCTAssertEqual(
            CandidateWindow.shared.accessibilityCandidateLabels,
            ["1, apply", "2, apple, Space accepts apple"]
        )
        XCTAssertEqual(
            CandidateWindow.shared.accessibilitySelectedCandidateLabel,
            "2, apple, Space accepts apple"
        )
    }

    func testGridNavigationMovesSpaceIndicatorWithoutChangingIndexes() {
        CandidateWindow.shared.show(
            candidates: ["apply", "apple", "application"],
            defaultSpaceAction: .prediction(index: 0),
            literalSpaceText: "appl",
            layout: .grid,
            client: nil
        )

        CandidateWindow.shared.moveActiveColumnRight()
        CandidateWindow.shared.moveActiveColumnRight()

        XCTAssertEqual(CandidateWindow.shared.selectedCandidate(), "apple")
        XCTAssertEqual(CandidateWindow.shared.selectedPredictionIndex, 1)
        XCTAssertEqual(CandidateWindow.shared.predictionIndexAt(gridColumn: 1), 1)
        XCTAssertEqual(
            CandidateWindow.shared.accessibilityCandidateLabels,
            ["1, apply", "2, apple, Space accepts apple", "3, application"]
        )
    }

    func testLiteralSpaceActionShowsCheckmarkWithoutRepeatingWord() throws {
        CandidateWindow.shared.show(
            candidates: ["appreciate", "apply"],
            defaultSpaceAction: .literal,
            defaultSpaceReason: .exactCompletion,
            literalSpaceText: "app",
            layout: .vertical,
            client: nil
        )

        let indicator = try XCTUnwrap(CandidateWindow.shared.spaceHintText)
        XCTAssertFalse(indicator.contains("Space"))
        XCTAssertFalse(indicator.contains("app"))
        XCTAssertTrue(indicator.contains("Exact match"))
        XCTAssertTrue(indicator.contains("\u{FFFC}") || indicator.contains("✓"))
        XCTAssertEqual(CandidateWindow.shared.accessibilityCandidateLabels, ["1, appreciate", "2, apply"])
        XCTAssertNil(CandidateWindow.shared.selectedCandidate())
        XCTAssertEqual(CandidateWindow.shared.predictionIndexAt(gridColumn: 0), 0)
    }

    func testNonExactLiteralUsesKeepTypedLabel() throws {
        CandidateWindow.shared.show(
            candidates: ["example"],
            defaultSpaceAction: .literal,
            defaultSpaceReason: .fallbackLiteral,
            literalSpaceText: "xqzpl",
            client: nil
        )

        let indicator = try XCTUnwrap(CandidateWindow.shared.spaceHintText)
        XCTAssertTrue(indicator.contains("Keep typed"))
        XCTAssertFalse(indicator.contains("Exact match"))
        XCTAssertFalse(indicator.contains("xqzpl"))
    }

    func testHideClearsSpaceHint() {
        CandidateWindow.shared.show(
            candidates: ["appreciate"],
            literalSpaceText: "app",
            client: nil
        )

        CandidateWindow.shared.hide()

        XCTAssertNil(CandidateWindow.shared.spaceHintText)
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
        var selectedIndex: Int?
        CandidateWindow.shared.show(
            candidates: ["hello"],
            layout: .vertical,
            client: nil,
            candidateSelectionHandler: { selectedIndex = $0 }
        )
        CandidateWindow.shared.hide()

        XCTAssertTrue(CandidateWindow.shared.accessibilityCandidateLabels.isEmpty)
        XCTAssertFalse(CandidateWindow.shared.performAccessibilityCandidateSelection(at: 0))
        XCTAssertNil(selectedIndex)
    }

    func testChangingToNarrowerGridRemovesStaleAccessibilityCells() {
        let originalColumns = Constants.gridMaxVisibleCols
        defer { ThemeManager.shared.setGridCols(originalColumns) }
        ThemeManager.shared.setGridCols(6)
        CandidateWindow.shared.show(candidates: ["a", "b", "c", "d", "e", "f"], layout: .grid, client: nil)
        XCTAssertEqual(CandidateWindow.shared.accessibilityCandidateLabels.count, 6)

        ThemeManager.shared.setGridCols(4)
        CandidateWindow.shared.show(candidates: ["a", "b", "c", "d"], layout: .grid, client: nil)

        XCTAssertEqual(CandidateWindow.shared.accessibilityCandidateLabels, ["1, a", "2, b", "3, c", "4, d"])
        XCTAssertFalse(CandidateWindow.shared.performAccessibilityCandidateSelection(at: 4))
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
