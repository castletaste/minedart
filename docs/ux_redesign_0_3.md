# Minedart UX/worldgen redesign 0.3

Status: approved on 2026-08-25. Multiplayer remains out of scope.

## Product contract

- `E` opens a compact block inventory. `Q` and keyboard-place are removed;
  world edits remain LMB/RMB only.
- The inventory shows blocks absent from the nine-slot hotbar. Activating a
  tile replaces the selected slot and closes the modal. Digits 1-9 select the
  replacement slot; E/Escape close it.
- Initial slot 9 is TNT instead of brick.
- Photo Mode, P binding, capture UI and photo-only renderer state are removed.
- Pause remains, with a compact original block-game visual language and a
  visible control-key legend. The same non-interactive legend appears on world
  start and disappears on the first movement/look input.
- Create World exposes Classic, Flat and Islands presets. `seed`, `preset` and
  local `world` URL parameters remain; `builder` is removed entirely.
- Islands are deterministic and materially richer: varied archipelago masks,
  beaches/shelves, cliffs, stone/gravel variation, trees/flora, caves and ore
  pockets, plus a safe spawn.
- The game root owns a Material/Scaffold context, so HUD text never inherits
  Flutter's yellow diagnostic underline.

## Stable boundaries

- World dimensions, block ids 1-32, chunk ordering, MDRT2 and the 20-float
  mesh vertex ABI do not change.
- Preset is still inferred from safe world-id prefixes; no MDRT migration.
- Inventory/pause modals own input through `ModalInputRegion`; opening them
  releases Pointer Lock, and the recapture click must not edit the world.
- All UI layout decisions use parent constraints, not platform checks.
- No Mojang texture, font or audio assets.

## Agent write ownership

- Islands agent: new/changed pure-Dart generator files under
  `packages/core/lib/src/gen/**`, core exports and core generator tests only.
- Inventory agent: `builder_studio_controller.dart`, `builder_studio.dart`,
  `block_palette.dart` and their focused controller/widget/HUD tests only.
- Pause agent: `pause_options.dart`, a new shared controls-hint widget, and
  focused pause/hint widget tests only.
- Preset agent: World Library controller/view/callback contracts and their
  focused tests only. It defines a UI-layer preset choice enum.
- Main agent: `ShowcaseApp`, main/input/game integration, launch config,
  world-preset mapping, exports, renderer cleanup, photo-file deletion,
  dependency resolution and all conflicts.

## Acceptance and review

- Compact inventory fits both a 360 px viewport and desktop without a
  full-height studio or horizontal hotbar editor.
- macOS and web live checks cover E, Escape, Pointer Lock release/recapture,
  inventory selection, Pause controls and the startup hint dismissal.
- Islands tests prove same-seed hash stability, mixed water/land/beach/cliff
  materials, flora/trees, caves/ores and a safe spawn.
- GPT-authored core is reviewed by Anthropic; GPT-authored Flutter/runtime is
  reviewed independently by another Anthropic reviewer before final QA.
