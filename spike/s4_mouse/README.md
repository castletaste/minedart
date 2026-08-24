# S4 macOS mouse capture spike

Native bridge:

- `MethodChannel('minedart/mouse')`: `capture()` and `release()`.
- `EventChannel('minedart/mouse/events')`: maps with `type: delta`, `dx`, `dy` plus capture-state events.
- `CGAssociateMouseAndMouseCursorPosition(false)` freezes cursor position; a local `NSEvent` monitor emits relative deltas.
- Capture is released on Esc, app deactivation, key-window loss, window close, and widget disposal.

## Build

Use the pinned Flutter, not the global executable:

```sh
cd /Users/savva/code/minedart/spike/s4_mouse
/Users/savva/fvm/versions/stable/bin/flutter analyze
/Users/savva/fvm/versions/stable/bin/flutter test
/Users/savva/fvm/versions/stable/bin/flutter build macos --release
```

## Manual GUI check

```sh
open /Users/savva/code/minedart/spike/s4_mouse/build/macos/Build/Products/Release/s4_mouse.app
```

1. Focus the window and click **Capture mouse**. The cursor must disappear and remain at its capture position even after enough physical movement to cross a screen edge.
2. Move horizontally and vertically. Confirm the cube rotates, `events` rises, non-zero signed `delta` is shown, and note `events/s avg` after at least 10 seconds.
3. Click **Capture mouse** repeatedly while captured. The status must say the capture was already active, and there must still be only one effective stream: event rate and rotation sensitivity must not multiply.
4. Press Esc. The cursor must reappear and cube movement must stop.
5. Capture again, then Cmd-Tab away and return. Capture must be released with status `app-inactive`; it must not auto-recapture.
6. Capture again and switch Spaces. Verify release on focus loss.
7. With multiple displays, capture near every display edge, move across that edge for 10 seconds, then Esc. Deltas must continue while captured; note where the cursor reappears.

## Known limits

- GUI behavior is not proven by `flutter build`; the checklist above is required for E2E evidence.
- The local monitor observes this app's events only and therefore requires the app to stay active/key. That intentionally avoids global event taps and Accessibility permission.
- One platform-channel message is sent per native mouse event. Dart coalesces visual updates to one per Flutter frame, but very high polling-rate mice can still make channel traffic expensive. Measure before production use.
- Mouse acceleration remains macOS-controlled; `deltaX/deltaY` are not raw HID counts.
- Capture is process-global in effect. A production multi-window app needs a single app-level owner, not one controller per window.
- Spaces and multi-monitor behavior depend on WindowServer and must be tested manually on the target arrangement.
