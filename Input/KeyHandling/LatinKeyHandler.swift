import AppKit
import InputMethodKit

/// English candidate selection and trailing-space behavior.
@MainActor struct LatinKeyHandler {
    func handleCandidateSelection(
        predictionIndex: Int,
        controller: InputController,
        client: any IMKTextInput,
    ) {
        controller.selectCandidateByIndex(predictionIndex, client: client)
    }

    func handleSpace(
        controller: InputController,
        client: any IMKTextInput,
    ) -> Bool {
        let state = controller.state

        if CandidateWindow.shared.isVisible,
           let selected = CandidateWindow.shared.selectedCandidate()
        {
            controller.commitWord(selected, client: client)
            return true
        }

        guard !state.compositionBuffer.isEmpty else {
            return false
        }

        controller.commitWord(state.compositionBuffer, client: client)
        return true
    }

    func handleReturn(
        controller: InputController,
        client: any IMKTextInput,
    ) -> Bool {
        guard CandidateWindow.shared.isVisible else {
            if !controller.state.compositionBuffer.isEmpty {
                controller.commitCompositionBuffer(client: client)
            }
            return false
        }

        let word = CandidateWindow.shared.selectedCandidate()
            ?? controller.state.compositionBuffer
        if !word.isEmpty {
            controller.commitWord(word, trailingSpace: false, client: client)
        }
        return true
    }
}
