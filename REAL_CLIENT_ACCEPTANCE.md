# SwiftType Real-Client Acceptance Checklist

Use this checklist after installing a new build. Unit tests cannot reproduce every InputMethodKit host behavior.

## Before testing

1. Record the installed build number from **Settings → About**.
2. Quit and reopen applications that were running during installation.
3. If SwiftType is selectable but receives no events, log out and back in before changing source code.
4. Do not run Debug test bundles concurrently with this matrix.

## Core matrix

For each application, test letters, punctuation, Backspace, Space, Return, a numbered candidate, and Caps Lock switching after a partial word.

Smart Space examples to record exactly:

- `the` + Space → `the `
- `but` + Space → `but `
- `app` + Space → `app `
- `appl` + Space → the candidate visibly marked `Space` (expected `apply ` on the researched machine)
- `appli` + Space → the candidate visibly marked `Space` (expected `application ` on the researched machine)
- `coord` + Space → the candidate visibly marked `Space` (expected `coordinate ` on the researched machine)
- `convinient` + Space → `convenient ` when that correction is visibly offered

Apple's candidate order can vary by OS, dictionary, learned words, and account. Treat disagreement between the visible Space target and committed text as a defect; record ranking differences rather than silently treating them as code failures.

| Application | Expected mode | Expected behavior |
| --- | --- | --- |
| TextEdit | Inline | Marked composition and candidates; Caps Lock switches language |
| Spotlight | Inline | Ordinary typing and language switching work |
| Safari | Inline | Marked composition and candidates |
| Microsoft Edge | Inline | No dropped letters; Edge web apps follow the same policy |
| Chrome | Transparent prediction | Letters appear immediately without marked text; number keys select candidates |
| WeCom | Transparent prediction | Same behavior as Chrome |
| Terminal | Passthrough | SwiftType does not intercept typing or show candidates |
| VS Code | Passthrough | SwiftType does not interfere with editor/terminal key handling |
| Word | Inline default | Composition, replacement, and switching work |
| System Settings | Inline default | Search fields accept typing normally |

## Candidate UI checks

- Vertical List and Grid both display the documented shortcuts.
- A candidate marked with the spacebar icon is committed by Space when there is no explicit selection.
- `✓ Exact match` means Space preserves the completed word already visible at the caret; `✓ Keep typed` covers conservative literal fallbacks. Neither indicator repeats the word in the panel.
- Arrow navigation moves both the explicit selection and its Space indication; Return behavior remains tied to explicit selection only.
- Transparent clients pass arrows and Tab to the host while dismissing candidates.
- The panel remains near the caret at screen edges, after scrolling, and on two displays.
- Moving to another field while a transparent refresh is pending does not show stale candidates.

## Accessibility checks

With VoiceOver enabled:

- The candidate container is announced as “SwiftType candidates.”
- Only visible candidates are present in the accessibility tree.
- Candidate labels include the visible shortcut where one is active and announce “Space accepts …” for the current Space candidate.
- A literal default updates the container description to announce that Space keeps the typed word without marking a candidate selected.
- Arrow navigation updates the selected row without moving keyboard focus away from the host editor.
- Hidden/preallocated rows are not announced.

Also check Increase Contrast, Reduce Transparency, light/dark appearance, and a custom low-contrast theme.

## Privacy-preserving latency measurement

SwiftType emits Points of Interest signposts for:

- `Key handling`
- `Prediction update`
- `Spell correction`
- `Spell completions`
- `Spell guesses`
- `Candidate presentation`
- `Candidate geometry`
- `Candidate rendering`

Attach Instruments to the running SwiftType process using the **Points of Interest** template. Measure cold-first-word and warm p50/p95/p99 durations separately. Compare key-handler return time and time to visible candidates in TextEdit, Safari, Edge, and Chrome.

The signposts contain durations and fixed operation names only. Do not add typed words, prefixes, surrounding document text, bundle paths, or candidate text to performance metadata.

## Installation acceptance

Before publishing a PKG, use a disposable macOS account or machine to check:

1. Fresh installation.
2. Upgrade over an existing working version.
3. Missing/corrupt payload failure.
4. No logged-in GUI user failure.
5. Recovery of the previous installation after an injected post-swap failure.
6. `/Applications/SwiftType.app` collision with a normal file and with a symlink.

Never fault-test the installer against the active daily-use input method.
