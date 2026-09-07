# SwiftType Improvement Review

Date: 2026-09-07

Scope: input routing, prediction latency, candidate UI, accessibility, settings, installation, packaging, documentation, and tests. This is a source review, not a runtime benchmark or a claim that every potential issue reproduces on this Mac.

Only this report was added for the review. The existing changes to `scripts/install.sh` were left untouched. No installer, input-source modification, service restart, or application-code change was performed during this review. Tests were inspected but not rerun, to avoid recreating discoverable Debug input-method bundles during a documentation-only task.

## Executive Summary

The architecture is appropriately small for an offline input method. Keep the native spell checker, separate client modes, preallocated candidate cells, and conservative text-replacement checks. A large rewrite or a new prediction engine is not justified by the available evidence.

The highest-value next steps are:

1. Make package upgrades and uninstall failures safe and visible.
2. Measure native-app key-handling latency before changing scheduling or suggestion ranking.
3. Explain candidate shortcuts and compatibility differences in the app and documentation.
4. Audit candidate accessibility and improve positioning when caret geometry is unavailable.
5. Add deterministic scheduling tests and a small real-client acceptance matrix.

**Important context:** the user confirmed that restarting the affected applications restored the `S` icon and normal language switching. That supports stale registration/session state as a contributor, but does not isolate which cleanup action was decisive. Do not reopen the resolved incident as a proven current input-controller bug.

The current source explicitly routes Edge and its dotted bundle-ID descendants to **inline** mode (`Input/InputClientPolicy.swift:34-38`). Chrome and WeCom generally use **transparent prediction**. Older descriptions in `HANDOFF.md` do not reflect this distinction.

## Priority Guide

| Priority | Meaning |
| --- | --- |
| P1 | Address first: installation safety or substantial everyday usability/latency risk |
| P2 | Valuable follow-up: robustness, accessibility validation, discoverability, or polish |
| P3 | Optional cleanup or product enhancement |

Confidence labels distinguish **confirmed code behavior**, **runtime validation needed**, and **product suggestion**. Priority is implementation order, not a claim that an unmeasured issue is severe.

## 1. Safer Package Upgrades

**P1 | Confirmed failure paths | Medium effort**

Evidence: `scripts/release/release.sh:109-131` generates a preinstall script that deletes existing system/user installations before the replacement is validated. The generated postinstall at lines 139-171 has no strict error handling, deletes the destination, copies the payload, changes ownership, and removes staging without checking each operation. A failed copy can be followed by successful commands and a success-looking final exit status. Lines 143-146 explicitly report success when there is no GUI user, despite not installing the user-level input method.

Recommendation: validate the target user and staged bundle before touching the existing installation; check all critical operations; keep a recoverable previous version until destination validation succeeds. Report a failed installation as failure. Treat no-GUI-user installs explicitly rather than silently succeeding. Validate the user-home lookup without splitting a path containing spaces. Keep root-run staging controlled and reject unexpected symlinks.

The local installer also updates an existing destination in place using `rsync --delete` (`scripts/install.sh:46-59`). Strict shell behavior catches failure, but does not restore an interrupted update. Preserve the stable installation path if required by input-method registration, while designing an explicit recovery path.

Validation: simulate missing payload, failed copy, unwritable destination, invalid home, and interrupted replacement in an isolated test directory or disposable macOS environment. Assert that the old installation survives or is recoverable and no failed operation reports success. Do not fault-test against the active input method.

## 2. Make Uninstall Errors Actionable

**P1 | Confirmed code behavior | Small effort**

Evidence: `UI/Settings/SettingsWindowControllerAbout.swift:70-91` catches deletion errors, logs only a generic message, then logs completion and terminates regardless. The confirmation at line 58 mentions logout but not manual removal from Input Sources.

Recommendation: return a removal result and show a clear failure or partial-success alert. Distinguish a missing file from a permissions error. Explain that users should switch to another input source and remove the SwiftType entry in System Settings. Do not automatically modify their configured input sources. Preserve preferences unless the user explicitly requests their removal.

Validation: cover missing app, successful removal, failed app removal, and failed Applications-symlink removal. Verify the UI never claims full success after partial failure.

## 3. Measure and Reduce Synchronous Prediction Work

**P1 | Synchronous work confirmed; latency impact unmeasured | Medium effort**

Evidence: inline typing calls `updatePredictions` directly (`Input/Controller/InputControllerKeyHandling.swift:189,199,278`). `InputControllerPredictions.swift:7-20` synchronously fetches suggestions and shows the panel. `Prediction/SpellCheckPredictor.swift:26-62` may call correction, completions, and guesses for one prefix. `UI/Candidate/CandidateWindow.swift:144-168,302-310` adds client queries, layout, sizing, and presentation. Transparent prediction instead coalesces refreshes for 75 ms (`InputControllerTransparentPrediction.swift:214-232`), still executing the eventual work on the main actor.

Recommendation: instrument key-handler duration, individual spell-check stages, client geometry queries, and candidate rendering. Record cold-first-word and warm p50/p95/p99 times separately in TextEdit, Safari, Edge, and Chrome. Also measure time from key press to visible suggestions; shorter handler time alone can hide a worse perceived delay.

Start with redundant UI work, then consider coalescing inline prediction refreshes if measurements justify it. Keep text composition immediate. Do not move AppKit work to a detached task without validating isolation requirements. Do not blindly copy the 75 ms delay: fast digit/Space/Return handling currently depends on candidate visibility and selection state.

If spell correction dominates, evaluate a bounded short-lived cache or a different invocation threshold against suggestion quality. Changing correction-first ordering can alter expected typo fixes, so it is not a free optimization. Avoid persisting typed-prefix caches.

Validation: compare typing, backspace, immediate candidate selection, and immediate language switching before/after. Report CPU and allocation changes as well as latency. Never log actual typed words or surrounding document text in performance diagnostics.

## 4. Keep Deferred Candidates Tied to Their Input State

**P2 | Guard gap confirmed; user-visible failure needs reproduction | Medium effort**

Evidence: the delayed task checks cancellation, mirror mode, and buffer equality, but not current selection before displaying (`InputControllerTransparentPrediction.swift:214-232`). Stale-client checks run at the next keydown (`:17-18,197-212`). Existing candidates also remain visible while a changed prefix waits for its refresh (`:125-137,152-156`).

Recommendation: explicitly associate candidates with a composition generation/prefix. Decide whether stale candidates should disappear, be temporarily unselectable, or remain selectable as displayed. Revalidate available client/selection information before a delayed show, without treating an unreliable client identifier as universally authoritative. Keep app-switch cancellation intact.

Validation: queue a refresh, change selection or field before it fires, and verify stale UI is not shown. Test type/backspace followed immediately by a digit. Include clients returning `NSNotFound`; do not sacrifice safe fallback behavior to enforce a range that the client cannot provide.

## 5. Explain the Actual Candidate Controls

**P1 | Documentation mismatch confirmed | Small effort**

Evidence: the default is Vertical List (`UI/Theme/ThemeManager.swift:62`), while `README.md:67-87` explains a collapsed grid and active-row column selection. Production predictions start with no selected candidate (`CandidateWindow.swift:147-149`). Transparent mode passes arrows and Tab through while dismissing candidates (`InputControllerTransparentPrediction.swift:44-46`), unlike inline navigation.

Recommendation: document Vertical and Grid separately, and distinguish inline from transparent-mode controls. Explain that a visible list is not necessarily a selected suggestion, and that Space without a selection preserves literal typing. Describe digit labels in terms of the visible slots, not a fixed universal column count.

Add a compact in-app Shortcuts/Help entry. In transparent mode, do not advertise arrow-based selection that the implementation intentionally does not consume. Explain why terminals and VS Code have no suggestions rather than letting users assume the input method failed.

Validation: give a new user only the in-app help and ask them to select a suggestion, retain a literal word, enter a number, and switch languages in TextEdit and Chrome.

## 6. Audit Candidate Accessibility

**P2 | Missing explicit semantics confirmed; actual VoiceOver behavior untested | Medium effort**

Evidence: candidate cells are custom highlight containers with attributed text labels (`UI/Candidate/CandidateView.swift:5-52,349-371`). Selection is expressed visually; there is no explicit candidate-list accessibility model in that file or `CandidateWindow.swift`. Native text fields may still expose some content automatically, so this is not proof that the entire panel is inaccessible.

Recommendation: inspect the live accessibility tree first. Expose each candidate's text, shortcut, and selection state with an appropriate container structure. Ensure hidden/preallocated cells do not appear as stale suggestions. Support assistive navigation without stealing keyboard focus from the host application. Announcements should be restrained and user-tested, not emitted on every keystroke.

Validation: VoiceOver, keyboard-only use, Increase Contrast, Reduce Transparency, light/dark appearance, and custom low-contrast themes. Confirm the host caret remains focused while candidates are explored.

## 7. Make Candidate Placement More Stable

**P2 | Fallback behavior confirmed; impact client-dependent | Small to medium effort**

Evidence: missing caret geometry falls back to `NSEvent.mouseLocation` (`UI/Candidate/CandidateWindow.swift:313-323`). Expand/reframe uses `lastCursorRect` (`:295-299`). A stationary pointer on another monitor can therefore become the fallback anchor even while typing elsewhere.

Recommendation: prefer a valid recent caret rectangle from the same input session before falling back to the mouse. Clear cached anchors on session changes. Re-query only when needed so positioning improvements do not add expensive client IPC to every navigation event. Do not substitute `NSWorkspace.frontmostApplication` for the actual IMK client.

Validation: two monitors, scrolling, moving between fields, full-screen windows, screen edges, and clients reporting zero/unknown geometry. Treat changing the hardcoded character-index query as an experiment, not an assumed fix; IMK client conventions differ.

## 8. Finish Installation Diagnostics Without Broad Side Effects

**P2 | Remaining artifacts and service scope confirmed | Medium effort**

Evidence: `scripts/install.sh:21-24` removes one project Debug bundle and line 36 disables build-time LaunchServices registration, but the built Release bundle remains after installation. DerivedData copies are not addressed. Lines 55-58 restart shared input UI services, including forced termination of the switcher and cursor service. The release build at `scripts/release/release.sh:57-69` does not use the same registration setting.

Recommendation: distinguish normal installation from an explicit repair/diagnostic operation. Keep ordinary restart scope minimal; document broader service resets as potentially affecting other input methods. Review build-artifact discoverability across local builds, tests, and packages rather than assuming one build setting eliminates every duplicate-registration path. Never delete arbitrary DerivedData trees or unregister sources automatically.

Add an opt-in, read-only diagnostic summary: running bundle path, version/build, configured policy mode, and relevant input-source/icon metadata. Avoid document text and redact personal paths before sharing. The existing instruction to quit/reopen host apps is useful and should remain.

Validation: install, restart hosts, verify icon and switching, then build/test again and confirm the installed source is still resolved correctly. No claim is made here that a remaining bundle necessarily causes a recurrence.

## 9. Low-Risk Settings and Rendering Polish

**P2/P3 | Confirmed behaviors plus optional UX improvements**

| Opportunity | Evidence | Suggested change |
| --- | --- | --- |
| Unnecessary panel theme work | `UI/Candidate/CandidateWindow.swift:84-95,100-124,144` | Rely on theme/appearance invalidation where possible instead of rewriting unchanged layer properties on every show. Preserve dynamic appearance handling. |
| Reset scope is implicit | `UI/Settings/SettingsWindowControllerCustomization.swift:24,135-137`; `UI/Theme/ThemeManager.swift:144-155` | Rename to "Reset All Appearance"; consider undo or confirmation because layout, rows, columns, opacity, and colors all reset. The button is already below the complete form, not inside the Colors section. |
| Opacity values are not validated at the persistence boundary | `UI/Theme/ThemeManager.swift:86-87,175-179` | Clamp finite values to 0...1 and reject non-finite values; test malformed stored preferences as well as slider input. |
| Settings location resets | `UI/Settings/SettingsWindowController.swift:67` | Remember the window frame instead of centering on every open. |
| Live settings are hard to preview | `UI/Settings/SettingsWindowControllerCustomization.swift:6-39` | Add a small fixed-data candidate preview if customization is important; avoid simulating input into another application. |
| Keyboard layout is forced | `Input/Controller/InputControllerLifecycle.swift:13` | Document the US-layout override and test Dvorak/AZERTY before deciding whether configurability is appropriate. Do not remove it without auditing physical key-code shortcuts. |
| First-run guidance lives in README | `README.md:54-59`; `App/StatusBarController.swift` | Add an "Enable SwiftType" help action with manual System Settings instructions. Do not force-enable or select input sources. |

## 10. Tests and Documentation Worth Improving

**P2 | Confirmed coverage limitations | Small to medium effort**

- **Deterministic scheduling:** `Tests/Input/InputControllerTransparentPredictionTests.swift` uses elapsed-time waits for delayed refreshes. Inject a controllable delay/clock where practical; cover cancellation, coalescing, field changes, and immediate selection without long sleeps.
- **Real-client acceptance:** mock clients cannot prove Chromium's raw-key forwarding behavior. Test Chrome/WeCom separately from Edge, including letters, punctuation, Backspace, correction replacement, Space, Return, and language switching. Only add a Chromium-behavior simulator after validating its model against real clients.
- **Installer failure tests:** the package generator's embedded scripts deserve isolated failure-path tests, not just shell syntax checks.
- **Refresh the handoff:** `HANDOFF.md:3,14-18,43,72-80` describes an older installation and letter-pass-through design. Current transparent typing calls `insertText` and consumes printable keys (`InputControllerTransparentPrediction.swift:152-173`). Document verified behavior and the now-resolved local switching incident; do not infer that this documentation mismatch proves duplicate typing today.
- **Review unused flexibility:** the production `CandidateWindow.show` call does not supply `literalText` (`InputControllerPredictions.swift:16-20`), while considerable UI/test code supports it. Decide whether it is a planned product capability before maintaining or deleting it. This is cleanup, not a performance priority.

## Suggested Delivery Order

1. **Safety and clarity:** fix installer/uninstaller failure reporting, update handoff and shortcut documentation, and add in-app enablement/help instructions.
2. **Measurement:** establish a privacy-preserving latency baseline and real-client acceptance checklist before tuning prediction scheduling.
3. **Targeted responsiveness:** remove measured redundant work and strengthen deferred candidate freshness without changing immediate text insertion.
4. **UX quality:** validate accessibility, improve same-session caret fallback, and add focused settings polish.

## Guardrails

- Preserve the offline design; no network prediction service is needed for these improvements.
- Keep `client.bundleIdentifier()` as the routing source of truth and preserve the explicit Edge exception.
- Keep Terminal/VS Code passthrough and the current Latin input-source metadata.
- Do not introduce persistent marked text in transparent mode just to simplify candidate handling.
- Never replace client text at an unverified location to make a failed correction appear successful.
- Do not automate TIS enable/disable/select operations or `lsregister -u` as part of these suggestions.
- Do not add per-app menu switches contrary to the existing project decision.
- Do not claim performance improvements until measured, or repeat historical test counts as a fresh test run.
