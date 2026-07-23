# Nudge

Nudge is a native macOS prototype that turns natural-language intentions into contextual reminders. It lives as a quiet Liquid Glass bubble at the right edge of the screen and expands only when something becomes relevant.

## Run

Requirements: macOS 26 and Xcode 26 or newer.

```bash
swift run Nudge
```

The app runs without a Dock icon. Look for the floating bubble at the right edge of the screen or the sparkle in the menu bar.

To build a launchable macOS app bundle:

```bash
chmod +x scripts/build-app.sh
scripts/build-app.sh
open output/Nudge.app
```

## Demo

- Press `Option-Space` to open capture from any app.
- Type `Remind me to message Alex` and press Return. Nudge infers a broad messaging context.
- Switch to Slack, Messages, or Microsoft Teams to fire the reminder from the real frontmost-app context. No Accessibility permission is required.
- The menu-bar **Slack becomes active** action remains available as a deterministic demo fallback.
- Add `Remind me to order coffee filters`, then choose **Visit amazon.com** to fire its inferred shopping trigger.
- Start Focus mode before simulating a context to queue the reminder. Ending Focus shows one short recap.
- Choose **Run 10-second demo** for the complete urgent/grouped/focus sequence.

Voice transcription, LLM parsing, and browser URL events are intentionally mocked. Frontmost messaging-app activity is detected live through macOS. The saved model separates the raw request, inferred semantic context, runtime identifiers, confidence, and time fallback so the remaining integrations can replace the mocks without redesigning the UI.

## Test

```bash
swift test
```
