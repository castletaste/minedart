---
name: minedart-game-ux
description: "Implement or debug Minedart's Flutter game shell: HUD, Pause and inventory surfaces, keyboard/mouse ownership, capture transitions, controls, accessibility, and responsive desktop/web behavior. Excludes voxel simulation and GPU rendering."
---

# Minedart Game UX

Keep Flutter UI, controllers, and input ownership separate from the Flame simulation. Use explicit callbacks/state rather than allowing widgets, native window events, DOM events, and the game loop to compete for the same action.

- Gameplay capture is entered only from a deliberate gesture on the game/HUD surface. Opening Pause, inventory, World Library, or another modal releases/suspends capture; arbitrary window clicks must not recapture it.
- `ModalInputRegion` owns pointer and keyboard input while visible. The capture/recapture click must never break or place a block, and closing a modal restores gameplay at most once.
- Preserve the canonical controls unless the user changes them: WASD, Space, double-W sprint, digits 1–9, `E` inventory, LMB break, RMB place, Escape Pause/release; `Q` and keyboard break/place stay unbound.
- The default nine-slot hotbar starts with TNT selected in slot 1. Inventory replacement may change slots without renumbering block ids.
- Hotbar digits, shadows, focus, and overlays must derive from current layout coordinates so window/fullscreen transitions cannot leave stale painting in the screen center.
- Pause and compact inventory must remain usable at a 360 px-wide viewport and desktop sizes. Keep the game visible behind Pause and expose controls in the menu. The startup hint hides after actual move/look input, returns after six active-gameplay seconds without movement, and hides again on activity; modal time does not advance that idle window.
- Sprint FOV is 70 to 75 with short allocation-stable interpolation; Reduced Motion keeps the base 70. F3 movement text must reflect the same physics state.
- Treat `docs/ux_redesign_0_3.md` and `docs/deep_links.md` as product contracts, but verify their status against current code before extending them.

Add deterministic controller/widget tests for state transitions and responsive layout. Live-check macOS and Web for cursor visibility, clickable modals, Escape/focus loss, capture-without-edit, LMB/RMB, inventory selection, hotbar scaling, sprint indication, and reduced motion.
