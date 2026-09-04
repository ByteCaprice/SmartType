@testable import SwiftType
import AppKit
import InputMethodKit
import XCTest

@MainActor
final class InputControllerTransparentPredictionTests: XCTestCase {
    private var controller: InputController!
    private var client: RecordingTextInputClient!

    override func setUpWithError() throws {
        try super.setUpWithError()
        CandidateWindow.shared.hide()
        client = RecordingTextInputClient()
        client.bundleIdentifierValue = "com.microsoft.edgemac"
        controller = try XCTUnwrap(
            InputController(server: nil, delegate: nil, client: nil),
            "InputController must be instantiable without a live IMKServer for unit tests"
        )
    }

    override func tearDown() {
        CandidateWindow.shared.hide()
        super.tearDown()
    }

    func testChromiumFamilyUsesTransparentPrediction() {
        XCTAssertTrue(InputController.usesTransparentPrediction(bundleIdentifier: "com.microsoft.edgemac"))
        XCTAssertTrue(InputController.usesTransparentPrediction(bundleIdentifier: "com.microsoft.edgemac.canary"))
        XCTAssertTrue(InputController.usesTransparentPrediction(bundleIdentifier: "com.tencent.WeWorkMac"))
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

    func testLetterInEdgeIsPassedThroughWithoutMarkedText() throws {
        let handled = try type("h", keyCode: 4)

        XCTAssertFalse(handled)
        XCTAssertEqual(controller.state.compositionBuffer, "h")
        XCTAssertTrue(controller.state.mirrorsClientText)
        XCTAssertTrue(client.markedText.isEmpty)
        XCTAssertTrue(client.insertedText.isEmpty)
        XCTAssertEqual(controller.composedString(client) as? String, "")
    }

    func testWeComLettersStayMirroredWithoutInserts() throws {
        client.bundleIdentifierValue = "com.tencent.WeWorkMac"
        try type("h", keyCode: 4)
        try type("e", keyCode: 14)

        XCTAssertEqual(controller.state.compositionBuffer, "he")
        XCTAssertTrue(client.markedText.isEmpty)
        XCTAssertTrue(client.insertedText.isEmpty)
        XCTAssertEqual(controller.state.expectedCursor, 2)
    }

    func testBackspaceShrinksMirrorAndLeavesDeletionToClient() throws {
        try type("h", keyCode: 4)
        try type("e", keyCode: 14)
        let handled = try type("\u{8}", keyCode: KeyCode.backspace.rawValue)

        XCTAssertFalse(handled)
        XCTAssertEqual(controller.state.compositionBuffer, "h")
        XCTAssertEqual(controller.state.expectedCursor, 1)
        XCTAssertTrue(client.insertedText.isEmpty)
        XCTAssertTrue(client.markedText.isEmpty)
    }

    func testCapsLockDropsMirrorWithoutCommitting() throws {
        try type("h", keyCode: 4)
        try type("e", keyCode: 14)
        let event = Self.flagsChangedEvent(keyCode: 0x39, flags: .maskAlphaShift)

        XCTAssertFalse(controller.handle(event, client: client))
        XCTAssertEqual(controller.state.compositionBuffer, "")
        XCTAssertFalse(controller.state.mirrorsClientText)
        XCTAssertTrue(client.insertedText.isEmpty)
        XCTAssertTrue(client.markedText.isEmpty)
    }

    func testDeactivateDoesNotInsertMirroredText() throws {
        try type("h", keyCode: 4)

        controller.deactivateServer(client)

        XCTAssertEqual(controller.state.compositionBuffer, "")
        XCTAssertTrue(client.insertedText.isEmpty)
        XCTAssertTrue(client.markedText.isEmpty)
    }

    func testStaleCursorDropsMirrorThenStartsNewLetter() throws {
        try type("h", keyCode: 4)
        client.selectedLocation = 9

        let handled = try type("e", keyCode: 14)

        XCTAssertFalse(handled)
        XCTAssertEqual(controller.state.compositionBuffer, "e")
        XCTAssertEqual(controller.state.expectedCursor, 10)
        XCTAssertTrue(client.insertedText.isEmpty)
    }

    func testLiteralSpacePassesThroughWithoutInsert() throws {
        try type("h", keyCode: 4)
        showCandidates(["hello"])

        let handled = try type(" ", keyCode: KeyCode.space.rawValue)

        XCTAssertFalse(handled)
        XCTAssertEqual(controller.state.compositionBuffer, "")
        XCTAssertTrue(client.insertedText.isEmpty)
        XCTAssertTrue(controller.state.didAutoInsertTrailingSpace)
    }

    func testCandidateDigitInsertsSuffixOnly() throws {
        try type("h", keyCode: 4)
        try type("e", keyCode: 14)
        try type("l", keyCode: 37)
        controller.state.currentPredictions = ["hel", "hello"]
        showCandidates(["hello"])

        let handled = try type("2", keyCode: KeyCode.key2.rawValue)

        XCTAssertTrue(handled)
        XCTAssertEqual(client.insertedText, ["lo "])
        XCTAssertEqual(client.insertionRanges.last?.location, NSNotFound)
        XCTAssertEqual(controller.state.compositionBuffer, "")
        XCTAssertTrue(controller.state.didAutoInsertTrailingSpace)
    }

    func testCorrectionPrimesMarkedTextThenCommitsFullWord() throws {
        try type("t", keyCode: 17)
        try type("e", keyCode: 14)
        try type("h", keyCode: 4)
        controller.state.currentPredictions = ["teh", "the"]
        showCandidates(["the"])

        let handled = try type("2", keyCode: KeyCode.key2.rawValue)

        XCTAssertTrue(handled)
        XCTAssertEqual(client.markedText, ["the "])
        XCTAssertEqual(client.insertedText, ["the "])
        XCTAssertEqual(client.markedReplacementRanges.last, NSRange(location: 0, length: 3))
        XCTAssertEqual(controller.state.compositionBuffer, "")
    }

    func testCommandKeyDropsMirrorWithoutInsert() throws {
        try type("h", keyCode: 4)
        let event = try Self.keyDownEvent(characters: "c", keyCode: 8, modifiers: .command)

        XCTAssertFalse(controller.handle(event, client: client))
        XCTAssertEqual(controller.state.compositionBuffer, "")
        XCTAssertTrue(client.insertedText.isEmpty)
        XCTAssertTrue(client.markedText.isEmpty)
    }

    func testArrowKeyDropsMirrorAndPassesThrough() throws {
        try type("h", keyCode: 4)
        let handled = try type("\u{F701}", keyCode: KeyCode.downArrow.rawValue)

        XCTAssertFalse(handled)
        XCTAssertEqual(controller.state.compositionBuffer, "")
        XCTAssertTrue(client.insertedText.isEmpty)
    }

    @discardableResult
    private func type(_ characters: String, keyCode: UInt16) throws -> Bool {
        let event = try Self.keyDownEvent(characters: characters, keyCode: keyCode)
        let handled = controller.handle(event, client: client)
        if !handled, characters.count == 1, let char = characters.first, char.isLetter
            || EnglishTypingRules.shared.compositionContinuationMarks.contains(char)
        {
            client.document += characters
            client.selectedLocation += (characters as NSString).length
        }
        return handled
    }

    private func showCandidates(_ candidates: [String]) {
        CandidateWindow.shared.show(
            candidates: candidates,
            literalText: controller.state.compositionBuffer,
            layout: .vertical,
            client: client,
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

private final class RecordingTextInputClient: NSObject, IMKTextInput {
    var bundleIdentifierValue = "com.microsoft.edgemac"
    var document = ""
    var selectedLocation = 0
    var selectedLength = 0

    private(set) var insertedText: [String] = []
    private(set) var markedText: [String] = []
    private(set) var insertionRanges: [NSRange] = []
    private(set) var markedReplacementRanges: [NSRange] = []

    func insertText(_ string: Any, replacementRange: NSRange) {
        insertedText.append(stringValue(string))
        insertionRanges.append(replacementRange)
    }

    func setMarkedText(_ string: Any, selectionRange _: NSRange, replacementRange: NSRange) {
        markedText.append(stringValue(string))
        markedReplacementRanges.append(replacementRange)
    }

    private func stringValue(_ string: Any) -> String {
        if let s = string as? String { return s }
        if let a = string as? NSAttributedString { return a.string }
        return String(describing: string)
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
    ) -> [AnyHashable: Any]? { [:] }

    func validAttributesForMarkedText() -> [Any] { [] }
    func overrideKeyboard(withKeyboardNamed _: String!) {}
    func selectMode(_: String!) {}
    func supportsUnicode() -> Bool { true }
    func bundleIdentifier() -> String! { bundleIdentifierValue }
    func windowLevel() -> CGWindowLevel { 0 }
    func supportsProperty(_: TSMDocumentPropertyTag) -> Bool { false }
    func uniqueClientIdentifierString() -> String! { "recording-client" }
    func string(from _: NSRange, actualRange _: NSRangePointer!) -> String! { nil }
    func firstRect(forCharacterRange _: NSRange, actualRange _: NSRangePointer!) -> NSRect { .zero }
}
