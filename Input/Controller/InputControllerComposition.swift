import AppKit
import InputMethodKit

/// Buffer commit, candidate selection, and marked-text helpers.
extension InputController {
    // MARK: - Composition

    /// Commits text through a short-lived marked phase for clients that reject
    /// direct `insertText` calls without one. The subsequent insert clears the mark
    /// synchronously, so no composition remains to block input-source switching.
    func insertTextForCompatibility(
        _ text: String,
        replacing replacementRange: NSRange = Constants.replacementNotFound,
        forceMarkedText: Bool = false,
        client: any IMKTextInput,
    ) {
        if !text.isEmpty,
           forceMarkedText
            || InputClientPolicy.requiresMarkedTextForDirectCommit(client.bundleIdentifier())
        {
            let attrString = NSAttributedString(string: text, attributes: Self.markedTextAttributes)
            client.setMarkedText(
                attrString,
                selectionRange: NSRange(location: (text as NSString).length, length: 0),
                replacementRange: replacementRange,
            )
            client.insertText(text, replacementRange: Constants.replacementNotFound)
            return
        }

        client.insertText(text, replacementRange: replacementRange)
    }

    func commitCompositionBuffer(client: any IMKTextInput) {
        let mode = InputClientPolicy.mode(forBundleIdentifier: client.bundleIdentifier())
        if state.mirrorsClientText || mode == .transparentPrediction {
            discardMirroredComposition()
            return
        }
        if mode == .passthrough || mode == .directInput {
            state.compositionBuffer = ""
            cancelPredictions()
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
        let mode = InputClientPolicy.mode(forBundleIdentifier: client.bundleIdentifier())
        if state.mirrorsClientText || mode == .transparentPrediction {
            discardMirroredComposition()
            return
        }
        // Match the lifecycle commit path: these clients never compose locally.
        // Do not write a leaked buffer or create a mark while macOS switches sources.
        if mode == .passthrough || mode == .directInput {
            state.compositionBuffer = ""
            cancelPredictions()
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

    func commitWord(
        _ word: String,
        trailingSpace: Bool = true,
        client: any IMKTextInput,
    ) {
        let committed = trailingSpace ? word + " " : word
        client.insertText(committed, replacementRange: Constants.replacementNotFound)
        state.compositionBuffer = ""
        if trailingSpace {
            recordAutoInsertedTrailingSpace(client: client)
        } else {
            clearAutoInsertedTrailingSpace()
        }
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
