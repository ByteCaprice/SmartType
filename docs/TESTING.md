# Testing and Acceptance

Automated tests protect deterministic behavior, but only real applications can verify InputMethodKit delivery, physical Caps Lock timing, host composition behavior, and candidate positioning.

## Automated verification

Run the full suite with isolated build output:

```bash
DERIVED_DATA="$(mktemp -d /tmp/SwiftTypeTests.XXXXXX)"
RESULT_BUNDLE="$(mktemp -d /tmp/SwiftTypeResults.XXXXXX)/Tests.xcresult"

xcodebuild \
  -project SwiftType.xcodeproj \
  -scheme SwiftType \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  -resultBundlePath "$RESULT_BUNDLE" \
  test
```

Xcode may register generated input-method bundles with LaunchServices even when build output is temporary. Tests do not copy a bundle into `~/Library/Input Methods/`.

Run shell verification from the repository root:

```bash
bash scripts/release/tests/test_diagnose.sh
bash scripts/release/tests/test_diagnose_input_sources.sh
bash scripts/release/tests/test_pkg_install.sh
bash -n scripts/install.sh scripts/diagnose.sh \
  scripts/release/pkg-scripts/install-common.sh

git diff --check
```

The installer harness uses isolated temporary directories and deliberately produces expected error messages while testing rollback and rejection paths. It must never fault-test against the active daily-use installation.

### Latest recorded baseline

On **2026-09-18**, the optimization and documentation working tree based on `b757996` passed:

- **613 XCTest cases**, zero failures or skips;
- the input-source diagnostic harness;
- the general diagnostic harness;
- **11 installer safety cases**;
- changed-file LSP and repository error diagnostics;
- Markdown link, anchor, whitespace, privacy-pattern, and secret-pattern checks;
- signature, universal `x86_64 arm64` architecture, and installed/Release bundle equality for build `20260918065419` (executable SHA-256 `b3da96742f81308138a4d91c0d408c0e4143b9c7b4add7389cb1db3106272b4f`).

This is a dated result, not a permanent test count or a guarantee for every application. Update it only after a fresh complete run.

## Focused contract areas

| Test area | Main coverage |
| --- | --- |
| `Tests/App/` | Required metadata, privacy logging, uninstall behavior |
| `Tests/Input/InputClientPolicyTests.swift` | Routing precedence, hard exceptions, runtime overrides |
| `Tests/Input/InputControllerEventRoutingTests.swift` | Flags changes, Caps Lock passthrough, lifecycle, inline/direct/passthrough behavior |
| `Tests/Input/InputControllerTransparentPredictionTests.swift` | Mirror safety, commit verification, stale state, debounce, no duplicate insertion |
| `Tests/Input/LatinKeyHandlerTests.swift` | Space, Return, punctuation, literal and candidate semantics |
| `Tests/Prediction/` | Injected policy evidence and live spell-check edge contracts |
| `Tests/UI/` | Candidate layouts, selection, accessibility, positioning, themes, settings |
| `scripts/release/tests/` | Read-only diagnostics and transactional installer failures/rollback |

System spell-check results can vary. Policy tests must use injected fixed evidence rather than depending on a particular live candidate ranking.

## Before real-client testing

1. Record the installed build number from Settings → About or `CFBundleVersion`.
2. Finish active compositions and quit/reopen apps that were running during installation.
3. Confirm the selected source and running executable path.
4. Do not run Debug test bundles concurrently with acceptance testing.
5. If the installed source is selectable but receives no events, log out and back in before changing production code.

For every applicable client, test letters, contractions, punctuation, Backspace, Space, Return, a numbered candidate, command/navigation keys, focus changes, and source switching before typing and during a partial word.

## Real-client matrix

| Application / surface | Expected mode | Essential checks |
| --- | --- | --- |
| TextEdit | Inline | Literal and candidate commits, Return, punctuation, Caps Lock during `hel` |
| Spotlight | Inline | Empty and active-composition switching; text remains exactly once |
| Safari | Inline | Page fields and address/search fields; candidate positioning |
| Microsoft Edge | Inline | No dropped letters; address bar and web fields; switching during composition |
| Chrome/Brave/Vivaldi | Transparent | Immediate text, Backspace once, suffix/correction safety, host-owned arrows/Tab/Return |
| WeCom and DingTalk | Transparent + compatibility commit | No dropped/duplicated text, Smart Space, no persistent marked range |
| Terminal/iTerm2/Ghostty | Passthrough | Shell/editor shortcuts unchanged, no candidates, normal switching |
| VS Code editor | Direct input | Printable text exactly once, no candidates, commands host-owned |
| VS Code integrated terminal | Direct input | Printable text and Space once; raw controls remain terminal-owned |
| ChatGPT/Claude/other Electron editors | Current configured policy | Composer behavior, Return/submission, switching, no drops or duplication |
| Termius | Passthrough | Terminal and settings/search fields; shortcuts remain unchanged |
| Word/System Settings | Inline default | Composition, replacement, search/input fields, switching |

Bundle-ID routing cannot distinguish all surfaces within one app. Record the exact app version, effective policy, field type, key sequence, visible candidates, and actual source selection when reporting a failure.

## Smart Space acceptance

Candidate order varies by machine. Verify that the **visible** Space target equals the committed text rather than requiring one universal ranking.

Representative cases:

- Exact evidence such as `the`, `but`, or `app` remains literal plus one space.
- A visible strict completion for `appl`, `appli`, or `coord` is accepted by Space.
- A visible correction for `convinient` is accepted when no prefix wins.
- Explicit candidate selection overrides the automatic target.
- Return without explicit selection preserves original letters.
- Fast Space before transparent debounce remains literal; delayed candidates do not reappear.
- Unsafe transparent replacement falls back without duplication or destructive editing.

## Candidate UI and accessibility

Check both Vertical List and Grid:

- shortcuts match the displayed rows;
- the Space indicator follows default or explicit selection correctly;
- literal reasons do not create a hidden selection;
- hidden/preallocated cells are absent from the accessibility tree;
- VoiceOver announces the container, candidate labels, Space action, and explicit selection;
- press actions commit the expected candidate;
- Increase Contrast, Reduce Transparency, light/dark appearance, and custom themes remain legible;
- positioning works near screen edges, after scrolling, and across displays;
- moving fields during pending transparent prediction never shows stale candidates.

## Privacy-preserving latency measurement

Use Instruments with the **Points of Interest** template and attach to the installed SmartType process (the technical executable remains named `SwiftType`). Available operations include:

- `Key handling`
- `Prediction update`
- `Spell correction`
- `Spell completions`
- `Spell guesses`
- `Candidate presentation`
- `Candidate geometry`
- `Candidate rendering`

Measure cold-first-word and warm p50/p95/p99 separately in representative inline and transparent clients. Never add words, prefixes, candidates, surrounding text, or paths to signpost metadata.

## Installation and release acceptance

Before distributing a PKG, use a disposable macOS account or machine to verify:

1. Fresh installation.
2. Upgrade over an existing working version.
3. Missing or corrupt payload rejection.
4. No-GUI-user failure.
5. Previous-installation recovery after an injected post-swap failure.
6. Destination collision with a normal file and a symlink.
7. Installed signature, architectures, bundle identifier, version, and source/installed equality.
8. Reconnection after affected applications are reopened.

Package generation is not installation. Installation or service restart requires explicit authorization and must not be hidden inside a test workflow.

## Reporting limits

A passing suite cannot prove:

- physical Caps Lock press/release timing;
- which Latin source macOS will choose;
- delivery by every Electron/CEF/native host version;
- live VoiceOver quality or multi-display geometry;
- sleep/wake and long-session behavior;
- notarized/disposable-machine package acceptance.

Report these as manual acceptance results, not unit-test guarantees.
