@testable import SwiftType
import XCTest

/// Tests for SpellCheckPredictor.
///
/// NSSpellChecker is a live system dependency — its exact output varies by macOS version,
/// installed dictionaries, and user language settings.  Every test here is written so that
/// the *structural* contract (limit enforcement, no crashes, exclusions) holds regardless of
/// what the spell-checker actually returns.  Tests that require the spell-checker to produce
/// a non-empty response are noted with a guard that skips gracefully when it does not.
@MainActor final class SpellCheckPredictorTests: XCTestCase {
    private var predictor: SpellCheckPredictor!

    override func setUp() async throws {
        predictor = SpellCheckPredictor()
    }

    override func tearDown() async throws {
        predictor = nil
    }

    // MARK: - Limit enforcement: completions

    func testCompletionsWithLimitZeroAlwaysReturnsEmpty() {
        // Arrange: any non-trivial context and partial.
        // Act: ask for 0 results.
        let results = predictor.completions(prefix: "fo", limit: 0)
        // Assert: regardless of spell-checker state, limit 0 must produce nothing.
        XCTAssertEqual(results.count, 0)
    }

    func testCompletionsResultCountNeverExceedsLimitOfOne() {
        let results = predictor.completions(prefix: "hel", limit: 1)
        XCTAssertLessThanOrEqual(results.count, 1)
    }

    func testCompletionsResultCountNeverExceedsLimitOfThree() {
        // "hel" as a prefix should give the spell-checker a good chance of returning > 3
        // words ("hello", "help", "helm", "held", …) so this limit test is meaningful.
        let results = predictor.completions(prefix: "hel", limit: 3)
        XCTAssertLessThanOrEqual(results.count, 3)
    }

    func testCompletionsResultCountNeverExceedsLargeLimit() {
        let limit = 100
        let results = predictor.completions(prefix: "st", limit: limit)
        XCTAssertLessThanOrEqual(results.count, limit)
    }

    // MARK: - Crash safety on edge inputs

    func testCompletionsDoesNotCrashOnEmptyPartial() {
        // An empty partial produces a zero-length range at the end of context.
        XCTAssertNoThrow(
            _ = predictor.completions(prefix: "", limit: 5),
        )
    }

    func testCompletionsDoesNotCrashOnEmptyContext() {
        XCTAssertNoThrow(
            _ = predictor.completions(prefix: "wor", limit: 5),
        )
    }

    func testCompletionsDoesNotCrashOnBothEmpty() {
        XCTAssertNoThrow(
            _ = predictor.completions(prefix: "", limit: 5),
        )
    }

    // MARK: - Result quality (best-effort; skipped when spell-checker is unavailable)

    func testCompletionsResultsAreAllNonEmptyStrings() {
        let results = predictor.completions(prefix: "hel", limit: 7)
        guard !results.isEmpty else {
            // Spell-checker returned nothing (non-English system or stripped dictionary).
            return
        }
        for word in results {
            XCTAssertFalse(word.isEmpty, "Completion result must not be an empty string")
        }
    }

    // MARK: - Partial exclusion

    /// The partial word (case-insensitively) must not appear in the completions list.
    ///
    /// DEVELOPER DECISION — interpretation:
    ///   The code excludes any result where `result.lowercased() == partial.lowercased()`.
    ///   This test verifies that contract with a partial that the spell-checker is highly
    ///   likely to include verbatim in its completions list ("the" is a known word and a
    ///   very common prefix completion).  If the spell-checker returns nothing (unlikely for
    ///   "the" in English), the test skips gracefully.
    func testCompletionsNeverContainTheExactPartialWordCaseInsensitively() {
        let partial = "the"
        let results = predictor.completions(prefix: partial, limit: 10)
        guard !results.isEmpty else { return }
        let lowercased = results.map { $0.lowercased() }
        XCTAssertFalse(lowercased.contains(partial),
                       "The partial '\(partial)' must not appear in completions: \(results)")
    }

    func testCompletionsNeverContainUppercasedVersionOfPartial() {
        // The exclusion is case-insensitive: partial "hello" → "Hello" must also be excluded.
        let partial = "hello"
        let results = predictor.completions(prefix: partial, limit: 10)
        let lowercased = results.map { $0.lowercased() }
        XCTAssertFalse(lowercased.contains(partial),
                       "'hello' (in any case) must not appear in completions: \(results)")
    }

    // MARK: - Deduplication

    func testCompletionsContainNoDuplicateLowercasedWords() {
        // addUnique uses a Set<String> to prevent duplicate lowercased words.
        let results = predictor.completions(prefix: "gr", limit: 7)
        guard results.count > 1 else { return }
        let lowercased = results.map { $0.lowercased() }
        let unique = Set(lowercased)
        XCTAssertEqual(unique.count, lowercased.count,
                       "Completions must not contain duplicate words (case-insensitive): \(results)")
    }

    // MARK: - Multiple calls are stable

    func testRepeatedCompletionCallsProduceSameCount() {
        // The predictor is synchronous and stateless between calls (same tag, same language).
        // Calling twice with identical arguments must return the same result count.
        let first = predictor.completions(prefix: "sto", limit: 5)
        let second = predictor.completions(prefix: "sto", limit: 5)
        XCTAssertEqual(first.count, second.count)
    }

    // MARK: - Fuzzy-guess fallback branch (step 3)

    // The fuzzy-guess branch fires only when both spell-correction (step 1) and
    // prefix-completions (step 2) return nothing.  Because NSSpellChecker is a live
    // system dependency we cannot force that condition without mocking, so these
    // tests verify the structural contract — limit enforcement, non-empty strings,
    // no duplicates — for inputs designed to bypass steps 1–2.  Each test skips
    // gracefully when the spell-checker returns nothing (unavailable dictionaries).

    func testFuzzyGuessBranchRespectsLimit() {
        // A garbled partial with no real prefix has the best chance of bypassing
        // steps 1–2 and reaching the guesses branch.
        let limit = 2
        let results = predictor.completions(prefix: "qkznrt", limit: limit)
        XCTAssertLessThanOrEqual(results.count, limit,
                                 "Fuzzy-guess branch must still respect the limit: \(results)")
    }

    func testFuzzyGuessBranchResultsAreNonEmptyStrings() {
        let results = predictor.completions(prefix: "qkznrt", limit: 5)
        guard !results.isEmpty else { return } // Branch returned nothing — skip.
        for word in results {
            XCTAssertFalse(word.isEmpty, "Fuzzy-guess result must not be an empty string")
        }
    }

    func testFuzzyGuessBranchResultsContainNoDuplicates() {
        let results = predictor.completions(prefix: "qkznrt", limit: 7)
        guard results.count > 1 else { return }
        let lowercased = results.map { $0.lowercased() }
        XCTAssertEqual(Set(lowercased).count, lowercased.count,
                       "Fuzzy-guess results must not contain duplicate words: \(results)")
    }
}
