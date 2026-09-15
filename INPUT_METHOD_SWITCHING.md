# SwiftType Input-Method Switching Guide

This guide documents the switching behavior of the current SwiftType implementation. It is intended for maintainers changing InputMethodKit event handling, per-application routing, input-source metadata, or installation behavior.

The switching foundation has since been extended with Smart Space, targeted client compatibility, and stale-state safeguards. This guide describes the current implementation rather than a historical commit snapshot.

## 1. What Performs the Switch

SwiftType does not select another input source itself. macOS performs the switch.

SwiftType has only two responsibilities when Caps Lock is pressed:

1. Finish or discard any SwiftType composition state that could block switching.
2. Return `false` from the event handler so the event continues to macOS.

Do not call `TISEnableInputSource`, `TISDisableInputSource`, or `TISSelectInputSource` from the input controller. Programmatically changing the user's input sources creates global state, races with macOS, and does not fix a client that is holding an active marked-text composition.

Apple documents `TICapsLockLanguageSwitchCapable` as enabling Caps Lock switching between Latin and non-Latin input sources. The user must also enable the matching macOS Keyboard setting.

## 2. User Setup

The user needs SwiftType and at least one non-Latin input source, such as a Chinese input method.

1. Open **System Settings > Keyboard > Text Input > Edit**.
2. Add **SwiftType** if it is not already present.
3. Add the non-Latin input source that SwiftType should switch to and from.
4. Enable **Use the Caps Lock key to switch to and from** the Latin input source. The exact label varies by macOS version.
5. Select SwiftType from the input menu.
6. Test both Caps Lock and the system's normal input-source shortcut, usually `Control-Space`.

If `Control-Space` works but Caps Lock does not, check the Caps Lock preference, SwiftType metadata, and flags-changed event handling. If neither works, investigate installation, registration, or the active host session first.

### Caps Lock sometimes returns to ABC

Caps Lock does not have a fixed app-controlled “default English input method.” Apple describes its Latin destination as the **last-used Latin input source**. ABC and SwiftType are both Latin sources, so selecting ABC, or entering a field that changes the input source, can affect subsequent switching. The destination is selected by macOS, not by SwiftType while Pinyin is active.

1. Finish the current composition and open a normal, non-password field in TextEdit.
2. Select **SwiftType** explicitly from the input menu, then select **Pinyin**.
3. Tap and release Caps Lock, checking the actual input-menu selection after each switch. Holding Caps Lock also has a capitalization function; the app cannot remove the system's key timing.
4. Compare with **Control-Space**, which selects the last-used source. **Control-Option-Space** selects the next source; Globe/Fn configured to change input source can cycle through all enabled sources, including ABC.
5. In Keyboard > Text Input > Edit, check the displayed Caps Lock destination and **Automatically switch to a document's input source**. If enabled, temporarily turning the document option off manually can help isolate per-document switching. Remember its previous value.
6. If ABC is not wanted in regular switching, inspect whether System Settings allows removing it while retaining SwiftType and Pinyin. Do not force removal by editing HIToolbox preferences or disabling the last system keyboard layout. Secure fields may still require a system layout.

These steps are a diagnostic/setup procedure, not a guarantee that macOS will always choose SwiftType. Do not add a global ABC-to-SwiftType redirect, keyboard event tap, private preference override, or automatic source selection to the controller as a workaround.

The read-only diagnostic below distinguishes the **selected input source** from its **underlying keyboard layout**. SwiftType intentionally uses a US layout for key interpretation; seeing US there does not mean macOS switched away from SwiftType. Likewise, `TISCopyInputSourceForLanguage("en")` is an English-language lookup, not a documented Caps Lock destination API.

## 3. Required Bundle Metadata

The following values in [`Info.plist`](Info.plist) are part of the switching contract:

```xml
<key>TICapsLockLanguageSwitchCapable</key>
<true/>
<key>TISInputSourceID</key>
<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
<key>TISIntendedLanguage</key>
<string>en</string>
<key>tsInputMethodCharacterRepertoireKey</key>
<array>
    <string>Latn</string>
</array>
<key>InputMethodConnectionName</key>
<string>$(PRODUCT_BUNDLE_IDENTIFIER)_Connection</string>
<key>InputMethodServerControllerClass</key>
<string>InputController</string>
```

These values tell macOS that SwiftType is a Latin input source, supports Caps Lock language switching, and exposes the expected InputMethodKit connection and controller.

Do not remove or rename these keys as an application-specific workaround. [`Tests/App/ConstantsTests.swift`](Tests/App/ConstantsTests.swift) protects `TICapsLockLanguageSwitchCapable`, `TISInputSourceID`, and `TISIntendedLanguage`; the connection, controller, and repertoire keys still require code-review verification.

## 4. The Critical Event Contract

[`Input/Controller/InputControllerKeyHandling.swift`](Input/Controller/InputControllerKeyHandling.swift) must request both key-down and flags-changed events:

```swift
override func recognizedEvents(_ sender: Any!) -> Int {
    Int(NSEvent.EventTypeMask.keyDown.union(.flagsChanged).rawValue)
}
```

Caps Lock is a flags-changed event with physical key code `0x39`. The current handler prepares the composition and then passes the event through:

```swift
if event.type == .flagsChanged, event.keyCode == 0x39,
   let client = sender as? (any IMKTextInput)
{
    MainActor.assumeIsolated {
        if state.mirrorsClientText
            || Self.usesTransparentPrediction(bundleIdentifier: client.bundleIdentifier())
        {
            discardMirroredComposition()
        } else if !state.compositionBuffer.isEmpty {
            commitCompositionForLanguageSwitch(client: client)
        }
    }
    return false
}
```

Both parts are mandatory:

| Requirement | Failure when removed |
|---|---|
| Include `.flagsChanged` in `recognizedEvents(_:)` | The controller does not receive Caps Lock flags-changed events; switching commonly appears stuck during composition. |
| Return `false` for Caps Lock | SwiftType consumes the event and macOS cannot perform the switch. |
| Avoid client-policy IPC when no composition exists | A busy special client can delay an otherwise immediate system switch. |
| Resolve client policy only once for an active composition | Duplicate synchronous client calls add avoidable latency to the switch path. |
| Finish inline marked text before returning | Some clients defer switching while a marked range remains active. |
| Discard transparent mirror state without inserting it | The client already owns the typed text; inserting it again duplicates text. |

Other flags-changed events, including ordinary Shift state changes, must also pass through unchanged.

The Caps Lock path must avoid unnecessary synchronous calls into the host process. With no local composition, it returns `false` without querying the IMK client's bundle identifier. With an active buffer, client policy is resolved once inside `commitCompositionForLanguageSwitch(client:)`. This matters when a web renderer or other special client is temporarily busy: redundant cross-process calls can make an otherwise system-owned switch feel delayed.

## 5. Composition Lifecycle

### Inline mode

TextEdit, Spotlight, Safari, Xcode, Edge, and most applications use inline mode. SwiftType owns an active marked-text composition in this mode.

When Caps Lock is received, `commitCompositionForLanguageSwitch(client:)` performs this order:

1. Clear marked text synchronously with `setMarkedText("")`.
2. Insert the composition buffer once.
3. Clear local state and candidates.
4. Return `false` from `handle(_:client:)`.

The order matters. Inserting first can leave a marked range alive briefly in some clients, which can delay or prevent the switch.

`deactivateServer(_:)` is the safety net. When macOS ends the SwiftType session, it commits an unfinished inline composition and hides the candidate window. It must not replace the Caps Lock event path because deactivation happens only after macOS has decided to switch.

### Transparent-prediction mode

Chrome, Brave, Chromium, Arc, Opera, Vivaldi, WeCom, and DingTalk use transparent prediction. These clients can defer Caps Lock switching while persistent marked text is active. WeCom and DingTalk require a temporary `setMarkedText` followed immediately by `insertText` for direct commits; this synchronous handshake does not leave a marked range active.

The invariant is:

> The client owns the typed text. SwiftType owns only a mirror used to calculate predictions.

Therefore transparent mode must:

- Insert printable text into the client without leaving persistent marked text.
- Return an empty composition from `composedString(_:)` and `originalString(_:)` while mirroring.
- Let Backspace reach the client while updating only the mirror.
- Discard mirror state on Caps Lock, deactivation, stale selection, or application changes.
- Never insert the complete mirror during Caps Lock or deactivation.
- Use marked text only for one-shot verified replacements or the audited WeCom/DingTalk direct-commit handshake, completed within the same key event.
- Preserve the current consume/insert pairing for printable keys; changing only the return value can make Chromium redeliver a key and duplicate characters.

Adding normal inline marked text to transparent mode commonly recreates the original Chromium switching failure.

### Direct-input and passthrough modes

Native terminal applications use passthrough mode. SwiftType returns `false` without starting composition so shell line editors and raw-mode applications receive keys unchanged.

VS Code uses no-prediction direct-input mode. Live testing found that Monaco drops printable IMK events returned as unhandled even though the integrated terminal accepts them. SwiftType therefore commits unmodified printable characters through a synchronous temporary marked phase, while Command/Control/Option combinations, Backspace, arrows, Tab, Escape, and Return still pass through. The same bundle ID serves both surfaces, so real-client regression testing must cover both.

Do not remove native terminal applications from passthrough merely to make candidates appear. That can break terminal editing and is unrelated to input-source switching.

## 6. Per-Application Routing

[`Input/InputClientPolicy.swift`](Input/InputClientPolicy.swift) resolves modes in this order:

1. Missing bundle identifier: inline.
2. SwiftType's own process: passthrough.
3. Microsoft Edge and `com.microsoft.edgemac.*`: inline.
4. VS Code: direct input.
5. Known native terminals: passthrough.
6. Known Chromium/CEF clients and explicit user additions: transparent prediction.
7. Everything else: inline.

The order is intentional. In particular:

- TextEdit and Spotlight must remain on the default inline path.
- Edge must remain inline even though it is Chromium-based; its fields require the inline behavior used by the current version.
- Native-terminal passthrough and VS Code direct input must win before broad Chromium-family detection.
- A broad substring rule must not accidentally classify unrelated native applications as transparent.

When adding support for a new application, use `client.bundleIdentifier()` as the source of truth. Do not route using `NSWorkspace.frontmostApplication`; the frontmost application and the actual InputMethodKit client can differ. InputMethodKit exposes no reliable public Electron/CEF/Qt engine flag, so framework guessing cannot safely replace per-client policy.

Three UserDefaults arrays provide a no-rebuild recovery path. Entries match an exact bundle ID or dotted helper descendant, never an arbitrary string prefix:

| Key | Use |
| --- | --- |
| `transparentPredictionBundleIdentifiers` | Preserve Smart Space while avoiding persistent inline composition; configured entries also receive direct-commit priming. |
| `directInputBundleIdentifiers` | Disable composition/candidates and reliably commit printable text while leaving commands host-owned. This overrides built-in terminal passthrough except for SwiftType itself. |
| `markedTextPrimingBundleIdentifiers` | Keep the existing mode but temporarily mark direct commits before inserting them. |

Only add an application to transparent prediction after reproducing a client failure and after testing insertion, correction, Space, Return, Backspace, and candidate selection. Use direct input as the conservative recovery when an app mixes terminal/editor surfaces or predictions are unsafe. Edge remains inline even if configured in these arrays.

## 7. Safe Change Procedure

Before changing switching behavior:

1. Reproduce the issue in a newly opened host application.
2. Record whether the issue affects TextEdit and Spotlight, only Chromium clients, or every application.
3. Confirm whether `Control-Space` still switches input sources.
4. Confirm which SwiftType binary is running.
5. Capture the InputController log while pressing Caps Lock.
6. Change the smallest applicable policy or lifecycle path.
7. Run automated tests and the real-application matrix below.

Do not globally change all applications to passthrough or transparent mode to fix one client.

## 8. Diagnostics

### Confirm the installed build

```bash
/usr/libexec/PlistBuddy \
  -c 'Print :CFBundleVersion' \
  "$HOME/Library/Input Methods/SwiftType.app/Contents/Info.plist"

codesign --verify --deep --strict --verbose=2 \
  "$HOME/Library/Input Methods/SwiftType.app"

pgrep -fl 'SwiftType.app/Contents/MacOS/SwiftType'
```

The running executable must come from `~/Library/Input Methods/SwiftType.app`. A process that started before installation may still represent the previous build.

Check for a second system-wide installation:

```bash
ls -ld \
  "$HOME/Library/Input Methods/SwiftType.app" \
  "/Library/Input Methods/SwiftType.app"
```

There should not be competing SwiftType bundles with the same bundle identifier. Do not delete anything until the active path and intended installation are confirmed.

### Observe the actual source changes

With Xcode's command-line tools installed, run a snapshot or a bounded observation:

```bash
xcrun swift scripts/diagnose-input-sources.swift
xcrun swift scripts/diagnose-input-sources.swift --watch 60
```

During the watch, manually reproduce in TextEdit and note which tap felt slow or selected ABC. The script observes only public Text Input Source notifications and reads source identifiers/capabilities. It does **not** read keystrokes, document contents, or clipboard data; change preferences; select/enable/disable sources; or restart services. Ctrl-C stops it early; the maximum duration is 300 seconds.

Notifications identify a source change, not what caused it. Their timestamps alone do not measure physical Caps Lock latency. Compare the selected source with the controller logs below. A Pinyin-to-ABC change with no SwiftType session is not evidence of a stuck SwiftType composition. An enabled-source preference readout is also not authoritative: live TIS registration can report SwiftType enabled even when the readable HIToolbox list omits it.

### Observe Caps Lock delivery

```bash
/usr/bin/log stream \
  --style compact \
  --level info \
  --predicate 'subsystem == "com.matthew.inputmethod.SwiftType" AND category == "InputController"'
```

Press Caps Lock in the failing field and look for:

```text
Caps Lock event received
Committing composition before language switch
```

Interpret the result as follows:

| Observation | Most likely area |
|---|---|
| No Caps Lock log in TextEdit or Spotlight | Wrong/stale binary, registration problem, or `.flagsChanged` is no longer requested. |
| Caps Lock log appears but no switch occurs | Event may be consumed, marked text may remain active, metadata may be wrong, or the macOS Caps Lock preference is disabled. |
| Native apps work but one Chromium client fails | Per-app policy or transparent composition behavior. |
| Switching fails only immediately after installation | Host application may still hold its old InputMethodKit connection. |
| Text is duplicated after switching | Transparent mirror text was incorrectly committed. |
| Text disappears after switching | Inline composition was discarded instead of committed. |

### Repair stale sessions safely

After rebuilding with `./scripts/install.sh`:

1. Fully quit affected host applications, including TextEdit or the application containing the failing field.
2. Reopen them and select SwiftType again.
3. If source metadata or menu entries remain stale, log out and back in.
4. Recheck the running executable path and build version.

The installer intentionally restarts `TextInputMenuAgent` and `TextInputSwitcher` after replacing and registering the bundle. Manually restarting additional services, or force-killing broad macOS text-input services, is not an input-controller fix and can disrupt other input methods. Use a logout/login for persistent system cache state.

## 9. Required Real-Application Tests

Run this matrix after any change to `Info.plist`, event handling, composition lifecycle, client policy, or installation scripts.

| Application | Expected mode | Test | Expected result |
|---|---|---|---|
| TextEdit | Inline | Type `hel`, then press Caps Lock | `hel` is committed exactly once and macOS switches source. |
| Spotlight | Inline | Open Spotlight, type `hel`, then press Caps Lock | Text remains, no duplicate appears, and the source switches. |
| TextEdit and Spotlight | Inline | Press Caps Lock before typing | Source switches immediately. |
| Chrome or Brave | Transparent | Type `hel`, then press Caps Lock | Existing text remains exactly once and the source switches without persistent marked text. |
| Edge | Inline | Type `hel`, then press Caps Lock | Inline text is committed once and the source switches when the event is delivered. |
| Terminal | Passthrough | Type shell commands and switch sources | Keys remain unchanged; no candidate composition interferes. |
| VS Code | Direct input | Type in editor and integrated terminal; test commands separately | Printable text appears once, no candidates; host-owned controls and source switching still work. |
| Installed Electron clients | Inline unless configured | Test ChatGPT, Claude, Cherry Studio, OpenCode, and OpenChamber editors/chat fields | Text appears while typing; no dropped or duplicated input; switching works. |
| Installed CEF clients | Configured or inline | Test WeCom, DingTalk, and NeteaseMusic text fields | Text appears once; configured candidates work; switching leaves no mark. |
| Termius | Passthrough unless configured | Test terminal and settings/search fields | Both surfaces accept text and terminal shortcuts remain unchanged. |
| Any supported app | Its configured mode | Switch away with `Control-Space` | SwiftType deactivates cleanly without losing or duplicating text. |
| Any supported app | Its configured mode | Switch back to SwiftType | A new session starts with empty composition state. |

Test switching both before typing and during an active word. Testing only an empty field does not exercise the composition bug.

## 10. Automated Regression Tests

Run the complete suite:

```bash
xcodebuild -project SwiftType.xcodeproj \
  -scheme SwiftType \
  -configuration Debug \
  test
```

The most relevant tests are:

| Test file | Contract |
|---|---|
| [`Tests/App/ConstantsTests.swift`](Tests/App/ConstantsTests.swift) | Required Info.plist language and Caps Lock metadata. |
| [`Tests/Input/InputControllerEventRoutingTests.swift`](Tests/Input/InputControllerEventRoutingTests.swift) | `.flagsChanged`, Caps Lock passthrough, inline commit, deactivation, Edge, terminals, and VS Code. |
| [`Tests/Input/InputControllerTransparentPredictionTests.swift`](Tests/Input/InputControllerTransparentPredictionTests.swift) | No persistent marked text, mirror disposal, no duplicate insertion, and Chromium candidate behavior. |
| [`Tests/Input/InputClientPolicyTests.swift`](Tests/Input/InputClientPolicyTests.swift) | Per-app mode ordering and hard exceptions. |

Additional Caps Lock regressions cover the flag-off edge, repeated on/off events followed by system commits/deactivation, system commit before the Caps Lock callback, zero client-policy calls for an empty composition, and one policy call for an active composition. Synthetic events are passed directly to test controllers, never posted to macOS.

Validate the optional read-only diagnostic separately:

```bash
bash scripts/release/tests/test_diagnose_input_sources.sh
```

Unit tests cannot prove that a real host application forwards every event through InputMethodKit or that macOS chooses a particular destination. Keep the real-application matrix mandatory.

## 11. Code Review Checklist

Reject or revise a switching-related change if any answer is "no":

- Does `recognizedEvents(_:)` still include both `.keyDown` and `.flagsChanged`?
- Does Caps Lock always return `false`?
- Does inline mode clear marked text before committing during a language switch?
- Does transparent mode avoid persistent marked text?
- Does transparent mode discard, rather than insert, mirrored text on switching?
- Does `deactivateServer(_:)` preserve unfinished inline text without duplicating transparent text?
- Do TextEdit and Spotlight remain inline?
- Does Edge remain explicitly inline?
- Do native terminals remain passthrough and VS Code remain direct input before broad heuristics?
- Are routing decisions based on the InputMethodKit client's bundle identifier?
- Are all required `Info.plist` keys unchanged?
- Were both automated tests and the real-application matrix completed?
- Were affected host applications reopened after installation?

## 12. Authoritative References

- [Apple: Write in another language on Mac — switching shortcuts and the last-used Latin source](https://support.apple.com/guide/mac-help/mchlp1406/mac)
- [Apple: InputMethodKit](https://developer.apple.com/documentation/inputmethodkit)
- [Apple: IMKInputController](https://developer.apple.com/documentation/inputmethodkit/imkinputcontroller)
- [Apple: TICapsLockLanguageSwitchCapable](https://developer.apple.com/documentation/bundleresources/information-property-list/ticapslocklanguageswitchcapable)
- [Apple: NSEvent.EventTypeMask.flagsChanged](https://developer.apple.com/documentation/appkit/nsevent/eventtypemask/flagschanged)

The Apple capability documentation establishes the system-level Caps Lock behavior. SwiftType's event, composition, and per-client rules above are project-specific compatibility requirements derived from the current implementation and regression tests.
