@preconcurrency import AppKit
@preconcurrency import InputMethodKit
import os

/// Key routing and shared key handlers. Language-specific behaviour is delegated
/// to the active `keyHandler` (see `LatinKeyHandler`).
extension InputController {
    // MARK: - Key Routing

    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask.keyDown.union(.flagsChanged).rawValue)
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event else { return false }

        // Caps Lock and dedicated language keys arrive as flags-changed events.
        // Some web-based clients defer the source switch while marked text is active,
        // so commit first and still leave the event to macOS.
        if event.type == .flagsChanged, event.keyCode == 0x39,
           let client = sender as? (any IMKTextInput)
        {
            Log.inputController.info("Caps Lock event received")
            MainActor.assumeIsolated {
                if state.mirrorsClientText
                    || Self.usesTransparentPrediction(bundleIdentifier: client.bundleIdentifier())
                {
                    discardMirroredComposition()
                } else if !state.compositionBuffer.isEmpty {
                    Log.inputController.info("Committing composition before language switch")
                    commitCompositionForLanguageSwitch(client: client)
                }
            }
            return false
        }

        // Leave other modifier changes to macOS.
        guard event.type == .keyDown else { return false }
        guard let client = sender as? (any IMKTextInput) else {
            Log.inputController.error("Input client has an unexpected type")
            return false
        }
        let keyCode = event.keyCode
        let modifierFlags = event.modifierFlags.rawValue
        let characters = event.characters

        return MainActor.assumeIsolated {
            PerformanceTrace.measure("Key handling") {
                handleKey(
                    keyCode: keyCode,
                    modifierFlags: NSEvent.ModifierFlags(rawValue: modifierFlags),
                    characters: characters,
                    client: client,
                )
            }
        }
    }

    private func handleKey(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        characters: String?,
        client: any IMKTextInput,
    ) -> Bool {
        // Terminal line editors and raw-mode TUIs need every key unchanged. IMK cannot
        // distinguish a shell prompt from programs running inside the same terminal.
        switch InputClientPolicy.mode(forBundleIdentifier: client.bundleIdentifier()) {
        case .passthrough:
            return false
        case .transparentPrediction:
            return handleTransparentPredictionKey(
                keyCode: keyCode,
                modifierFlags: modifierFlags,
                characters: characters,
                client: client,
            )
        case .inline:
            break
        }

        let key = KeyCode(rawValue: keyCode)
        let modifiers = modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Pass through modifier key combinations (Cmd, Ctrl, Option)
        if !modifiers.isDisjoint(with: Self.modifierMask) {
            commitCompositionBuffer(client: client)
            return false
        }

        switch key {
        case .key1, .key2, .key3, .key4, .key5, .key6, .key7:
            if let key, handleCandidateKey(key, modifiers: modifiers, client: client) { return true }

        case .backspace:
            return handleBackspace(client: client)

        case .space:
            return keyHandler.handleSpace(controller: self, client: client)

        case .returnKey:
            return keyHandler.handleReturn(controller: self, client: client)

        case .escape:
            let hadContent = !state.compositionBuffer.isEmpty
                || CandidateWindow.shared.isVisible
            commitCompositionBuffer(client: client)
            return hadContent

        case .downArrow:
            return handleNavigation(client: client) {
                CandidateWindow.shared.moveActiveRowDown()
            }

        case .upArrow:
            return handleNavigation(client: client) {
                CandidateWindow.shared.moveActiveRowUp()
            }

        case .tab, .rightArrow:
            return handleNavigation(client: client) {
                CandidateWindow.shared.moveActiveColumnRight()
            }

        case .leftArrow:
            return handleNavigation(client: client) {
                CandidateWindow.shared.moveActiveColumnLeft()
            }

        default:
            break
        }

        return handleCharacterInput(characters, client: client)
    }

    // MARK: - Key Handlers

    /// Executes `action` when the candidate window is visible; otherwise commits the buffer
    /// and passes through. Shared by all arrow/tab navigation keys.
    private func handleNavigation(client: any IMKTextInput, action: () -> Void) -> Bool {
        if CandidateWindow.shared.isVisible {
            action()
            return true
        }
        commitCompositionBuffer(client: client)
        return false
    }

    private func handleCandidateKey(
        _ key: KeyCode,
        modifiers: NSEvent.ModifierFlags,
        client: any IMKTextInput,
    ) -> Bool {
        guard CandidateWindow.shared.isVisible, !modifiers.contains(.shift) else { return false }
        guard let slotIndex = KeyCode.candidateKeys.firstIndex(of: key) else { return false }

        // `slotIndex` is the 0-based column of the active grid row.
        if CandidateWindow.shared.isLiteralAt(gridColumn: slotIndex) {
            commitWord(state.compositionBuffer, client: client)
            return true
        }
        if let predIdx = CandidateWindow.shared.predictionIndexAt(gridColumn: slotIndex),
           predIdx < state.currentPredictions.count
        {
            keyHandler.handleCandidateSelection(
                predictionIndex: predIdx,
                controller: self,
                client: client,
            )
            return true
        }

        // Empty cells are not candidate shortcuts. End the composition and let the
        // client receive the digit normally.
        commitCompositionBuffer(client: client)
        return false
    }

    private func handleCharacterInput(_ characters: String?, client: any IMKTextInput) -> Bool {
        guard let characters, characters.count == 1, let char = characters.first else {
            if characters != nil, !state.compositionBuffer.isEmpty {
                commitCompositionBuffer(client: client)
            }
            return false
        }

        if char.isLetter {
            clearAutoInsertedTrailingSpace()
            state.compositionBuffer.append(char)
            updateMarkedText(client: client)
            updatePredictions(client: client)
            return true
        }

        // Continue composing when an apostrophe follows word characters — this keeps
        // contractions like "don't" and "I'm" in a single composition buffer rather than
        // splitting at the apostrophe.
        if typingRules.compositionContinuationMarks.contains(char), !state.compositionBuffer.isEmpty {
            state.compositionBuffer.append(char)
            updateMarkedText(client: client)
            updatePredictions(client: client)
            return true
        }

        if !state.compositionBuffer.isEmpty {
            commitCompositionBuffer(client: client)
        }

        cancelPredictions()

        if typingRules.autoRemoveSpaceChars.contains(char) {
            return handleAutoSpacePunctuation(char, client: client)
        }

        return false
    }

    private func handleAutoSpacePunctuation(_ char: Character, client: any IMKTextInput) -> Bool {
        let charStr = String(char)

        if state.didAutoInsertTrailingSpace {
            if let replacementRange = autoInsertedSpaceRange(client: client) {
                client.insertText(charStr, replacementRange: replacementRange)
                clearAutoInsertedTrailingSpace()
                return true
            }
        }

        client.insertText(charStr, replacementRange: Constants.replacementNotFound)
        clearAutoInsertedTrailingSpace()
        return true
    }

    /// Returns the range of the auto-inserted trailing space preceding the cursor, or `nil` if not found.
    func autoInsertedSpaceRange(client: any IMKTextInput) -> NSRange? {
        let selection = client.selectedRange()
        guard state.autoInsertedSpaceClientBundleID == client.bundleIdentifier(),
              let expectedCursor = state.autoInsertedSpaceExpectedCursor,
              selection.location == expectedCursor,
              selection.length == 0,
              expectedCursor > 0
        else {
            return nil
        }

        let range = NSRange(location: expectedCursor - 1, length: 1)
        let precedingChar = client.attributedSubstring(from: range)?.string ?? ""
        guard precedingChar == " " else { return nil }

        return range
    }

    func recordAutoInsertedTrailingSpace(
        client: any IMKTextInput,
        expectedCursor: Int? = nil,
    ) {
        let selection = client.selectedRange()
        state.didAutoInsertTrailingSpace = true
        state.autoInsertedSpaceClientBundleID = client.bundleIdentifier()
        state.autoInsertedSpaceExpectedCursor = expectedCursor
            ?? (selection.location == NSNotFound ? nil : selection.location)
    }

    func clearAutoInsertedTrailingSpace() {
        state.didAutoInsertTrailingSpace = false
        state.autoInsertedSpaceClientBundleID = nil
        state.autoInsertedSpaceExpectedCursor = nil
    }

    private func handleBackspace(client: any IMKTextInput) -> Bool {
        guard !state.compositionBuffer.isEmpty else { return false }

        state.compositionBuffer.removeLast()

        if state.compositionBuffer.isEmpty {
            // Buffer empty — clear marked text and cancel predictions.
            commitCompositionBuffer(client: client)
        } else {
            updateMarkedText(client: client)
            updatePredictions(client: client)
        }

        return true
    }
}
