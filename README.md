# Nudge

Nudge is a native macOS app for contextual reminders. Capture something once, then let it resurface when the relevant application or broad work context becomes active. If that context never appears, Nudge falls back to a normal time-based reminder.

The active V1 roadmap is tracked in [`V1_TASKS.md`](V1_TASKS.md).

## What works

- Global capture with `Option-Space`
- On-device Apple Intelligence inference through Apple’s Foundation Models framework
- Automatic fallback to a deterministic local parser when Apple Intelligence is unavailable
- Dynamic discovery of applications installed in user, system, and standard Applications folders
- Exact application-activation conditions for named installed apps
- Broad context inference for messaging, shopping, calendar, browser, and general work reminders
- Separate reminder conditions and actions
- Open Application and Open URL actions
- Live frontmost-app detection for every activated application
- Focus mode that quietly holds non-urgent reminders and releases them as a batch
- Automatic fallback reminders after a configurable number of days
- Local persistence for reminders, completion state, Focus state, and settings
- Backward decoding for state written by the earlier trigger-and-URL model
- A floating Liquid Glass timeline plus a menu-bar control

Nudge performs inference and app-context matching locally. It does not require Accessibility permission, a cloud API key, or a network LLM request.

## Reminder model

A reminder now separates the event that makes it useful from the action offered to the user:

```swift
let condition = NudgeCondition.applicationActivated(
    bundleIdentifier: "com.hnc.Discord",
    applicationName: "Discord"
)

let action = NudgeAction.openApplication(
    bundleIdentifier: "com.hnc.Discord",
    applicationName: "Discord",
    applicationURL: URL(fileURLWithPath: "/Applications/Discord.app")
)
```

This distinction lets future browser, calendar, and other adapters add new conditions without changing the action system.

## Inference architecture

Reminder creation depends on `NudgeInferenceProvider`, an asynchronous black-box interface. Providers receive a structured `NudgeInferenceRequest` containing:

- the user’s text
- reference date and fallback preference
- locale and time zone
- a validated catalog of relevant installed applications

They return one provider-neutral `InferenceResult` containing:

- display title and detail
- priority and Focus interruption behavior
- one or more conditions
- an action
- an optional exact fallback date

The production store talks only to `NudgeInferenceService`; it does not know how interpretation was produced.

`AppleIntelligenceInferenceProvider` is the default provider. It uses Apple’s Foundation Models framework and guided generation to receive a constrained Swift value directly from the on-device model. When a request names an installed application, the generated bundle identifier must match the catalog supplied by Nudge. Invented identifiers are rejected and fall back to a validated broad context.

The live service wraps Apple Intelligence in `FallbackInferenceProvider`. If the device is ineligible, Apple Intelligence is disabled, the model is not ready, or generation fails, Nudge transparently falls back to `MockLLMInferenceProvider`. The deterministic provider uses the same installed-app catalog and can resolve an explicitly named app without model access.

```swift
let inference = NudgeInferenceService(
    provider: FallbackInferenceProvider(
        primary: AppleIntelligenceInferenceProvider(),
        fallback: MockLLMInferenceProvider()
    ),
    applicationCatalog: InstalledApplicationCatalog.live
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
