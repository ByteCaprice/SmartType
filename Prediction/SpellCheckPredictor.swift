import AppKit

@MainActor final class SpellCheckPredictor {
    private static let language = "en_US"
    private let spellChecker = NSSpellChecker.shared
    private nonisolated let tag: Int

    init() {
        tag = NSSpellChecker.uniqueSpellDocumentTag()
    }

    deinit {
        NSSpellChecker.shared.closeSpellDocument(withTag: tag)
    }

    /// Returns up to `limit` English spelling corrections and completions for `prefix`.
    func completions(prefix: String, limit: Int) -> [String] {
        guard limit > 0, !prefix.isEmpty else { return [] }

        let prefixLength = (prefix as NSString).length
        let prefixRange = NSRange(location: 0, length: prefixLength)
        let lowercasedPrefix = prefix.lowercased()
        var results: [String] = []
        var seen = Set<String>()

        // 1. Spell correction — if the prefix is misspelled, offer the fix first
        let correction = spellChecker.correction(
            forWordRange: prefixRange,
            in: prefix,
            language: Self.language,
            inSpellDocumentWithTag: tag,
        )
        if let correction, correction.lowercased() != lowercasedPrefix {
            results.append(correction)
            seen.insert(correction.lowercased())
        }

        // 2. Prefix completions from the system dictionary
        if results.count < limit {
            let completions = spellChecker.completions(
                forPartialWordRange: prefixRange,
                in: prefix,
                language: Self.language,
                inSpellDocumentWithTag: tag,
            )
            if let completions {
                addUnique(from: completions, to: &results, seen: &seen, excluding: lowercasedPrefix, limit: limit)
            }
        }

        // 3. Fuzzy guesses — fill remaining slots (handles typos like "helo")
        if results.count < limit {
            let guesses = spellChecker.guesses(
                forWordRange: prefixRange,
                in: prefix,
                language: Self.language,
                inSpellDocumentWithTag: tag,
            )
            if let guesses {
                addUnique(from: guesses, to: &results, seen: &seen, excluding: lowercasedPrefix, limit: limit)
            }
        }

        return results
    }

    private func addUnique(from words: [String], to results: inout [String], seen: inout Set<String>, excluding lowercasedPrefix: String, limit: Int) {
        for word in words {
            guard results.count < limit else { break }
            let lower = word.lowercased()
            if lower != lowercasedPrefix, seen.insert(lower).inserted {
                results.append(word)
            }
        }
    }
}
