# Nudge V1 Task List

## V1 definition

Nudge V1 lets someone capture a reminder in natural language, verify what Nudge understood, and reliably receive it when a specific Mac application becomes active or when its fallback time arrives.

The V1 trigger surface is intentionally narrow:

- installed application activation
- broad local contexts when no exact application is named
- deterministic fallback date and time

Browser-tab contents, calendar-event contents, contacts, messages, voice capture, cloud sync, and mobile clients are post-V1 integrations.

## P0 — Product correctness

- [x] Remove seeded demo data from production launches
- [x] Persist reminders and settings locally
- [x] Surface overdue fallback reminders while Nudge is running
- [x] Introduce a provider-neutral asynchronous inference interface
- [x] Add Apple Intelligence through Foundation Models with a deterministic fallback
- [x] Discover installed Mac applications dynamically
- [x] Separate reminder conditions from reminder actions
- [x] Support exact application-activation conditions
- [x] Support Open Application and Open URL actions
- [x] Add a review-and-correct step before committing a model interpretation
- [x] Make quick add and full capture use the same pending contextual lifecycle
- [ ] Replace model-owned date arithmetic with deterministic temporal resolution
- [ ] Show the actual inference provider used and any fallback reason

## P0 — Reliable delivery

- [ ] Add Launch at Login
- [ ] Schedule native macOS notifications for fallback dates
- [ ] Add notification actions: Open, Complete, and Snooze
- [ ] Reconcile reminders after sleep, restart, clock changes, and timezone changes
- [ ] Define behavior when Nudge is quit and communicate monitoring state

## P1 — Reminder management

- [ ] Edit title, condition, action, and fallback
- [ ] Delete a reminder
- [ ] Snooze a surfaced reminder
- [ ] Undo accidental completion
- [ ] Add completed/history view
- [ ] Add provider confidence and interpretation details to the edit surface

## P1 — First-run experience

- [ ] Add onboarding explaining contextual reminders and Option-Space
- [ ] Explain Apple Intelligence availability and local-parser fallback
- [ ] Request notification permission in context
- [ ] Offer Launch at Login
- [ ] Show a real first nudge example
- [ ] Add privacy and local-data explanation

## P1 — Data durability

- [ ] Add snapshot schema versioning
- [ ] Add forward migrations
- [ ] Keep a last-known-good backup
- [ ] Quarantine corrupted state instead of silently presenting an empty timeline
- [ ] Persist important mutations immediately

## P1 — Quality and release

- [ ] Build and run the full suite on macOS 26 with Xcode 26
- [ ] Add macOS GitHub Actions CI
- [ ] Add inference fixtures for ambiguous and multilingual reminders
- [ ] Add accessibility and keyboard-navigation verification
- [ ] Add an app icon and production bundle metadata
- [ ] Add Developer ID signing and hardened runtime
- [ ] Add notarization and stapling
- [ ] Produce a distributable ZIP or DMG
- [ ] Add version/build automation
- [ ] Choose an update mechanism
- [ ] Add privacy policy, support URL, and exportable diagnostics

## Post-V1

- [ ] Browser-domain and tab awareness
- [ ] EventKit calendar awareness
- [ ] Contact and conversation awareness
- [ ] Real speech transcription
- [ ] Recurring reminders
- [ ] Cloud provider selection
- [ ] Cross-device sync
- [ ] iPhone and iPad clients
