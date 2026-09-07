# SwiftType Developer Handoff

Last updated: 2026-09-07

This document supersedes the previous 2026-09-04 handoff. It describes the current source, the local troubleshooting outcome, pending changes, and the recommended next work. Historical observations are explicitly labeled; do not mistake them for fresh checks or current failures.

## 1. Start Here

SwiftType is an English-only, offline macOS input method built with Swift 6, AppKit, InputMethodKit, and the system spell checker. It offers word completions/corrections through a floating candidate panel. It has no network prediction dependency.

**Current user-visible status:** the user confirmed that, after completely quitting and reopening the affected applications, the new `S` input-source icon appears and language switching works normally. The latest confirmation was: "After restarting the apps, everything is normal; they can all switch normally." There is no outstanding user-reported switching failure to reproduce at handoff time.

**Current assignment:** the user requested a broad improvement review, then this detailed handoff for another developer. Suggestions are in [IMPROVEMENT_REVIEW.md](./IMPROVEMENT_REVIEW.md). Those suggestions have not been implemented. Do not treat the report as blanket authorization to change every area at once.

Recommended first steps for the next developer:

1. Read this document and `IMPROVEMENT_REVIEW.md`.
2. Check `git status`, inspect the installer-hardening history, and preserve all existing work.
3. Choose a small, agreed improvement, preferably installation safety or documentation/UX clarity before speculative optimization.
4. Read the relevant implementation and tests; preserve client-specific input behavior.
5. Run targeted/full verification as appropriate, recording fresh results and any generated input-method bundles.
6. Do not reinstall or reset system services just to read the project. The user's current setup works.

## 2. Repository and Worktree

| Item | State verified while preparing this handoff |
| --- | --- |
| Workspace | `/Users/developer/coding/SwiftType` |
| Branch | `main` |
| Implementation baseline before this handoff commit | `02f45be` - `Improve prediction reliability and candidate UI` |
| Previous implementation commit | `45aa8ba` - `Rework input handling: English-only, Caps Lock switching, per-app client modes` |
| Tracking branch | `github/main`; local tracking state shows no ahead/behind difference |
| Private working remote | `github` = `https://github.com/ByteCaprice/SwiftType.git` |
| Public upstream | `origin` = `https://github.com/mgxv/SwiftType.git` |

Always refresh remote state before publishing; branch information in documentation becomes historical immediately. Never accidentally push private work to `origin`.

Changes prepared together for the handoff commit:

| File | Purpose |
| --- | --- |
| `scripts/install.sh` | Installation-hardening change from the preceding troubleshooting session |
| `IMPROVEMENT_REVIEW.md` | Improvement report from the source review |
| `HANDOFF.md` | Current developer handoff |

No production Swift files were changed during the review or handoff. The previous handoff's claim of numerous uncommitted architecture changes is obsolete: the relevant source work is now in the commits above. Always recheck the worktree rather than relying permanently on this snapshot.

## 3. Installed Application and Local Environment

| Item | Value / evidence status |
| --- | --- |
| Intended installation | `/Users/developer/Library/Input Methods/SwiftType.app` |
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
4. Known terminal/VS Code passthrough IDs: passthrough.
5. Transparent custom entries, known IDs/prefixes, or Chromium-family heuristic: transparent prediction.
6. Everything else: inline.

| Mode | Current examples | Behavior |
| --- | --- | --- |
| Inline | TextEdit, Safari, Xcode, Edge and its dotted bundle descendants | Marked-text composition and synchronous predictions |
| Passthrough | Terminal, iTerm2, Ghostty, WezTerm, kitty, Alacritty, Warp, Hyper, Termius, VS Code, own UI | Keydown returns false; no composition or suggestions |
| Transparent prediction | Chrome, Chromium, Brave, Arc, Opera, Vivaldi, WeCom and known helpers | No persistent marked text; mirrored state and delayed predictions |

**Important correction from the old handoff:** Edge is deliberately inline in current code. Do not move it back to transparent mode based on the old incident narrative. The README explains that its fields drop modeless input.

The custom UserDefaults key is `transparentPredictionBundleIdentifiers`. Entries currently match exact IDs or raw prefixes. Known helpers include `88L2Q4487U.com.tencent.wework`; the heuristic checks substrings such as `chrome` and `chromium`. Broad matching is a review opportunity, not something already fixed.

Existing manual opt-in mechanism for a newly problematic app:

```bash
defaults write com.matthew.inputmethod.SwiftType transparentPredictionBundleIdentifiers -array-add 'com.example.NewApp'
```

This changes preferences; do not run it casually. The Edge and passthrough exceptions take precedence over this array. Do not add per-app menu switches without revisiting the explicit project decision.

## 6. Key Handling and Text Safety

### Inline Mode

- Letters and continuation apostrophes accumulate in `compositionBuffer`, update marked text, and immediately fetch/render predictions.
- Backspace edits composition and is consumed when the buffer is nonempty; otherwise it passes through.
- Digits choose a populated visible candidate slot when Shift is not held. Empty slots commit the literal composition and let the digit through.
- Space commits the selected candidate, or the literal buffer when nothing is selected, with a trailing space. With no composition/selection, it passes through.
- Return while the panel is visible commits the selected candidate or literal buffer without a trailing space and is consumed. With the panel hidden, any buffer is committed and Return passes through.
- Escape commits literal text and dismisses; it is consumed only if composition/panel content existed.
- Arrows/Tab navigate when the panel is visible. Otherwise they commit composition and pass through.
- Command/Control/Option combinations commit composition and pass through.
- Language switching clears marked text synchronously, commits pending literal text, and leaves the switch event to macOS.

### Transparent Mode

The previous handoff said letters passed through without any client write. That is no longer the implementation. Current printable handling calls `client.insertText` and returns true, while maintaining a mirror and leaving no persistent marked text.

| Event | Current behavior |
| --- | --- |
| Letter or continuation apostrophe | Append mirror, insert the character, schedule prediction refresh, consume |
| Ordinary number/punctuation/symbol not handled as selection | Discard mirror, insert character, consume |
| Backspace | Update mirror and expected cursor, schedule refresh or clear; return false so host deletes once |
| Space without successful selected-candidate commit | Discard mirror, explicitly insert space; record trailing-space state when applicable |
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

Current single-character insertion and the historical gate description need real-client verification/documentation, not an automatic rollback. Mock IMK clients do not reproduce Chromium's native event pipeline. The review did not establish a current duplicate-typing bug. Test Chrome/WeCom directly and Edge separately before changing these paths.

Historical upstream references: Chromium `content/app_shim_remote_cocoa/render_widget_host_view_cocoa.mm`, Squirrel `force_marked_text_for_direct_commit`/issue #906, fcitx5-macos dummy preedit, macSKK Direct Mode. These references were investigated earlier, not freshly verified for current upstream versions in this handoff.

## 7. Prediction, UI, and Settings

- `NSSpellChecker` is local, fixed to `en_US`, with a per-predictor spell-document tag. Results are correction first, then completions, then guesses; case-insensitive duplicates and the literal prefix are excluded.
- `Constants.spellCompletionLimit` is five. Do not confuse the five-result limit with the maximum number of preallocated grid cells.
- Inline prediction work is synchronous in key handling. Transparent refreshes cancel/coalesce for 75 ms, then run spell-check/UI work on the main actor. Coalescing is not background spell-checking.
- Default layout is Vertical List; default rows are four, options three/four/five. Grid columns default to five, options four/five/six. Preallocation supports up to five rows and seven columns.
- Production calls supply predictions only, no literal candidate slot. The panel starts without an active selection. Literal-slot support remains in UI code/tests but is not used by normal prediction display.
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
/Users/developer/coding/SwiftType/build/Debug/SwiftType.app
/Users/developer/coding/SwiftType/build/Release/SwiftType.app
/Users/developer/Library/Developer/Xcode/DerivedData/SwiftType-hirodvyrzwyfzdheybukpvcimzru/Build/Products/Debug/SwiftType.app
/Users/developer/Library/Input Methods/SwiftType.app
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

The `scripts/install.sh` change included with this handoff adds:

- Removal of `build/Debug/SwiftType.app` when installing a non-Debug configuration.
- `REGISTER_WITH_LAUNCH_SERVICES=NO` for its build.
- Restart of `imklaunchagent` in addition to the input menu agent.
- Forced termination of `TextInputSwitcher` and `CursorUIViewService` during installation.

The script already builds before replacing the installed copy, verifies build/staging signatures, uses in-place `rsync` for an existing destination, registers the destination, and prints instructions to reopen existing host apps. Those existing instructions are not new changes in the patch.

Verification performed for this patch: shell syntax passed, whitespace diff check passed, and `xcodebuild -showBuildSettings` echoed `REGISTER_WITH_LAUNCH_SERVICES = NO`. A printed build setting alone is not proof of full registration/discovery behavior. **The patched installer has not been rerun end to end after these additions.** The working user session was not disrupted to test it.

Follow-up review considerations:

- Shared-service termination affects more than SwiftType. Decide whether broad resets should be an explicit repair option rather than routine installation.
- The local Release build still remains on disk, and arbitrary DerivedData copies are not removed. This is not a comprehensive duplicate-bundle prevention solution.
- In-place copy failure has no rollback despite strict shell error handling.
- Keep cleanup limited to known owned artifacts, never arbitrary app bundles or input-source settings.
- Release packaging uses a separate build/install path and does not automatically inherit these changes.

## 10. Improvement Review and Next Work

`IMPROVEMENT_REVIEW.md` contains evidence, priorities, validation ideas, and confidence labels. It is a source review, not a benchmark or new runtime test report.

| Priority area | Main finding / recommended work |
| --- | --- |
| Package safety | Generated preinstall deletes the old installation early; postinstall lacks checked critical operations and can report success without a user installation. Validate payload/user first and preserve recovery. |
| Uninstall UX | Removal errors are swallowed into generic logs, then the app terminates and reports completion. Surface partial/failure outcomes and explain manual source removal. |
| Performance measurement | Profile inline spell-check stages, client IPC, and panel layout before changing scheduling/ranking. Measure cold/warm and end-to-end suggestion latency. |
| Candidate freshness | Delayed tasks validate buffer/cancellation but not current selection before show; stale visible candidates can remain during debounce. Add reproducible tests and define selection semantics. |
| Shortcut clarity | README focuses on grid despite vertical default and does not fully distinguish inline/transparent behavior. Add concise in-app help. |
| Accessibility | Candidate UI lacks explicit list/selection semantics. Inspect actual VoiceOver behavior before claiming it is inaccessible; avoid announcements on every key. |
| Positioning | Prefer a valid same-session caret anchor over an unrelated mouse location when possible; test multiple displays and missing geometry. |
| Settings polish | Clarify reset scope, validate stored opacity, retain settings frame, consider a small appearance preview. |
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
| Chrome and WeCom / transparent | Letters/punctuation inserted once, Backspace deletes once, suffix and typo correction commits, arrows/Tab preserve host behavior, switching leaves no composition |
| Terminal and VS Code / passthrough | Shell/editor shortcuts and input unchanged, no candidate popup, normal source switching |
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
| Initial Edge collection | `/Users/developer/.local/share/opencode/tool-output/tool_079b2ee7e001JNWFhf1oswk8ka` |
| Edge collection after service refresh | `/Users/developer/.local/share/opencode/tool-output/tool_079b73791001i81iWGZa4q8mtW` |
| Older Caps Lock investigation | `/var/folders/yt/ngt31b5x55zgdf8lj7xwqqt40000gn/T/opencode/swifttype-caps.log` |
| Input-source preference file | `/Users/developer/Library/Preferences/com.apple.HIToolbox.plist` (inspect only unless explicitly authorized) |
| Prior local comparison project | `/Users/developer/coding/hallelujahIM` |

## 13. Non-Negotiable Guardrails

- Preserve user and concurrent-agent changes. Never reset/checkout the worktree to remove unrelated edits.
- Do not commit, amend, push, or create a PR without an explicit request. Check the remote carefully when publishing.
- Do not use `TISEnableInputSource`, `TISDisableInputSource`, `TISSelectInputSource`, or `lsregister -u` to force system configuration.
- Keep routing grounded in `client.bundleIdentifier()`, not `NSWorkspace.frontmostApplication`.
- Keep VS Code and terminals passthrough; no browser Web CLI special case is requested.
- Do not add per-app menu toggles contrary to the existing decision; use the existing documented preference mechanism when appropriate.
- Preserve Latin/English input-source metadata and the template icon resource.
- Do not persist or log user-entered words/document contents for diagnostics or optimization.
- Do not introduce persistent marked text into transparent prediction or blindly convert it to consumed/no-write events.
- Never insert a mirrored composition again during lifecycle cleanup, or overwrite unverified client ranges.
- Avoid broad service resets, permission changes, filesystem cleanup, or input-source preference writes when a read-only investigation suffices.
- Treat the working local switching result as the baseline. Changes need evidence and focused regression verification, not assumptions from the obsolete handoff.
