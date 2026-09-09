import AppKit

/// The action Space performs when no candidate has been explicitly selected.
enum DefaultSpaceAction: Equatable, Sendable {
    case literal
    case prediction(index: Int)
}

/// Why the Smart Space policy chose its default action.
enum DefaultSpaceReason: Equatable, Sendable {
    case protectedLiteral
    case exactCompletion
    case prefixCompletion
    case correction
    case fallbackLiteral
}

/// Raw, ordered evidence returned by the spell-checking provider.
struct SpellCheckEvidence: Equatable, Sendable {
    var completions: [String]
    var correction: String?
    var guesses: [String]
    var isLearnedWord: Bool
    var isIgnoredWord: Bool
}

/// Ranked alternatives and the default Space action for one composition buffer.
struct PredictionResult: Equatable, Sendable {
    var predictions: [String]
    var defaultSpaceAction: DefaultSpaceAction
    var reason: DefaultSpaceReason
}

@MainActor protocol PredictionProviding: AnyObject {
    func predictionResult(prefix: String, limit: Int) -> PredictionResult
}

/// Pure ranking policy kept separate from the live NSSpellChecker dependency.
enum SmartSpacePolicy {
    static func rank(prefix: String, evidence: SpellCheckEvidence, limit: Int) -> PredictionResult {
        guard !prefix.isEmpty, limit > 0 else {
            return PredictionResult(predictions: [], defaultSpaceAction: .literal, reason: .fallbackLiteral)
        }

        let lowercasedPrefix = prefix.lowercased()
        let hasExactCompletion = evidence.completions.contains {
            $0.lowercased() == lowercasedPrefix
        }
        let isProtected = evidence.isLearnedWord
            || evidence.isIgnoredWord
            || !isAutomaticCompletionToken(prefix)

        var predictions: [String] = []
        var seen = Set<String>()

        func add(_ word: String) {
            guard predictions.count < limit, !word.isEmpty else { return }
            let lowercasedWord = word.lowercased()
            guard lowercasedWord != lowercasedPrefix, seen.insert(lowercasedWord).inserted else { return }
            predictions.append(word)
        }

        let prefixCompletions = evidence.completions.filter {
            let candidate = $0.lowercased()
            return candidate != lowercasedPrefix && candidate.hasPrefix(lowercasedPrefix)
        }
        for completion in prefixCompletions {
            add(completion)
        }

        if let correction = evidence.correction {
            add(correction)
        }
        for guess in evidence.guesses {
            add(guess)
        }

        if isProtected {
            return PredictionResult(
                predictions: predictions,
                defaultSpaceAction: .literal,
                reason: .protectedLiteral
            )
        }
        if hasExactCompletion {
            return PredictionResult(
                predictions: predictions,
                defaultSpaceAction: .literal,
                reason: .exactCompletion
            )
        }
        if !prefixCompletions.isEmpty,
           let index = predictions.firstIndex(where: {
               $0.lowercased() == prefixCompletions[0].lowercased()
           })
        {
            return PredictionResult(
                predictions: predictions,
                defaultSpaceAction: .prediction(index: index),
                reason: .prefixCompletion
            )
        }
        if let correction = evidence.correction,
           let index = predictions.firstIndex(where: {
               $0.lowercased() == correction.lowercased()
           })
        {
            return PredictionResult(
                predictions: predictions,
                defaultSpaceAction: .prediction(index: index),
                reason: .correction
            )
        }
        return PredictionResult(
            predictions: predictions,
            defaultSpaceAction: .literal,
            reason: .fallbackLiteral
        )
    }

    /// V1 applies automatic completion only to ordinary ASCII English words and
    /// contractions. Acronyms, identifiers, non-Latin text, and dangling apostrophes
    /// remain literal unless the user explicitly chooses a candidate.
    static func isAutomaticCompletionToken(_ token: String) -> Bool {
        guard !token.isEmpty else { return false }

        let apostrophes: Set<Unicode.Scalar> = ["'", "\u{2019}"]
        let scalars = Array(token.unicodeScalars)
        guard scalars.indices.allSatisfy({ index in
            let scalar = scalars[index]
            let value = scalar.value
            let isASCIILetter = (65 ... 90).contains(value) || (97 ... 122).contains(value)
            if isASCIILetter { return true }
            guard apostrophes.contains(scalar), index > 0, index < scalars.count - 1 else {
                return false
            }
            return !apostrophes.contains(scalars[index - 1])
        }) else {
            return false
        }

        let letters = scalars.filter { !apostrophes.contains($0) }
        guard !letters.isEmpty else { return false }
        let uppercaseIndices = letters.indices.filter { letters[$0].properties.isUppercase }
        return uppercaseIndices.isEmpty || uppercaseIndices == [letters.startIndex]
    }
}

@MainActor final class SpellCheckPredictor: PredictionProviding {
    private static let language = "en_US"
    private let spellChecker = NSSpellChecker.shared
    private nonisolated let tag: Int

    init() {
        tag = NSSpellChecker.uniqueSpellDocumentTag()
    }

    deinit {
        NSSpellChecker.shared.closeSpellDocument(withTag: tag)
    }

    func predictionResult(prefix: String, limit: Int) -> PredictionResult {
        guard limit > 0, !prefix.isEmpty else {
            return SmartSpacePolicy.rank(
                prefix: prefix,
                evidence: SpellCheckEvidence(
                    completions: [], correction: nil, guesses: [],
                    isLearnedWord: false, isIgnoredWord: false
                ),
                limit: limit
            )
        }

        let prefixRange = NSRange(location: 0, length: (prefix as NSString).length)
        let correction = PerformanceTrace.measure("Spell correction") {
            spellChecker.correction(
                forWordRange: prefixRange,
                in: prefix,
                language: Self.language,
                inSpellDocumentWithTag: tag,
            )
        }
        let completions = PerformanceTrace.measure("Spell completions") {
            spellChecker.completions(
                forPartialWordRange: prefixRange,
                in: prefix,
                language: Self.language,
                inSpellDocumentWithTag: tag,
            ) ?? []
        }
        let isLearnedWord = spellChecker.hasLearnedWord(prefix)
        let ignoredWords = spellChecker.ignoredWords(inSpellDocumentWithTag: tag) ?? []
        let isIgnoredWord = ignoredWords.contains {
            $0.compare(prefix, options: .caseInsensitive) == .orderedSame
        }

        var evidence = SpellCheckEvidence(
            completions: completions,
            correction: correction,
            guesses: [],
            isLearnedWord: isLearnedWord,
            isIgnoredWord: isIgnoredWord
        )
        var result = SmartSpacePolicy.rank(prefix: prefix, evidence: evidence, limit: limit)

        if result.predictions.count < limit {
            evidence.guesses = PerformanceTrace.measure("Spell guesses") {
                spellChecker.guesses(
                    forWordRange: prefixRange,
                    in: prefix,
                    language: Self.language,
                    inSpellDocumentWithTag: tag,
                ) ?? []
            }
            result = SmartSpacePolicy.rank(prefix: prefix, evidence: evidence, limit: limit)
        }
        return result
    }

    /// Compatibility accessor for callers that only need ranked alternatives.
    func completions(prefix: String, limit: Int) -> [String] {
        predictionResult(prefix: prefix, limit: limit).predictions
    }
}
