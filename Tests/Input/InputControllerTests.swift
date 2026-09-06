@testable import SwiftType
import XCTest

// MARK: - InputStateTests

@MainActor final class InputStateTests: XCTestCase {
    func testResetClearsAllFields() {
        let state = InputState()
        state.compositionBuffer = "hello"
        state.currentPredictions = ["world"]
        state.didAutoInsertTrailingSpace = true
        state.mirrorsClientText = true
        state.compositionBaseline = NSRange(location: 3, length: 0)
        state.expectedCursor = 8
        state.compositionClientBundleID = "com.microsoft.edgemac"
        state.autoInsertedSpaceClientBundleID = "com.microsoft.edgemac"
        state.autoInsertedSpaceExpectedCursor = 9

        state.reset()

        XCTAssertEqual(state.compositionBuffer, "")
        XCTAssertTrue(state.currentPredictions.isEmpty)
        XCTAssertFalse(state.didAutoInsertTrailingSpace)
        XCTAssertFalse(state.mirrorsClientText)
        XCTAssertNil(state.compositionBaseline)
        XCTAssertNil(state.expectedCursor)
        XCTAssertNil(state.compositionClientBundleID)
        XCTAssertNil(state.autoInsertedSpaceClientBundleID)
        XCTAssertNil(state.autoInsertedSpaceExpectedCursor)
    }

    func testCompositionBufferDefaultsToEmpty() {
        let state = InputState()
        XCTAssertEqual(state.compositionBuffer, "")
    }

    func testDidAutoInsertTrailingSpaceDefaultsToFalse() {
        let state = InputState()
        XCTAssertFalse(state.didAutoInsertTrailingSpace)
    }

    func testMultipleResetsAreIdempotent() {
        let state = InputState()
        state.compositionBuffer = "test"
        state.reset()
        state.reset()
        XCTAssertEqual(state.compositionBuffer, "")
    }
}

// MARK: - KeyCode Candidate Selection Logic

@MainActor final class KeyCodeCandidateLogicTests: XCTestCase {
    func testCandidateKeysHaveSevenEntries() {
        XCTAssertEqual(KeyCode.candidateKeys.count, 7)
    }

    func testCandidateKeysAreOrdered1Through7() {
        // The order determines which slot each number key selects.
        for (index, key) in KeyCode.candidateKeys.enumerated() {
            XCTAssertEqual(key.digit, index + 1,
                           "candidateKeys[\(index)] should map to digit \(index + 1)")
        }
    }

    func testKey1IsFirstCandidateKey() {
        XCTAssertEqual(KeyCode.candidateKeys.first, .key1)
    }

    func testKey7IsLastCandidateKey() {
        XCTAssertEqual(KeyCode.candidateKeys.last, .key7)
    }

    func testSelectNextKeysContainTabAndRightArrow() {
        // Column-right navigation. Down arrow is now a dedicated grid-row key.
        XCTAssertTrue(KeyCode.selectNextKeys.contains(.tab))
        XCTAssertTrue(KeyCode.selectNextKeys.contains(.rightArrow))
        XCTAssertFalse(KeyCode.selectNextKeys.contains(.downArrow))
    }

    func testSelectNextKeysDoNotContainLeftArrowOrUpArrow() {
        // Left/Up move backward — they should trigger selectPrevious / row-up, not selectNext.
        XCTAssertFalse(KeyCode.selectNextKeys.contains(.leftArrow))
        XCTAssertFalse(KeyCode.selectNextKeys.contains(.upArrow))
    }

    func testNavigationKeysContainAllArrowsAndTab() {
        XCTAssertTrue(KeyCode.navigationKeys.contains(.tab))
        XCTAssertTrue(KeyCode.navigationKeys.contains(.leftArrow))
        XCTAssertTrue(KeyCode.navigationKeys.contains(.rightArrow))
        XCTAssertTrue(KeyCode.navigationKeys.contains(.upArrow))
        XCTAssertTrue(KeyCode.navigationKeys.contains(.downArrow))
    }

    func testBackspaceIsNotANavigationKey() {
        XCTAssertFalse(KeyCode.navigationKeys.contains(.backspace))
    }

    func testSpaceIsNotACandidateKey() {
        XCTAssertFalse(KeyCode.candidateKeys.contains(.space))
    }

    func testReturnKeyIsNotACandidateKey() {
        XCTAssertFalse(KeyCode.candidateKeys.contains(.returnKey))
    }
}

// MARK: - Note on InputController.handle() Integration Tests

//
// Full key-routing integration tests (simulating letter keypresses, space commits,
// backspace, etc.) require an instantiated InputController connected to a real or
// mocked IMKServer via IMKInputController(server:delegate:client:). IMKServer demands
// a live Mach connection bootstrapped from Info.plist's InputMethodConnectionName,
// which is unavailable in the unit-test process.
//
// The routing logic IS covered at the component level:
//   - InputState fields and transitions       → InputStateTests above
//   - Capitalization rules                    → InputLogicTests
//   - Candidate window selection state        → CandidateWindowSelectionTests
//   - SpellCheckPredictor deduplication/limit → SpellCheckPredictorTests
//
// A future integration test harness could use XCTestCase with a custom NSApplication
// subclass that boots IMKServer in setUp, but this is currently out of scope.
