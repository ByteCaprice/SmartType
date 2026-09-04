/// English punctuation and capitalization rules.
struct EnglishTypingRules: Sendable {
    static let shared = EnglishTypingRules()

    /// Punctuation that removes an auto-inserted trailing space when typed immediately
    /// after a committed word. Includes closing brackets/quotes and common sentence
    /// punctuation. Note: U+2019 (') is also in `compositionContinuationMarks`; the
    /// contraction check in `handleCharacterInput` runs first, so a mid-word apostrophe
    /// never reaches the auto-space-removal path.
    let autoRemoveSpaceChars: Set<Character> = [
        ".", ",", "!", "?", ":", ";", ")", "]", "}", "%",
        "\u{201D}", "\u{2019}", "\u{00BB}", "\u{2026}",
    ]

    /// Characters that extend the composition buffer mid-word. U+0027 (') covers
    /// straight-apostrophe contractions ("don't"); U+2019 (') covers smart-quote
    /// contractions typed by macOS's auto-substitution.
    let compositionContinuationMarks: Set<Character> = ["'", "\u{2019}"]

    func preserveCapitalization(original: String, suggested: String) -> String {
        guard let firstChar = original.first, firstChar.isUppercase else { return suggested }
        return suggested.prefix(1).uppercased() + suggested.dropFirst()
    }
}
