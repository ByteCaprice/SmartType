import AppKit
import InputMethodKit

/// Buffer commit, candidate selection, and marked-text helpers.
extension InputController {
    // MARK: - Composition

    func commitCompositionBuffer(client: any IMKTextInput) {
        if state.mirrorsClientText
            || Self.usesTransparentPrediction(bundleIdentifier: client.bundleIdentifier())
        {
            discardMirroredComposition()
            return
        }

        let text = state.compositionBuffer
        if text.isEmpty {
            // Nothing to commit — clear any lingering marked text and hide predictions.
            client.setMarkedText(
                "",
                selectionRange: NSRange(location: 0, length: 0),
                replacementRange: Constants.replacementNotFound,
            )
            cancelPredictions()
            return
        }
        client.insertText(text, replacementRange: Constants.replacementNotFound)
        state.compositionBuffer = ""
        cancelPredictions()
    }

    func commitCompositionForLanguageSwitch(client: any IMKTextInput) {
        if state.mirrorsClientText
            || Self.usesTransparentPrediction(bundleIdentifier: client.bundleIdentifier())
        {
            discardMirroredComposition()
            return
        }

        let text = state.compositionBuffer
        guard !text.isEmpty else { return }

        // Electron-style clients may keep the marked range alive briefly after
        // insertText. Clear it synchronously so macOS can switch input sources.
        client.setMarkedText(
            "",
            selectionRange: NSRange(location: 0, length: 0),
            replacementRange: Constants.replacementNotFound,
        )
        client.insertText(text, replacementRange: Constants.replacementNotFound)
        state.compositionBuffer = ""
        cancelPredictions()
    }

    func commitWord(_ word: String, client: any IMKTextInput) {
        let committed = word + " "
        client.insertText(committed, replacementRange: Constants.replacementNotFound)
        state.compositionBuffer = ""
        state.didAutoInsertTrailingSpace = true
        cancelPredictions()
    }

    // MARK: - Candidate Selection

    /// Commits the prediction at `index` in `state.currentPredictions`.
    func selectCandidateByIndex(_ index: Int, client: any IMKTextInput) {
        guard index < state.currentPredictions.count else { return }

        let prediction = state.currentPredictions[index]
        let word = typingRules.preserveCapitalization(
            original: state.compositionBuffer,
            suggested: prediction,
        )

        commitWord(word, client: client)
    }

    // MARK: - Marked Text

    func updateMarkedText(client: any IMKTextInput) {
        setMarkedText(state.compositionBuffer, client: client)
    }

    private func setMarkedText(_ text: String, client: any IMKTextInput) {
        let attrString = NSAttributedString(string: text, attributes: Self.markedTextAttributes)
        client.setMarkedText(
            attrString,
            selectionRange: NSRange(location: (text as NSString).length, length: 0),
            replacementRange: Constants.replacementNotFound,
        )
    }
}
