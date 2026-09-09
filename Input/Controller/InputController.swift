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
/// | `LatinKeyHandler` | English candidate and trailing-space handling |
///
/// ## Composition state
///
/// The user builds a word character by character.
/// - `state.compositionBuffer` accumulates the raw keystrokes (e.g. `"hel"`).
/// - `state.currentPredictions` holds spell-checker completions only. The raw composition
///   remains at the insertion point and is not duplicated in the candidate window.
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
        .foregroundColor: NSColor.textColor,
        .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
    ]

    // MARK: - State + Strategy

    let state = InputState()
    lazy var spellPredictor: any PredictionProviding = SpellCheckPredictor()
    let keyHandler = LatinKeyHandler()
    let typingRules = EnglishTypingRules.shared
    var pendingTransparentPredictionUpdate: Task<Void, Never>?
    var transparentPredictionGeneration: UInt = 0
    var waitForTransparentPredictionDebounce: @MainActor () async throws -> Void = {
        try await Task.sleep(for: .milliseconds(75))
    }

    // MARK: - Init

    /// Swift requires designated initializer overrides to reside in the class body, not extensions.
    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
        Log.inputController.info("InputController initialized")
    }
}
