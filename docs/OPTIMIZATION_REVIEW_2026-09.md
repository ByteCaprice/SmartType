# SmartType: Optional Improvements Review

Date: **2026-09-17**

Source baseline: **`b757996`**, with the pending documentation consolidation.

## Recommendation

**Keep the current version as the stable daily-use baseline.** The user is satisfied with its behavior. No rewrite, prediction-engine replacement, broad compatibility change, or immediate installation is warranted by this review.

This began as source inspection rather than a runtime benchmark. Suggestions below remain optional experiments; a source-level inefficiency is not evidence of a noticeable slowdown.

## Implementation update — 2026-09-18

Following explicit authorization to improve the project, the working tree now implements two low-risk items from this review:

- **Event-scoped client identity reuse:** direct-input and transparent-prediction key handling resolve the IMK client identity once per synchronous event. Delayed transparent refresh still performs fresh identity and cursor validation.
- **Candidate-index hardening:** normal and transparent candidate-selection paths reject negative, empty, and end indices without insertion or state mutation.

The identity-query tests failed before the optimization and pass afterward. A fresh isolated run completed **613 XCTest cases with zero failures or skips**. Focused and independent adjacent-suite verification also passed. After explicit authorization, Release build **`20260918065419`** was installed transactionally; its signature, `x86_64 arm64` architectures, and equality with the Release output were verified. No input source was selected automatically. Release provenance, prediction-provider micro-optimization, rendering changes, and documentation-check automation remain deferred.

## Priorities

| Order | Opportunity | Expected value | Risk if implemented |
| --- | --- | --- | --- |
| 1 | Record a small real-client and latency baseline | Protect the working experience; identify actual bottlenecks | Low; observation only |
| 2 | Reuse client identity within a synchronous key event | Reduce repeated client queries without changing typing policy | Low–medium; freshness boundaries matter |
| 3 | Make release verification reproducible | Reduce accidental packaging of a different or unverified build | Low to runtime; moderate tooling effort |
| 4 | Strengthen defensive candidate-index validation | Make internal helpers robust against malformed indices | Low |
| 5 | Measure prediction-provider and rendering costs | Target optimization only where it matters | Low to measure; implementation-dependent |
| 6 | Automate documentation integrity checks | Prevent stale paths and misleading verification claims | Low |

## 1. Establish a small, repeatable real-client baseline

**Evidence:** [Testing and acceptance](TESTING.md) separates deterministic tests from physical Caps Lock timing, live VoiceOver, multi-display positioning, and host delivery. Existing signposts already cover prediction, spelling, candidate geometry, and rendering; new typed-text logging is unnecessary.

**Proposal:** Before optimizing, record a short acceptance pass in TextEdit, Safari or Edge, one transparent Chromium client, VS Code, and one native terminal. Include an affected chat app if there is a current reproducible problem.

Record only:

- app/macOS version, installed build, effective input policy, and field type;
- cold-first-word versus warm latency, using existing Points of Interest;
- Space, immediate Space before prediction, Return, Backspace, punctuation, and explicit selection;
- physical Caps Lock switching with no composition and with visible candidates;
- pass/fail and a reproducible synthetic key sequence, not private document contents.

**Decision rule:** If responsiveness is already satisfactory and measurements show no meaningful bottleneck, stop. A stable baseline is a successful outcome, not a reason to invent more work.

**Validation:** Repeat the same scenarios after any future change. Keep cold and warm p50/p95/p99 separate, and compare candidate appearance as well as key-handler duration. Unit tests alone cannot establish an improvement in physical switching latency.

## 2. Reduce repeated client identity queries within one key event

**Confirmed observation:** Client identity is queried in several related paths:

- [InputControllerKeyHandling.swift](../Input/Controller/InputControllerKeyHandling.swift): `handleKey` resolves the client mode.
- [InputControllerComposition.swift](../Input/Controller/InputControllerComposition.swift): `insertTextForCompatibility` checks priming policy using another bundle-ID query.
- [InputControllerTransparentPrediction.swift](../Input/Controller/InputControllerTransparentPrediction.swift): `isMirroredCompositionStale` checks client identity, and `appendMirroredCharacter` captures it when a new mirror starts.

The exact number depends on the path; these calls do **not** all run for every character. `bundleIdentifier()` is an IMK client query and should not be assumed free. Policy resolution also reads runtime defaults. The Caps Lock empty-composition path already avoids this work; preserve that fix.

**Minimal experiment:** Capture the bundle identifier once at a suitable synchronous event boundary and pass it to helpers that only need identity/policy. Keep lifecycle helpers independently usable. Consider reusing the resolved policy only if its semantics remain unchanged.

**Important limits:**

- Do not carry an event snapshot across `await`, debounce, focus changes, or lifecycle callbacks.
- Keep fresh client/cursor/document validation before delayed candidate presentation or replacement.
- Do not replace the IMK client identity with the frontmost application's identity.
- Do not remove document-range checks merely to reduce IPC.

**Confidence:** Repeated queries are visible in source; latency benefit is unmeasured.

**Validation:** Extend existing recording clients and call-count tests for first and subsequent transparent letters, primed/unprimed clients, direct input, commands, focus changes, and deferred refresh. Assert path-specific counts, not “one query forever.” Preserve insertion/marked-text order and runtime override behavior, then measure in real clients.

## 3. Make release provenance and staging more reproducible

**Confirmed observation:** [release.sh](../scripts/release/release.sh) rebuilds Release, stamps the version, re-signs and verifies the app, and creates a PKG. It uses shared `build/` staging and removes that directory before building. It does not itself run the test suite or produce a machine-readable record tying verification to the final artifact.

Signature verification and transactional installation already exist. This proposal concerns **build provenance and packaging workflow**, not a replacement of those safeguards.

**Proposal:**

1. Use invocation-specific build/staging directories, with cleanup limited to directories owned by that invocation; alternatively, explicitly reject concurrent packaging runs.
2. Emit a small release manifest with commit, dirty-worktree status, Xcode/macOS versions, bundle version, architectures, final artifact hashes, signature result, and associated verification result location/status.
3. Distinguish “built and signed” from “tested.” Do not infer test success just from a commit hash or number of test methods.
4. Keep package creation separate from installation; neither verification nor packaging should silently install or restart services.

**Confidence:** Shared staging and absence of a test/provenance step are confirmed. No packaging race or bad release was reproduced.

**Validation:** Use stubbed tools and isolated temporary directories to exercise success, interruption, build/signing failure, dirty trees, and concurrent invocation. Confirm the final hash is computed **after** version stamping and re-signing. Run genuine PKG acceptance only in a disposable environment with authorization.

## 4. Complete defensive candidate-index bounds checking

**Confirmed observation:** In [InputControllerComposition.swift](../Input/Controller/InputControllerComposition.swift), `selectCandidateByIndex` checks `index < state.currentPredictions.count` before subscripting, but does not explicitly reject negative indices. A negative value would pass that upper-bound check.

Normal keyboard/UI callers are expected to produce nonnegative indices. This review did not establish a user-reachable crash, so this is defensive hardening, not an urgent defect report.

**Minimal proposal:** Use the collection's `indices.contains(index)` check, consistent with the bounds-validation style already used by `defaultSpacePrediction` in [InputControllerPredictions.swift](../Input/Controller/InputControllerPredictions.swift).

**Validation:** Add focused tests for `-1`, an empty prediction array, `count`, and valid first/last indices. Invalid indices must perform no insertion and leave composition and candidate state unchanged. Valid selection must retain capitalization and trailing-space semantics.

## 5. Optimize prediction and presentation only after measurement

### Spell-check evidence collection

**Confirmed observation:** [SpellCheckPredictor.swift](../Prediction/SpellCheckPredictor.swift), `predictionResult`, fetches correction, completions, learned-word evidence, and the ignored-word list. Guesses are already conditional on available candidate capacity. Ranking may run again after guesses are fetched.

A narrow possible optimization is to avoid the ignored-word lookup when learned-word evidence or token-shape protection already guarantees the protected-literal result. This is a small opportunity, not a demonstrated bottleneck. Protected tokens still need their explicit alternatives; do not skip the whole prediction pipeline.

**Validation:** Measure first. If worthwhile, add a provider-level seam or equivalent test instrumentation to prove lookup counts as well as result equivalence for learned words, ordinary words, contractions, acronyms, and identifiers. Pure ranking tests alone cannot prove the live provider avoided a call. Do not mutate the user's dictionary or introduce long-lived dictionary caches that hide external changes.

### Candidate rendering and geometry

**Confirmed observation:** [CandidateWindow.swift](../UI/Candidate/CandidateWindow.swift), `show`, refreshes the candidate model, queries window level and caret geometry, and renders/sizes the panel. These costs already have signposts.

**Proposal:** If rendering dominates, first investigate skipping genuinely unchanged visual work. A comparison must include default Space action/reason, explicit selection, layout, theme, and accessibility state—not just candidate strings.

Do **not** blindly cache caret geometry or window level by bundle ID. Two fields/windows in the same application can require different placement or levels. Preserve fresh positioning after scrolling, field changes, and display changes.

**Validation:** Compare both layouts, identical alternatives with a changed Space reason, VoiceOver state, window changes, scrolling, and multiple displays. Reject optimizations that save layout time but show stale candidates or misplaced panels.

### What to defer

Inline prediction currently runs synchronously; transparent prediction uses a debounce. Copying the transparent delay into inline mode is **not** automatically an improvement: it changes candidate availability when Space, digits, or Return arrive quickly. Do not change scheduling or move AppKit work to detached tasks unless measurements establish a need and freshness/commit semantics are independently proven.

## 6. Add lightweight documentation checks

**Observation:** The documentation consolidation creates clear active guides and explicitly dated archives. Links and contracts were checked during that work, but repeatable checks would reduce future drift.

**Proposal:** Add a dependency-free local check for repository-relative Markdown links and anchors, with explicit handling of external URLs and historical archive references. Optionally include it in a future verification entry point alongside shell syntax and whitespace checks.

Keep version/build/test counts explicitly dated. Do not automatically rewrite them from source test-method counts: source counts are not executed-test evidence. Avoid tests that duplicate entire prose documents and become expensive to maintain.

**Validation:** Test missing files, renamed headings, fragments, external URLs, and intentionally historical references in small temporary fixtures. The checker must not require network access, installation, or input-source changes.

## Things to preserve, not “optimize away”

- macOS owns source switching; no automatic ABC redirection or TIS selection calls.
- Empty Caps Lock paths avoid client-policy IPC; mirrored text is discarded rather than inserted again.
- Edge stays inline, native terminals passthrough, and VS Code direct input unless reproducible client evidence justifies a targeted change.
- No additional marked-text calls during deactivation without a named failing client and evidence; extra synchronous client communication can itself delay switching.
- Smart Space requires fresh, visible, buffer-matching evidence. Return and explicit selection retain their separate semantics.
- Transparent replacement remains verified and falls back safely. No asynchronous insertion retries.
- Offline prediction, no typed-text telemetry, and no dictionary mutation for testing.
- Transactional installation, rollback, signature verification, and explicit installation authorization.
- Existing tested literal-slot support is not worth removing merely because normal presentation does not currently use it.
- Keep the repository private; this review changes neither licensing status nor publication policy.

## Suggested next step

Use installed build **`20260918065419`** in the real-client baseline when convenient. Reopen affected applications so they reconnect, then observe normal typing and physical Caps Lock behavior. Keep the remaining optimization ideas deferred unless measurements or a reproducible client problem justify one of them.

### Review limits

The implementation was covered by deterministic tests and exact Release/install verification, but it was not benchmarked in real applications. Unit tests cannot prove physical Caps Lock timing, host event delivery, VoiceOver behavior, or candidate placement on every display and client. No automatic input-source selection was used. The repository commit and push status should be determined from Git rather than inferred from this dated review.
