# Smart Space: Technical Research and Implementation Guide

> **Archived:** This is the original Smart Space research and implementation plan. Smart Space is now implemented. See the current [`Smart Space design`](../SMART_SPACE.md) and [`testing guide`](../TESTING.md).


Research date: 2026-09-09. Audience: the next implementation agent, including GPT-5.6-sol.

**Status: implemented on the `smart-space` branch and installed for user evaluation on 2026-09-09 as client-compatibility build `20260909100351`; automated verification is recorded below. Real-client validation remains pending.**

## 1. Product requirement

The user wants to finish English words with Space instead of reaching for a number key:

| Current input | Desired Space result |
| --- | --- |
| `the` | `the `, not `they ` |
| `but` | `but `, not `butter ` |
| `app` | `app ` |
| `appl` | `apply ` when that is the displayed default completion |
| `appli` | `application ` when that is the displayed default completion |
| `coord` | `coordinate ` when that is the displayed default completion |
| `convinient` | `convenient ` when a correction is available |

All Space commits above include **one trailing space**, consistent with current candidate commits. Space with an empty composition remains ordinary spacing; it must not suppress intentionally repeated spaces.

The intended interaction is: **finish a complete word literally; complete a prefix; use Return to keep the original letters when the suggestion is unwanted.** The result must follow the current buffer, not a previous prediction generation.

Preserve:

- Explicit arrow/Tab selection: Space accepts the explicitly selected candidate, not always candidate 1.
- Number shortcuts, capitalization rules, and punctuation removal of an automatic trailing space.
- Existing Return and Caps Lock / 中英 behavior; see the important Return nuance in section 7.
- Native/Edge inline, Chrome transparent prediction, WeCom/DingTalk transparent compatibility commits, native Terminal passthrough, and VS Code no-prediction direct input.
- Local processing, existing UI style, nonactivating candidate panel, and no typed-text telemetry.

**Do not implement this by merely selecting/highlighting row 1 on every candidate refresh.** That would alter Return and navigation semantics and would still turn complete words into unwanted longer words.

## 2. Executive conclusion

This is feasible without a new dependency, network service, or language model. The engineering complexity is moderate: the key dispatch change is small, but candidate evidence, default-action presentation, deferred-result freshness, and transparent-client commits need coordinated tests.

The earlier suggestion, “if the spell checker considers it valid, keep it,” is insufficient. On this machine **`coord` is not flagged as misspelled**, despite being an intended prefix in the user's workflow.

Two current implementation choices cause most of the mismatch:

1. Exact matches are discarded before the UI sees predictions, throwing away evidence that `app`, `the`, or `but` is already complete.
2. Spell corrections precede prefix completions. Here `appl` and `appli` both receive `apple` as a correction, even though raw completions start with `apply` and `application`, respectively.

Recommendation: **retain raw completion evidence, distinguish literal/default/explicit selection, and use a completion-oriented default policy.** Do not claim this policy can perfectly identify all complete English words or infer the user's desired word from an ambiguous prefix.

## 3. Evidence gathered on this machine

### Environment and safety

- macOS 26.6.2, build 25G83.
- Xcode 26.6, build 17F113; inspected SDK 26.5.
- SwiftType committed baseline: `0abe996`, with substantial existing uncommitted improvements. Preserve the current worktree, not just the baseline commit.
- Installed build read during research: `20260908093335`.
- Used a separate command-line Swift probe with `NSSpellChecker.shared`, an isolated spell-document tag, and explicit `en_US` language.
- Samples were fixed example strings, not captured user input or document contents. No learn/unlearn/ignore/record-response calls; no installed app or service changes.

### Actual raw results

These are **observations**, not cross-version API guarantees. Exact-match lookup examined the entire returned completion array, before applying SwiftType's five-result limit. Ranks below are one-based.

| Input | Spelling check | Exact input in raw completions? | First raw completion | Proposed correction |
| --- | --- | --- | --- | --- |
| `the` | Not flagged | Yes, rank 1 | `the` | None |
| `but` | Not flagged | Yes, rank 1 | `but` | None |
| `app` | Not flagged | Yes, rank 3 | `appreciate` | None |
| `appl` | Flagged | No | `apply` | `apple` |
| `appli` | Flagged | No | `application` | `apple` |
| `coord` | **Not flagged** | **No** | `coordinate` | None |
| `coordinate` | Not flagged | Yes, rank 1 | `coordinate` | None |
| `hello` | Not flagged | Yes, rank 1 | `hello` | None |
| `a` | Not flagged | Yes, rank 5 | `agent` | None |
| `api` | Not flagged | Yes (`API`), rank 2 | `apices` | None |
| `teh` | Flagged | No | None | `the` |
| `convinient` | Flagged | No | None | `convenient` |
| `helo` | Flagged | No | `helots` | `help` |
| `im` | Flagged | No | `imagine` | `I'm` |
| `SwiftType` | Not flagged | No | None | None |
| `中文` | Not flagged; word count 0 | No | None | None |

Additional observations:

- `appl`: completions began `apply`, `apple`, `application`, `applied`, `apples`.
- `appli`: completions began `application`, `applied`, `applications`, `appliance`, `applicants`.
- `coord`: completions began `coordinate`, `coordinator`, `coordination`, `coordinating`, `coordinated`.
- Several arrays contained 20 results; `coord` contained 11. Do not assume an exhaustive lexicon or that an exact word must appear in the top five.
- The language list contained `en` and several regional English identifiers, but not literal `en_US`; nevertheless the existing explicit `en_US` calls returned the results above. **Do not add a naive `availableLanguages.contains("en_US")` guard that disables predictions.** Alias/fallback resolution is not established by this probe; retain existing language behavior and investigate any future language change separately.

### Consequences

- `correction == nil` does not prove a complete word: `coord` is a counterexample.
- “No misspelling found” does not prove a standalone dictionary word: abbreviations, learned words, names, and unrecognized-script tokens complicate that interpretation.
- Exact membership in raw completions is useful **positive evidence**. Absence is not proof of incompleteness; the provider may omit or truncate a valid word.
- Prefix-first ranking supports the requested examples here, but can turn a typo such as `helo` into the obscure completion `helots`. This trade-off must be visible and tested, not concealed as perfect autocorrection.

## 4. Apple API research: guarantees versus assumptions

Research used local SDK headers and an isolated read-only Scout with Exa lookups of Apple documentation. Tavily search was rate-limited; it was not required for the conclusions.

| API | Useful contract | Do not assume |
| --- | --- | --- |
| `checkSpelling(of:startingAt:language:wrap:inSpellDocumentWithTag:wordCount:)` | Finds the first misspelled range | It is a complete-word dictionary membership API |
| `completions(forPartialWordRange:in:language:inSpellDocumentWithTag:)` | Supplies complete words the user might intend, in presentation order | Stable exact order, exhaustive results, or a guaranteed specific first word |
| `correction(forWordRange:in:language:inSpellDocumentWithTag:)` | Proposes one correction for a misspelled word | That a partial word should be corrected rather than completed; calibrated confidence |
| `guesses(forWordRange:in:language:inSpellDocumentWithTag:)` | Supplies alternatives whether or not the word is misspelled | That guess 1 is safe to commit automatically |
| `hasLearnedWord(_:)` | Identifies a user-learned word | General dictionary membership |

Apple describes completion order as the order in which results should be presented. We may preserve that order **within a product-defined category**, but cannot promise `apply` or `application` ranks first on every OS/account. Apply an explicit case-insensitive prefix filter if the application requires strict prefix completion; do not infer source category solely from the final flat string array.

The local spelling probe observed `{NSNotFound, 0}` for inputs not flagged. Retrieved Apple text describes the first misspelled range but did not explicitly establish the no-error sentinel in the material reviewed. Encapsulate/check this convention in the provider adapter and integration tests; do not mistake it for positive lexical proof. `wordCount == 1` is also not lexical proof (`coord` returned 1).

Keep explicit language arguments rather than mutating shared `setLanguage` or automatic-language preferences. Preserve the existing unique document tag and close it on deinit. Learned/ignored word state and user correction history can affect behavior. Do not mutate those to make tests pass.

### Sources

- [Apple: NSSpellChecker](https://developer.apple.com/documentation/appkit/nsspellchecker)
- [Apple: completions](https://developer.apple.com/documentation/appkit/nsspellchecker/completions(forpartialwordrange:in:language:inspelldocumentwithtag:))
- [Apple: correction](https://developer.apple.com/documentation/appkit/nsspellchecker/correction(forwordrange:in:language:inspelldocumentwithtag:))
- [Apple: guesses](https://developer.apple.com/documentation/appkit/nsspellchecker/guesses(forwordrange:in:language:inspelldocumentwithtag:))
- [Apple: checkSpelling](https://developer.apple.com/documentation/appkit/nsspellchecker/checkspelling(of:startingat:language:wrap:inspelldocumentwithtag:wordcount:))
- [Apple: hasLearnedWord](https://developer.apple.com/documentation/appkit/nsspellchecker/haslearnedword(_:))
- [Apple archived spelling guide](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/SpellCheck/Tasks/CheckingTextSpelling.html)
- Locally inspected authority: `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.5.sdk/System/Library/Frameworks/AppKit.framework/Headers/NSSpellChecker.h`.

The header also exposes asynchronous checking/candidate APIs. They are not a reason to rewrite scheduling in this task. New system inline-prediction APIs include macOS 14 availability constraints, while this project targets macOS 13; swapping to them is a separate architecture/compatibility decision.

## 5. Recommended v1 policy

### Separate three decisions

1. **What evidence does the provider return?** Exact matches, strict prefix completions, correction, guesses, spelling status.
2. **What action would Space take?** Preserve literal or accept a particular candidate.
3. **What has the user explicitly selected?** Navigation selection remains independent of the default action.

A string array alone cannot reliably express all three.

### Default-action decision order

For a fresh prediction snapshot corresponding to a nonempty buffer:

1. **Protected literal:** preserve explicitly learned/ignored words and unsupported automatic-completion token shapes. For v1, restrict automatic inference to ASCII English letters with internal straight/curly apostrophes; preserve non-Latin text, trailing apostrophes, and identifier-like mixed-case/acronym forms conservatively. Do not prevent explicit number selection of suggestions. Define and test the token-shape predicate; it is not a new input-routing rule.
2. **Exact completion evidence:** if any raw completion equals the buffer case-insensitively, preserve the exact original buffer (including casing), regardless of that completion's rank. This covers `the`, `but`, `app`, `a`, `api` in the observed environment.
3. **Strict prefix completion exists:** use the first eligible strict extension in provider order. This is deliberately allowed even when spelling is not flagged, so `coord` can complete. Put this candidate first in the displayed suggestion list.
4. **No prefix completion, spelling flagged, correction available:** default to that correction. This covers `teh` and `convinient` here.
5. **Otherwise:** preserve the literal. Fuzzy guesses may remain explicit choices, but do not silently use guess 1 as the automatic fallback.

Before this decision is used, an **explicitly selected candidate overrides it**. With no fresh visible suggestion, Space falls back immediately to literal plus space. A literal decision requires no visible candidate window.

This is a **completion-oriented heuristic**, not the logically impossible claim that every complete word can be distinguished from every intended prefix.

### Critical ambiguity: accepted spelling without an exact completion

Step 3 intentionally chooses `coordinate` for `coord`, even though the spell checker accepts `coord`. The same shape of evidence can occur for a genuine uncommon word missing from the returned completion list. Therefore:

- Never label this condition “proven incomplete.”
- Show the exact Space target before accepting it.
- Preserve learned terms and provide Return as the unmodified-literal escape path.
- Evaluate a fixed corpus of common words, abbreviations, proper names, and incomplete prefixes before shipping.
- If unintended expansion of valid words is unacceptable in that evaluation, use a conservative alternative: preserve all unflagged ambiguous tokens and add an explicit user-controlled prefix preference for cases such as `coord`. That alternative **will not satisfy `coord` automatically without the preference**. Do not hide this trade-off or patch it with secret hard-coded examples.

No `if prefix == "appl"` / `"appli"` / `"coord"` production branches. These examples belong in fixtures and acceptance checks, not a special-case dictionary.

### Completion versus typo ambiguity

Prefix-first means observed `helo` would default to `helots`, and `im` to `imagine`, not necessarily the user's intended correction. This is a known v1 limitation, not an implementation bug. Keep corrections accessible and report the result during user evaluation.

Do not invent a confidence score from Apple rank numbers, use edit distance as proof of intention, or automatically assume the shortest completion is best. All can break `appl`/`appli` and other useful prefixes. If broad typo recovery and exact user-intended ranking become requirements, a frequency lexicon or explicit opt-in preference model is a separate project with licensing, privacy, size, and maintenance work.

### Ordering and limits

- Collect the complete array returned by the provider before applying the UI limit; do not stop exact-match analysis after the first five items.
- Preserve source provenance even when correction and completion return the same string (`apple` for `appl` is both).
- Build displayed alternatives in a documented order: strict prefix extensions first, correction next if not already included, then remaining alternatives/guesses. Non-prefix results from the completions API are not automatic strict-completion targets.
- Deduplicate case-insensitively and remove the exact literal from the alternatives list, as today. Keep literal evidence separately.
- Apply the five-candidate cap after classification/ranking/deduplication. Keep a safe explicit identity/index for the chosen default after capping.
- If correcting is the automatic default, ensure the correction is displayed as number 1. If a required target is filtered/truncated away, fall back to literal rather than accepting an invisible candidate.

## 6. Suggested implementation architecture

Names below are illustrative; fit the existing code and avoid unnecessary framework abstractions.

### A. Provider adapter plus a pure policy

Add an injectable boundary around NSSpellChecker rather than mocking the OS singleton. A small `@MainActor` protocol or injected closures is sufficient. Keep AppKit calls on the main actor.

Provider evidence should retain:

- Original token and language.
- Raw ordered completions, optional correction, and guesses.
- Spelling outcome (`notFlagged`, `flagged`, `unknown`) where queried; distinguish unavailable/unsupported input from positive evidence.
- Explicit learned/ignored-word evidence if used by the policy.

A pure policy function consumes fixed evidence and returns ranked alternative candidates plus a default action and a reason. Reason codes are useful for tests; they must not result in production logging of token/candidate strings.

Avoid adding all OS queries to every Space press. Acquire evidence once as part of the existing prediction update; skip expensive calls when already unnecessary. Do not duplicate the existing spell-check calls for classification and rendering. A `checkSpelling` call is additional work and must be measured, not assumed free.

### B. A per-composition prediction snapshot

Suggested conceptual shape:

```swift
// Pseudocode, not a drop-in implementation.
enum DefaultSpaceAction {
    case literal
    case candidate(index: Int)
}

struct PredictionSnapshot {
    let buffer: String
    let generation: UInt
    let alternatives: [String]
    let defaultSpaceAction: DefaultSpaceAction
    // Optional typed provenance/reason for tests and display mapping.
}
```

Keep the existing original/display-capitalized distinction. Literal acceptance must use the original buffer, not a dictionary-normalized spelling. Candidate acceptance uses the existing capitalization transformation.

Publish the snapshot and UI together on the main actor. Clear snapshot/default action whenever `cancelPredictions()` clears candidates: on new transparent keystrokes, Backspace refresh, commit, reset, Escape, focus/session changes, and Caps Lock.

At Space, validate snapshot buffer/generation and current client state before accepting any default or explicit suggestion. Never fetch a new candidate synchronously on Space just because the panel is empty; that would accept unseen text and could reintroduce Chromium key-handler stalls.

### C. Space resolution order

Conceptually:

```text
passthrough mode -> leave event untouched
direct-input mode -> commit printable text synchronously; leave commands untouched
modifier shortcut -> preserve existing shortcut behavior
nonempty composition + fresh visible candidate presentation:
    explicit candidate selection -> use it
    explicit literal selection (if supported) -> use original
    default candidate -> use that displayed candidate
otherwise -> original text + ordinary space semantics
```

Use a dedicated resolver shared by inline and transparent handlers where practical. Its output is an intention, not the low-level insertion operation; the existing client modes still need different commit mechanics.

Do not alter `selectedCandidate()` to return the default implicitly. Return and navigation already depend on nil meaning “no explicit selection.”

## 7. Return, Caps Lock, navigation, and UI

### Return is not identical in every current mode

The request says Return remains unchanged. Preserve the actual existing contracts:

- **Inline, visible candidates, no explicit selection:** commits the original buffer without a trailing space and consumes Return.
- **Inline, explicit selection:** commits that selection without a trailing space.
- **Inline, hidden panel:** commits a pending original buffer and passes Return to the host.
- **Transparent, no explicit selection:** original letters are already in the document; discard the mirror and pass Return to the host. It may submit a message/search or insert a newline.
- **Transparent, explicit selection:** attempts existing candidate commit without a trailing space.

Thus “Return keeps original letters” is correct for ordinary unselected typing, but it is **not a guaranteed literal-only key after navigation**, nor a harmless no-submit action in chat clients. Explain this to the user; making Return always literal or suppressing host submission would be a separately approved behavior change.

Caps Lock / 中英 must continue preserving the original text and passing switching to macOS. Never accept the default Space target during deactivation/system commit; never introduce `TISSelectInputSource` or change the US keyboard override.

### Show the Space target without redefining selection

Recommended minimal UI:

- For an automatic candidate target, add a subtle spacebar icon to that candidate (normally candidate 1). Use the native SF Symbol `space` with Unicode `␣` as a runtime fallback; keep the spoken accessibility label explicit.
- For a literal target, show a compact reason-aware footer without consuming a numbered candidate slot or repeating the word already visible at the caret: `✓ Exact match` for exact dictionary evidence and `✓ Keep typed` for protected/uncertain literal fallbacks. Use the native SF Symbol `checkmark` with `✓` fallback.
- When explicit navigation selects a different item, update the Space indication to that item. Existing Return selection semantics remain tied only to explicit selection.
- No default-selection highlight that secretly flips `hasActiveSelection`.
- Accessibility should announce the default action, e.g. “Space accepts application,” without marking an unselected row as explicitly selected. Preserve existing press actions and nonactivating behavior.
- If there are no alternatives and the decision is literal, keep the candidate panel hidden as today; ordinary text already communicates the result. Do not show a new panel merely to echo every word.

This preserves the current alternatives-only index mapping. **Do not casually use `literalText:` to prepend a new literal row.** That path changes the unified grid indexes, initial selection, number shortcuts, and accessibility index offsets. It is possible as a separate UI design, but not the smallest safe change here.

## 8. Transparent prediction safety

`InputControllerTransparentPrediction.swift` is not interchangeable with inline composition:

- Printable letters are already inserted into Chrome/WeCom. Never call inline `commitWord` on the mirror or reinsert the entire literal token.
- Literal Space must use the existing one-space insertion path, discard the mirror, and preserve automatic-space tracking when appropriate.
- A prefix extension can use existing `commitTransparentWord` suffix insertion.
- Corrections/case-changing replacements require the current verified document range and immediate priming/commit behavior. Preserve the guards against unsupported document access and mismatched text.
- If commit cannot be safely verified, preserve the document and insert only a space. Do not retry with unchecked replacement, guess a UTF-16 range, or insert both a completion and literal space.
- Keep stale-cursor/client checks before candidate acceptance; buffer equality alone is not enough. Preserve the existing `NSNotFound` path where supported rather than demanding document access for every safe suffix insertion.
- Snapshot any needed fallback bookkeeping before a failed `commitTransparentWord`, because that method clears mirrored state on failure.
- Cancel pending debounce work after Space so candidates do not reappear for the word just committed.
- Space before the 75 ms transparent debounce completes remains literal. This is an explicit safety trade-off: select only an already displayed current suggestion, not a hidden stale or freshly computed one. Assess user-perceived timing in Chrome/WeCom; do not tune the debounce in the same patch without evidence.

## 9. File-by-file work map

| File | Planned responsibility |
| --- | --- |
| `Prediction/SpellCheckPredictor.swift` | Injectable evidence collection, retain exact matches as metadata, ranked alternatives and default-action policy |
| `Input/State/InputState.swift` | Store/clear coherent prediction snapshot or equivalent metadata |
| `Input/Controller/InputController.swift` | Predictor injection seam only if needed; keep current client policy and scheduler |
| `Input/Controller/InputControllerPredictions.swift` | Publish candidates, capitalization, and default hint from the same snapshot |
| `Input/Controller/InputControllerStateManagement.swift` | Invalidate new metadata alongside existing cancellation/generation |
| `Input/KeyHandling/LatinKeyHandler.swift` | Space default resolution; leave Return logic unchanged |
| `Input/Controller/InputControllerTransparentPrediction.swift` | Same Space intention with transparent-safe commit/fallback |
| `UI/Candidate/CandidateWindow.swift` | Separate default hint from `hasActiveSelection`; preserve indexing/navigation |
| `UI/Candidate/CandidateView.swift` | Minimal default-action visual and accessibility labels |
| `UI/Settings/SettingsWindowControllerCustomization.swift` | Keep fixed preview compatible if rendering API changes |
| `App/StatusBarController.swift` | Update shortcut help accurately, including transparent Return caveat where appropriate |
| `README.md`, `REAL_CLIENT_ACCEPTANCE.md`, `HANDOFF.md` | Document new behavior, limitations, and verified results |
| `SwiftType.xcodeproj/project.pbxproj` | Add new production/test files to correct targets if needed |

New pure policy/provider types can live in small focused files. Do not refactor unrelated installers, switching code, geometry, or settings during this work.

## 10. Test plan

### Deterministic provider/policy tests (mandatory)

Use injected fixed evidence; do not assert exact Apple ranking in ordinary XCTest.

1. `the`/`but` have exact completion evidence and extensions: literal default.
2. `app` exact result at rank 3, even behind `appreciate`: literal default.
3. Exact result beyond UI limit (including `limit == 1`): still literal default.
4. `appl`: correction `apple`; completions `apply`, `apple`, `application`: default `apply`, no duplicate `apple`.
5. `appli`: correction `apple`; completions `application`, `applied`: default `application`; non-prefix correction cannot win.
6. `coord`: spelling not flagged, no exact completion, extensions available: default `coordinate` under the recommended completion-oriented policy.
7. `coordinate` exact evidence: keep original.
8. `teh` / `convinient`: flagged, no prefix extension, correction available: correction default.
9. Fuzzy-only input: original default, guesses remain optional explicit choices.
10. Nil/empty provider results, unknown classification, zero/negative limits: safe behavior, no invalid candidate indexes.
11. Case-insensitive exact `API` for input `api`: preserve original case; uppercase first-letter completion follows existing capitalization rules.
12. Explicit learned/ignored token with extensions: original default. Never mutate the live dictionary in tests.
13. Non-Latin, trailing apostrophe, mixed-case/acronym, and contraction shapes: tested protection policy. Include `don't`, `I'm`, `application'`.
14. `helo`/`im`: fixtures document the prefix-first trade-off; do not falsely assert they are always corrected to `hello`/`I'm`.
15. Abbreviation/valid-word absent from exact completions: document the ambiguity and test the chosen policy, not a fictional certainty flag.
16. Provider rank changes: default and displayed candidate 1 stay consistent, without asserting a universal word choice.

Keep the existing alternatives-exclude-literal tests valid by storing exact evidence separately. Do not weaken those assertions to accommodate a different presentation accidentally.

### Controller and UI tests

Extend existing `InputControllerEventRoutingTests`, `InputControllerTransparentPredictionTests`, `CandidateWindowUpdateTests`, and selection/navigation tests:

- Replace old Space-without-selection expectations only where deliberately changed; retain literal cases for complete words, absent candidates, stale results, and fallbacks.
- `app -> appl -> appli` through typing and `appli -> appl -> app` through Backspace: default changes with each fresh snapshot.
- Space with no explicit selection accepts the default; explicit candidate 2 wins over default candidate 1.
- Original/candidate commit gets exactly one automatic trailing space; next punctuation replaces only that tracked space.
- Return with default hint but no explicit selection still commits original; explicit Return remains unchanged. Include transparent host passthrough results.
- Caps Lock/deactivate/system commit retain original even while a candidate has a Space badge.
- Empty composition, double Space, modified Space, digits, and passthrough clients remain correct.
- Use `ManualPredictionDelay` to release/cancel transparent work deterministically. No new wall-clock sleeps.
- Space before debounce: literal once; delayed task cannot show candidates afterward.
- New generation, cursor move, selection change, client switch, or hidden panel: no stale default acceptance.
- Transparent prefix suffix insertion, different-prefix correction, case change, unavailable document access, and mismatched document: correct commit or literal-space fallback, never duplication/destructive replacement.
- Grid/Vertical layouts, capped/scrolled rows, default hint versus explicit selection, hidden cells, and accessibility press indexes stay aligned.
- Default hint never changes `selectedCandidate()`, selected accessibility rows, or first-navigation activation behavior.

### Live provider observation versus unit tests

Keep a small repeatable fixed-word probe (section 12) and record the actual machine's ranking separately. A fake-provider test proves policy behavior; it cannot prove Apple returns `apply` first on another machine. If desired rankings differ, report them rather than hard-coding examples or silently passing an acceptance test.

## 11. Validation and delivery order

1. Re-read current source/tests and preserve all existing worktree changes. Do not reset to remote main or overwrite the installed build.
2. Implement provider evidence and pure policy; run focused tests before wiring key behavior.
3. Wire coherent snapshot invalidation and separate Space resolver; keep Return and switching unchanged.
4. Add minimal visual/accessibility hint and documentation; verify preview and number-index mapping.
5. Run focused tests, then full suite in fresh temporary DerivedData. Last prior suite was 543 passing tests; do not treat that as verification of this new feature.
6. Run LSP diagnostics before build and `lens_diagnostics` mode `all`, plus relevant lint and `git diff --check`. Do not weaken existing checks.
7. Measure additional prediction-update work with existing privacy-safe signposts. Do not benchmark by logging real words or saving typed-word caches.
8. Obtain independent Tester review. Use fixed fixtures for policy and actual host tests for integration.
9. **Install only on explicit user approval for the implementation build.** This research request is not installation authorization.
10. Real-client matrix: TextEdit, Spotlight, Safari, Edge, Chrome, WeCom, DingTalk, Terminal, and both VS Code's Monaco editor and integrated terminal. Verify temporary compatibility commits insert exactly once, VS Code shows no candidates, and host-owned commands still pass through. Test exact examples, quick Space, Return in a chat/search field, punctuation, switching during composition, and focus changes.

Use temporary build/test paths rather than arbitrary DerivedData cleanup. Xcode previously emitted registration commands even with `REGISTER_WITH_LAUNCH_SERVICES=NO`; disclose this limitation, do not automatically unregister input sources or restart shared IMK services. If a newly installed build fails to connect, inspect registration/session state and try user-controlled logout/login before changing switching code.

Release gate: the visible Space target and actual output agree, complete-word fixtures stay literal, requested prefix fixtures complete, no double insertion/lost text occurs, and Return/Caps Lock/client routing regressions remain green. Broader completion-quality issues such as `helo` must be reported as limitations, not hidden behind a passing unit suite.

## 12. Reproducible read-only API probe

Run in a separate terminal process, not inside the active input method. This prints only the fixed examples below. It does not install an app, learn/unlearn words, or change input sources. Compilation/OS services may maintain their ordinary caches; “read-only” here means no intentional application/settings/dictionary mutation.

```bash
swift - <<'SWIFT'
import AppKit
import Foundation

let checker = NSSpellChecker.shared
let tag = NSSpellChecker.uniqueSpellDocumentTag()
defer { checker.closeSpellDocument(withTag: tag) }
let language = "en_US"
print(ProcessInfo.processInfo.operatingSystemVersionString)
for token in ["the", "but", "app", "appl", "appli", "coord",
              "coordinate", "hello", "teh", "convinient", "helo", "im"] {
    let range = NSRange(location: 0, length: (token as NSString).length)
    var count = 0
    let misspelling = checker.checkSpelling(
        of: token, startingAt: 0, language: language, wrap: false,
        inSpellDocumentWithTag: tag, wordCount: &count
    )
    let completions = checker.completions(
        forPartialWordRange: range, in: token, language: language,
        inSpellDocumentWithTag: tag
    ) ?? []
    let correction = checker.correction(
        forWordRange: range, in: token, language: language,
        inSpellDocumentWithTag: tag
    )
    let exact = completions.contains { $0.lowercased() == token.lowercased() }
    print(token, "notFlagged:", misspelling.location == NSNotFound,
          "exact:", exact, "wordCount:", count,
          "correction:", correction ?? "<none>",
          "completions:", Array(completions.prefix(5)))
}
SWIFT
```

## 13. Implementation status

Implemented behavior:

- Exact completion evidence remains separate from displayed alternatives, so complete words can stay literal even when the exact result falls beyond the UI limit.
- Strict prefix completions precede corrections; corrections precede fuzzy guesses. Fuzzy guesses alone never become the automatic Space action.
- A buffer-bound `PredictionSnapshot` stores ranked alternatives and the default action. Automatic commits require a visible panel, matching buffer, and valid index.
- Inline and transparent Space share the same resolved candidate but retain their existing commit mechanics and safe transparent fallback.
- The candidate UI marks the current Space candidate with a native spacebar icon (Unicode `␣` fallback) without creating an explicit selection. Literal decisions use a separate reason-aware `✓ Exact match` / `✓ Keep typed` footer that does not repeat the word. Navigation moves the marker to the explicit selection.
- Return, Caps Lock / 中英, number shortcuts, passthrough routing, automatic-space punctuation, and transparent debounce behavior remain separately tested.
- The implementation does not add `checkSpelling`; it uses completion exact-match evidence, strict-prefix evidence, optional correction, guesses, and learned-word state.

Automated verification on 2026-09-09:

- Focused Smart Space/policy/controller/transparent/UI tests passed.
- Full XCTest suite passed after client-compatibility coverage: **585 tests, 0 failures, 0 skips** on macOS 26.6.2.
- Unsigned Release validation produced a universal `x86_64 arm64` executable and a valid `Info.plist` in temporary DerivedData.
- After implementation verification, the user explicitly authorized installation. Transactional installation of client-compatibility build `20260909100351` succeeded; signature and universal architecture were verified. Real-client validation remains pending.

## 14. Instructions to future implementation agents

Implement the agreed behavior, not a wholesale IME redesign. Start from this guide's actual evidence, especially the `coord` counterexample. Keep raw exact-match evidence, preserve Return's explicit-selection distinction, and share the Space decision without merging inline/transparent insertion paths.

If you discover that satisfying all complete-word preservation cases requires a dictionary or a preference UI, stop and explain that trade-off. Do not claim that an opaque system spell-checker can perfectly distinguish intent. The user prefers useful, predictable completion with a literal escape key; correctness and honest limitations matter more than passing three hard-coded examples.
