# SmartType Documentation

SmartType is the user-visible project and application name. The app bundle, executable, Xcode targets, bundle identifiers, settings domain, and technical filenames retain the `SwiftType` name for compatibility.

## Current documentation

| Document | Purpose |
| --- | --- |
| [Architecture](ARCHITECTURE.md) | Runtime design, client routing, composition invariants, privacy, and installer behavior |
| [Smart Space](SMART_SPACE.md) | Current prediction policy, candidate behavior, safety rules, and known limitations |
| [Input-method switching](INPUT_METHOD_SWITCHING.md) | Caps Lock and macOS source-switching contract, diagnostics, and safe maintenance |
| [Testing](TESTING.md) | Automated verification, real-client acceptance, accessibility, latency, and release checks |
| [Optional improvements review](OPTIMIZATION_REVIEW_2026-09.md) | Measured low-risk optimizations, implementation status, deferred ideas, and guardrails |

For installation and normal use, start with the repository [README](../README.md).

## Historical records

[`archive/`](archive/) preserves the dated developer handoff, improvement review, original Smart Space research, and pre-consolidation acceptance checklist. They explain why decisions were made, but their build numbers, branch status, assignments, and verification counts are historical. Current behavior is defined by source, tests, and the documents above.

## Maintenance rule

Keep active documentation focused on current contracts. Move dated investigations and one-time delivery notes to `archive/` instead of extending active guides with another status ledger. Verification counts should be labeled with a date and updated only after a fresh complete run.
