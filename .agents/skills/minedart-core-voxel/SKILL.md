---
name: minedart-core-voxel
description: "Implement or debug Minedart's pure-Dart voxel core: blocks, chunks, worldgen, meshing, physics, raycasts, bounded simulation, and edit history. Excludes Flutter, rendering, and storage."
---

# Minedart Core Voxel

Keep `packages/core` pure Dart: no Flutter, `dart:ui`, platform IO/JS, Flame, or app types.

- Preserve the finite 256x64x256 world, 16-cubed chunks, chunk order `cx + cz*X + cy*X*Z`, and local order `x + z*16 + y*256` unless persistence migrates too.
- Blocks are `Uint16` with 12-bit id/4-bit metadata. IDs 1–21 are legacy contracts. Add behavior through `BlockDef`/`BlockBehavior` and synchronize definitions, atlas, validation, and tests.
- Use `VoxelWorld.setBlock` or `WorldChangeSetBuilder` to maintain skylight and dirty chunks; bulk writes require recount/skylight recomputation. Preserve core's full dirty set.
- `ChunkSnapshot` is an immutable 18³ block plus 18² skylight halo. `ChunkMeshData` is deterministic typed output with opaque/translucent passes and the 20-float vertex ABI.
- Keep hidden-face culling, AO/light, fluid height, half-texel UVs, and two-quad crosses deterministic.
- Local `Chunk.revision` misses halo-only changes; app scheduling must use a monotonic per-target mesh generation.
- Preserve fixed-step physics with retained remainder, swept voxel collision, DDA raycasts, bounded FIFO tick work, and grouped change sets for undo/redo.

Run `dart analyze` and `dart test` in `packages/core`; benchmark only performance claims. Load `minedart-world-storage` for id, dimension, raw-layout, or ordering changes.
