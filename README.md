<div align="center">
  <img src="./Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png" width="144" height="144" alt="SmartType app icon">

  # SmartType

  **A small, native typing assistant for macOS.**<br>
  Thoughtful English completions, safer corrections, and no cloud required.

  [![macOS 13+](https://img.shields.io/badge/macOS-13%2B-111111?logo=apple)](https://www.apple.com/macos/)
  [![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](https://www.swift.org/)
  [![Offline](https://img.shields.io/badge/predictions-fully_offline-2ea44f)](#privacy-by-design)
  [![InputMethodKit](https://img.shields.io/badge/native-InputMethodKit-007AFF)](https://developer.apple.com/documentation/inputmethodkit)
  [![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](./LICENSE)

  [Install](#install) · [How it feels](#how-it-feels) · [Compatibility](#app-compatibility) · [Contribute](#contributing)
</div>

---

SmartType brings a lightweight candidate window to the place where you are already typing. It uses macOS's built-in spell checker to suggest completions and corrections, then lets **you** decide what gets committed.

No account. No language model download. No typed text sent to a server.

> [!NOTE]
> SmartType is an evolving macOS input method. Input behavior varies between applications, so real-world compatibility reports are especially valuable.

## Why SmartType?

- **Smart Space** — press Space to accept a clear completion or correction; exact and uncertain words stay exactly as typed.
- **You stay in control** — select a numbered alternative, navigate with the keyboard, or press Return to preserve your original letters.
- **Native macOS experience** — built with Swift, AppKit, `NSSpellChecker`, and InputMethodKit.
- **Private by design** — prediction happens locally using the dictionaries already on your Mac.
- **Made for different editors** — tailored modes handle native apps, Chromium browsers, VS Code, terminals, and compatibility-sensitive clients.
- **Customizable** — choose a vertical list or grid and adjust colors, opacity, rows, columns, and sizing.

## How it feels

Type a partial word and SmartType presents nearby candidates:

```text
appl  →  apple
coord →  coordinate
```

The candidate window always explains what Space will do:

| Indicator | Space action |
|---|---|
| Spacebar icon beside a candidate | Accept that visible suggestion |
| **✓ Exact match** | Keep the word you typed |
| **✓ Keep typed** | Preserve uncertain text conservatively |
| Explicit selection | Accept your chosen candidate |

Return and Space intentionally differ: **Space** may accept the visible Smart Space target and adds a trailing space, while **Return** preserves your original letters unless you explicitly selected a candidate.

### Keyboard controls

| Key | Action while candidates are visible |
|---|---|
| `1`–`7` | Accept the corresponding populated candidate |
| `↓`, `Tab`, `→` | Activate the first candidate, then move forward |
| `↑`, `←` | Move backward |
| `Space` | Accept the selection or Smart Space target, then add a space |
| `Return` | Commit the selection or original text without a space |
| `Escape` | Keep literal text and dismiss candidates |

Grid layout adds row and column navigation. Shifted digits remain ordinary typing.

## Install

### Requirements

- macOS 13 Ventura or later
- Xcode for source builds

### Build and install from source

Clone the repository and run the installer:

```bash
git clone https://github.com/ByteCaprice/SmartType.git
cd SmartType
./scripts/install.sh
```

The script creates a Release build, verifies its signature, and safely installs it to:

```text
~/Library/Input Methods/SwiftType.app
```

The technical bundle and executable keep the historical `SwiftType` name for compatibility; the product shown in macOS is **SmartType**.

### Enable SmartType

1. Open **System Settings → Keyboard → Text Input → Edit → +**.
2. Add **SmartType** to your input sources.
3. Select it from the macOS input menu and begin typing in a supported field.

After updating, quit and reopen affected apps so they reconnect to the input method. If SmartType does not appear, log out and back in after saving your work.

### Packaged releases

When a packaged build is available, download it from [GitHub Releases](https://github.com/ByteCaprice/SmartType/releases). Current packages are ad-hoc signed rather than Apple-notarized, so macOS may ask you to confirm the installation in **System Settings → Privacy & Security**. Never disable Gatekeeper globally.

## App compatibility

macOS applications do not all communicate with input methods in the same way. SmartType selects a policy using the active input client's bundle identifier.

| Mode | Typical apps | Experience |
|---|---|---|
| **Inline** | TextEdit, Safari, Xcode, Edge | Marked-text composition with full candidates and navigation |
| **Transparent prediction** | Chrome, Brave, Vivaldi, Opera, WeCom, DingTalk | Immediate commits plus a local prediction mirror |
| **Direct input** | VS Code | Compatibility-focused typing without candidates |
| **Passthrough** | Terminal, iTerm2, Ghostty | Host-owned keys with no predictions |

Compatibility is necessarily imperfect: an editor and terminal inside the same app can behave differently, and application updates can change text-input behavior. See the [architecture and client-routing guide](./docs/ARCHITECTURE.md#client-routing) for targeted recovery settings and implementation details.

> SmartType currently requests the US keyboard layout while active. Other layouts have not yet been fully validated.

## Privacy by design

SmartType uses the local macOS `NSSpellChecker` and does not need a prediction service.

- Typed words and surrounding document text are not sent to SmartType servers—there are no SmartType servers.
- Predictions use the dictionaries and learned-word state on your Mac.
- Diagnostics report installation, process, signature, architecture, and compatibility configuration—not typed or document text.
- Performance signposts intentionally exclude words, prefixes, candidates, surrounding text, and file paths.

Run the read-only diagnostic with:

```bash
./scripts/diagnose.sh
```

## Settings

Choose **Settings** from the `EN` menu-bar item to customize:

- vertical-list or grid presentation;
- colors and opacity;
- candidate window dimensions;
- grid rows and columns;
- theme preview and reset controls.

Appearance settings and per-app compatibility preferences are stored locally.

## Development

### Run the test suite

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

Run the installer and diagnostic safety checks separately:

```bash
bash scripts/release/tests/test_diagnose.sh
bash scripts/release/tests/test_diagnose_input_sources.sh
bash scripts/release/tests/test_pkg_install.sh
```

See [Testing and acceptance](./docs/TESTING.md) for the latest recorded baseline, real-client matrix, accessibility checks, and release verification steps.

### Architecture at a glance

```text
macOS → IMKServer → InputController
                    ├── InputClientPolicy
                    ├── LatinKeyHandler
                    ├── Transparent Prediction
                    ├── SpellCheckPredictor
                    ├── SmartSpacePolicy
                    └── CandidateWindow
```

| Directory | Responsibility |
|---|---|
| `App/` | Startup, menu bar, constants, and privacy-aware logging |
| `Input/` | Client routing, keyboard handling, composition, and state |
| `Prediction/` | Local spell-check evidence and Smart Space policy |
| `Rules/` | English punctuation and capitalization behavior |
| `UI/` | Candidate window, settings, and themes |
| `Tests/` | Automated regression coverage |
| `scripts/` | Installation, diagnostics, and release packaging |

For a deeper tour, read [Architecture](./docs/ARCHITECTURE.md) and [Smart Space design](./docs/SMART_SPACE.md).

### Build a package

```bash
./scripts/release/release.sh        # timestamp version
./scripts/release/release.sh 1.2.0  # explicit version
```

The resulting `.pkg` is written to `dist/`.

## Contributing

SmartType gets better through real typing. Bug reports, compatibility findings, focused fixes, tests, and documentation improvements are welcome.

A useful compatibility report includes:

- macOS and application versions;
- the field type, such as editor, address bar, terminal, or chat composer;
- the exact key sequence;
- what candidates were visible;
- what happened and what you expected.

Please avoid including private text from your documents or conversations. Before opening a pull request, run the focused tests for your change and keep input-client work narrowly scoped—fixing one application globally can easily break another.

## Documentation

- [Documentation index](./docs/README.md)
- [Architecture and client routing](./docs/ARCHITECTURE.md)
- [Smart Space behavior](./docs/SMART_SPACE.md)
- [Input-method switching](./docs/INPUT_METHOD_SWITCHING.md)
- [Testing and acceptance](./docs/TESTING.md)

## License

SmartType is available under the [MIT License](./LICENSE).

## Acknowledgements

SmartType continues the work of the original [SwiftType](https://github.com/mgxv/SwiftType) project and its contributors. It is built on Apple's AppKit, InputMethodKit, and system spell-checking technologies.

<div align="center">
  <strong>Quietly helpful. Deliberately local. Always your choice.</strong>
</div>
