import InputMethodKit
import os

/// State reset and prediction cancellation.
extension InputController {
    // MARK: - State Management

    func resetState() {
        cancelPredictions()
        state.reset()
    }

    func cancelPredictions() {
        pendingTransparentPredictionUpdate?.cancel()
        pendingTransparentPredictionUpdate = nil
        state.currentPredictions = []
        CandidateWindow.shared.hide()
    }
}
