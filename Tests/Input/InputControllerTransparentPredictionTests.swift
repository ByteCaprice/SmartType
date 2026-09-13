@testable import SwiftType
import AppKit
import InputMethodKit
import XCTest

@MainActor
// swiftlint:disable:next type_body_length
final class InputControllerTransparentPredictionTests: XCTestCase {
    private var controller: InputController!
    private var client: RecordingTextInputClient!
    private var predictionDelay: ManualPredictionDelay!

    override func setUp() async throws {
        try await super.setUp()
        CandidateWindow.shared.hide()
        client = RecordingTextInputClient()
        client.bundleIdentifierValue = "com.google.Chrome"
        controller = try XCTUnwrap(
            InputController(server: nil, delegate: nil, client: nil),
            "InputController must be instantiable without a live IMKServer for unit tests"
        )
        let delay = ManualPredictionDelay()
        predictionDelay = delay
        controller.waitForTransparentPredictionDebounce = {
            await delay.wait()
        }
    }

    override func tearDown() async throws {
        CandidateWindow.shared.hide()
        try await super.tearDown()
    }

    func testChromiumFamilyUsesTransparentPrediction() {
        XCTAssertFalse(InputController.usesTransparentPrediction(bundleIdentifier: "com.microsoft.edgemac"))
        XCTAssertFalse(InputController.usesTransparentPrediction(bundleIdentifier: "com.microsoft.edgemac.canary"))
        XCTAssertFalse(
            InputController.usesTransparentPrediction(
                bundleIdentifier: "com.microsoft.edgemac.app.mjoklplbddabcmpepnokjaffbmgbkkgg"
            )
        )
        XCTAssertTrue(InputController.usesTransparentPrediction(bundleIdentifier: "com.tencent.WeWorkMac"))
        XCTAssertTrue(InputController.usesTransparentPrediction(bundleIdentifier: "com.alibaba.DingTalkMac"))
        XCTAssertTrue(
            InputController.usesTransparentPrediction(
                bundleIdentifier: "88L2Q4487U.com.tencent.wework.helper.renderer"
            )
        )
        XCTAssertTrue(InputController.usesTransparentPrediction(bundleIdentifier: "com.google.Chrome"))
        XCTAssertFalse(InputController.usesTransparentPrediction(bundleIdentifier: "com.microsoft.VSCode"))
        XCTAssertFalse(InputController.usesTransparentPrediction(bundleIdentifier: "com.apple.TextEdit"))
        XCTAssertFalse(InputController.usesTransparentPrediction(bundleIdentifier: nil))
    }

    func testLetterInChromiumIsInsertedWithoutMarkedText() throws {
        let handled = try type("h", keyCode: 4)

        XCTAssertTrue(handled)
        XCTAssertEqual(controller.state.compositionBuffer, "h")
        XCTAssertTrue(controller.state.mirrorsClientText)
        XCTAssertTrue(client.markedText.isEmpty)
        XCTAssertEqual(client.insertedText, ["h"])
        XCTAssertEqual(client.document, "h")
        XCTAssertEqual(controller.composedString(client) as? String, "")
    }

    func testLetterDoesNotSynchronouslyQueryClientForCandidateWindow() throws {
        let handled = try type("h", keyCode: 4)

        XCTAssertTrue(handled)
        XCTAssertEqual(client.windowLevelQueryCount, 0)
        XCTAssertEqual(client.attributesQueryCount, 0)
    }

    // MARK: - Deferred candidate refresh (Chromium typing-stall fix)

    func testDeferredRefreshStillShowsCandidatesAfterDebounce() async throws {
        try type("h", keyCode: 4)
        XCTAssertEqual(client.windowLevelQueryCount, 0, "keydown must not synchronously query the client")

        let refreshed = await releaseDeferredPredictionTasks()
        XCTAssertTrue(refreshed, "the deferred prediction refresh must eventually run")

        XCTAssertNotEqual(
            controller.state.currentPredictions.first?.lowercased(),
            "h",
            "the raw typing buffer must not be duplicated in the predictions"
        )
        XCTAssertEqual(client.windowLevelQueryCount, 1)
        XCTAssertEqual(client.attributesQueryCount, 1)
        XCTAssertTrue(CandidateWindow.shared.isVisible, "the candidate window must appear after the debounce")
    }

    func testDeferredRefreshCoalescesRapidKeystrokes() async throws {
        try type("h", keyCode: 4)
        try type("e", keyCode: 14)
        try type("l", keyCode: 37)

        let refreshed = await releaseDeferredPredictionTasks()
        XCTAssertTrue(refreshed)

        XCTAssertEqual(client.windowLevelQueryCount, 1, "a typing burst must produce exactly one candidate refresh")
        XCTAssertEqual(client.attributesQueryCount, 1)
        XCTAssertNotEqual(
            controller.state.currentPredictions.first?.lowercased(),
            "hel",
            "the refreshed list must contain predictions only"
        )
    }

    func testDiscardingCompositionDuringDebounceCancelsRefresh() async throws {
        try type("h", keyCode: 4)
        _ = try type("\u{1B}", keyCode: KeyCode.escape.rawValue)

        await releaseDeferredPredictionTasks()

        XCTAssertEqual(client.windowLevelQueryCount, 0)
        XCTAssertFalse(CandidateWindow.shared.isVisible)
        XCTAssertTrue(controller.state.currentPredictions.isEmpty)
        XCTAssertEqual(controller.state.compositionBuffer, "")
    }

    func testSelectionChangeBeforeDeferredRefreshDiscardsStaleMirror() async throws {
        try type("h", keyCode: 4)
        client.selectedLocation = 9

        await releaseDeferredPredictionTasks()

        XCTAssertEqual(client.windowLevelQueryCount, 0)
        XCTAssertFalse(CandidateWindow.shared.isVisible)
        XCTAssertEqual(controller.state.compositionBuffer, "")
        XCTAssertFalse(controller.state.mirrorsClientText)
    }

    func testUnknownSelectionStillAllowsDeferredRefresh() async throws {
        client.selectedLocation = NSNotFound
        try type("h", keyCode: 4)

        let refreshed = await releaseDeferredPredictionTasks()

        XCTAssertTrue(refreshed)
        XCTAssertTrue(CandidateWindow.shared.isVisible)
        XCTAssertEqual(controller.state.compositionBuffer, "h")
    }

    func testNewKeystrokeHidesCandidatesUntilTheirGenerationRefreshes() async throws {
        try type("h", keyCode: 4)
        _ = await releaseDeferredPredictionTasks()
        XCTAssertTrue(CandidateWindow.shared.isVisible)

        try type("e", keyCode: 14)

        XCTAssertFalse(CandidateWindow.shared.isVisible)
        XCTAssertTrue(controller.state.currentPredictions.isEmpty)
        XCTAssertEqual(controller.state.compositionBuffer, "he")
    }

    func testDeferredRefreshMakesFirstPredictionSelectableWithDigitOne() async throws {
        try type("h", keyCode: 4)
        try type("e", keyCode: 14)
        try type("l", keyCode: 37)
        let refreshed = await releaseDeferredPredictionTasks()
        XCTAssertTrue(refreshed)
        XCTAssertTrue(CandidateWindow.shared.isVisible)

        let expected = try XCTUnwrap(controller.state.currentPredictions.first)
        let handled = try type("1", keyCode: KeyCode.key1.rawValue)

        XCTAssertTrue(handled)
        XCTAssertEqual(client.document, expected + " ")
        XCTAssertEqual(controller.state.compositionBuffer, "")
        XCTAssertTrue(controller.state.didAutoInsertTrailingSpace)
    }

    func testAccessibilityCandidateActionCommitsTransparentPrediction() async throws {
        try type("h", keyCode: 4)
        try type("e", keyCode: 14)
        try type("l", keyCode: 37)
        let refreshed = await releaseDeferredPredictionTasks()
        XCTAssertTrue(refreshed)
        let expected = try XCTUnwrap(controller.state.currentPredictions.first)

        XCTAssertTrue(CandidateWindow.shared.performAccessibilityCandidateSelection(at: 0))

        XCTAssertEqual(client.document, expected + " ")
        XCTAssertEqual(controller.state.compositionBuffer, "")
    }

    func testAccessibilityCandidateActionRejectsStaleSelection() async throws {
        try type("h", keyCode: 4)
        try type("e", keyCode: 14)
        try type("l", keyCode: 37)
        let refreshed = await releaseDeferredPredictionTasks()
        XCTAssertTrue(refreshed)
        client.selectedLocation = 0

        XCTAssertTrue(CandidateWindow.shared.performAccessibilityCandidateSelection(at: 0))

        XCTAssertEqual(client.document, "hel")
        XCTAssertEqual(controller.state.compositionBuffer, "")
        XCTAssertFalse(controller.state.mirrorsClientText)
    }

    func testWeComLettersUseTemporaryMarkedTextPriming() throws {
        client.bundleIdentifierValue = "com.tencent.WeWorkMac"
        try type("h", keyCode: 4)
        try type("e", keyCode: 14)

        XCTAssertEqual(controller.state.compositionBuffer, "he")
        XCTAssertEqual(client.markedText, ["h", "e"])
        XCTAssertEqual(client.insertedText, ["h", "e"])
        XCTAssertEqual(client.document, "he")
        XCTAssertEqual(controller.state.expectedCursor, 2)
    }

    func testWeComPrimedSuffixCommitLandsExactlyOnce() throws {
        client.bundleIdentifierValue = "com.tencent.WeWorkMac"
        try type("h", keyCode: 4)
        try type("e", keyCode: 14)
        try type("l", keyCode: 37)
        controller.state.currentPredictions = ["hello"]
        showCandidates(["hello"])

        let handled = try type("1", keyCode: KeyCode.key1.rawValue)

        XCTAssertTrue(handled)
        // The typed prefix already lives in the document; only the "lo " suffix is
        // committed, through the primed mark-then-insert path, exactly once.
        XCTAssertEqual(client.document, "hello ")
        XCTAssertEqual(client.insertedText, ["h", "e", "l", "lo "])
        XCTAssertEqual(client.markedText, ["h", "e", "l", "lo "])
        XCTAssertEqual(controller.state.compositionBuffer, "")
        XCTAssertTrue(controller.state.didAutoInsertTrailingSpace)
        XCTAssertFalse(CandidateWindow.shared.isVisible)
    }

    func testWeComPrimedCorrectionReplacesTypedRegionExactlyOnce() throws {
        client.bundleIdentifierValue = "com.tencent.WeWorkMac"
        try type("t", keyCode: 17)
        try type("e", keyCode: 14)
        try type("h", keyCode: 4)
        setPredictionSnapshot(
            buffer: "teh",
            predictions: ["the"],
            action: .prediction(index: 0),
            reason: .correction
        )

        let handled = try type(" ", keyCode: KeyCode.space.rawValue)

        XCTAssertTrue(handled)
        // The verified typed region is replaced by "the " — primed, so the letters
        // are marked first, and the document ends with a single corrected word.
        XCTAssertEqual(client.document, "the ")
        XCTAssertEqual(client.insertedText, ["t", "e", "h", "the "])
        XCTAssertEqual(client.markedText, ["t", "e", "h", "the "])
        XCTAssertEqual(controller.state.compositionBuffer, "")
        XCTAssertTrue(controller.state.didAutoInsertTrailingSpace)
    }

    func testDingTalkUsesPrimingForLettersPunctuationAndSpace() throws {
        client.bundleIdentifierValue = "com.alibaba.DingTalkMac"

        XCTAssertTrue(try type("h", keyCode: 4))
        XCTAssertTrue(try type(".", keyCode: 47))
        XCTAssertTrue(try type(" ", keyCode: KeyCode.space.rawValue))

        XCTAssertEqual(client.markedText, ["h", ".", " "])
        XCTAssertEqual(client.insertedText, ["h", ".", " "])
        XCTAssertEqual(client.document, "h. ")
        XCTAssertEqual(controller.state.compositionBuffer, "")
    }

    func testBackspaceShrinksMirrorAndLeavesDeletionToClient() throws {
        try type("h", keyCode: 4)
        try type("e", keyCode: 14)
        let handled = try type("\u{8}", keyCode: KeyCode.backspace.rawValue)

        XCTAssertFalse(handled)
        XCTAssertEqual(controller.state.compositionBuffer, "h")
        XCTAssertEqual(controller.state.expectedCursor, 1)
        XCTAssertEqual(client.insertedText, ["h", "e"])
        XCTAssertTrue(client.markedText.isEmpty)
    }

    func testCapsLockDropsMirrorWithoutCommitting() throws {
        try type("h", keyCode: 4)
        try type("e", keyCode: 14)
        let event = Self.flagsChangedEvent(keyCode: 0x39, flags: .maskAlphaShift)

        XCTAssertFalse(controller.handle(event, client: client))
        XCTAssertEqual(controller.state.compositionBuffer, "")
        XCTAssertFalse(controller.state.mirrorsClientText)
        XCTAssertEqual(client.insertedText, ["h", "e"])
        XCTAssertTrue(client.markedText.isEmpty)
    }

    func testDeactivateDoesNotInsertMirroredText() throws {
        try type("h", keyCode: 4)

        controller.deactivateServer(client)

        XCTAssertEqual(controller.state.compositionBuffer, "")
        XCTAssertEqual(client.insertedText, ["h"])
        XCTAssertTrue(client.markedText.isEmpty)
    }

    func testStaleCursorDropsMirrorThenStartsNewLetter() throws {
        try type("h", keyCode: 4)
        client.selectedLocation = 9

        let handled = try type("e", keyCode: 14)

        XCTAssertTrue(handled)
        XCTAssertEqual(controller.state.compositionBuffer, "e")
        XCTAssertEqual(controller.state.expectedCursor, 10)
        XCTAssertEqual(client.insertedText, ["h", "e"])
    }

    func testLiteralSpaceIsInsertedWithoutMarkedText() throws {
        try type("h", keyCode: 4)
        showCandidates(["hello"])

        let handled = try type(" ", keyCode: KeyCode.space.rawValue)

        XCTAssertTrue(handled)
        XCTAssertEqual(controller.state.compositionBuffer, "")
        XCTAssertEqual(client.insertedText, ["h", " "])
        XCTAssertEqual(client.document, "h ")
        XCTAssertTrue(controller.state.didAutoInsertTrailingSpace)
    }

    func testSpaceInsertsFreshDefaultCompletionSuffix() throws {
        try type("a", keyCode: 0)
        try type("p", keyCode: 35)
        try type("p", keyCode: 35)
        try type("l", keyCode: 37)
        setPredictionSnapshot(
            buffer: "appl",
            predictions: ["apply", "apple"],
            action: .prediction(index: 0),
            reason: .prefixCompletion
        )

        let handled = try type(" ", keyCode: KeyCode.space.rawValue)

        XCTAssertTrue(handled)
        XCTAssertEqual(client.insertedText, ["a", "p", "p", "l", "y "])
        XCTAssertEqual(client.document, "apply ")
        XCTAssertTrue(controller.state.didAutoInsertTrailingSpace)
    }

    func testSpacePreservesTransparentCompleteWord() throws {
        try type("a", keyCode: 0)
        try type("p", keyCode: 35)
        try type("p", keyCode: 35)
        setPredictionSnapshot(
            buffer: "app",
            predictions: ["appreciate", "apply"],
            action: .literal,
            reason: .exactCompletion
        )

        XCTAssertTrue(try type(" ", keyCode: KeyCode.space.rawValue))
        XCTAssertEqual(client.insertedText, ["a", "p", "p", " "])
        XCTAssertEqual(client.document, "app ")
    }

    func testSpaceAppliesVerifiedTransparentCorrection() throws {
        try type("t", keyCode: 17)
        try type("e", keyCode: 14)
        try type("h", keyCode: 4)
        setPredictionSnapshot(
            buffer: "teh",
            predictions: ["the"],
            action: .prediction(index: 0),
            reason: .correction
        )

        XCTAssertTrue(try type(" ", keyCode: KeyCode.space.rawValue))
        XCTAssertEqual(client.markedText, ["the "])
        XCTAssertEqual(client.document, "the ")
    }

    func testUnverifiedTransparentDefaultFallsBackToLiteralSpace() throws {
        try type("t", keyCode: 17)
        try type("e", keyCode: 14)
        try type("h", keyCode: 4)
        client.supportsDocumentAccess = false
        setPredictionSnapshot(
            buffer: "teh",
            predictions: ["the"],
            action: .prediction(index: 0),
            reason: .correction
        )

        XCTAssertTrue(try type(" ", keyCode: KeyCode.space.rawValue))
        XCTAssertTrue(client.markedText.isEmpty)
        XCTAssertEqual(client.document, "teh ")
        XCTAssertEqual(client.insertedText, ["t", "e", "h", " "])
    }

    func testSpaceWithNoCompositionIsInsertedOnceAndConsumed() throws {
        // Space outside any composition must land exactly once: consumed by the
        // input method and inserted via insertText, never both.
        let handled = try type(" ", keyCode: KeyCode.space.rawValue)

        XCTAssertTrue(handled)
        XCTAssertEqual(client.insertedText, [" "])
        XCTAssertEqual(client.document, " ")
        XCTAssertTrue(client.markedText.isEmpty)
        XCTAssertFalse(controller.state.didAutoInsertTrailingSpace)
    }

    func testDigitWithNoCompositionIsInsertedOnceAndConsumed() throws {
        // Digits fall through the candidate shortcut path (no window) and must be
        // inserted exactly once instead of starting a composition.
        let handled = try type("5", keyCode: KeyCode.key5.rawValue)

        XCTAssertTrue(handled)
        XCTAssertEqual(client.insertedText, ["5"])
        XCTAssertEqual(client.document, "5")
        XCTAssertEqual(controller.state.compositionBuffer, "")
        XCTAssertTrue(client.markedText.isEmpty)
    }

    func testReturnCommitsSelectedPredictionWithoutTrailingSpace() throws {
        try type("h", keyCode: 4)
        try type("e", keyCode: 14)
        try type("l", keyCode: 37)
        controller.state.currentPredictions = ["hello"]
        showCandidates(["hello"])
        CandidateWindow.shared.moveActiveColumnRight()

        let handled = try type("\r", keyCode: KeyCode.returnKey.rawValue)

        XCTAssertTrue(handled)
        XCTAssertEqual(controller.state.compositionBuffer, "")
        XCTAssertEqual(client.insertedText, ["h", "e", "l", "lo"])
        XCTAssertEqual(client.document, "hello")
        XCTAssertFalse(controller.state.didAutoInsertTrailingSpace)
    }

    func testReturnWithoutSelectionDiscardsMirrorWithoutInsert() throws {
        try type("h", keyCode: 4)
        try type("e", keyCode: 14)
        try type("l", keyCode: 37)
        controller.state.currentPredictions = ["hello"]
        showCandidates(["hello"])

        let handled = try type("\r", keyCode: KeyCode.returnKey.rawValue)

        // The literal text already lives in the client document, so Return only
        // ends the composition; the newline itself is left to the client and no
        // trailing blank is inserted.
        XCTAssertFalse(handled)
        XCTAssertEqual(controller.state.compositionBuffer, "")
        XCTAssertEqual(client.insertedText, ["h", "e", "l"])
        XCTAssertEqual(client.document, "hel")
        XCTAssertFalse(controller.state.didAutoInsertTrailingSpace)
    }

    func testSpaceBeforeDeferredRefreshStaysLiteralAndCancelsCandidates() async throws {
        try type("h", keyCode: 4)

        let handled = try type(" ", keyCode: KeyCode.space.rawValue)

        XCTAssertTrue(handled)
        XCTAssertEqual(client.document, "h ")
        XCTAssertEqual(client.insertedText, ["h", " "])
        XCTAssertNil(controller.pendingTransparentPredictionUpdate)
        await releaseDeferredPredictionTasks()
        XCTAssertEqual(client.windowLevelQueryCount, 0)
        XCTAssertFalse(CandidateWindow.shared.isVisible)
    }

    func testReturnBeforeDeferredRefreshCancelsPendingCandidates() async throws {
        try type("h", keyCode: 4)

        let handled = try type("\r", keyCode: KeyCode.returnKey.rawValue)

        XCTAssertFalse(handled)
        XCTAssertEqual(controller.state.compositionBuffer, "")
        XCTAssertNil(controller.pendingTransparentPredictionUpdate)
        await releaseDeferredPredictionTasks()
        XCTAssertEqual(client.windowLevelQueryCount, 0)
    }

    func testCandidateDigitInsertsSuffixOnly() throws {
        try type("h", keyCode: 4)
        try type("e", keyCode: 14)
        try type("l", keyCode: 37)
        controller.state.currentPredictions = ["hello"]
        showCandidates(["hello"])

        let handled = try type("1", keyCode: KeyCode.key1.rawValue)

        XCTAssertTrue(handled)
        XCTAssertEqual(client.insertedText, ["h", "e", "l", "lo "])
        XCTAssertEqual(client.insertionRanges.last?.location, NSNotFound)
        XCTAssertEqual(client.document, "hello ")
        XCTAssertEqual(controller.state.compositionBuffer, "")
        XCTAssertTrue(controller.state.didAutoInsertTrailingSpace)
    }

    func testCandidateWithDifferentPrefixCasingReplacesTypedRegion() throws {
        try type("H", keyCode: 4)
        try type("E", keyCode: 14)
        try type("L", keyCode: 37)
        controller.state.currentPredictions = ["hello"]
        showCandidates(["Hello"])

        let handled = try type("1", keyCode: KeyCode.key1.rawValue)

        XCTAssertTrue(handled)
        XCTAssertEqual(client.markedText, ["Hello "])
        XCTAssertEqual(client.insertedText, ["H", "E", "L", "Hello "])
        XCTAssertEqual(client.markedReplacementRanges.last, NSRange(location: 0, length: 3))
        XCTAssertEqual(client.document, "Hello ")
    }

    func testCorrectionPrimesMarkedTextThenCommitsFullWord() throws {
        try type("t", keyCode: 17)
        try type("e", keyCode: 14)
        try type("h", keyCode: 4)
        controller.state.currentPredictions = ["the"]
        showCandidates(["the"])

        let handled = try type("1", keyCode: KeyCode.key1.rawValue)

        XCTAssertTrue(handled)
        XCTAssertEqual(client.markedText, ["the "])
        XCTAssertEqual(client.insertedText, ["t", "e", "h", "the "])
        XCTAssertEqual(client.markedReplacementRanges.last, NSRange(location: 0, length: 3))
        XCTAssertEqual(client.document, "the ")
        XCTAssertEqual(controller.state.compositionBuffer, "")
    }

    func testCorrectionWithoutDocumentAccessInsertsDigit() throws {
        try type("t", keyCode: 17)
        try type("e", keyCode: 14)
        try type("h", keyCode: 4)
        client.supportsDocumentAccess = false
        controller.state.currentPredictions = ["the"]
        showCandidates(["the"])

        let handled = try type("1", keyCode: KeyCode.key1.rawValue)

        XCTAssertTrue(handled)
        XCTAssertTrue(client.markedText.isEmpty)
        XCTAssertEqual(client.insertedText, ["t", "e", "h", "1"])
        XCTAssertEqual(client.document, "teh1")
        XCTAssertEqual(controller.state.compositionBuffer, "")
    }

    func testUnverifiedCorrectionInsertsDigitInstead() throws {
        try type("t", keyCode: 17)
        try type("e", keyCode: 14)
        try type("h", keyCode: 4)
        client.document = "different text"
        controller.state.currentPredictions = ["the"]
        showCandidates(["the"])

        let handled = try type("1", keyCode: KeyCode.key1.rawValue)

        XCTAssertTrue(handled)
        XCTAssertTrue(client.markedText.isEmpty)
        XCTAssertEqual(client.insertedText, ["t", "e", "h", "1"])
        XCTAssertEqual(client.document, "dif1ferent text")
        XCTAssertEqual(controller.state.compositionBuffer, "")
    }

    func testPunctuationReplacesTransparentAutoInsertedSpace() throws {
        try type("h", keyCode: 4)
        showCandidates(["hello"])
        _ = try type(" ", keyCode: KeyCode.space.rawValue)
        client.document = "h "
        client.selectedLocation = 2

        let handled = try type(".", keyCode: 47)

        XCTAssertTrue(handled)
        XCTAssertEqual(client.markedText, ["."])
        XCTAssertEqual(client.insertedText, ["h", " ", "."])
        XCTAssertEqual(client.markedReplacementRanges.last, NSRange(location: 1, length: 1))
        XCTAssertEqual(client.document, "h.")
        XCTAssertFalse(controller.state.didAutoInsertTrailingSpace)
    }

    func testPunctuationDoesNotReplaceSpaceOwnedByAnotherClient() throws {
        try type("h", keyCode: 4)
        showCandidates(["hello"])
        _ = try type(" ", keyCode: KeyCode.space.rawValue)
        let otherClient = RecordingTextInputClient()
        otherClient.bundleIdentifierValue = "com.brave.Browser"
        otherClient.uniqueIdentifierValue = "other-client"
        otherClient.document = "x "
        otherClient.selectedLocation = 2
        let event = try Self.keyDownEvent(characters: ".", keyCode: 47)

        let handled = controller.handle(event, client: otherClient)

        XCTAssertTrue(handled)
        XCTAssertTrue(otherClient.markedText.isEmpty)
        XCTAssertEqual(otherClient.insertedText, ["."])
        XCTAssertEqual(otherClient.document, "x .")
        XCTAssertFalse(controller.state.didAutoInsertTrailingSpace)
    }

    func testChangingClientIdentifierDoesNotDropMirror() throws {
        try type("h", keyCode: 4)
        client.uniqueIdentifierValue = "changed-client-identifier"

        let handled = try type("e", keyCode: 14)

        XCTAssertTrue(handled)
        XCTAssertEqual(controller.state.compositionBuffer, "he")
    }

    func testShiftedCandidateDigitDiscardsMirrorAndInsertsSymbol() throws {
        try type("h", keyCode: 4)
        showCandidates(["hello"])
        let event = try Self.keyDownEvent(
            characters: "!",
            keyCode: KeyCode.key1.rawValue,
            modifiers: .shift
        )

        let handled = controller.handle(event, client: client)

        XCTAssertTrue(handled)
        XCTAssertEqual(controller.state.compositionBuffer, "")
        XCTAssertFalse(CandidateWindow.shared.isVisible)
        XCTAssertEqual(client.insertedText, ["h", "!"])
        XCTAssertEqual(client.document, "h!")
    }

    func testCommandKeyDropsMirrorWithoutInsert() throws {
        try type("h", keyCode: 4)
        let event = try Self.keyDownEvent(characters: "c", keyCode: 8, modifiers: .command)

        XCTAssertFalse(controller.handle(event, client: client))
        XCTAssertEqual(controller.state.compositionBuffer, "")
        XCTAssertEqual(client.insertedText, ["h"])
        XCTAssertTrue(client.markedText.isEmpty)
    }

    func testArrowKeyDropsMirrorAndPassesThrough() throws {
        try type("h", keyCode: 4)
        let handled = try type("\u{F701}", keyCode: KeyCode.downArrow.rawValue)

        XCTAssertFalse(handled)
        XCTAssertEqual(controller.state.compositionBuffer, "")
        XCTAssertEqual(client.insertedText, ["h"])
    }

    @discardableResult
    private func type(_ characters: String, keyCode: UInt16) throws -> Bool {
        let event = try Self.keyDownEvent(characters: characters, keyCode: keyCode)
        return controller.handle(event, client: client)
    }

    /// Releases every scheduled debounce and waits for the controller task to settle.
    /// This keeps scheduling tests deterministic and independent of wall-clock timing.
    @discardableResult
    private func releaseDeferredPredictionTasks() async -> Bool {
        for _ in 0 ..< 100 where predictionDelay.pendingCount == 0 {
            await Task.yield()
        }
        predictionDelay.resumeAll()
        for _ in 0 ..< 100 where controller.pendingTransparentPredictionUpdate != nil {
            await Task.yield()
        }
        return client.windowLevelQueryCount > 0
    }

    private func showCandidates(_ candidates: [String]) {
        CandidateWindow.shared.show(
            candidates: candidates,
            layout: .vertical,
            client: client,
        )
    }

    private func setPredictionSnapshot(
        buffer: String,
        predictions: [String],
        action: DefaultSpaceAction,
        reason: DefaultSpaceReason
    ) {
        controller.state.predictionSnapshot = PredictionSnapshot(
            buffer: buffer,
            predictions: predictions,
            defaultSpaceAction: action,
            reason: reason
        )
        CandidateWindow.shared.show(
            candidates: predictions,
            defaultSpaceAction: action,
            literalSpaceText: buffer,
            layout: .vertical,
            client: client
        )
    }

    private static func flagsChangedEvent(keyCode: CGKeyCode, flags: CGEventFlags) -> NSEvent {
        let cgEvent = CGEvent(
            keyboardEventSource: CGEventSource(stateID: .hidSystemState),
            virtualKey: keyCode,
            keyDown: false,
        )!
        cgEvent.type = .flagsChanged
        cgEvent.flags = flags
        return NSEvent(cgEvent: cgEvent)!
    }

    private static func keyDownEvent(
        characters: String,
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = [],
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode,
        ))
    }
}

@MainActor private final class ManualPredictionDelay {
    private var continuations: [CheckedContinuation<Void, Never>] = []

    var pendingCount: Int { continuations.count }

    func wait() async {
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func resumeAll() {
        let pending = continuations
        continuations.removeAll()
        for continuation in pending {
            continuation.resume()
        }
    }
}

private final class RecordingTextInputClient: NSObject, IMKTextInput {
    var bundleIdentifierValue = "com.google.Chrome"
    var uniqueIdentifierValue = "recording-client"
    var document = ""
    var selectedLocation = 0
    var selectedLength = 0
    var supportsDocumentAccess = true

    private(set) var insertedText: [String] = []
    private(set) var markedText: [String] = []
    private(set) var insertionRanges: [NSRange] = []
    private(set) var markedReplacementRanges: [NSRange] = []
    private(set) var windowLevelQueryCount = 0
    private(set) var attributesQueryCount = 0
    private var pendingMarkedReplacementRange: NSRange?

    func insertText(_ string: Any, replacementRange: NSRange) {
        let text = stringValue(string)
        insertedText.append(text)
        insertionRanges.append(replacementRange)
        let effectiveRange = replacementRange.location == NSNotFound
            ? pendingMarkedReplacementRange ?? selectedRange()
            : replacementRange
        replaceDocumentText(in: effectiveRange, with: text)
        pendingMarkedReplacementRange = nil
    }

    func setMarkedText(_ string: Any, selectionRange _: NSRange, replacementRange: NSRange) {
        markedText.append(stringValue(string))
        markedReplacementRanges.append(replacementRange)
        pendingMarkedReplacementRange = replacementRange.location == NSNotFound
            ? selectedRange()
            : replacementRange
    }

    private func stringValue(_ string: Any) -> String {
        if let plainString = string as? String { return plainString }
        if let attributedString = string as? NSAttributedString { return attributedString.string }
        return String(describing: string)
    }

    private func replaceDocumentText(in range: NSRange, with text: String) {
        let nsDocument = document as NSString
        guard range.location != NSNotFound,
              range.location >= 0,
              NSMaxRange(range) <= nsDocument.length
        else {
            return
        }
        document = nsDocument.replacingCharacters(in: range, with: text)
        selectedLocation = range.location + (text as NSString).length
        selectedLength = 0
    }

    func selectedRange() -> NSRange {
        NSRange(location: selectedLocation, length: selectedLength)
    }

    func markedRange() -> NSRange { NSRange(location: NSNotFound, length: NSNotFound) }

    func attributedSubstring(from range: NSRange) -> NSAttributedString! {
        let nsDocument = document as NSString
        guard range.location != NSNotFound,
              range.location >= 0,
              NSMaxRange(range) <= nsDocument.length
        else {
            return nil
        }
        return NSAttributedString(string: nsDocument.substring(with: range))
    }

    func length() -> Int { (document as NSString).length }

    func characterIndex(
        for _: NSPoint,
        tracking _: IMKLocationToOffsetMappingMode,
        inMarkedRange _: UnsafeMutablePointer<ObjCBool>!
    ) -> Int { 0 }

    func attributes(
        forCharacterIndex _: Int,
        lineHeightRectangle _: UnsafeMutablePointer<NSRect>?
    ) -> [AnyHashable: Any]? {
        attributesQueryCount += 1
        return [:]
    }

    func validAttributesForMarkedText() -> [Any] { [] }
    func overrideKeyboard(withKeyboardNamed _: String!) {}
    func selectMode(_: String!) {}
    func supportsUnicode() -> Bool { true }
    func bundleIdentifier() -> String! { bundleIdentifierValue }
    func windowLevel() -> CGWindowLevel {
        windowLevelQueryCount += 1
        return 0
    }
    func supportsProperty(_: TSMDocumentPropertyTag) -> Bool { supportsDocumentAccess }
    func uniqueClientIdentifierString() -> String! { uniqueIdentifierValue }
    func string(from _: NSRange, actualRange _: NSRangePointer!) -> String! { nil }
    func firstRect(forCharacterRange _: NSRange, actualRange _: NSRangePointer!) -> NSRect { .zero }
}
