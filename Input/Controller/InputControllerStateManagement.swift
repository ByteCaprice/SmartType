import InputMethodKit
import os

/// State reset and prediction cancellation.
extension InputController {
    // MARK: - State Management

    func resetState() {
        state.reset()
        CandidateWindow.shared.hide()
    }

    func cancelPredictions() {
        state.currentPredictions = []
        CandidateWindow.shared.hide()
    }
}
