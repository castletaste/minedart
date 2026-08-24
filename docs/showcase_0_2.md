# Minedart Classic Showcase 0.2 — implementation contract

Status: historical 0.2 snapshot, superseded by `ux_redesign_0_3.md` and
`deep_links.md`. The current product keeps multiplayer out of scope and does
not expose removed 0.2-only surfaces or bindings.

## Product acceptance

- 32 selectable non-air blocks, preserving IDs 1..21 for MDRT1 saves.
- `E` opens the compact block inventory; keyboard/focus/semantics remain
  supported at compact and desktop sizes.
- Classic controls: `F` cycles fog presets, `Enter` saves a teleport point,
  `R` teleports to it; noclip moves to a rebindable action.
- Target outline, pooled block particles, procedural/CC0 audio.
- Deterministic falling sand/gravel, bounded water/lava updates, sponge
  absorption, TNT fuse/explosion. No entity or network simulation.
- Undo/redo groups world edits and simulation consequences.
- Multiple worlds on macOS and web. Native uses files; web uses IndexedDB.
  Import/export uses the same MDRT2 bytes. MDRT1 remains readable.
- World Library supports create, load, rename, duplicate, delete/reset,
  import/export and seed sharing. Destructive UI still confirms explicitly.
- Flutter showcase: Render Lab, expanded F3 frame graph, passive minimap,
  adaptive settings/input rebinding, high contrast/reduced motion.
- macOS release >=60 FPS on the current Apple Silicon machine; web remains
  playable after initial time-sliced meshing.

## Stable contracts

### Core

- `VoxelWorld`, `Chunk`, `ChunkMeshData` and the 20-float vertex ABI remain
  Flutter-free.
- IDs 1..21 never change. IDs 22..32 add lava, TNT, sapling, gold/iron
  blocks and six cloth colours.
- `BlockDef` gains behavior flags through a small enum, not feature-specific
  checks spread across the app.
- `WorldTickEngine` owns bounded simulation queues. One call accepts an update
  budget and returns a grouped change set plus dirty chunks.
- `EditHistory` stores grouped old/new raw block values. It is capped and
  returns dirty chunks on undo/redo.

### Persistence

- `WorldRepository` is the single source of truth for world summaries and
  bytes. UI never calls `dart:io` or IndexedDB directly.
- MDRT2: magic/version + UTF-8 metadata + gzip block payload. Metadata includes
  id, name, seed, created/updated timestamps, spawn and format version.
- MDRT1 loader migrates to MDRT2 in memory; no destructive rewrite until the
  next explicit/autosave.
- Native repository: Application Support/minedart/worlds/<id>.mdrt.
- Web repository: IndexedDB database `minedart`, store `worlds`, key `id`.
- Deep links share seed/preset only. Full edited worlds use export/import.

### Flutter UI

- UI follows View + ChangeNotifier/Listenable controller boundaries.
- Layout decisions use `LayoutBuilder` constraints: compact <600, medium
  600..899, expanded >=900. No platform-name layout branching.
- Game input is disabled while a modal editing/settings surface owns focus.
- Every block tile and control has semantics labels and keyboard focus.

### Renderer/demo

- Existing PackedSurface and VoxelMaterial paths remain canonical.
- Outline and particles are pooled components; no per-frame mesh allocation.
- Render Lab updates uniforms/settings, not shader/material instances.
- F3 samples into a fixed-size ring buffer; charts repaint without rebuilding
  the game widget.
- Minimap is a Flutter CustomPainter over the height map, not another 3D pass.

## Agent write ownership

- Core agent: `packages/core/lib/src/showcase/**`, core tests, and additions to
  `block.dart`/exports only.
- Persistence agent: `app/lib/data/worlds/**`, persistence tests, no UI/main.
- UI agent: `app/lib/showcase/ui/**`, `app/lib/showcase/controller/**`, widget
  tests, no renderer/core.
- Renderer agent: `app/lib/showcase/render/**`, shader/render integrations,
  renderer tests, no persistence/core.
- Audio agent: `app/lib/audio/**`, `app/bin/make_sounds.dart`, generated audio
  assets, no pubspec/main.
- Main agent owns pubspec, main/game integration and all conflict resolution.

## Review gates

1. Main agent integrates and runs app/core tests.
2. GPT-authored code is reviewed by Claude Opus; Claude-authored code is
   reviewed by GPT Sol.
3. Only reproducible defects against this contract are fixed in-place.
4. Scope expansions are reported separately; multiplayer is never inferred.

## Validation snapshot

- Local `.fvmrc` resolves the working stable SDK (Flutter 3.44.4 / Dart
  3.12.2 during validation); CI pins 3.44.4 exactly.
- `flutter analyze`: clean.
- App tests: 139 passed. Core tests: 79 passed.
- macOS release: 47.1 MB; live F3 capture at render distance 16 showed
  105 FPS, p50 8.3 ms and p95 16.7 ms with an empty mesh queue.
- Web Wasm release: verified by `tool/build_web_release.sh` (76 files, largest
  asset 7,229,467 bytes). Live WebGPU smoke showed ~57 FPS, p50 16.7 ms and
  p95 25.0 ms at render distance 6 with an empty mesh queue.
- Current browser contracts cover seed/preset/world deep links, compact
  inventory, Pause, World Library, Render Lab, F3, IndexedDB startup, water
  rendering and water on the minimap. Removed 0.2 URL/UI surfaces are not
  supported.
- The polish pass adds double-W sprint, 200 ms falling-block cadence,
  material-specific soft grass/dirt/wood/leaves audio, noclip minimap tracking,
  and light-blocking alpha-cutout leaves.
- Cross-brand review gates were run with GPT and Anthropic reviewers. Confirmed
  defects were fixed and the renderer post-fix review returned clean.

Known upstream limitation: flame_3d 0.3.0 does not expose deterministic
per-resource GPU disposal; replaced mesh buffers are reclaimed by its resource
and runtime lifecycle rather than an app-level dispose API.
