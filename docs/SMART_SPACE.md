# Smart Space

Smart Space defines what Space does when SmartType has prediction evidence. It is implemented with the local macOS spell checker and does not use a network service, language model, or typed-text telemetry.

## User-visible contract

- A complete word with exact completion evidence remains literal: `the` + Space → `the `.
- A strict prefix may accept the visible default completion: `appl` may become `apply ` when `apply` is shown as the Space target.
- A misspelling may accept a visible correction when no strict prefix wins: `convinient` may become `convenient `.
- Uncertain, protected, stale, hidden, or unverifiable results fall back to literal text.
- An explicitly selected candidate always takes priority.
- Return preserves the original letters when there is no explicit selection; mode-specific host Return behavior remains unchanged.
- Every Space word commit adds one trailing space. Existing punctuation logic may replace only that tracked automatic space.

macOS dictionary contents, ranking, learned words, locale behavior, and OS versions can change the candidates. SmartType guarantees consistency between the visible Space target and the committed result, not a universal word ranking.

## Evidence and ranking

`SpellCheckPredictor` gathers:

- exact case-insensitive membership in raw completions;
- strict prefix completions in provider order;
- an optional correction;
- fuzzy guesses;
- learned-word evidence and token-shape protection.

The product policy is:

1. Preserve protected token shapes and learned words.
2. Preserve the literal when exact completion evidence exists.
3. Otherwise use the first eligible strict prefix completion.
4. Otherwise use a correction when spelling is flagged.
5. Otherwise preserve the literal; fuzzy guesses remain explicit alternatives.

Alternatives are deduplicated case-insensitively, ranked by category, and capped only after evidence classification. Exact evidence remains available even when the exact word would fall beyond the visible candidate limit.

This is a completion-oriented heuristic, not proof of user intent. For example, an accepted abbreviation can still look like a prefix, while a typo can have an obscure strict completion. Do not introduce hard-coded words or claim perfect intent detection.

## Snapshot and freshness model

A `PredictionSnapshot` binds these values together:

- the composition buffer;
- ranked alternatives;
- `DefaultSpaceAction`;
- `DefaultSpaceReason`.

SmartType publishes the snapshot and candidate UI together on the main actor. Space accepts an automatic candidate only when:

- the snapshot still matches the current buffer;
- the candidate is visible and its index remains valid;
- no newer generation invalidated the result;
- transparent-mode client/cursor/document checks still pass.

Prediction cancellation clears both candidates and snapshot state. Space pressed before transparent prediction debounce completes remains literal; hidden or late results are never accepted retroactively.

## Default action versus explicit selection

The panel begins with no explicit selection.

- A native spacebar symbol marks the current automatic candidate.
- `✓ Exact match` indicates positive evidence for preserving the typed word.
- `✓ Keep typed` indicates a conservative literal fallback.
- Arrow or Tab navigation creates an explicit selection and moves the Space marker.
- Default presentation does not change `selectedCandidate()` or accessibility selected state.

This separation preserves Return and first-navigation behavior. Do not implement Smart Space by automatically selecting row 1.

## Mode-specific commits

### Inline

Space commits the explicit selection, fresh default candidate, or literal buffer, followed by one space. Return commits the explicit selection or original buffer without a trailing space.

### Transparent prediction

The typed letters already exist in the host document:

- Strict completion can insert only a verified suffix.
- Correction or case change requires a verified replacement range.
- Failed verification discards prediction state and produces literal Space behavior.
- No operation may insert the entire mirrored token a second time.
- Return without explicit selection discards the mirror and passes through to the host; in chat or search fields this may submit.

### Direct input and passthrough

Direct-input clients do not show candidates. Passthrough clients leave input entirely host-owned.

## Safe maintenance

When changing Smart Space:

- Keep evidence collection injectable so policy tests remain deterministic.
- Never mutate the user's spell-check dictionary to satisfy tests.
- Do not synchronously fetch an unseen candidate on Space.
- Keep inline and transparent insertion mechanics separate even when they share policy intent.
- Preserve number shortcuts, explicit navigation, Return, Caps Lock, punctuation, and stale-state behavior.
- Verify candidate indicators and accessibility labels match the actual commit.

See [Testing](TESTING.md) for required deterministic and real-client coverage.

## References and historical research

- [Apple: NSSpellChecker](https://developer.apple.com/documentation/appkit/nsspellchecker)
- [Apple: completions](https://developer.apple.com/documentation/appkit/nsspellchecker/completions(forpartialwordrange:in:language:inspelldocumentwithtag:))
- [Apple: correction](https://developer.apple.com/documentation/appkit/nsspellchecker/correction(forwordrange:in:language:inspelldocumentwithtag:))
- [Apple: guesses](https://developer.apple.com/documentation/appkit/nsspellchecker/guesses(forwordrange:in:language:inspelldocumentwithtag:))
- [Original research and implementation plan](archive/SMART_SPACE_RESEARCH_2026-09.md)
