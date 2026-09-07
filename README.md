<div align="center">
  <img src="./Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png"
       width="150"
       height="150">

  # SwiftType
</div>

<div align="center">
  <img 
  src="https://github.com/user-attachments/assets/c9d41752-d676-4ca5-83da-694390464168" 
  width="600" 
  alt="SwiftType Demo"
  style="border-radius: 18px;"
  >
</div>

A lightweight native macOS input method that helps complete and correct English words as you type. It shows a floating candidate bar below your cursor, using the system dictionary locally with no network calls.

Built with Swift 6, [InputMethodKit](https://developer.apple.com/documentation/inputmethodkit), and macOS's native `NSSpellChecker`.

---

## ✨ Features

- **Up to five word completions and corrections** as you type, powered by macOS's built-in spell checker
- **Fully offline** — suggestions use the system dictionary and no data leaves your machine
- **Expandable candidate grid** — starts as a single row and expands when more candidates are available
- **Themeable candidate window** — customize colors, opacity, grid size, and border through the Settings UI
- **Menu bar integration** — shows `EN` and provides quick access to Settings

---

## 🖥️ Requirements

macOS 13.0 or later. Xcode required only if building from source.

---

## 📦 Install

### From PKG (recommended)

Download the latest `.pkg` from [Releases](../../releases) and double-click to install. The app is ad-hoc signed and not notarized, so you'll need to **right-click → Open** the installer on first launch to bypass Gatekeeper.

### Build from source

```bash
./scripts/install.sh
```

The script completes an optimized Release build before replacing the copy in `~/Library/Input Methods/`. Regular builds and tests never modify the installed input method. Use `CONFIGURATION=Debug ./scripts/install.sh` only when debugging the installed process.

### Enable the input source

1. Open **System Settings → Keyboard → Input Sources → Edit → +**
2. Select **SwiftType**
3. Click **Add**
4. Switch to SwiftType from the input source menu in the menu bar

---

## 🚀 Usage

Switch to SwiftType, open any text field, and start typing. The candidate bar appears below your cursor.

### Candidate selection

| Key | Action |
|---|---|
| `1`–`6` | Commit the prediction in that column |
| `Space` | Commit selected prediction |
| `Return` | Commit current selection |
| `Escape` | Commit raw text and dismiss |

### Grid navigation

The candidate bar starts collapsed (one row). Press `↓` to expand into a multi-row grid.

| Key | Action |
|---|---|
| `↓` | Expand grid / move down |
| `↑` | Move up / collapse at top |
| `Tab` / `→` | Cycle column right |
| `←` | Cycle column left |

Number keys always target the **active row**.

---

## ⚙️ Settings

Open Settings from the menu bar icon.

| Pane | What it does |
|---|---|
| **Appearance** | Adjust candidate bar colors, opacity, column count (4–6), and row count (3–5) |
| **About** | Shows the installed version |

Reset all settings: `defaults delete com.matthew.inputmethod.SwiftType`

---

## 🏗️ How It Works

### Prediction pipeline

```
Keystroke
 → SpellCheckPredictor (macOS spell checker → corrections + completions)
 → CandidateWindow (floating grid below cursor)
```

**SpellCheckPredictor** wraps `NSSpellChecker` to produce spelling corrections, prefix completions, and fuzzy guesses — all synchronous, no network calls.

### Architecture

```
macOS → IMKServer → InputController
                        ├── InputClientPolicy    — per-app mode: passthrough / inline / transparent prediction
                        ├── LatinKeyHandler      — English key dispatch (inline mode)
                        ├── InputControllerTransparentPrediction — mirrored-buffer predictions for Chromium/CEF apps
                        ├── SpellCheckPredictor — local completions and corrections
                        ├── EnglishTypingRules — punctuation and capitalization
                        └── CandidateWindow   — floating grid UI
```

### Per-app compatibility

SwiftType handles three kinds of text clients, selected automatically by `InputClientPolicy`:

- **Inline** (default): marked-text preedit with candidates — native apps like TextEdit, Safari, Xcode, Electron/Qt apps, plus the Microsoft Edge family and its installed web apps, whose text fields drop modeless input.
- **Passthrough**: every keystroke goes to the app untouched — terminals and VS Code, whose line editors fight inline preedit.
- **Transparent prediction**: Other Chromium/CEF apps (Chrome, Brave, Vivaldi, Opera, WeCom/企业微信) defer Caps Lock input-source switching while marked text is active, so SwiftType keeps no composition there — letters land in the app directly and only the completion suffix is inserted when you pick a candidate.

If a newly released app shows the same broken Caps Lock switching, enable transparent prediction for it without rebuilding:

```bash
defaults write com.matthew.inputmethod.SwiftType transparentPredictionBundleIdentifiers -array-add 'com.example.NewApp'
```

Caps Lock (中/英) switching to other input methods is supported system-wide via the input method's `TICapsLockLanguageSwitchCapable` capability.

Maintainers should read the [Input-Method Switching Guide](INPUT_METHOD_SWITCHING.md) before changing event handling, composition lifecycle, per-app policy, or installation behavior.

### Concurrency

Application state is `@MainActor`-isolated under **Swift 6 strict concurrency**. InputMethodKit delivers callbacks on the main thread; the controller verifies that boundary before accessing composition state. Chromium candidate refreshes are asynchronously coalesced on the main actor so key handling can return to the browser before spell-checking and UI work begin.

---

## 🧪 Tests

```bash
xcodebuild -scheme SwiftType -configuration Debug test
```

The test suite covers input state, per-app client modes, transparent prediction, grid navigation, key routing, spell-check predictions, privacy-sensitive logging, the theme system, settings persistence, and candidate window behavior.

---

## 📁 Project Structure

```
SwiftType/
├── App/            App delegate, constants, logging, and menu bar
├── Input/          Input controller, English key handling, and state
├── Prediction/     Native spell-check and completion provider
├── Rules/          English punctuation and capitalization rules
├── UI/             Candidate window, appearance settings, and theme system
├── Tests/          Unit tests across all subsystems
└── scripts/        Release packaging
```

---

## 📋 Building a Release

```bash
./scripts/release/release.sh          # auto-versioned (UTC timestamp)
./scripts/release/release.sh 1.2.0    # explicit version
```

Produces `dist/SwiftType-<version>.pkg` — a flat installer that copies the app to `~/Library/Input Methods/` and creates a `/Applications/SwiftType.app` symlink.

---

## 🔧 Troubleshooting

| Problem | Fix |
|---|---|
| SwiftType not in Input Sources | Run `./scripts/install.sh`, add SwiftType in **System Settings → Keyboard**, then log out and back in |
| An app cannot type after installing or rebuilding SwiftType | Fully quit and reopen that app so it reconnects to the new input-method process; if that fails, log out and back in |
| Old binary after rebuild | Run `./scripts/install.sh`, quit and reopen apps that were running during installation, then log out and back in if needed |
| Duplicate entries | `sudo rm -rf /Library/Input\ Methods/SwiftType.app` then re-login |
| Gatekeeper error | Right-click → Open, or run `xattr -dr com.apple.quarantine ~/Library/Input\ Methods/SwiftType.app` |
