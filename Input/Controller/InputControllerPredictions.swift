import InputMethodKit

/// Prediction fetching and display-word transformation.
extension InputController {
    // MARK: - Predictions

    func updatePredictions(client: any IMKTextInput) {
        PerformanceTrace.measure("Prediction update") {
            guard !state.compositionBuffer.isEmpty else {
                cancelPredictions()
                return
            }

            let result = fetchPredictionResult(limit: Constants.spellCompletionLimit)
            let display = displayWords(from: result.predictions)

            state.predictionSnapshot = PredictionSnapshot(
                buffer: state.compositionBuffer,
                predictions: result.predictions,
                defaultSpaceAction: result.defaultSpaceAction,
                reason: result.reason
            )
            CandidateWindow.shared.show(
                candidates: display,
                defaultSpaceAction: result.defaultSpaceAction,
                defaultSpaceReason: result.reason,
                literalSpaceText: state.compositionBuffer,
                layout: ThemeManager.shared.candidateLayout,
                client: client,
                candidateSelectionHandler: { [weak self] index in
                    guard let self else { return }
                    if self.state.mirrorsClientText {
                        self.selectTransparentCandidateByIndex(index, client: client)
                    } else {
                        self.selectCandidateByIndex(index, client: client)
                    }
                }
            )
        }
    }

    // MARK: - Private

    private func fetchPredictionResult(limit: Int) -> PredictionResult {
        spellPredictor.predictionResult(
            prefix: state.compositionBuffer,
            limit: min(limit, Constants.spellCompletionLimit)
        )
    }

    /// Returns the display-capitalised automatic candidate for the current visible
    /// presentation, or nil when Space should preserve the literal buffer.
    func defaultSpacePrediction() -> String? {
        guard CandidateWindow.shared.isVisible,
              let snapshot = state.predictionSnapshot,
              snapshot.buffer == state.compositionBuffer,
              case let .prediction(index) = snapshot.defaultSpaceAction,
              snapshot.predictions.indices.contains(index)
        else {
            return nil
        }

        return typingRules.preserveCapitalization(
            original: snapshot.buffer,
            suggested: snapshot.predictions[index]
        )
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
