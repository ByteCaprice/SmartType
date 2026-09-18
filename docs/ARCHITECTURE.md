# SmartType Architecture

This document describes the current design. SmartType is an English-only, offline macOS input method built with Swift 6, AppKit, InputMethodKit, and `NSSpellChecker`.

## Runtime overview

```text
macOS → IMKServer → InputController
                    ├── InputClientPolicy
                    ├── LatinKeyHandler
                    ├── InputControllerTransparentPrediction
                    ├── SpellCheckPredictor + SmartSpacePolicy
                    └── CandidateWindow
```

| Area | Main files | Responsibility |
| --- | --- | --- |
| Startup | `main.swift`, `App/` | Application lifecycle, IMK server, status menu, privacy-safe logging |
| Input controller | `Input/Controller/` | Event routing, composition, predictions, lifecycle, transparent commits |
| Client policy | `Input/InputClientPolicy.swift` | Bundle-ID-based mode selection and runtime overrides |
| Key behavior | `Input/KeyHandling/LatinKeyHandler.swift`, `Rules/` | English input, punctuation, capitalization, candidate actions |
| State | `Input/State/` | Composition, prediction snapshots, candidate navigation |
| Prediction | `Prediction/` | Local spell-check evidence, ranking, and Smart Space policy |
| Candidate UI | `UI/Candidate/` | Nonactivating candidate panel, layout, selection, accessibility |
| Settings | `UI/Settings/`, `UI/Theme/` | Appearance, preview, About, reset, uninstall |
| Distribution | `scripts/` | Transactional installation, diagnostics, packaging, shell tests |

Application and AppKit state is main-actor isolated. IMK callback overrides enter that state with `MainActor.assumeIsolated`. The candidate window is process-wide; composition state belongs to each controller.

## Client routing

Routing uses `IMKTextInput.bundleIdentifier()`, not the frontmost application. The actual text client may differ from the foreground app.

Policy precedence is:

1. Missing bundle ID: inline.
2. SmartType's own UI: passthrough.
3. Microsoft Edge and descendants: inline.
4. VS Code or a custom direct-input entry: direct input.
5. Known native terminals: passthrough.
6. Known/custom Chromium or CEF clients: transparent prediction.
7. Everything else: inline.

| Mode | Typical clients | Contract |
| --- | --- | --- |
| Inline | TextEdit, Safari, Xcode, Edge | Marked composition, synchronous predictions, full candidate navigation |
| Transparent prediction | Chrome, Brave, Vivaldi, Opera, WeCom, DingTalk | Text is committed immediately; local mirror supports safe predictions without persistent marked text |
| Direct input | VS Code | Printable text uses a compatibility commit; no candidates; commands remain host-owned |
| Passthrough | Terminal, iTerm2, Ghostty and other terminal families | SwiftType does not intercept typing or show candidates |

Runtime recovery arrays in the `com.matthew.inputmethod.SwiftType` defaults domain are:

- `transparentPredictionBundleIdentifiers`
- `directInputBundleIdentifiers`
- `markedTextPrimingBundleIdentifiers`

Entries match exact bundle IDs or dotted helper descendants. These are targeted recovery options, not universal compatibility switches. Finish composition, quit the affected app, change only the appropriate array, and reopen the app.

## Composition invariants

### Inline mode

SwiftType owns the uncommitted text. Letters update `compositionBuffer`, marked text, predictions, and the candidate panel. A commit inserts the literal or selected candidate exactly once and clears local state.

During a language switch, SwiftType clears the marked range before inserting the pending literal, then returns the event to macOS. See [Input-method switching](INPUT_METHOD_SWITCHING.md).

### Transparent mode

The host already owns every typed character. SwiftType owns only a mirror used for prediction.

Therefore:

- Lifecycle cleanup and source switching discard the mirror; they never insert it again.
- Backspace updates the mirror but remains host-owned.
- Prefix completion may append a verified suffix.
- Correction or case-changing replacement requires a verified document range.
- If replacement cannot be verified, the implementation falls back to literal typing.
- Pending prediction work is generation-, buffer-, client-, and cursor-validated before presentation or commit.

WeCom and DingTalk use a temporary `setMarkedText` → `insertText` handshake for direct commits. VS Code uses the same compatibility shape without prediction. The marked phase is completed synchronously and must not become persistent composition.

### Host-owned controls

Command, Control, Option, Return, Escape, arrows, and Tab remain host-owned where the selected client mode requires it. Do not add asynchronous insertion retries: delayed client-state changes can turn a retry into duplicate text.

## Prediction and candidate presentation

Prediction is local and fixed to `en_US`. `SpellCheckPredictor` gathers exact-completion evidence, strict prefix completions, an optional correction, guesses, and learned-word evidence. `SmartSpacePolicy` chooses a default action without changing explicit selection.

A `PredictionSnapshot` binds alternatives and the default action to the current buffer. Automatic acceptance requires a fresh matching snapshot and visible candidate presentation. See [Smart Space](SMART_SPACE.md).

The candidate window supports vertical and grid layouts, preallocated cells, accessibility labels/actions, theme customization, and caret-position fallback. Default-action indicators are presentation state; they are not explicit selection.

## Privacy and diagnostics

SmartType does not use network prediction or typed-text telemetry. Logs and Points of Interest contain fixed operation names and timing only, never words, candidates, document text, or clipboard contents.

`scripts/diagnose.sh` reports installation and runtime metadata. `scripts/diagnose-input-sources.swift` observes public Text Input Source state and bounded source-change notifications. Neither diagnostic reads typed/document text or changes input sources.

## Installation and removal

`scripts/install.sh` and PKG scripts share `scripts/release/pkg-scripts/install-common.sh`. Installation validates the source, stages a same-directory copy, verifies it, retains the previous bundle during replacement, and rolls back on failure.

The normal installer refreshes the text-input menu/switcher agents but does not broadly restart InputMethodKit services. Persistent session cache problems should be handled by reopening affected apps or logging out and back in, not by unsafe automatic registry or preference mutation.

Uninstall removes only audited SmartType artifacts. User input-source preferences and unrelated applications remain user-controlled.

## Non-negotiable safety rules

- Let macOS own input-source switching; do not redirect ABC or call TIS selection APIs from the controller.
- Preserve required English/Latin metadata and the US keyboard-layout override unless a separately tested layout project replaces it.
- Keep routing based on the IMK client bundle ID.
- Keep native terminals passthrough, Edge inline, and VS Code direct input unless real-client evidence supports a targeted change.
- Never commit mirrored transparent text during lifecycle cleanup.
- Never replace an unverified document range.
- Do not log or persist user-entered text for diagnostics or optimization.
- Do not weaken transactional installation, rollback, signature, symlink, or ownership checks.
