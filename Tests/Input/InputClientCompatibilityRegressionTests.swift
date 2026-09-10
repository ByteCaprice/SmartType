@testable import SwiftType
import AppKit
import Carbon.HIToolbox
import InputMethodKit
import XCTest

/// Regression coverage for the client-compatibility patch: VS Code direct input,
/// WeCom/DingTalk marked-text priming, and the mode guards on both composition
/// commit paths (`commitCompositionBuffer` and `commitCompositionForLanguageSwitch`).
///
/// The safety rules under test:
///
/// 1. A leaked/stale composition buffer must never be inserted into — or marked in —
///    a passthrough or direct-input client, whether the trigger is `deactivateServer`
///    or a Caps Lock language switch.
/// 2. Direct input commits printable text exactly once through the primed
///    mark-then-insert path and never starts a composition or shows predictions.
/// 3. Compatibility priming keeps Smart Space's auto-space bookkeeping intact.
///
/// The recording client faithfully models document text, the selection cursor, and
/// the mark-then-insert handshake (`setMarkedText` primes a replacement range that
/// the following `insertText` consumes), mirroring how real IMK clients behave.
@MainActor
final class InputClientCompatibilityRegressionTests: XCTestCase {
    private var controller: InputController!
    private var client: RecordingCompatibilityClient!

    override func setUp() async throws {
        try await super.setUp()
        CandidateWindow.shared.hide()
        client = RecordingCompatibilityClient()
        controller = try XCTUnwrap(
            InputController(server: nil, delegate: nil, client: nil),
            "InputController must be instantiable without a live IMKServer for unit tests"
        )
    }

    override func tearDown() async throws {
        CandidateWindow.shared.hide()
        try await super.tearDown()
    }

    // MARK: - Stale composition state must never leak into passthrough / direct-input clients

    func testDeactivateServerDoesNotCommitStaleBufferIntoTerminal() {
        client.bundleIdentifierValue = "com.apple.Terminal"
        controller.state.compositionBuffer = "hel" // leaked from a prior inline session

        controller.deactivateServer(client)

        XCTAssertTrue(
            client.insertedText.isEmpty,
            "passthrough clients must never receive committed composition text"
        )
        XCTAssertTrue(
            client.markedText.isEmpty,
            "passthrough clients must never receive marked text"
        )
        XCTAssertEqual(controller.state.compositionBuffer, "")
        XCTAssertFalse(CandidateWindow.shared.isVisible)
    }

    func testDeactivateServerDoesNotCommitStaleBufferIntoVSCode() {
        client.bundleIdentifierValue = "com.microsoft.VSCode"
        controller.state.compositionBuffer = "hel"

        controller.deactivateServer(client)

        XCTAssertTrue(
            client.insertedText.isEmpty,
            "direct-input clients must never receive committed composition text"
        )
        XCTAssertTrue(
            client.markedText.isEmpty,
            "direct-input clients must never receive marked text"
        )
        XCTAssertEqual(controller.state.compositionBuffer, "")
        XCTAssertFalse(CandidateWindow.shared.isVisible)
    }

    func testCapsLockDoesNotCommitStaleBufferIntoTerminal() {
        client.bundleIdentifierValue = "com.apple.Terminal"
        controller.state.compositionBuffer = "hel"

        let handled = controller.handle(
            Self.flagsChangedEvent(keyCode: 0x39, flags: .maskAlphaShift),
            client: client
        )

        XCTAssertFalse(handled)
        XCTAssertEqual(
            client.insertedText, [],
            "the Caps Lock commit path must apply the same mode guards as commitCompositionBuffer"
        )
        XCTAssertEqual(
            client.markedText, [],
            "a leaked buffer must not create a temporary mark that can block the source switch"
        )
        XCTAssertEqual(controller.state.compositionBuffer, "")
    }

    func testCapsLockDoesNotCommitStaleBufferIntoVSCode() {
        client.bundleIdentifierValue = "com.microsoft.VSCode"
        controller.state.compositionBuffer = "hel"

        let handled = controller.handle(
            Self.flagsChangedEvent(keyCode: 0x39, flags: .maskAlphaShift),
            client: client
        )

        XCTAssertFalse(handled)
        XCTAssertEqual(
            client.insertedText, [],
            "inserting stale text through a temporary mark can block input-source switching"
        )
        XCTAssertEqual(
            client.markedText, [],
            "a leaked buffer must not create a temporary mark that can block the source switch"
        )
        XCTAssertEqual(controller.state.compositionBuffer, "")
    }

    // MARK: - Caps Lock on direct-input clients in the normal flow

    func testCapsLockInVSCodePassesThroughWithoutExtraClientWrites() throws {
        client.bundleIdentifierValue = "com.microsoft.VSCode"

        XCTAssertTrue(controller.handle(
            try Self.keyDownEvent(characters: "a", keyCode: 0),
            client: client
        ))
        let handled = controller.handle(
            Self.flagsChangedEvent(keyCode: 0x39, flags: .maskAlphaShift),
            client: client
        )

        XCTAssertFalse(handled)
        XCTAssertEqual(client.insertedText, ["a"])
        XCTAssertEqual(client.markedText, ["a"])
        XCTAssertEqual(controller.state.compositionBuffer, "")
        XCTAssertFalse(controller.state.mirrorsClientText)
        XCTAssertNil(controller.state.compositionClientBundleID)
        XCTAssertFalse(CandidateWindow.shared.isVisible)
    }

    func testActivateServerResetsStaleDirectInputState() {
        client.bundleIdentifierValue = "com.microsoft.VSCode"
        controller.state.compositionBuffer = "hel"
        controller.state.mirrorsClientText = true
        controller.state.compositionClientBundleID = "com.tencent.WeWorkMac"

        controller.activateServer(client)

        XCTAssertEqual(controller.state.compositionBuffer, "")
        XCTAssertFalse(controller.state.mirrorsClientText)
        XCTAssertNil(controller.state.compositionClientBundleID)
        XCTAssertEqual(client.overriddenKeyboardNames, ["com.apple.keylayout.US"])
    }

    // MARK: - Direct input must stay prediction-free and non-interfering

    func testVSCodeSpaceCommitsExactlyOnceWithPrimedMark() throws {
        client.bundleIdentifierValue = "com.microsoft.VSCode"

        let handled = controller.handle(
            try Self.keyDownEvent(characters: " ", keyCode: KeyCode.space.rawValue),
            client: client
        )

        XCTAssertTrue(handled)
        XCTAssertEqual(client.markedText, [" "])
        XCTAssertEqual(client.insertedText, [" "])
        XCTAssertEqual(client.document, " ")
        XCTAssertEqual(controller.state.compositionBuffer, "")
        XCTAssertNil(controller.state.predictionSnapshot)
        XCTAssertFalse(CandidateWindow.shared.isVisible)
    }

    func testVSCodeDigitWithoutCandidatesIsLiteralInput() throws {
        client.bundleIdentifierValue = "com.microsoft.VSCode"

        let handled = controller.handle(
            try Self.keyDownEvent(characters: "3", keyCode: KeyCode.key3.rawValue),
            client: client
        )

        XCTAssertTrue(handled)
        XCTAssertEqual(client.insertedText, ["3"])
        XCTAssertEqual(client.markedText, ["3"])
        XCTAssertEqual(controller.state.compositionBuffer, "")
        XCTAssertFalse(CandidateWindow.shared.isVisible)
    }

    func testVSCodeNewlineAndNonPrintableCharactersStayHostOwned() throws {
        client.bundleIdentifierValue = "com.microsoft.VSCode"

        XCTAssertFalse(controller.handle(
            try Self.keyDownEvent(characters: "\n", keyCode: 36),
            client: client
        ))
        XCTAssertFalse(controller.handle(
            try Self.keyDownEvent(characters: "\u{7}", keyCode: 0),
            client: client
        ))

        XCTAssertTrue(client.insertedText.isEmpty)
        XCTAssertTrue(client.markedText.isEmpty)
    }

    // MARK: - Smart Space / primed commit ordering for compatibility clients

    func testWeComSpaceFallbackPrimesMarkBeforeInsert() throws {
        client.bundleIdentifierValue = "com.tencent.WeWorkMac"
        try Self.type(controller: controller, client: client, "h")
        try Self.type(controller: controller, client: client, "e")

        let handled = controller.handle(
            try Self.keyDownEvent(characters: " ", keyCode: KeyCode.space.rawValue),
            client: client
        )

        XCTAssertTrue(handled)
        XCTAssertEqual(client.markedText, ["h", "e", " "])
        XCTAssertEqual(client.insertedText, ["h", "e", " "])
        XCTAssertEqual(client.document, "he ")
        XCTAssertEqual(controller.state.compositionBuffer, "")
        XCTAssertTrue(controller.state.didAutoInsertTrailingSpace)
    }

    func testDingTalkHelperDescendantIsTransparentWithPriming() {
        XCTAssertEqual(
            InputClientPolicy.mode(forBundleIdentifier: "com.alibaba.DingTalkMac.helper"),
            .transparentPrediction
        )
        XCTAssertTrue(
            InputClientPolicy.requiresMarkedTextForDirectCommit("com.alibaba.DingTalkMac.helper.GPU")
        )
    }

    // MARK: - Event synthesis helpers

    private static func type(
        controller: InputController,
        client: RecordingCompatibilityClient,
        _ character: String,
    ) throws {
        XCTAssertTrue(controller.handle(
            try Self.keyDownEvent(characters: character, keyCode: 0),
            client: client
        ))
    }

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

/// A recording `IMKTextInput` stand-in that models document text and the cursor.
/// `insertText` appends at the selection (or at the range primed by the preceding
/// `setMarkedText`, matching the compatibility commit handshake) and moves the
/// cursor to the end of the inserted text, as real clients do.
private final class RecordingCompatibilityClient: NSObject, IMKTextInput {
    var bundleIdentifierValue = "com.swifttype.tests.compatibility-client"

    var document = ""
    var selectedLocation = 0
    var selectedLength = 0

    private(set) var insertedText: [String] = []
    private(set) var markedText: [String] = []
    private(set) var overriddenKeyboardNames: [String] = []
    private var pendingMarkedReplacementRange: NSRange?

    func insertText(_ string: Any, replacementRange: NSRange) {
        let text = stringValue(string)
        insertedText.append(text)
        let effectiveRange = replacementRange.location == NSNotFound
            ? pendingMarkedReplacementRange ?? selectedRange()
            : replacementRange
        replaceDocumentText(in: effectiveRange, with: text)
        pendingMarkedReplacementRange = nil
    }

    func setMarkedText(_ string: Any, selectionRange _: NSRange, replacementRange: NSRange) {
        markedText.append(stringValue(string))
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

    // MARK: - Neutral stubs

    func selectedRange() -> NSRange {
        NSRange(location: selectedLocation, length: selectedLength)
    }

    func markedRange() -> NSRange { NSRange(location: NSNotFound, length: NSNotFound) }
    func attributedSubstring(from range: NSRange) -> NSAttributedString! {
        guard range.location != NSNotFound,
              range.location >= 0,
              NSMaxRange(range) <= (document as NSString).length
        else { return nil }
        return NSAttributedString(
            string: (document as NSString).substring(with: range)
        )
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
    func overrideKeyboard(withKeyboardNamed keyboardName: String!) {
        overriddenKeyboardNames.append(keyboardName)
    }
    func selectMode(_: String!) {}
    func supportsUnicode() -> Bool { true }
    func bundleIdentifier() -> String! { bundleIdentifierValue }
    func windowLevel() -> CGWindowLevel { 0 }
    func supportsProperty(_: TSMDocumentPropertyTag) -> Bool { false }
    func uniqueClientIdentifierString() -> String! { "compatibility-client" }
    func string(from _: NSRange, actualRange _: NSRangePointer!) -> String! { nil }
    func firstRect(forCharacterRange _: NSRange, actualRange _: NSRangePointer!) -> NSRect { .zero }
}
