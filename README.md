# Nudge

Nudge is a native macOS app for contextual reminders. Capture something once, then let it resurface when the relevant kind of app becomes active. If that context never appears, Nudge falls back to a normal time-based reminder.

## What works

- Global capture with `Option-Space`
- On-device Apple Intelligence inference through Apple’s Foundation Models framework
- Context inference for messaging, shopping, calendar, browser, and general work reminders
- Automatic fallback to a deterministic local parser when Apple Intelligence is unavailable
- Live frontmost-app detection for supported messaging, calendar, browser, and productivity apps
- Focus mode that quietly holds non-urgent reminders and releases them as a batch
- Automatic fallback reminders after a configurable number of days
- Local persistence for reminders, completion state, Focus state, and settings
- A floating Liquid Glass timeline plus a menu-bar control

Nudge performs inference and app-context matching locally and does not require Accessibility permission, a cloud API key, or a network LLM request.

## Inference architecture

Reminder creation depends on `NudgeInferenceProvider`, an asynchronous black-box interface. Providers receive a structured `NudgeInferenceRequest` containing the user’s text, reference date, fallback preference, locale, and time zone. They return one provider-neutral `InferenceResult` containing:

- display title and detail
- priority and Focus interruption behavior
- one or more app/context triggers with confidence
- an optional action URL
- an optional exact fallback date

The production store talks only to `NudgeInferenceService`; it does not know how interpretation was produced.

`AppleIntelligenceInferenceProvider` is the default provider. It uses Apple’s Foundation Models framework and guided generation to receive a constrained Swift value directly from the on-device model. Before the generated value reaches the store, Nudge validates identifiers, URLs, confidence, fallback timing, and Focus interruption behavior.

The live service wraps Apple Intelligence in `FallbackInferenceProvider`. If the device is ineligible, Apple Intelligence is disabled, the model is not ready, or generation fails, Nudge transparently falls back to `MockLLMInferenceProvider`, which delegates to the deterministic parser.

```swift
let inference = NudgeInferenceService(
    provider: FallbackInferenceProvider(
        primary: AppleIntelligenceInferenceProvider(),
        fallback: MockLLMInferenceProvider()
    )
)

let store = NudgeStore(
    seedDemoData: false,
    inferenceService: inference
)
```

Other providers can conform to the same protocol and replace or compose with the default without changing capture, persistence, scheduling, or context matching.

## Run

Requires macOS 26 and Xcode 26 or newer. Apple Intelligence inference additionally requires a compatible Mac with Apple Intelligence enabled and its on-device model ready. Nudge remains usable through the local parser when those conditions are not met.

```bash
git clone https://github.com/jlgrimes/nudge.git
cd nudge
swift run
```

Nudge runs without a Dock icon. Look for it at the right edge of the screen or in the menu bar.

To build a launchable app bundle:

```bash
chmod +x scripts/build-app.sh
scripts/build-app.sh
open output/Nudge.app
```

## Debug scenarios

The visual scenario strip, simulated contexts, and mocked voice button are intentionally excluded from normal launches. Enable them explicitly when working on the UI:

```bash
swift run Nudge --debug-scenarios
```

You can also set `NUDGE_DEBUG_PANEL=1` in the environment.

## Test

```bash
swift test
```

## Current integration boundary

Nudge currently observes frontmost application changes. URL-level browser matching and speech transcription are separate integrations; the production UI does not present mocked versions of either feature. Apple Intelligence interprets the reminder, but it does not inspect browser tabs, calendar events, contacts, or message contents.
