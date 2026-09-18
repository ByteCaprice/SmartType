# SwiftType Developer Handoff

> **Archived:** This is a dated development handoff preserved for historical context. For current documentation, start at [`docs/README.md`](../README.md). Build numbers, branches, assignments, and pending work below are not current.


Last updated: 2026-09-09

This document supersedes the previous 2026-09-04 handoff. It describes the current source, the local troubleshooting outcome, pending changes, and the recommended next work. Historical observations are explicitly labeled; do not mistake them for fresh checks or current failures.

## 1. Start Here

SwiftType is an English-only, offline macOS input method built with Swift 6, AppKit, InputMethodKit, and the system spell checker. It offers word completions/corrections through a floating candidate panel. It has no network prediction dependency.

**Current user-visible status:** after the installed guide-compliant build encountered a stale `imklaunchagent` connection refusal, restarting macOS restored normal input and Caps Lock language switching in TextEdit and Spotlight. SwiftType is operating normally. Preserve this known-good routing and input-source metadata.

**Current assignment:** validate the implementation of [original Smart Space research](SMART_SPACE_RESEARCH_2026-09.md) on the `smart-space` branch while preserving the completed improvement-review work. Smart Space retains exact-word evidence, prefers strict prefix completions over corrections, and gives Space a visible default action without creating an explicit candidate selection. The latest full isolated suite passes 596 tests (585 existing plus 11 new compatibility regressions). The client-compatibility patch for dropped input in VS Code Monaco, WeCom 5.0.10, and DingTalk 8.5.0 is unit-verified and installed for live validation as build `20260909100351`, with a valid signature and universal `x86_64 arm64` executable matching the current Release build. The user subsequently confirmed that typing works well; the installed process and signature were rechecked during the reliability audit. This is general user confirmation, not a completed per-application acceptance matrix. The user then authorized installation of the defensive Caps Lock stale-buffer fix: build `20260909103324` is now installed, signature-valid and universal, and matches the new Release executable. No SwiftType process was observed immediately after replacement; reopen clients and select SwiftType to reconnect. Real-client, VoiceOver, positioning, and latency checks remain necessary.

### Reliability audit — 2026-09-09

- Independent delivery and candidate/state reviews found no reproduced main-path dropped-input defect. Host delivery remains a live-only boundary; do not add speculative insertion retries that could duplicate text.
- Added a no-write passthrough/direct-input guard to `commitCompositionForLanguageSwitch`, consistent with lifecycle commits. It prevents stale composition from being inserted on Caps Lock if incompatible state reaches such a client; normal typing does not produce this state. New regression tests cover both modes, activation/deactivation, direct-input commands and primed literal Space.
- Authoritatively verified 596 passed, zero failed/skipped in `/tmp/SwiftTypeTesterFull-C8149C5A-AAA1-4137-96E4-BE5ACEA02088.xcresult`; matching full log uses the same basename with `.log`. Focused tests: `/tmp/SwiftTypeTesterFocused2.xcresult` (11 passed).
- Installer harness 10/10, diagnostic harness, shell syntax, whitespace, changed-Swift LSP checks passed; session diagnostics contain hints only. Unsigned universal Release built in `/tmp/SwiftTypeReliabilityRelease.As9Zuu`; log `/tmp/swifttype-reliability-release.log`. No installation or input-service restart was performed. Xcode did emit LaunchServices registration for temporary products despite the disable request.
- Residual checks: VS Code editor versus raw-mode integrated terminal, Option/dead keys, rapid focus/source switching, sleep/wake, and newly updated apps. Finish a composition and close the affected host before changing recovery routing preferences; policy is read dynamically, not pinned to a session.
- Following the audit, the user authorized installation of the Caps Lock hardening. Build `20260909103324` replaced `20260909100351`; signature, `x86_64 arm64` architectures, and installed/Release executable equality passed. Install log: `/tmp/swifttype-caps-lock-hardening-install.log`. The install script stopped SwiftType and refreshed TextInputMenuAgent/TextInputSwitcher; no broad IMK service restart was performed. The compatibility changes and audit are included in the work being merged into `main`.

Recommended first steps for the next developer:

1. Read this document and the archived [improvement review](IMPROVEMENT_REVIEW_2026-09.md).
2. Check `git status`, inspect the installer-hardening history, and preserve all existing work.
3. Choose a small, agreed improvement, preferably installation safety or documentation/UX clarity before speculative optimization.
4. Read the relevant implementation and tests; preserve client-specific input behavior.
5. Run targeted/full verification as appropriate, recording fresh results and any generated input-method bundles.
6. Do not reinstall or reset system services just to read the project. The user's current setup works.

## 2. Repository and Worktree

| Item | State verified while preparing this handoff |
| --- | --- |
| Workspace | Local checkout (personal home paths redacted) |
| Branch | `main` |
| Current baseline | Smart Space, client compatibility, and Caps Lock hardening; consult `git log` for current hashes after the privacy rewrite |
| Earlier implementation commits | `02f45be` - prediction/candidate reliability; `45aa8ba` - English-only input, Caps Lock switching, and per-app modes |
| Private tracking branch | `github/main`; the feature work is being merged for publication preparation |
| Private working remote | `github` = `https://github.com/ByteCaprice/SmartType.git` |
| Public upstream | `origin` = `https://github.com/mgxv/SwiftType.git` |

Always refresh remote state before publishing; branch information in documentation becomes historical immediately. Never accidentally push private work to `origin`. The remote switching guide was copied into the worktree as a specification only; remote source did not replace local `main`.

The installation, prediction, compatibility, and UI improvements below are included in the feature work being merged into `main`. Historical hashes in this document predate the privacy rewrite and must not be treated as current references. SmartType is the repository/README name only; application identifiers and code remain unchanged. Only the repository owner's local commit identities and personal home paths are anonymized; upstream authorship is preserved. The repository remains private pending a separate publication decision.

## 3. Installed Application and Local Environment

| Item | Value / evidence status |
| --- | --- |
| Intended installation | `~/Library/Input Methods/SwiftType.app` |
| Bundle and input-source ID | `com.matthew.inputmethod.SwiftType` |
| Installed short version | `1.0`, reread from installed `Info.plist` for this handoff |
| Installed build version | `20260907020122`, reread for this handoff |
| Connection name | `com.matthew.inputmethod.SwiftType_Connection` |
| Controller class | `InputController` |
| Minimum supported macOS | `13.0` |
| Architectures/signature | Universal `x86_64 arm64`, signature valid during preceding installation verification; not rechecked in this documentation task |
| Local machine | Previously observed MacBook Air `Mac17,3`, Apple M5 |
| Local macOS | Previously observed `26.6.2 (25G83)` |

The installed app was built/installed after syncing `02f45be` in the preceding session. Do not assume future source or script edits are automatically installed. About displays the short version, so the build number is useful for distinguishing local installations.

Input-source metadata that must remain intact:

```text
TICapsLockLanguageSwitchCapable = true
TISIntendedLanguage = en
tsInputMethodCharacterRepertoireKey = [Latn]
TISInputSourceID = com.matthew.inputmethod.SwiftType
TISIconIsTemplate = true
tsInputMethodIconFileKey = SwiftTypeInputSourceIcon.png
```

The input-source icon is `Resources/SwiftTypeInputSourceIcon.png`, a 32x32 template `S`. The app icon and the status-menu display are separate: the status item currently uses text `EN`. A bundled `SwiftTypeMenuIcon.png` is not the same as the TIS icon.

## 4. Architecture Map

| Area | Main files and responsibilities |
| --- | --- |
| Startup | `main.swift`, `App/AppDelegate.swift`, `App/NSManualApplication.swift`: application and IMK server setup |
| Status menu | `App/StatusBarController.swift`: `EN`, Settings, Quit |
| Controller | `Input/Controller/InputController.swift`: per-controller state, lazy predictor, pending refresh task |
| Client policy | `Input/InputClientPolicy.swift`: pure/testable bundle-ID routing |
| Key events | `Input/Controller/InputControllerKeyHandling.swift`: keyDown/flagsChanged, inline input, navigation, auto-space checks |
| Transparent input | `Input/Controller/InputControllerTransparentPrediction.swift`: immediate printable insertion, mirrored buffer, deferred predictions, verified replacement |
| Composition | `Input/Controller/InputControllerComposition.swift`: literal/candidate commits and marked text |
| Lifecycle | `Input/Controller/InputControllerLifecycle.swift`: activation/deactivation, commit/cancel callbacks |
| Cancellation | `Input/Controller/InputControllerStateManagement.swift`: cancel task, clear predictions, hide panel |
| English behavior | `Input/KeyHandling/LatinKeyHandler.swift`, `Rules/Conformers/EnglishRules.swift`: candidate commits, capitalization, punctuation/contractions |
| State | `Input/State/InputState.swift`, `Input/State/GridCandidateState.swift`: input state and candidate navigation |
| Prediction | `Prediction/SpellCheckPredictor.swift`: `en_US` correction, prefix completions, fuzzy guesses |
| Candidate UI | `UI/Candidate/CandidateWindow.swift`, `CandidateView.swift`: shared nonactivating panel, preallocated cells, selection, positioning |
| Settings | `UI/Settings/SettingsWindowController*.swift`: Appearance, About, uninstall |
| Theme | `UI/Theme/ThemeManager.swift`, `Theme.swift`, `NSColorHex.swift`: preferences, semantic defaults, customization |
| Logging | `App/Log.swift`; privacy behavior covered by `Tests/App/PrivacyLoggingTests.swift` |
| Distribution | `scripts/install.sh`, `scripts/release/release.sh` |

The application uses main-actor-isolated state. IMK callback overrides use `MainActor.assumeIsolated` at the callback boundary. Do not casually move AppKit/IMK work into detached tasks. The candidate window is process-wide, while composition state belongs to each controller.

## 5. Current Client Routing

Read `InputClientPolicy.mode`, not just `usesTransparentPrediction`, when determining the effective mode. The controller's wrapper calls `mode`, preserving its exceptions.

Routing priority:

1. Missing/empty bundle ID: inline.
2. The app's own bundle ID: passthrough.
3. `com.microsoft.edgemac` or a dotted descendant (`com.microsoft.edgemac.*`): inline.
4. VS Code or a custom direct-input entry: direct compatibility input.
5. Known native terminal IDs: passthrough.
6. Transparent custom entries, known IDs/prefixes, or Chromium-family heuristic: transparent prediction.
7. Everything else: inline.

| Mode | Current examples | Behavior |
| --- | --- | --- |
| Inline | TextEdit, Safari, Xcode, Edge and its dotted bundle descendants | Marked-text composition and synchronous predictions |
| Passthrough | Terminal, iTerm2, Ghostty, WezTerm, kitty, Alacritty, Warp, Hyper, Termius, own UI | Keydown returns false; no composition or suggestions |
| Direct input | VS Code | No suggestions; temporary mark-and-commit for printable text; commands/navigation remain host-owned |
| Transparent prediction | Chrome, Chromium, Brave, Arc, Opera, Vivaldi, WeCom/DingTalk and known helpers | No persistent marked text; mirrored state and delayed predictions; affected CEF clients use temporary mark-and-commit |

**Important correction from the old handoff:** Edge is deliberately inline in current code. Do not move it back to transparent mode based on the old incident narrative. The README explains that its fields drop modeless input.

Compatibility can be changed without rebuilding through three UserDefaults arrays: `transparentPredictionBundleIdentifiers`, `directInputBundleIdentifiers`, and `markedTextPrimingBundleIdentifiers`. Entries match exact IDs or dotted helper descendants. A custom transparent entry automatically receives marked-text priming; custom direct input overrides built-in terminal passthrough. Edge and SwiftType's own process remain hard exceptions. Known helpers include `88L2Q4487U.com.tencent.wework`; the Chromium heuristic still checks substrings such as `chrome` and `chromium`.

Examples for a newly problematic app:

```bash
defaults write com.matthew.inputmethod.SwiftType transparentPredictionBundleIdentifiers -array-add 'com.example.NewApp'
defaults write com.matthew.inputmethod.SwiftType directInputBundleIdentifiers -array-add 'com.example.NewApp'
defaults write com.matthew.inputmethod.SwiftType markedTextPrimingBundleIdentifiers -array-add 'com.example.NewApp'
```

Choose one based on the documented behavior; do not write all three casually. Quit and reopen the affected app after changing policy. Do not add a per-app menu based on `NSWorkspace.frontmostApplication`, because it may not identify the actual IMK client.

## 6. Key Handling and Text Safety

### Inline Mode

- Letters and continuation apostrophes accumulate in `compositionBuffer`, update marked text, and immediately fetch/render predictions.
- Backspace edits composition and is consumed when the buffer is nonempty; otherwise it passes through.
- Digits choose a populated visible candidate slot when Shift is not held. Empty slots commit the literal composition and let the digit through.
- Space commits an explicitly selected candidate first. Otherwise it accepts a fresh visible Smart Space candidate or preserves the literal buffer, with a trailing space. With no composition/selection, it passes through.
- Return while the panel is visible commits the selected candidate or literal buffer without a trailing space and is consumed. With the panel hidden, any buffer is committed and Return passes through.
- Escape commits literal text and dismisses; it is consumed only if composition/panel content existed.
- Arrows/Tab navigate when the panel is visible. Otherwise they commit composition and pass through.
- Command/Control/Option combinations commit composition and pass through.
- Language switching clears marked text synchronously, commits pending literal text, and leaves the switch event to macOS.

### Transparent Mode

The previous handoff said letters passed through without any client write. That is no longer the implementation. Current printable handling commits text and returns true, while maintaining a mirror and leaving no persistent marked text. WeCom and DingTalk require `setMarkedText(text)` immediately followed by `insertText(text)`; other transparent clients retain direct insertion.

| Event | Current behavior |
| --- | --- |
| Letter or continuation apostrophe | Append mirror, insert the character, schedule prediction refresh, consume |
| Ordinary number/punctuation/symbol not handled as selection | Discard mirror, insert character, consume |
| Backspace | Update mirror and expected cursor, schedule refresh or clear; return false so host deletes once |
| Space with a fresh visible Smart Space candidate | Insert a safe suffix or verified replacement; otherwise fall back to literal space |
| Space without a successful candidate commit | Discard mirror, explicitly insert space; record trailing-space state when applicable |
| Return without selection | Discard mirror and pass through; retain normal host submit/newline behavior |
| Digit on a populated slot | Attempt safe candidate commit; on failure fall back to ordinary character handling |
| Escape/arrows/Tab | Discard mirror and pass through; do not implement inline candidate navigation here |
| Command/Control/Option | Discard mirror and pass through |
| Multi-character/dead-key input | Discard mirror when applicable and pass through |
| Caps Lock flagsChanged | Discard mirror only, no duplicate buffer insertion; return false |

At the start of a nonempty mirrored keydown, stale detection checks bundle ID, nonempty selection, and expected cursor location. `NSNotFound` selection degrades conservatively. The baseline/expected cursor use UTF-16 lengths where client ranges require them.

Transparent candidate commit has two successful paths:

1. If the chosen word has the exact-case typed prefix and the suffix including optional space has UTF-16 length greater than one, insert only that suffix.
2. Otherwise require document-access support and a verified substring matching the typed buffer case-insensitively. In one synchronous event, set marked text over that verified range and immediately insert the committed text, ending marked composition.

If neither path is safe, discard mirrored state and return false. Do not replace arbitrary ranges to force a correction. `transparentSuffix` currently uses case-sensitive `hasPrefix`; the old handoff's claim that this path was case-insensitive was incorrect.

Lifecycle commits in mirror mode must only discard the mirror: the text already exists in the host. `composedString`/`originalString` expose an empty composition for mirrored state. `discardMirroredComposition` clears baseline/cursor/client identity and cancels predictions.

Automatic punctuation cleanup verifies the same client, expected collapsed cursor, and an actual preceding space before replacing that space. On verification failure, it inserts punctuation without deleting unverified text. Keep this safety property.

### Chromium Compatibility Caution

Historical investigation of Chromium identified a marked-text/multi-character-insertion gate for raw-key forwarding. A simplistic "consume key, do not set marked text, do not insert anything" implementation can leak or duplicate events. Persistent marked text can also interfere with language switching in some clients.

Live testing on 2026-09-09 established three dropped-input failures: VS Code 1.136.2 Monaco editors under bare passthrough, WeCom 5.0.10 under single-character direct insertion, and DingTalk 8.5.0 under inline composition. VS Code's integrated terminal still accepted raw passthrough, proving that bundle-ID routing cannot distinguish its editor and terminal surfaces. The compatibility implementation therefore gives VS Code no predictions but commits printable text through a synchronous temporary marked phase; control/navigation keys still pass through. WeCom and DingTalk use the same temporary handshake inside transparent prediction. Unit tests verify call order and state, but real clients must confirm delivery exactly once.

Upstream precedent: Rime Squirrel's `force_marked_text_for_direct_commit` performs the same `setMarkedText` then `insertText` sequence because some `NSTextInputClient` implementations require a marked phase before accepting direct commits. Chromium `content/app_shim_remote_cocoa/render_widget_host_view_cocoa.mm`, fcitx5-macos dummy preedit, and macSKK Direct Mode remain related references.

## 7. Prediction, UI, and Settings

- `NSSpellChecker` is local, fixed to `en_US`, with a per-predictor spell-document tag. Results are correction first, then completions, then guesses; case-insensitive duplicates and the literal prefix are excluded.
- `Constants.spellCompletionLimit` is five. Do not confuse the five-result limit with the maximum number of preallocated grid cells.
- Inline prediction work is synchronous in key handling. Transparent refreshes cancel/coalesce for 75 ms, then run spell-check/UI work on the main actor. Coalescing is not background spell-checking.
- Default layout is Vertical List; default rows are four, options three/four/five. Grid columns default to five, options four/five/six. Preallocation supports up to five rows and seven columns.
- Production calls supply predictions only, no literal candidate slot. The panel starts without an active selection. A separate Smart Space action marks the automatic candidate or shows a reason-aware `✓ Exact match` / `✓ Keep typed` literal indicator; it does not change Return/navigation selection state. Literal-slot support remains in UI code/tests but is not used by normal prediction display.
- Vertical digit labels refer to visible rows. Inline arrows/Tab activate and move selection; grid navigation uses active rows/columns. Transparent arrows/Tab dismiss instead.
- Candidate cells are preallocated and theme fonts/colors are partly cached. The window still reapplies layer theme work on each show and queries host geometry/window level.
- Caret geometry currently comes from `attributes(forCharacterIndex: 0, ...)`; invalid origin falls back to the mouse. Expand/reframe uses a cached rectangle. Do not assume another index is universally correct across IMK clients without testing.
- Appearance uses semantic system defaults unless customized. Some hex-default helpers use a separate palette; see the review before attempting consolidation.
- Reset clears colors, opacity, grid dimensions, and layout. About offers uninstall; the status menu offers Quit. Both destructive/lifecycle flows deserve careful UX review.
- Activation explicitly overrides to the US keyboard layout. Non-QWERTY support is a product/compatibility decision, not a safe one-line deletion.

## 8. Resolved Local Switching/Icon Incident

### Symptoms and Evidence

Before cleanup, Edge/TextEdit and Terminal behaved differently when pressing the Chinese/English (Caps Lock) key. Some applications displayed an old crossed-arrow/generic icon instead of the `S`. A single-step observation also found a switch to `com.apple.keylayout.ABC`, so a visual "uppercase/lowercase" impression was not sufficient to prove a hardware Caps Lock change.

Historical read-only checks repeatedly showed `HIDCapsLockState = No` and `HIDCapsLockLEDOn = No`. Other observed preferences were `TISRomanSwitchState = 1`, `AppleCapsLockPressAndHoldToggleOff = 0`, HID `CapsLockLanguageSwitch = Yes`, and no `hidutil UserKeyMapping`. These are historical observations, not instructions to write those values.

Input-source queries made after switching back to ChatGPT reported Simplified Pinyin (`com.apple.inputmethod.SCIM.ITABC`). Because per-app/document input context can restore a different source, cross-app queries can misrepresent what happened in the target field. Test before/after in the same host context.

Multiple discoverable bundles shared the same ID:

```text
~/coding/SwiftType/build/Debug/SwiftType.app
~/coding/SwiftType/build/Release/SwiftType.app
~/Library/Developer/Xcode/DerivedData/SwiftType-<build-id>/Build/Products/Debug/SwiftType.app
~/Library/Input Methods/SwiftType.app
```

The project Debug bundle had old icon metadata, lacking `tsInputMethodIconFileKey` and `TISIconIsTemplate`. Its presence plus long-lived input UI/IMK sessions was a plausible source of stale behavior.

### Actions Already Performed

1. Synced `02f45be`, ran the full tests successfully, built and installed Release, and checked signature/architectures/version.
2. Removed only the three identified rebuildable project/DerivedData `.app` copies above, retaining the intended installation.
3. Verified Spotlight's bundle-ID query then returned only the intended installed bundle.
4. Ran LaunchServices garbage collection and force-registered the intended bundle. Did not use `lsregister -u`.
5. Restarted SwiftType, `imklaunchagent`, and `TextInputMenuAgent`; forcibly terminated long-lived `TextInputSwitcher` and `CursorUIViewService` instances.
6. Confirmed the TIS icon URL resolved to the installed `Contents/Resources/SwiftTypeInputSourceIcon.png`. Source and installed icon hashes matched at that time.
7. Asked the user to save documents, completely quit the affected hosts, reopen them, and test. The user confirmed both the `S` icon and normal switching, then confirmed all affected apps switched normally.

**Conclusion:** stale duplicate registration/metadata and existing host sessions were likely contributors. Several cleanup actions preceded success, so the exact contribution of each is not experimentally isolated. Do not claim this proved all Chromium switching issues are cache-only, and do not present the earlier failure as still open.

An old `/private/tmp/swifttype-test-dd/Build/Products/Debug/SwiftType.app` entry remained in a LaunchServices dump after its file was gone. Its actual impact was not demonstrated; do not pursue registry cleanup merely because an old record exists.

### Diagnostic Limitations and History

- Global HID key-event tracing was deferred by the user; no completed trace established letter-event `alphaShift` state for the affected hosts.
- `osascript` UI inspection was blocked with `osascript is not allowed assistive access. (-1719)`. Do not assume Accessibility permission is now available.
- `TextInputGlobalPropertyPerContextInput` / `KB_PerContextInput` strings were found in System Settings binaries, but no corresponding written preference was found. Do not invent or write undocumented values based on strings alone.
- An `xcodebuild clean` attempt failed because custom build output was not recognized as build-system-owned. Targeted removal of known rebuildable app products was used instead. Do not solve this by deleting broad unrelated directories.
- `CapsLockDelayOverride` had previously been restored to the observed system default, 75. There is no current request for keyboard timing tweaks.

## 9. Installer Hardening Included With This Handoff

Both local and PKG installation now use `scripts/release/pkg-scripts/install-common.sh` to validate the source bundle, copy it to a same-directory temporary location, verify the copied signature, retain the previous installation during the swap, and restore it if post-swap validation fails.

The PKG scripts are checked-in and testable rather than generated heredocs. They use strict shell behavior, fail when there is no GUI user, preserve home paths containing spaces, validate ownership, reject unexpected destination symlinks, and remove legacy/system copies only after the user installation succeeds. The preinstall no longer deletes the working installation.

Ordinary local installation does not restart `imklaunchagent` or force-kill shared cursor services. It refreshes the normal text-input menu/switcher agents and instructs the user to log out and back in if hosts cannot reconnect. Broad repair actions remain manual and separate.

The isolated shell harness at `scripts/release/tests/test_pkg_install.sh` never touches the active input method. Its ten cases cover missing/invalid/corrupt payloads, successful replacement, error/signal rollback, failed first installation, unwritable destination, and file/directory symlink rejection. `scripts/release/tests/test_diagnose.sh` verifies the read-only diagnostic against an isolated home. A real generated PKG installation in a disposable environment remains recommended before public distribution.

Phase 1–3 verification on 2026-09-08: shell syntax and whitespace checks passed, the original installer harness passed 4/4, the full isolated Xcode suite passed 533 tests with 0 failures, and the independent Tester returned PASS. After the remaining improvements, the final isolated Xcode suite passed 543 tests with 0 failures. The expanded installer harness passed 10/10, the diagnostic harness and live redaction check passed, and a third independent Tester returned PASS. Smart Space and client-compatibility verification on 2026-09-09 passed 585 tests with 0 failures or skips; focused policy/controller/UI tests and an independent Tester also passed, and an unsigned temporary Release build was universal `x86_64 arm64` with a valid plist. Temporary DerivedData does not alter the installed input method. Xcode still emitted LaunchServices registration commands despite requesting `REGISTER_WITH_LAUNCH_SERVICES=NO`; no automated unregister operation was performed.

## 10. Improvement Review and Next Work

The archived [improvement review](IMPROVEMENT_REVIEW_2026-09.md) contains evidence, priorities, validation ideas, and confidence labels. It is a source review, not a benchmark or new runtime test report.

| Priority area | Main finding / recommended work |
| --- | --- |
| Package safety | Implemented transactionally with validation, rollback, strict scripts, and isolated shell tests; disposable-environment PKG acceptance remains. |
| Uninstall UX | Implemented actionable success/partial-failure reporting; preferences and configured input sources remain user-controlled. |
| Performance measurement | Points of Interest now cover total key handling, prediction stages, geometry, rendering, and presentation without text metadata. Collect real cold/warm p50/p95/p99 measurements before tuning. |
| Candidate freshness | Implemented generation-bound refreshes, selection revalidation, stale-candidate hiding, `NSNotFound` fallback, and deterministic tests. |
| Shortcut clarity | Implemented separate Vertical/Grid and client-mode guidance in README and the status-menu help. |
| Accessibility | Candidate list/row labels, hidden-row exclusion, selected state, selection notifications, and press actions are implemented. Perform the live VoiceOver matrix before claiming completion. |
| Positioning | Current attributes and first-rect geometry now fall back to a valid recent same-client/session anchor before the mouse. Test multiple displays and missing geometry. |
| Settings polish | Reset scope/confirmation, opacity and grid-column validation, frame autosave, and a fixed-data live preview are implemented. |
| Tests/docs | Deterministic debounce tests, real-client acceptance, isolated installer failure tests, current documentation. |

Suggested sequence: safety/clarity, measurement, measured responsiveness changes, then accessibility/positioning/polish. Avoid a prediction-engine rewrite or network service. No latency numbers were collected in this review; do not advertise a speedup based only on source inspection.

## 11. Build and Verification Workflow

Run from the repository root. The shared scheme is `SwiftType`, not `SwiftTypeTests` (the latter is a test target).

```bash
# Read-only state checks
git status --short
git diff --check

# Full test suite; builds test products but should not replace the installed app
xcodebuild -scheme SwiftType -configuration Debug test

# Syntax check for the local installer
bash -n scripts/install.sh

# Explicit installation; changes the active local setup and restarts services
./scripts/install.sh

# Only for deliberately debugging the installed process
CONFIGURATION=Debug ./scripts/install.sh

# Build a distributable package, not a routine test operation
./scripts/release/release.sh
```

Use the shebang/executable or Bash for these scripts, not `sh`. Package generation cleans project build artifacts, and package installation runs scripts with broader filesystem effects. Read them before execution. Current distribution is ad-hoc signed, not notarized; do not assume the README's Gatekeeper instructions work identically on every macOS release without testing.

Build/test products may become discoverable input-method bundles even though normal builds/tests do not copy to `~/Library/Input Methods`. Check this if icon/routing symptoms recur after tests. Do not automatically rerun the installer or kill shared services after every test.

### Verification Ledger

| Verification | Result and freshness |
| --- | --- |
| Full suite after syncing `02f45be` | Earlier session reported `TEST SUCCEEDED`; exact current count not re-established here |
| Old handoff's 491-case total | Historical 2026-09-04 result; not a fresh count for HEAD |
| Installed build version/metadata | Reread during this handoff; build `20260907020122` |
| Installed architecture/signature/icon hash | Passed earlier installation checks; not rerun for documentation |
| User switching/icon acceptance | Passed after fully reopening affected hosts |
| Installer patch syntax/diff/build-setting check | Passed earlier; no patched-installer end-to-end run |
| Improvement review | Source/test inspection only; no application-code changes or runtime benchmarking |
| Handoff update | Documentation only; no fresh full-suite run or system-service reset |

### Relevant Existing Tests

- `Tests/Input/InputClientPolicyTests.swift`: mode precedence, Edge exception, custom IDs, helper families.
- `Tests/Input/InputControllerEventRoutingTests.swift`: modifier events, lifecycle, inline/passthrough behavior, pending-task cancellation.
- `Tests/Input/InputControllerTransparentPredictionTests.swift`: printable insertion, no persistent marked text, deferred/coalesced refresh, suffix/verified correction commits, stale state, trailing-space protection.
- `Tests/Input/LatinKeyHandlerTests.swift`, state/key/grid tests: literal/candidate semantics, navigation, bounds.
- `Tests/Prediction/SpellCheckPredictor*Tests.swift`: live system-spell-check contracts; dictionary content may vary by OS.
- `Tests/UI/CandidateWindow*Tests.swift` and theme tests: selection, layouts, rows, preferences, appearance.
- `Tests/App/ConstantsTests.swift`, `PrivacyLoggingTests.swift`: input-source metadata and privacy expectations.

Mocks do not emulate real host text pipelines or system input-source switching. Existing wall-clock sleeps in deferred tests are a known test-quality opportunity. Do not weaken tests to accommodate an unverified behavior change.

### Manual Acceptance Matrix for Future Input Changes

| Host / mode | Essential scenarios |
| --- | --- |
| TextEdit and Safari / inline | Literal text, suggestion commit, arrows, Space/Return, contractions, Backspace, switch during a partial word |
| Edge / inline exception | Same scenarios in address bar and page field; no missing/duplicate characters; input-source switch during composition |
| Chrome / transparent | Letters/punctuation inserted once, Backspace deletes once, suffix and typo correction commits, arrows/Tab preserve host behavior, switching leaves no composition |
| WeCom and DingTalk / transparent compatibility | Same as Chrome, plus verify temporary mark-and-commit neither drops nor duplicates characters |
| Native terminals / passthrough | Shell/editor shortcuts and input unchanged, no candidate popup, normal source switching |
| VS Code / direct input | Monaco editor and integrated terminal both accept printable text once; no popup; Ctrl/Cmd/Option, Backspace, arrows, Tab, Escape, and Return remain host-owned |
| Multiple fields/displays | Move caret/select text/switch field during delayed refresh; no stale overwrite or misplaced panel |

Save user documents before any requested host restart. Do not force-quit browsers/editors with unsaved work. Record exact app version, effective policy mode, field type, key sequence, and actual input source in the same context.

## 12. Diagnostics and Historical Artifacts

Read-only diagnostics, if an actual failure recurs:

```bash
mdfind 'kMDItemCFBundleIdentifier == "com.matthew.inputmethod.SwiftType"'
codesign --verify --deep --strict "$HOME/Library/Input Methods/SwiftType.app"
/usr/bin/log stream --style compact --level info \
  --predicate 'subsystem == "com.matthew.inputmethod.SwiftType" AND category == "InputController"'
```

Spotlight output is an inventory clue, not proof of the currently running bundle or TIS registration. Correlate process path, installed metadata, and TIS properties. Avoid capturing typed text; sanitize personal paths before sharing logs.

Historical artifacts, not guaranteed to still exist:

| Artifact | Location |
| --- | --- |
| Full test log after sync | `/var/folders/yt/ngt31b5x55zgdf8lj7xwqqt40000gn/T/opencode/swifttype-remote-sync-tests.log` |
| Initial Edge collection | Local diagnostic artifact (not distributed) |
| Edge collection after service refresh | Local diagnostic artifact (not distributed) |
| Older Caps Lock investigation | `/var/folders/yt/ngt31b5x55zgdf8lj7xwqqt40000gn/T/opencode/swifttype-caps.log` |
| Input-source preference file | `~/Library/Preferences/com.apple.HIToolbox.plist` (inspect only unless explicitly authorized) |
| Prior local comparison project | `~/coding/hallelujahIM` |

## 13. Non-Negotiable Guardrails

- Preserve user and concurrent-agent changes. Never reset/checkout the worktree to remove unrelated edits.
- Do not commit, amend, push, or create a PR without an explicit request. Check the remote carefully when publishing.
- Do not use `TISEnableInputSource`, `TISDisableInputSource`, `TISSelectInputSource`, or `lsregister -u` to force system configuration.
- Keep routing grounded in `client.bundleIdentifier()`, not `NSWorkspace.frontmostApplication`.
- Keep native terminals passthrough. Keep VS Code in no-prediction direct-input mode unless live editor and integrated-terminal evidence justifies another routing change.
- Do not add per-app menu toggles contrary to the existing decision; use the existing documented preference mechanism when appropriate.
- Preserve Latin/English input-source metadata and the template icon resource.
- Do not persist or log user-entered words/document contents for diagnostics or optimization.
- Do not introduce persistent marked text into transparent prediction or blindly convert it to consumed/no-write events.
- Never insert a mirrored composition again during lifecycle cleanup, or overwrite unverified client ranges.
- Avoid broad service resets, permission changes, filesystem cleanup, or input-source preference writes when a read-only investigation suffices.
- Treat the working local switching result as the baseline. Changes need evidence and focused regression verification, not assumptions from the obsolete handoff.
