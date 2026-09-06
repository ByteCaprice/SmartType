@testable import SwiftType
import AppKit
import Carbon.HIToolbox
import InputMethodKit
import XCTest

/// Regression tests for the Caps Lock / dedicated 中英-key bidirectional input-source
/// switching between SwiftType and Chinese input methods — including while a
/// composition is open ("even after typing").
///
/// The fix mirrors Squirrel's and has two cooperating parts that must stay in sync:
///
/// 1. `InputController.recognizedEvents(_:)` must include `.flagsChanged`. Without it
///    the IMK session never sees the Caps Lock flags-changed event and macOS defers
///    the source switch indefinitely while a composition is open — the "cannot switch
///    after typing" symptom.
/// 2. `handle(_:client:)` must pass flags-changed events through (return `false`) so
///    macOS — via the `TICapsLockLanguageSwitchCapable` Info.plist key (asserted in
///    `ConstantsTests.testInputMethodSupportsCapsLockLanguageSwitching`) — performs
///    the switch.
///
/// The switch-away safety net is `deactivateServer`, which commits any open
/// composition when macOS ends the session.
@MainActor
final class InputControllerEventRoutingTests: XCTestCase {
    private var controller: InputController!
    private var client: RecordingTextInputClient!

    override func setUpWithError() throws {
        try super.setUpWithError()
        CandidateWindow.shared.hide()
        client = RecordingTextInputClient()
        controller = try XCTUnwrap(
            InputController(server: nil, delegate: nil, client: nil),
            "InputController must be instantiable without a live IMKServer for unit tests"
        )
    }

    override func tearDown() {
        CandidateWindow.shared.hide()
        super.tearDown()
    }

    // MARK: - recognizedEvents must include flagsChanged (the core of the fix)

    func testRecognizedEventsIncludesKeyDownAndFlagsChanged() {
        let mask = controller.recognizedEvents(nil)

        XCTAssertEqual(mask, Int(NSEvent.EventTypeMask.keyDown.union(.flagsChanged).rawValue))
        XCTAssertTrue(
            mask & Int(NSEvent.EventTypeMask.flagsChanged.rawValue) != 0,
            "Dropping .flagsChanged re-breaks Caps Lock 中英 switching mid-composition"
        )
        XCTAssertTrue(mask & Int(NSEvent.EventTypeMask.keyDown.rawValue) != 0)
    }

    // MARK: - flags-changed events must be passed through to macOS

    func testCapsLockFlagsChangedEventIsPassedThroughToSystem() {
        let event = Self.flagsChangedEvent(keyCode: Self.capsLockKeyCode, flags: .maskAlphaShift)

        let handled = controller.handle(event, client: client)

        XCTAssertFalse(handled, "Caps Lock must reach macOS so it can switch the input source")
    }

    func testShiftFlagsChangedEventIsPassedThroughToSystem() {
        let event = Self.flagsChangedEvent(keyCode: Self.shiftKeyCode, flags: .maskShift)

        XCTAssertFalse(controller.handle(event, client: client))
    }

    func testCapsLockCommitsCompositionBeforePassthrough() {
        // "Even after typing": a composition is open when Caps Lock is pressed.
        controller.state.compositionBuffer = "hel"
        let event = Self.flagsChangedEvent(keyCode: Self.capsLockKeyCode, flags: .maskAlphaShift)

        let handled = controller.handle(event, client: client)

        XCTAssertFalse(handled)
        XCTAssertEqual(controller.state.compositionBuffer, "")
        XCTAssertEqual(client.insertedText, ["hel"])
        XCTAssertEqual(client.markedText, [""])
    }

    // MARK: - switch-away safety net

    func testActivateServerUsesUSKeyboardForPassthroughKeys() {
        controller.activateServer(client)

        XCTAssertEqual(client.overriddenKeyboardNames, ["com.apple.keylayout.US"])
    }

    func testDeactivateServerCommitsOpenComposition() {
        // When macOS switches to the Chinese input method, the session deactivates
        // and the in-progress buffer must be committed, not lost.
        controller.state.compositionBuffer = "hel"

        controller.deactivateServer(client)

        XCTAssertEqual(client.insertedText, ["hel"])
        XCTAssertEqual(controller.state.compositionBuffer, "")
    }

    func testCancelCompositionWithoutStoredClientResetsState() {
        controller.state.compositionBuffer = "hel"

        controller.cancelComposition() // controller was created with a nil client

        XCTAssertEqual(controller.state.compositionBuffer, "")
    }

    // MARK: - keyDown routing stays intact after the event-field extraction refactor

    func testKeyDownLetterIsHandledAndMarked() throws {
        let event = try Self.keyDownEvent(characters: "a", keyCode: 0)

        let handled = controller.handle(event, client: client)

        XCTAssertTrue(handled)
        XCTAssertEqual(controller.state.compositionBuffer, "a")
        XCTAssertEqual(client.markedText, ["a"])
        XCTAssertTrue(client.insertedText.isEmpty)
    }

    func testShiftKeyDownLetterIsStillComposed() throws {
        // Shift is deliberately NOT in InputController.modifierMask (Cmd/Ctrl/Option);
        // Shift+letter must continue composing, not pass through.
        let event = try Self.keyDownEvent(characters: "A", keyCode: 0, modifiers: .shift)

        let handled = controller.handle(event, client: client)

        XCTAssertTrue(handled)
        XCTAssertEqual(controller.state.compositionBuffer, "A")
    }

    func testCommandKeyDownIsPassedThroughAndCommitsBuffer() throws {
        controller.state.compositionBuffer = "hel"
        let event = try Self.keyDownEvent(characters: "c", keyCode: 8, modifiers: .command)

        let handled = controller.handle(event, client: client)

        XCTAssertFalse(handled, "Cmd-combinations must reach the client application")
        XCTAssertEqual(controller.state.compositionBuffer, "")
        XCTAssertEqual(client.insertedText, ["hel"], "The open composition is committed before passthrough")
    }

    func testMultiCharacterEventIsPassedThroughWithoutTruncation() throws {
        let event = try Self.keyDownEvent(characters: "ab", keyCode: 0)

        let handled = controller.handle(event, client: client)

        XCTAssertFalse(handled)
        XCTAssertEqual(controller.state.compositionBuffer, "")
        XCTAssertTrue(client.markedText.isEmpty)
    }

    func testMultiCharacterEventWithOpenCompositionCommitsAndPassesThrough() throws {
        controller.state.compositionBuffer = "hel"
        let event = try Self.keyDownEvent(characters: "ab", keyCode: 0)

        let handled = controller.handle(event, client: client)

        XCTAssertFalse(handled)
        XCTAssertEqual(
            client.insertedText,
            ["hel"],
            "The open composition is committed whole, never truncated to the first character"
        )
        XCTAssertEqual(controller.state.compositionBuffer, "")
    }

    func testEmptyCandidateDigitCommitsCompositionAndPassesThrough() throws {
        controller.state.compositionBuffer = "hel"
        controller.state.currentPredictions = ["hello"]
        CandidateWindow.shared.show(
            candidates: ["hello"],
            layout: .vertical,
            client: client
        )
        let event = try Self.keyDownEvent(characters: "7", keyCode: KeyCode.key7.rawValue)

        let handled = controller.handle(event, client: client)

        XCTAssertFalse(handled)
        XCTAssertEqual(client.insertedText, ["hel"])
        XCTAssertEqual(controller.state.compositionBuffer, "")
    }

    func testCandidateDigitSelectsFirstPredictionWithoutExplicitNavigation() throws {
        // With the literal slot removed, digit 1 must map directly to the first
        // prediction — no highlighted candidate is required beforehand.
        controller.state.compositionBuffer = "hel"
        controller.state.currentPredictions = ["hello"]
        CandidateWindow.shared.show(
            candidates: ["hello"],
            layout: .vertical,
            client: client
        )
        let event = try Self.keyDownEvent(characters: "1", keyCode: KeyCode.key1.rawValue)

        let handled = controller.handle(event, client: client)

        XCTAssertTrue(handled)
        XCTAssertEqual(client.insertedText, ["hello "])
        XCTAssertEqual(controller.state.compositionBuffer, "")
        XCTAssertTrue(controller.state.didAutoInsertTrailingSpace)
        XCTAssertFalse(CandidateWindow.shared.isVisible, "the window must hide after committing")
    }

    func testReturnWithoutSelectionCommitsTypedTextWithoutTrailingSpace() throws {
        controller.state.compositionBuffer = "hel"
        controller.state.currentPredictions = ["hello"]
        CandidateWindow.shared.show(
            candidates: ["hello"],
            layout: .vertical,
            client: client
        )
        let event = try Self.keyDownEvent(characters: "\r", keyCode: KeyCode.returnKey.rawValue)

        XCTAssertTrue(controller.handle(event, client: client))
        XCTAssertEqual(client.insertedText, ["hel"])
        XCTAssertFalse(controller.state.didAutoInsertTrailingSpace)
    }

    func testReturnWithHiddenCandidateWindowCommitsBeforePassingThrough() throws {
        controller.state.compositionBuffer = "xkq"
        let event = try Self.keyDownEvent(characters: "\r", keyCode: KeyCode.returnKey.rawValue)

        XCTAssertFalse(controller.handle(event, client: client))
        XCTAssertEqual(client.insertedText, ["xkq"])
        XCTAssertEqual(controller.state.compositionBuffer, "")
    }

    func testResetStateCancelsPendingPredictionUpdate() async {
        let pending = Task { @MainActor in
            _ = try? await Task.sleep(for: .seconds(5))
        }
        controller.pendingTransparentPredictionUpdate = pending

        controller.resetState()

        XCTAssertNil(controller.pendingTransparentPredictionUpdate)
        XCTAssertTrue(pending.isCancelled)
    }

    func testResetStateHidesCandidateWindowAndClearsPredictions() {
        // resetState previously hid the window explicitly; it now routes through
        // cancelPredictions(), which must preserve that observable behavior.
        controller.state.compositionBuffer = "hel"
        controller.state.currentPredictions = ["hello"]
        CandidateWindow.shared.show(
            candidates: ["hello"],
            layout: .vertical,
            client: client
        )
        XCTAssertTrue(CandidateWindow.shared.isVisible)

        controller.resetState()

        XCTAssertFalse(CandidateWindow.shared.isVisible)
        XCTAssertTrue(controller.state.currentPredictions.isEmpty)
        XCTAssertTrue(controller.state.compositionBuffer.isEmpty)
    }

    func testSpaceWithoutSelectionCommitsTypedTextWithTrailingSpace() throws {
        controller.state.compositionBuffer = "hel"
        controller.state.currentPredictions = ["hello"]
        CandidateWindow.shared.show(
            candidates: ["hello"],
            layout: .vertical,
            client: client
        )
        let event = try Self.keyDownEvent(characters: " ", keyCode: KeyCode.space.rawValue)

        XCTAssertTrue(controller.handle(event, client: client))
        XCTAssertEqual(client.insertedText, ["hel "])
        XCTAssertTrue(controller.state.didAutoInsertTrailingSpace)
    }

    func testReturnCommitsSelectedPredictionWithoutTrailingSpace() throws {
        controller.state.compositionBuffer = "hel"
        controller.state.currentPredictions = ["hello"]
        CandidateWindow.shared.show(
            candidates: ["hello"],
            layout: .vertical,
            client: client
        )
        CandidateWindow.shared.moveActiveColumnRight()
        let event = try Self.keyDownEvent(characters: "\r", keyCode: KeyCode.returnKey.rawValue)

        XCTAssertTrue(controller.handle(event, client: client))
        XCTAssertEqual(client.insertedText, ["hello"])
        XCTAssertFalse(controller.state.didAutoInsertTrailingSpace)
    }

    func testSpaceStillCommitsSelectedPredictionWithTrailingSpace() throws {
        controller.state.compositionBuffer = "hel"
        controller.state.currentPredictions = ["hello"]
        CandidateWindow.shared.show(
            candidates: ["hello"],
            layout: .vertical,
            client: client
        )
        CandidateWindow.shared.moveActiveColumnRight()
        let event = try Self.keyDownEvent(characters: " ", keyCode: KeyCode.space.rawValue)

        XCTAssertTrue(controller.handle(event, client: client))
        XCTAssertEqual(client.insertedText, ["hello "])
        XCTAssertTrue(controller.state.didAutoInsertTrailingSpace)
    }

    func testEventsForSwiftTypesOwnWindowsArePassedThrough() throws {
        // Typing in SwiftType's own windows (e.g. Settings search fields) must not
        // start a composition.
        client.bundleIdentifierValue = Bundle.main.bundleIdentifier ?? "com.matthew.inputmethod.SwiftType"
        let event = try Self.keyDownEvent(characters: "a", keyCode: 0)

        let handled = controller.handle(event, client: client)

        XCTAssertFalse(handled)
        XCTAssertEqual(controller.state.compositionBuffer, "")
    }

    func testDefaultPassthroughAppsDoNotStartComposition() throws {
        for bundleIdentifier in InputController.terminalBundleIdentifiers {
            client.bundleIdentifierValue = bundleIdentifier
            let event = try Self.keyDownEvent(characters: "a", keyCode: 0)

            XCTAssertFalse(controller.handle(event, client: client), bundleIdentifier)
            XCTAssertEqual(controller.state.compositionBuffer, "", bundleIdentifier)
        }
        XCTAssertTrue(client.markedText.isEmpty)
    }

    func testVSCodeDefaultsToPassthroughButXcodeDoesNot() {
        XCTAssertTrue(InputController.terminalBundleIdentifiers.contains("com.microsoft.VSCode"))
        XCTAssertFalse(InputController.terminalBundleIdentifiers.contains("com.apple.dt.Xcode"))
    }

    func testEdgeKeyEventsUseInlineComposition() throws {
        client.bundleIdentifierValue = "com.microsoft.edgemac"
        let event = try Self.keyDownEvent(characters: "a", keyCode: 0)

        XCTAssertTrue(controller.handle(event, client: client))
        XCTAssertEqual(controller.state.compositionBuffer, "a")
        XCTAssertTrue(client.insertedText.isEmpty)
        XCTAssertEqual(client.markedText, ["a"])
    }

    func testEdgeCapsLockCommitsInlineCompositionWhenDelivered() throws {
        client.bundleIdentifierValue = "com.microsoft.edgemac"
        _ = controller.handle(try Self.keyDownEvent(characters: "a", keyCode: 0), client: client)
        let event = Self.flagsChangedEvent(keyCode: Self.capsLockKeyCode, flags: .maskAlphaShift)

        XCTAssertFalse(controller.handle(event, client: client))
        XCTAssertEqual(controller.state.compositionBuffer, "")
        XCTAssertEqual(client.insertedText, ["a"])
        XCTAssertEqual(client.markedText, ["a", ""])
    }

    // MARK: - Event synthesis helpers

    private static let capsLockKeyCode: CGKeyCode = 0x39
    private static let shiftKeyCode: CGKeyCode = 0x38

    /// Synthesizes a flags-changed event (Caps Lock / Shift / …). `NSEvent.keyEvent`
    /// only accepts keyDown/keyUp, so build a CGEvent and retype it.
    private static func flagsChangedEvent(keyCode: CGKeyCode, flags: CGEventFlags) -> NSEvent {
        let cgEvent = CGEvent(
            keyboardEventSource: CGEventSource(stateID: .hidSystemState),
            virtualKey: keyCode,
            keyDown: false,
        )!
        cgEvent.type = .flagsChanged
        cgEvent.flags = flags
        let nsEvent = NSEvent(cgEvent: cgEvent)!
        XCTAssertEqual(nsEvent.type, .flagsChanged)
        return nsEvent
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

/// A recording stand-in for an `IMKTextInput` client. The methods `InputController`
/// actually invokes are implemented meaningfully; everything else returns neutral
/// values. Deliberately not `@MainActor` so its methods satisfy the nonisolated
/// ObjC protocol requirements under strict concurrency.
private final class RecordingTextInputClient: NSObject, IMKTextInput {
    var bundleIdentifierValue = "com.swifttype.tests.recording-client"

    private(set) var insertedText: [String] = []
    private(set) var markedText: [String] = []
    private(set) var overriddenKeyboardNames: [String] = []

    func insertText(_ string: Any, replacementRange _: NSRange) {
        insertedText.append(stringValue(string))
    }

    func setMarkedText(_ string: Any, selectionRange _: NSRange, replacementRange _: NSRange) {
        markedText.append(stringValue(string))
    }

    private func stringValue(_ string: Any) -> String {
        if let s = string as? String { return s }
        if let a = string as? NSAttributedString { return a.string }
        return String(describing: string)
    }

    // MARK: - Neutral stubs

    func selectedRange() -> NSRange { NSRange(location: 0, length: 0) }
    func markedRange() -> NSRange { NSRange(location: NSNotFound, length: NSNotFound) }
    func attributedSubstring(from _: NSRange) -> NSAttributedString! { nil }
    func length() -> Int { 0 }

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
    func overrideKeyboard(withKeyboardNamed keyboardName: String!) {
        overriddenKeyboardNames.append(keyboardName)
    }
    func selectMode(_: String!) {}
    func supportsUnicode() -> Bool { true }
    func bundleIdentifier() -> String! { bundleIdentifierValue }
    func windowLevel() -> CGWindowLevel { 0 }
    func supportsProperty(_: TSMDocumentPropertyTag) -> Bool { false }
    func uniqueClientIdentifierString() -> String! { "recording-client" }
    func string(from _: NSRange, actualRange _: NSRangePointer!) -> String! { nil }
    func firstRect(forCharacterRange _: NSRange, actualRange _: NSRangePointer!) -> NSRect { .zero }
}
