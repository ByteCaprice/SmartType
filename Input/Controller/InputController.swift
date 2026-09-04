import AppKit
import InputMethodKit
import os

/// The `IMKInputController` subclass that owns all input-method logic.
///
/// ## Architecture
///
/// `InputController` is split across focused extension files:
///
/// | File / Type | Responsibility |
/// |---|---|
/// | `InputControllerLifecycle` | IMK overrides: `activateServer`, `deactivateServer`, `composedString`, … |
/// | `InputControllerStateManagement` | `resetState`, `cancelPredictions` |
/// | `InputControllerPredictions` | Fetch and display spelling completions |
/// | `InputClientPolicy` | Per-app mode: passthrough, inline, or transparent prediction |
/// | `InputControllerTransparentPrediction` | Chromium/CEF passthrough prediction without marked text |
/// | `InputControllerComposition` | `commitCompositionBuffer`, `commitWord`, `selectCandidateByIndex`, marked text |
/// | `LatinKeyHandler` | English literal slot and trailing-space handling |
///
/// ## Composition state
///
/// The user builds a word character by character.
/// - `state.compositionBuffer` accumulates the raw keystrokes (e.g. `"hel"`).
/// - `state.currentPredictions` holds the unified candidate array. The first element is
///   the composition buffer itself (literal slot) and subsequent elements are spell-checker
///   completions.
/// - Marked text is shown in the active text field via `setMarkedText`.
///
/// ## Threading
/// All methods are called on the main thread by InputMethodKit.
@MainActor @objc(InputController)
class InputController: IMKInputController, @unchecked Sendable {
    // MARK: - Constants

    static let modifierMask: NSEvent.ModifierFlags = [.command, .control, .option]
    static let ownBundleIdentifier = Bundle.main.bundleIdentifier
    static let terminalBundleIdentifiers = InputClientPolicy.passthroughBundleIdentifiers

    static func usesTransparentPrediction(bundleIdentifier: String?) -> Bool {
        InputClientPolicy.mode(forBundleIdentifier: bundleIdentifier) == .transparentPrediction
    }

    static let markedTextAttributes: [NSAttributedString.Key: Any] = [
        .underlineStyle: NSUnderlineStyle.single.rawValue,
        .foregroundColor: NSColor.textColor,
        .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
    ]

    // MARK: - State + Strategy

    let state = InputState()
    lazy var spellPredictor = SpellCheckPredictor()
    let keyHandler = LatinKeyHandler()
    let typingRules = EnglishTypingRules.shared

    // MARK: - Init

    /// Swift requires designated initializer overrides to reside in the class body, not extensions.
    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
        Log.inputController.info("InputController initialized")
    }
}
