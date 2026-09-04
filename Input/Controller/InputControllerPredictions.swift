import InputMethodKit

/// Prediction fetching and display-word transformation.
extension InputController {
    // MARK: - Predictions

    func updatePredictions(client: any IMKTextInput) {
        guard !state.compositionBuffer.isEmpty else {
            cancelPredictions()
            return
        }

        let (unified, display) = fetchCompletions(limit: Constants.spellCompletionLimit)

        state.currentPredictions = unified
        CandidateWindow.shared.show(
            candidates: display,
            literalText: keyHandler.literalText(compositionBuffer: state.compositionBuffer),
            layout: ThemeManager.shared.candidateLayout,
            client: client,
        )
    }

    // MARK: - Private

    /// Fetches completions and returns both the unified predictions
    /// array (for `state.currentPredictions`) and the display-capitalised array (for
    /// `CandidateWindow`).
    private func fetchCompletions(limit: Int) -> (unified: [String], display: [String]) {
        let rawWords = spellPredictor.completions(
            prefix: state.compositionBuffer,
            limit: min(limit, Constants.spellCompletionLimit),
        )
        let unified = keyHandler.unifiedPredictions(
            from: rawWords, compositionBuffer: state.compositionBuffer,
        )
        let display = displayWords(from: rawWords)
        return (unified, display)
    }

    /// Maps raw (original-case) predictions to display-capitalised strings by matching
    /// the case of the composition buffer onto each suggestion.
    private func displayWords(from rawWords: [String]) -> [String] {
        rawWords.map {
            typingRules.preserveCapitalization(
                original: state.compositionBuffer,
                suggested: $0,
            )
        }
    }
}
