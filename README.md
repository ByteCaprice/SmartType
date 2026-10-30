<div align="center">
  <img src="./Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png"
       width="150" height="150" alt="SmartType icon">

  <h1>SmartType</h1>
  <p>Native English completions for macOS. Smart Space. Fully offline.</p>
</div>

SmartType is a lightweight macOS input method that suggests English word completions and corrections near your cursor. It uses the system spell checker—not a cloud service—and lets you choose when to accept a suggestion.

## Highlights

- **Smart Space:** keep an exact dictionary match, or accept the visible default completion or correction. Uncertain text falls back to keeping what you typed.
- **Explicit alternatives:** choose a numbered candidate rather than accepting the default.
- **Clear indicators:** a spacebar icon marks the default candidate; **✓ Exact match** or **✓ Keep typed** explains literal preservation.
- **Native candidate window:** choose a vertical list or expandable grid, with customizable colors, opacity, and dimensions.
- **Local processing:** predictions use macOS `NSSpellChecker`. No network predictions or typed-text telemetry.
- **Per-app compatibility:** separate input modes for native editors, browsers, terminals, and clients that need a compatibility commit.

Built with Swift 6, AppKit, and [InputMethodKit](https://developer.apple.com/documentation/inputmethodkit). Requires **macOS 13 or later**; building from source requires Xcode.

## Install

### Build from source

From the repository directory:

```bash
./scripts/install.sh
```

The script builds Release, validates its signature, and transactionally replaces the installed app in `~/Library/Input Methods/`. Failed replacement validation restores the previous installation.

### Install a packaged release

Check the repository's [Releases](https://github.com/ByteCaprice/SmartType/releases) page for a `.pkg`. The current packaging script produces an ad-hoc-signed app, not a notarized distribution. Only install packages from a source you trust; if macOS blocks installation, review the warning in **System Settings → Privacy & Security** rather than disabling Gatekeeper globally.

### Enable the input source

1. Open **System Settings → Keyboard → Text Input → Edit → +** (labels vary by macOS version).
2. Add the installed **SmartType** input source. The underlying app bundle, target, and bundle identifier retain the `SwiftType` technical name for compatibility.
3. Select SmartType from the input menu and start typing in a supported text field.

After an update, fully quit and reopen affected apps so they reconnect. A restart is not normally needed. If the input source is missing or sessions will not reconnect, log out and back in after saving your work.

## Typing with Smart Space

A visible candidate list starts with **no explicit selection**. Space and Return intentionally behave differently:

| Indicator or action | Meaning |
|---|---|
| Spacebar icon beside a candidate | Space accepts that fresh, visible default unless you explicitly selected another candidate |
| **✓ Exact match** | Space keeps the typed word because exact completion evidence exists |
| **✓ Keep typed** | Space keeps the typed text conservatively |
| Explicit candidate selection | Your selection takes priority over the Smart Space default |
| Return without a selection | Preserves your original letters instead of automatically completing them |

Space adds a trailing space when committing a word. Predictions depend on the local macOS dictionary and learned-word state; they are not guaranteed to match another Mac. Prefix completions rank ahead of corrections, and fuzzy guesses remain explicit choices rather than automatic replacements.

### Candidate controls in inline mode

The default layout is **Vertical List**:

| Key | Action while candidates are visible |
|---|---|
| `1`–`7` | Accept the correspondingly numbered populated candidate slot |
| `↓`, `Tab`, `→` | Activate the first candidate, then move down |
| `↑`, `←` | Move up |
| `Space` | Accept the explicit selection or Smart Space default, with a trailing space |
| `Return` | Commit the selection or original letters without a space; this Return is consumed |
| `Escape` | Preserve literal text and dismiss candidates |

With the panel hidden, Return commits any pending inline text and passes through to the app. Shifted digits remain ordinary typing, not candidate shortcuts.

For **Grid** layout, `↓` activates/expands/moves down, `↑` moves up or collapses at the top, and `Tab`/`→`/`←` move between columns. Number shortcuts refer to the active row.

## Application compatibility

Text fields do not all implement macOS input methods the same way—even an editor and terminal in one app can behave differently. SmartType uses the actual input client's bundle identifier to choose a mode:

| Mode | Examples | Behavior |
|---|---|---|
| **Inline** | TextEdit, Safari, Xcode, Edge; default for other clients | Marked-text composition with candidates and navigation |
| **Transparent prediction** | Chrome, Brave, Vivaldi, Opera, WeCom/企业微信, DingTalk/钉钉 | Immediate text commits, with a local mirror for predictions |
| **Direct input** | VS Code | Compatibility commits for printable text; no candidate list |
| **Passthrough** | Terminal, iTerm2, Ghostty, other configured terminal families | Keys remain host-owned; no predictions |

In transparent mode, Space and number shortcuts can accept candidates. Arrows and Tab dismiss candidates and belong to the app. Return without an explicit selection remains the app's submit/newline key. Corrections replace existing text only when the target can be verified; unsafe replacements fall back to literal typing.

WeCom, DingTalk, and VS Code use a temporary `setMarkedText` → `insertText` handshake instead of leaving a persistent composition. This addresses observed dropped-input failures, but does not establish universal compatibility with every host or future update.

VS Code's editor and integrated terminal share the direct-input policy. Command, Control, Option, Backspace, Return, Escape, arrows, and Tab remain host-owned. Option-generated characters, dead keys, and raw-mode terminal programs still deserve real-client testing.

Caps Lock / 中英 switching remains owned by macOS. The input method currently requests the **US keyboard layout** while active; other keyboard layouts are not yet validated.

### Recovering a newly incompatible app

First reopen the app and verify the selected input source. If a routing change is needed, targeted preferences allow recovery without rebuilding:

- **Transparent prediction with compatibility commits** keeps suggestions.
- **Direct input** omits candidates for mixed editor/terminal clients.
- **Marked-text priming only** adds the compatibility handshake to an already-transparent client.

Use the commands and technical preference identifiers in the [architecture guide](./docs/ARCHITECTURE.md#client-routing). Choose the appropriate option, not all three, and use the actual IMK client bundle ID.

Finish any composition and quit the affected app **before** changing these preferences, then reopen it. Matching is exact or a dotted helper descendant. A custom direct-input entry overrides terminal passthrough; Edge remains inline and the input method's own UI remains passthrough. These are targeted recovery options, not guaranteed fixes.

## Settings

Open **Settings** from the `EN` menu-bar item. Appearance controls include layout, colors, opacity, grid columns (4–6), and rows (3–5), with a preview and reset controls. About shows version information.

Prefer the Settings reset controls for appearance changes. Deleting the whole preference domain also removes per-app recovery settings.

## Troubleshooting

| Symptom | First steps |
|---|---|
| No text after an update | Confirm the installed input source is selected; fully quit and reopen the affected app |
| Input source missing | Add the installed input source in Keyboard settings; log out/in if registration has not refreshed |
| One app fails, others work | Record the app version and field type; editor and integrated terminal results can differ |
| Missing or duplicated characters | Note the keys and app involved; avoid speculative insertion retries or global routing changes |
| Unexpected candidate acceptance | Check the spacebar indicator; Return preserves literal text when nothing is explicitly selected |
| Suspected old or duplicate installation | Run the diagnostic below before removing anything or resetting services |

```bash
./scripts/diagnose.sh
```

This read-only diagnostic reports installation, signature, architecture, process, and compatibility preferences. It does not restart services, change input sources, unregister bundles, or collect typed/document text. Review paths before sharing its output.

## Development and verification

### Run tests

Run the shared Xcode test scheme with temporary DerivedData, following the exact commands in the [testing guide](./docs/TESTING.md#automated-verification). Run the isolated shell checks from the repository root:

```bash
bash scripts/release/tests/test_diagnose.sh
bash scripts/release/tests/test_pkg_install.sh
```

Builds and tests do not replace the installed input method, although Xcode can register generated bundles with LaunchServices.

The **2026-09-18 verification baseline** passed **613 unit tests**, **11 installer safety tests**, diagnostic checks, and a universal Intel/Apple Silicon Release build. Coverage includes Smart Space, candidate freshness, compatibility commits, Caps Lock cleanup and latency safeguards, input routing, settings, and privacy-sensitive logging. These are dated results, not a guarantee of bug-free typing in every application.

Users reported successful typing after the compatibility update. The complete per-client matrix, VoiceOver, multi-display positioning, sleep/wake, and physical Caps Lock latency remain separate acceptance work. See [Testing and acceptance](./docs/TESTING.md).

### Architecture

```text
macOS → IMKServer → InputController
                    ├── InputClientPolicy — per-client routing
                    ├── LatinKeyHandler — inline English input
                    ├── InputControllerTransparentPrediction — mirrored text
                    ├── SpellCheckPredictor — local dictionary evidence
                    ├── SmartSpacePolicy — literal or candidate default
                    └── CandidateWindow — presentation and selection
```

Application state is main-actor isolated. Transparent prediction refreshes are debounced and revalidated before display; spell-checking remains local and runs on the main actor.

| Directory | Purpose |
|---|---|
| `App/` | Startup, menu bar, constants, logging |
| `Input/` | Client routing, key handling, composition, state |
| `Prediction/` | Spell-check evidence and Smart Space policy |
| `Rules/` | English punctuation and capitalization |
| `UI/` | Candidate window, settings, themes |
| `Tests/` | Automated regression coverage |
| `scripts/` | Installation, diagnostics, release packaging |

### Package a release

```bash
./scripts/release/release.sh        # timestamp-based version
./scripts/release/release.sh 1.2.0  # explicit version
```

The package is written to `dist/`. It installs the input method in `~/Library/Input Methods/` and creates an application symlink in `/Applications/`. Packaging and system identifiers remain as defined in the existing build scripts.

### Further reading

- [Documentation index](./docs/README.md)
- [Architecture and client routing](./docs/ARCHITECTURE.md)
- [Smart Space design](./docs/SMART_SPACE.md)
- [Input-method switching and compatibility](./docs/INPUT_METHOD_SWITCHING.md)
- [Testing and real-client acceptance](./docs/TESTING.md)
- [Archived development records](./docs/archive/)
