# Touch controls and web startup

Touch controls are enabled initially for a coarse primary pointer on web and
Android/iOS on native platforms. A touch on the game surface also enables them
on hybrid devices. Pause → Controls → Touch controls is an explicit override
for the current session; later touches do not reverse that choice.

- Move with the left stick; push fully forward to sprint.
- Drag the world to look. Existing look sensitivity and vertical inversion apply.
- Hold the up-arrow button to jump. A short tap remains pending until an actual
  fixed physics step consumes it, including on high-refresh displays.
- Tap minus to break the targeted block, plus to place the selected block.
- Swipe the hotbar horizontally and tap a slot. Slots retain their 48 px width.
- The top-left buttons open Pause and Inventory. The minimap uses a compact
  layout and system safe-area insets are respected.

`GameShell` owns the selected control mode. `TouchControls` owns gesture pointer
IDs and only its joystick subtree rebuilds during movement. `MinedartGame` owns
`TouchInputState`, merges touch with keyboard input, and gates touch actions on
active runtime ownership, foreground state, readiness, and modal/pause state.
Desktop pointer capture and touch action gates remain separate. A touch never
requests Pointer Lock; DOM pointer-lock actions accept mouse events only.

Opening a modal, backgrounding, switching worlds, quiescing, or disposing drops
held and queued touch input. Gesture owners are removed/reset too, so late
pointer events cannot reactivate an old gesture after returning to gameplay.

The HTML loading screen appears before Flutter starts and offers retry for
engine loading failure. Flutter reports WebGPU API, adapter, and device startup
failures separately with recovery guidance; diagnostic causes stay in logs.
The release retains local renderer resources, Wasm, and the JS fallback.

## Validation (2026-09-06)

- App analyzer and formatter: pass.
- App VM suite: 331 tests pass.
- Chrome Pointer Lock / gzip suite: 8 tests pass, including non-mouse rejection.
- Vendored renderer analyzer and focused graphics/provenance tests: pass (11).
- Wasm release + bundle verification: pass; 89 files, local renderer resources,
  `main.dart.wasm`, `main.dart.mjs`, and `main.dart.js` present.
- Deterministic widget tests cover simultaneous movement/look/jump/edit,
  pointer cancellation, late events after background/menu reset, mouse routing,
  horizontal hotbar selection, and 320×568, 360×640, 640×360 with safe insets.
- Live local release in the Codex browser: WebGPU world presented, desktop
  Pause/Controls opened, touch mode enabled, and mobile HUD presented at 360×640.
  No captured browser errors in that observed startup/menu path.

Physical Android/iPhone multi-touch, sensitivity feel, landscape browser UI,
PWA mode, background/kill/save/reopen, and warmed phone performance remain
unverified. The owner reports the existing renderer works on their phone; that
is separate from validation of these new controls. No render-scale default was
changed and no FPS improvement is claimed.
