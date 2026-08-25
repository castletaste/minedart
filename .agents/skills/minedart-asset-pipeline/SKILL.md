---
name: minedart-asset-pipeline
description: "Create or debug Minedart's deterministic texture atlases and audio assets: provenance, tile and cue contracts, regeneration, alpha behavior, visual or listening QA, and IP-safe sourcing."
---

# Minedart Asset Pipeline

Generators and recorded sources are canonical. Outputs must be deterministic and IP-safe; never copy or minimally transform Mojang assets.

- Default atlas: `app/bin/make_alpha_atlas.dart` plus `app/tool/atlas_sources/default_alpha/**` own `atlas_alpha.png`. Preserve its timestamp-free provenance, accepted-sheet hash, 16x16 masters, generator hash, and output hash.
- Legacy fallback: `app/bin/make_atlas.dart` owns `atlas.png`. Do not delete or silently regenerate it. An approved additive tile must preserve reproducibility of the previous hash and update both provenance contracts explicitly.
- Runtime selection is `MINEDART_ATLAS=alpha|legacy`; `alpha` is default and invalid values fail. Keep the selected atlas and HUD swatch palette aligned.
- Atlas contract: 256² RGBA image, 16² row-major tiles. Keep generator indices, `Tiles`, `BlockDef.tiles`, HUD metadata, and tests synchronized without renumbering assigned block ids.
- Mesher UV inset is `0.5/256`; atlas/tile-size changes must update that contract. Preserve upright side faces and distinct top/bottom mappings.
- Opaque tile edges must not create accidental frames or bleed. Cutouts use transparent holes and opaque retained pixels around alpha 0.5; fluids may use partial alpha.
- Plants/mushrooms use two double-sided cross quads; do not add reversed duplicate geometry to fix texture issues.
- Audio sources need a checked-in source/license record. Keep WAV cue names aligned with `AudioCue`, material mappings, and pubspec; avoid clipping or sharp level jumps, and preserve deterministic variation where required. Startup preload/deduplication is runtime work, not an FPS claim.

From `app/`, regenerate with `fvm dart run bin/make_alpha_atlas.dart`, `fvm dart run bin/make_atlas.dart`, or `fvm dart run bin/make_sounds.dart` as appropriate. Compare hashes, run affected asset/runtime tests, and live-check changed faces/cutouts on macOS and Web for flips, seams, borders, halos, transparency, depth fighting, and cue harshness.
