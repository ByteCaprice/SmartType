# SwiftType Improvement Review

> **Archived:** This dated source review records improvements that were subsequently implemented. Use the current [`architecture`](../ARCHITECTURE.md) and [`testing`](../TESTING.md) guides for active contracts.


Date: 2026-09-07

Implementation status updated: 2026-09-08

Scope: input routing, prediction latency, candidate UI, accessibility, settings, installation, packaging, documentation, and tests. This is a source review, not a runtime benchmark or a claim that every potential issue reproduces on this Mac.

This document began as a source-only review. On 2026-09-08, the user authorized Phases 1–3: safety/clarity, transactional package installation, and generation-bound transparent candidate refreshes. The implementation status notes below distinguish completed work from remaining recommendations.

## Executive Summary

The architecture is appropriately small for an offline input method. Keep the native spell checker, separate client modes, preallocated candidate cells, and conservative text-replacement checks. A large rewrite or a new prediction engine is not justified by the available evidence.

The source-level improvements identified by this review are now implemented. The highest-value next steps require runtime evidence:

1. Install the optimized build when it is acceptable to disturb the current session, then run the real-client matrix.
2. Collect cold/warm key-handling and candidate-latency measurements before changing scheduling or ranking.
3. Validate VoiceOver and candidate placement in real applications and on multiple displays.
4. Exercise the generated PKG in a disposable macOS account or machine.

**Important context:** after installing the guide-compliant build, macOS logged `imklaunchagent: Refusing connection name for bundle: unrecognized 'InputMethodConnectionName' value`. Restarting the Mac created a fresh InputMethodKit session and restored normal input and Caps Lock language switching in TextEdit and Spotlight. The production switching code was not the cause established by this incident; preserve the now-working routing and metadata.

## Implementation Status

Completed in the Phase 1–3 worktree:

- Transactional local and PKG bundle replacement with signature validation, rollback, strict package scripts, safer user/home checks, and isolated shell failure tests.
- Actionable uninstall results that preserve preferences and no longer report success or terminate after partial failure.
- Correct Vertical/Grid and transparent/passthrough shortcut documentation plus in-app Setup & Shortcuts help.
- Finite `0...1` opacity validation at both persistence boundaries.
- Generation-bound transparent prediction refreshes that hide stale candidates, revalidate selection, tolerate `NSNotFound`, and use a test-injectable delay instead of wall-clock sleeps.

The remaining source improvements were subsequently implemented: privacy-safe performance signposts, candidate accessibility semantics/actions, recent same-client caret fallback, Settings frame persistence and preview, reset confirmation, grid-column write validation, and a real-client acceptance guide.

Still pending by design: collecting real latency numbers, live VoiceOver validation, multi-display/caret validation, real-client acceptance after installation, and a disposable-environment PKG installation. These require the optimized build to run in real hosts and must not be claimed from unit tests.

Verification: shell syntax and whitespace checks passed; the expanded isolated installer harness passed 10/10 and the read-only diagnostic test passed; the final full Xcode suite passed 543 tests with no failures using temporary DerivedData. Three independent Tester reviews returned PASS. Although tests requested `REGISTER_WITH_LAUNCH_SERVICES=NO`, Xcode still emitted registration commands for temporary bundles; those paths were deleted and no automated unregister operation was performed. The working installed input method was not replaced or restarted.

The current source explicitly routes Edge and its dotted bundle-ID descendants to **inline** mode. Chrome uses transparent prediction; WeCom and DingTalk add a temporary marked-text handshake to transparent commits; VS Code uses no-prediction direct compatibility input because Monaco drops bare passthrough while its integrated terminal does not. `HANDOFF.md`, README, and the acceptance matrix reflect these distinctions.

## Priority Guide

| Priority | Meaning |
| --- | --- |
| P1 | Address first: installation safety or substantial everyday usability/latency risk |
| P2 | Valuable follow-up: robustness, accessibility validation, discoverability, or polish |
| P3 | Optional cleanup or product enhancement |

Confidence labels distinguish **confirmed code behavior**, **runtime validation needed**, and **product suggestion**. Priority is implementation order, not a claim that an unmeasured issue is severe.

## 1. Safer Package Upgrades

**Implemented in Phase 2 | P1**

Evidence: `scripts/release/release.sh:109-131` generates a preinstall script that deletes existing system/user installations before the replacement is validated. The generated postinstall at lines 139-171 has no strict error handling, deletes the destination, copies the payload, changes ownership, and removes staging without checking each operation. A failed copy can be followed by successful commands and a success-looking final exit status. Lines 143-146 explicitly report success when there is no GUI user, despite not installing the user-level input method.

Recommendation: validate the target user and staged bundle before touching the existing installation; check all critical operations; keep a recoverable previous version until destination validation succeeds. Report a failed installation as failure. Treat no-GUI-user installs explicitly rather than silently succeeding. Validate the user-home lookup without splitting a path containing spaces. Keep root-run staging controlled and reject unexpected symlinks.

The local installer also updates an existing destination in place using `rsync --delete` (`scripts/install.sh:46-59`). Strict shell behavior catches failure, but does not restore an interrupted update. Preserve the stable installation path if required by input-method registration, while designing an explicit recovery path.

Validation: simulate missing payload, failed copy, unwritable destination, invalid home, and interrupted replacement in an isolated test directory or disposable macOS environment. Assert that the old installation survives or is recoverable and no failed operation reports success. Do not fault-test against the active input method.

## 2. Make Uninstall Errors Actionable

**Implemented in Phase 1 | P1**

Evidence: `UI/Settings/SettingsWindowControllerAbout.swift:70-91` catches deletion errors, logs only a generic message, then logs completion and terminates regardless. The confirmation at line 58 mentions logout but not manual removal from Input Sources.

Recommendation: return a removal result and show a clear failure or partial-success alert. Distinguish a missing file from a permissions error. Explain that users should switch to another input source and remove the SwiftType entry in System Settings. Do not automatically modify their configured input sources. Preserve preferences unless the user explicitly requests their removal.

Validation: cover missing app, successful removal, failed app removal, and failed Applications-symlink removal. Verify the UI never claims full success after partial failure.

## 3. Measure and Reduce Synchronous Prediction Work

**Instrumentation implemented, including total key handling; runtime benchmark pending | P2**

Evidence: inline typing calls `updatePredictions` directly (`Input/Controller/InputControllerKeyHandling.swift:189,199,278`). `InputControllerPredictions.swift:7-20` synchronously fetches suggestions and shows the panel. `Prediction/SpellCheckPredictor.swift:26-62` may call correction, completions, and guesses for one prefix. `UI/Candidate/CandidateWindow.swift:144-168,302-310` adds client queries, layout, sizing, and presentation. Transparent prediction instead coalesces refreshes for 75 ms (`InputControllerTransparentPrediction.swift:214-232`), still executing the eventual work on the main actor.

Recommendation: instrument key-handler duration, individual spell-check stages, client geometry queries, and candidate rendering. Record cold-first-word and warm p50/p95/p99 times separately in TextEdit, Safari, Edge, and Chrome. Also measure time from key press to visible suggestions; shorter handler time alone can hide a worse perceived delay.

Start with redundant UI work, then consider coalescing inline prediction refreshes if measurements justify it. Keep text composition immediate. Do not move AppKit work to a detached task without validating isolation requirements. Do not blindly copy the 75 ms delay: fast digit/Space/Return handling currently depends on candidate visibility and selection state.

If spell correction dominates, evaluate a bounded short-lived cache or a different invocation threshold against suggestion quality. Changing correction-first ordering can alter expected typo fixes, so it is not a free optimization. Avoid persisting typed-prefix caches.

Validation: compare typing, backspace, immediate candidate selection, and immediate language switching before/after. Report CPU and allocation changes as well as latency. Never log actual typed words or surrounding document text in performance diagnostics.

## 4. Keep Deferred Candidates Tied to Their Input State

**Implemented in Phase 3 | P1/P2**

Evidence: the delayed task checks cancellation, mirror mode, and buffer equality, but not current selection before displaying (`InputControllerTransparentPrediction.swift:214-232`). Stale-client checks run at the next keydown (`:17-18,197-212`). Existing candidates also remain visible while a changed prefix waits for its refresh (`:125-137,152-156`).

Recommendation: explicitly associate candidates with a composition generation/prefix. Decide whether stale candidates should disappear, be temporarily unselectable, or remain selectable as displayed. Revalidate available client/selection information before a delayed show, without treating an unreliable client identifier as universally authoritative. Keep app-switch cancellation intact.

Validation: queue a refresh, change selection or field before it fires, and verify stale UI is not shown. Test type/backspace followed immediately by a digit. Include clients returning `NSNotFound`; do not sacrifice safe fallback behavior to enforce a range that the client cannot provide.

## 5. Explain the Actual Candidate Controls

**Implemented in Phase 1 | P2**

Evidence: the default is Vertical List (`UI/Theme/ThemeManager.swift:62`), while `README.md:67-87` explains a collapsed grid and active-row column selection. Production predictions start with no selected candidate (`CandidateWindow.swift:147-149`). Transparent mode passes arrows and Tab through while dismissing candidates (`InputControllerTransparentPrediction.swift:44-46`), unlike inline navigation.

Recommendation: document Vertical and Grid separately, and distinguish inline from transparent-mode controls. Explain that a visible list is not necessarily an explicitly selected suggestion. Smart Space now exposes a separate visible default action without changing Return/navigation selection state. Describe digit labels in terms of the visible slots, not a fixed universal column count.

Add a compact in-app Shortcuts/Help entry. In transparent mode, do not advertise arrow-based selection that the implementation intentionally does not consume. Explain why terminals and VS Code have no suggestions rather than letting users assume the input method failed.

Validation: give a new user only the in-app help and ask them to select a suggestion, retain a literal word, enter a number, and switch languages in TextEdit and Chrome.

## 6. Audit Candidate Accessibility

**Semantics and press actions implemented; live VoiceOver audit pending | P2**

Evidence: candidate cells are custom highlight containers with attributed text labels (`UI/Candidate/CandidateView.swift:5-52,349-371`). Selection is expressed visually; there is no explicit candidate-list accessibility model in that file or `CandidateWindow.swift`. Native text fields may still expose some content automatically, so this is not proof that the entire panel is inaccessible.

Recommendation: inspect the live accessibility tree first. Expose each candidate's text, shortcut, and selection state with an appropriate container structure. Ensure hidden/preallocated cells do not appear as stale suggestions. Support assistive navigation without stealing keyboard focus from the host application. Announcements should be restrained and user-tested, not emitted on every keystroke.

Validation: VoiceOver, keyboard-only use, Increase Contrast, Reduce Transparency, light/dark appearance, and custom low-contrast themes. Confirm the host caret remains focused while candidates are explored.

## 7. Make Candidate Placement More Stable

**Implemented; real-client/multi-display validation pending | P2**

Evidence: missing caret geometry falls back to `NSEvent.mouseLocation` (`UI/Candidate/CandidateWindow.swift:313-323`). Expand/reframe uses `lastCursorRect` (`:295-299`). A stationary pointer on another monitor can therefore become the fallback anchor even while typing elsewhere.

Recommendation: prefer a valid recent caret rectangle from the same input session before falling back to the mouse. Clear cached anchors on session changes. Re-query only when needed so positioning improvements do not add expensive client IPC to every navigation event. Do not substitute `NSWorkspace.frontmostApplication` for the actual IMK client.

Validation: two monitors, scrolling, moving between fields, full-screen windows, screen edges, and clients reporting zero/unknown geometry. Treat changing the hardcoded character-index query as an experiment, not an assumed fix; IMK client conventions differ.

## 8. Finish Installation Diagnostics Without Broad Side Effects

**Implemented; post-install operational validation pending | P2**

Current state: ordinary installation no longer kills `imklaunchagent`, `CursorUIViewService`, or forcibly terminates shared UI processes. Local and package installation now use the same validated transactional replacement helper. The local installer refreshes only the text-input menu/switcher agents and prints logout guidance. Build products and arbitrary DerivedData remain untouched deliberately.

`scripts/diagnose.sh` now provides a read-only summary of the running state, installed version/build, signature, architectures, routing modes, relevant metadata, custom transparent clients, and discoverable same-ID bundles. It redacts the home directory and does not alter services, input sources, or registrations. Build products and arbitrary DerivedData remain untouched deliberately.

Validation: install, restart hosts, verify icon and switching, then build/test again and confirm the installed source is still resolved correctly. No claim is made here that a remaining bundle necessarily causes a recurrence.

## 9. Low-Risk Settings and Rendering Polish

**P2/P3 | Confirmed behaviors plus optional UX improvements**

| Opportunity | Evidence | Suggested change |
| --- | --- | --- |
| ~~Unnecessary panel theme work~~ | Implemented | Candidate presentation relies on theme/appearance invalidation instead of reapplying unchanged panel theme properties on every show. |
| ~~Reset scope is implicit~~ | Implemented | The action is named “Reset All Appearance…” and requires confirmation listing its scope. |
| ~~Opacity values are not validated at the persistence boundary~~ | Implemented in Phase 1 | Finite values are clamped to 0...1; non-finite writes are rejected and malformed persisted values fall back safely. |
| ~~Settings location resets~~ | Implemented | The Settings window uses AppKit frame autosave and is no longer recentered on every open. |
| ~~Live settings are hard to preview~~ | Implemented | Appearance includes a fixed-data candidate preview and never simulates host-application input. |
| Keyboard layout is forced | Partially addressed | The US-layout override is documented; Dvorak/AZERTY runtime testing remains required before configurability. |
| ~~First-run guidance lives only in README~~ | Implemented in Phase 1 | The status menu now includes Setup & Shortcuts with manual System Settings instructions and client-mode differences. |

## 10. Tests and Documentation Worth Improving

**P2 | Confirmed coverage limitations | Small to medium effort**

- **Deterministic scheduling — implemented:** transparent prediction uses an injectable delay, and tests release pending refreshes without elapsed-time sleeps. Coverage includes cancellation, coalescing, selection changes, stale UI hiding, immediate selection, and `NSNotFound` fallback.
- **Real-client acceptance:** the repeatable matrix is documented in `REAL_CLIENT_ACCEPTANCE.md`. Execution remains pending until the changed build is installed; mock clients cannot prove Chromium's raw-key forwarding behavior.
- **Installer failure tests — implemented:** the isolated harness now covers ten paths, including missing/invalid/corrupt payloads, successful replacement, rollback after errors and a signal interruption, failed first installation, unwritable destination, and file/directory symlink rejection.
- **Read-only diagnostics — implemented:** `test_diagnose.sh` verifies missing-install behavior and confirms that the diagnostic does not mutate its test home.
- **Refresh the handoff — implemented:** `HANDOFF.md` describes current routing, switching diagnosis, installer behavior, verification, and remaining live checks.
- **Literal-slot flexibility — retained deliberately:** production does not currently show a literal candidate, but the tested API supports future explicit literal selection and has negligible idle/runtime cost. Remove it only as a dedicated simplification if that product option is permanently rejected.

## Remaining Runtime Validation Order

1. **Real clients:** install when convenient and run `REAL_CLIENT_ACCEPTANCE.md` without changing routing during the same pass.
2. **Measurement:** collect privacy-preserving cold/warm latency baselines before considering further scheduling or ranking changes.
3. **UX validation:** test VoiceOver, contrast/transparency settings, caret fallback, scrolling, screen edges, and multiple displays.
4. **Distribution:** test fresh install, upgrade, and rollback using the generated PKG in a disposable environment.

## Guardrails

- Preserve the offline design; no network prediction service is needed for these improvements.
- Keep `client.bundleIdentifier()` as the routing source of truth and preserve the explicit Edge exception.
- Keep native terminals passthrough, VS Code in no-prediction direct-input compatibility mode, and the current Latin input-source metadata.
- Do not introduce persistent marked text in transparent mode just to simplify candidate handling.
- Never replace client text at an unverified location to make a failed correction appear successful.
- Do not automate TIS enable/disable/select operations or `lsregister -u` as part of these suggestions.
- Do not add per-app menu switches contrary to the existing project decision.
- Do not claim performance improvements until measured, or repeat historical test counts as a fresh test run.
