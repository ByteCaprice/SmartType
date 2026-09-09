import AppKit
import Carbon.HIToolbox
import InputMethodKit

/// Chromium/CEF clients ignore IMK `handle()` return values unless marked text is
/// active or a multi-character `insertText` happens in the same keyDown. Keeping
/// marked text blocks Caps Lock language switching, so these apps get a mirrored
/// prediction buffer: each printable key is inserted without marked text, while
/// completion suffixes are inserted when the user selects a candidate.
extension InputController {
    func handleTransparentPredictionKey(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        characters: String?,
        client: any IMKTextInput,
    ) -> Bool {
        if !state.compositionBuffer.isEmpty, isMirroredCompositionStale(client: client) {
            discardMirroredComposition()
        }

        let key = KeyCode(rawValue: keyCode)
        let modifiers = modifierFlags.intersection(.deviceIndependentFlagsMask)

        if !modifiers.isDisjoint(with: Self.modifierMask) {
            discardMirroredComposition()
            return false
        }

        switch key {
        case .key1, .key2, .key3, .key4, .key5, .key6, .key7:
            if let key, handleTransparentCandidateKey(key, modifiers: modifiers, client: client) {
                return true
            }

        case .backspace:
            return handleTransparentBackspace(client: client)

        case .space:
            return handleTransparentSpace(client: client)

        case .returnKey:
            return handleTransparentReturn(client: client)

        case .escape, .downArrow, .upArrow, .tab, .rightArrow, .leftArrow:
            discardMirroredComposition()
            return false

        default:
            break
        }

        return handleTransparentCharacterInput(characters, client: client)
    }

    func selectTransparentCandidateByIndex(_ index: Int, client: any IMKTextInput) {
        guard state.currentPredictions.indices.contains(index) else { return }
        let prediction = state.currentPredictions[index]
        let word = typingRules.preserveCapitalization(
            original: state.compositionBuffer,
            suggested: prediction
        )
        _ = commitTransparentWord(word, trailingSpace: true, client: client)
    }

    func discardMirroredComposition() {
        state.compositionBuffer = ""
        state.mirrorsClientText = false
        state.compositionBaseline = nil
        state.expectedCursor = nil
        state.compositionClientBundleID = nil
        cancelPredictions()
    }

    private func handleTransparentCandidateKey(
        _ key: KeyCode,
        modifiers: NSEvent.ModifierFlags,
        client: any IMKTextInput,
    ) -> Bool {
        guard CandidateWindow.shared.isVisible, !modifiers.contains(.shift) else { return false }
        guard let slotIndex = KeyCode.candidateKeys.firstIndex(of: key) else { return false }

        if CandidateWindow.shared.isLiteralAt(gridColumn: slotIndex) {
            return commitTransparentWord(state.compositionBuffer, trailingSpace: true, client: client)
        }
        guard let predIdx = CandidateWindow.shared.predictionIndexAt(gridColumn: slotIndex),
              predIdx < state.currentPredictions.count
        else {
            return false
        }

        let prediction = state.currentPredictions[predIdx]
        let word = typingRules.preserveCapitalization(
            original: state.compositionBuffer,
            suggested: prediction,
        )
        return commitTransparentWord(word, trailingSpace: true, client: client)
    }

    private func handleTransparentSpace(client: any IMKTextInput) -> Bool {
        // Capture fallback bookkeeping before attempting a candidate commit because a
        // failed verified replacement deliberately discards the mirrored composition.
        let hadComposition = !state.compositionBuffer.isEmpty
        let expectedSpaceCursor = state.expectedCursor.map { $0 + 1 }

        if CandidateWindow.shared.isVisible,
           let selected = CandidateWindow.shared.selectedCandidate(),
           commitTransparentWord(selected, trailingSpace: true, client: client)
        {
            return true
        }

        if let prediction = defaultSpacePrediction(),
           commitTransparentWord(prediction, trailingSpace: true, client: client)
        {
            return true
        }

        discardMirroredComposition()
        client.insertText(" ", replacementRange: Constants.replacementNotFound)
        if hadComposition {
            recordAutoInsertedTrailingSpace(client: client, expectedCursor: expectedSpaceCursor)
        } else {
            clearAutoInsertedTrailingSpace()
        }
        return true
    }

    private func handleTransparentReturn(client: any IMKTextInput) -> Bool {
        guard CandidateWindow.shared.isVisible else {
            if !state.compositionBuffer.isEmpty {
                discardMirroredComposition()
            }
            return false
        }

        if let selected = CandidateWindow.shared.selectedCandidate() {
            return commitTransparentWord(selected, trailingSpace: false, client: client)
        }

        discardMirroredComposition()
        return false
    }

    private func handleTransparentBackspace(client: any IMKTextInput) -> Bool {
        guard !state.compositionBuffer.isEmpty else { return false }

        let removed = String(state.compositionBuffer.removeLast())
        if let expectedCursor = state.expectedCursor {
            state.expectedCursor = max(0, expectedCursor - (removed as NSString).length)
        }

        if state.compositionBuffer.isEmpty {
            discardMirroredComposition()
        } else {
            scheduleTransparentPredictionUpdate(client: client)
        }
        return false
    }

    private func handleTransparentCharacterInput(
        _ characters: String?,
        client: any IMKTextInput,
    ) -> Bool {
        guard let characters, characters.count == 1, let char = characters.first else {
            if characters != nil {
                discardMirroredComposition()
            }
            return false
        }

        if char.isLetter {
            appendMirroredCharacter(char, client: client)
            client.insertText(String(char), replacementRange: Constants.replacementNotFound)
            scheduleTransparentPredictionUpdate(client: client)
            return true
        }

        if typingRules.compositionContinuationMarks.contains(char), !state.compositionBuffer.isEmpty {
            appendMirroredCharacter(char, client: client)
            client.insertText(String(char), replacementRange: Constants.replacementNotFound)
            scheduleTransparentPredictionUpdate(client: client)
            return true
        }

        if typingRules.autoRemoveSpaceChars.contains(char), state.didAutoInsertTrailingSpace {
            return handleTransparentAutoSpacePunctuation(char, client: client)
        }

        discardMirroredComposition()
        guard char.isNumber || char.isPunctuation || char.isSymbol else { return false }
        client.insertText(String(char), replacementRange: Constants.replacementNotFound)
        return true
    }

    private func appendMirroredCharacter(_ char: Character, client: any IMKTextInput) {
        if state.compositionBuffer.isEmpty {
            let selection = client.selectedRange()
            state.mirrorsClientText = true
            state.compositionClientBundleID = client.bundleIdentifier()
            if selection.location == NSNotFound {
                state.compositionBaseline = nil
                state.expectedCursor = nil
            } else {
                state.compositionBaseline = NSRange(location: selection.location, length: 0)
                state.expectedCursor = selection.location
            }
        }

        clearAutoInsertedTrailingSpace()
        state.compositionBuffer.append(char)
        if let expectedCursor = state.expectedCursor {
            state.expectedCursor = expectedCursor + (String(char) as NSString).length
        }
    }

    private func isMirroredCompositionStale(client: any IMKTextInput) -> Bool {
        if client.bundleIdentifier() != state.compositionClientBundleID {
            return true
        }
        let selection = client.selectedRange()
        if selection.location == NSNotFound {
            return false
        }
        if selection.length > 0 {
            return true
        }
        if let expectedCursor = state.expectedCursor, selection.location != expectedCursor {
            return true
        }
        return false
    }

    private func scheduleTransparentPredictionUpdate(client: any IMKTextInput) {
        cancelPredictions()
        let buffer = state.compositionBuffer
        let generation = transparentPredictionGeneration
        pendingTransparentPredictionUpdate = Task { @MainActor [weak self] in
            do {
                try await self?.waitForTransparentPredictionDebounce()
            } catch {
                return
            }
            guard let self,
                  !Task.isCancelled,
                  self.transparentPredictionGeneration == generation,
                  self.state.mirrorsClientText,
                  self.state.compositionBuffer == buffer
            else {
                return
            }
            guard !self.isMirroredCompositionStale(client: client) else {
                self.discardMirroredComposition()
                return
            }
            self.pendingTransparentPredictionUpdate = nil
            self.updatePredictions(client: client)
        }
    }

    private func handleTransparentAutoSpacePunctuation(
        _ char: Character,
        client: any IMKTextInput,
    ) -> Bool {
        guard let replacementRange = autoInsertedSpaceRange(client: client) else {
            clearAutoInsertedTrailingSpace()
            client.insertText(String(char), replacementRange: Constants.replacementNotFound)
            return true
        }

        primeAndCommit(String(char), replacing: replacementRange, client: client)
        clearAutoInsertedTrailingSpace()
        return true
    }

    private func commitTransparentWord(
        _ word: String,
        trailingSpace: Bool,
        client: any IMKTextInput,
    ) -> Bool {
        let committed = trailingSpace ? word + " " : word
        let buffer = state.compositionBuffer
        let suffix = Self.transparentSuffix(of: word, after: buffer, trailingSpace: trailingSpace)
        var expectedCursor: Int?

        if let suffix, (suffix as NSString).length > 1 {
            client.insertText(suffix, replacementRange: Constants.replacementNotFound)
            expectedCursor = state.expectedCursor.map { $0 + (suffix as NSString).length }
        } else if let typedRegion = verifiedTypedRegion(client: client, buffer: buffer) {
            primeAndCommit(committed, replacing: typedRegion, client: client)
            expectedCursor = typedRegion.location + (committed as NSString).length
        } else {
            discardMirroredComposition()
            clearAutoInsertedTrailingSpace()
            return false
        }

        discardMirroredComposition()
        if trailingSpace {
            recordAutoInsertedTrailingSpace(client: client, expectedCursor: expectedCursor)
        } else {
            clearAutoInsertedTrailingSpace()
        }
        return true
    }

    private func verifiedTypedRegion(client: any IMKTextInput, buffer: String) -> NSRange? {
        guard client.supportsProperty(TSMDocumentPropertyTag(kTSMDocumentSupportDocumentAccessPropertyTag)),
              let baseline = state.compositionBaseline,
              baseline.location != NSNotFound
        else {
            return nil
        }

        let range = NSRange(location: baseline.location, length: (buffer as NSString).length)
        guard let substring = client.attributedSubstring(from: range)?.string else {
            return nil
        }
        guard substring.compare(buffer, options: .caseInsensitive) == .orderedSame else {
            return nil
        }
        return range
    }

    private func primeAndCommit(
        _ text: String,
        replacing range: NSRange,
        client: any IMKTextInput,
    ) {
        let attrString = NSAttributedString(string: text, attributes: Self.markedTextAttributes)
        client.setMarkedText(
            attrString,
            selectionRange: NSRange(location: (text as NSString).length, length: 0),
            replacementRange: range,
        )
        client.insertText(text, replacementRange: Constants.replacementNotFound)
    }

    private static func transparentSuffix(
        of word: String,
        after buffer: String,
        trailingSpace: Bool,
    ) -> String? {
        guard word.hasPrefix(buffer) else { return nil }
        return String(word.dropFirst(buffer.count)) + (trailingSpace ? " " : "")
    }
}
