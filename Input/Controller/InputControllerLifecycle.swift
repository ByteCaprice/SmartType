@preconcurrency import AppKit
@preconcurrency import InputMethodKit
import os

/// IMKInputController activation, deactivation, and composition lifecycle.
extension InputController {
    // MARK: - IMKInputController Overrides

    override func activateServer(_: Any!) {
        MainActor.assumeIsolated {
            resetState()
        }
    }

    override func deactivateServer(_ sender: Any!) {
        let client = sender as? (any IMKTextInput)
        MainActor.assumeIsolated {
            if let client {
                commitCompositionBuffer(client: client)
            }
            CandidateWindow.shared.hide()
        }
    }

    override func composedString(_: Any!) -> Any! {
        MainActor.assumeIsolated { () -> String in
            state.mirrorsClientText ? "" : state.compositionBuffer
        }
    }

    override func originalString(_: Any!) -> NSAttributedString! {
        let string = MainActor.assumeIsolated { () -> String in
            state.mirrorsClientText ? "" : state.compositionBuffer
        }
        return NSAttributedString(string: string)
    }

    override func commitComposition(_ sender: Any!) {
        let client = sender as? (any IMKTextInput)
        MainActor.assumeIsolated {
            Log.inputController.info("commitComposition called by system")
            if let client {
                commitCompositionBuffer(client: client)
            }
        }
    }

    override func cancelComposition() {
        MainActor.assumeIsolated {
            guard let client = client() else {
                resetState()
                return
            }
            commitCompositionBuffer(client: client)
        }
    }

    override func hidePalettes() {
        MainActor.assumeIsolated {
            CandidateWindow.shared.hide()
        }
    }

}
