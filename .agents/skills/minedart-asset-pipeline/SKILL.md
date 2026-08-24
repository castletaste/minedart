---
name: minedart-asset-pipeline
description: "Create or debug Minedart's deterministic procedural atlas and audio: tile mappings, UV/alpha behavior, regeneration, visual QA, and IP-safe sourcing."
---

# Minedart Asset Pipeline

Generators are source: `app/bin/make_atlas.dart` owns the atlas and `make_sounds.dart` owns generated WAVs. Outputs must be deterministic; use generated or provenance-recorded compatible assets, never Mojang files.

- Atlas contract: 256² image, 16² row-major tiles. Keep generator indices, `Tiles`, `BlockDef.tiles`, HUD metadata, and tests synchronized without renumbering legacy block ids.
- Mesher UV inset is `0.5/256`; atlas/tile-size changes must update that contract. Preserve upright side faces and distinct top/bottom mappings.
- Opaque tile edges must not create accidental frames or bleed. Cutouts use transparent holes and opaque retained pixels around alpha 0.5; fluids may use partial alpha.
- Plants/mushrooms use two double-sided cross quads; do not add reversed duplicate geometry to fix texture issues.
- Keep WAV cue names aligned with `AudioCue`/pubspec, amplitudes bounded, and runtime variation deterministic where required.

From `app/`, regenerate with `dart run bin/make_atlas.dart` or `dart run bin/make_sounds.dart`; compare hashes when generator determinism changes. Run affected tests and live-check changed faces/cutouts on macOS and Web for flips, seams, borders, halos, and depth fighting.
