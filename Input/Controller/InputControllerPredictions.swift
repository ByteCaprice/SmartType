import InputMethodKit

/// Prediction fetching and display-word transformation.
extension InputController {
    // MARK: - Predictions

    func updatePredictions(client: any IMKTextInput) {
        guard !state.compositionBuffer.isEmpty else {
            cancelPredictions()
            return
        }

        let (predictions, display) = fetchCompletions(limit: Constants.spellCompletionLimit)

        state.currentPredictions = predictions
        CandidateWindow.shared.show(
            candidates: display,
            layout: ThemeManager.shared.candidateLayout,
            client: client,
        )
    }

    // MARK: - Private

    /// Fetches completions in their original and display-capitalised forms.
    private func fetchCompletions(limit: Int) -> (predictions: [String], display: [String]) {
        let rawWords = spellPredictor.completions(
            prefix: state.compositionBuffer,
            limit: min(limit, Constants.spellCompletionLimit),
        )
        let display = displayWords(from: rawWords)
        return (rawWords, display)
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
