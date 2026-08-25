---
name: minedart-flame-3d
description: "Implement or debug Minedart's flame_3d/flutter_gpu renderer: packed chunk surfaces, voxel shaders, culling, GPU bootstrap, and live rendering. Excludes voxel logic and persistence."
---

# Minedart Flame 3D

Production code is canonical; `spike/REPORT.md` is evidence only. Never copy spike code into production.

- Check `app/pubspec.yaml` and `app/pubspec.lock`. The contracts were validated on `flame_3d 0.3.0`/`flame 1.38.0`; version or source changes require rechecking Surface ABI, shader slots, culling, and bootstrap.
- If `flame_3d` resolves from `third_party/flame_3d`, treat `UPSTREAM.md`, `UPSTREAM_MANIFEST.sha256`, its change allow-list, and MIT license as integrity contracts. Never patch the global pub cache or copy disposable-spike code into the fork.
- Keep `ChunkMeshData` as the pure-Dart boundary and its 20-float layout: position 3, UV 2, color 4, normal 3, joints 4, weights 4.
- Feed typed buffers directly to `PackedSurface`; never repack the remesh hot path through `List<Vertex>`. Chunk surfaces should pass their known local AABB so positions stay lazy; preserve conservative culling correctness for plants and fluids.
- Preserve opaque/translucent passes, baked vertex lighting/AO, hard alpha cutout, and two non-duplicated cross quads.
- Keep native shader sources/bundle and the Web WGSL bundle aligned. Initialize `GpuBackend` first; preserve the macOS Impeller/FlutterGPU plist flags and `images.prefix = 'assets/';`.
- WebGPU cache work must keep pooled uniform uploads and bind groups frame-local. Keys include pipeline/layout, uniform identity/revision/content allocation, and texture/sampler identity; material, camera, pipeline, or resource changes must invalidate reuse. Preserve the compile-time cache-off arm and allocation-stable counters.
- Component-per-chunk is validated only at current finite-world scale. Consult `spike/NOTES-s6-culling.md` and remeasure before materially increasing visible meshes.

Verify provenance/drift tests, shader bundle equality, affected ABI/tests, build, and live renderer. A build is not visible-GPU proof; inspect cutouts, fluids, fog, seams, depth fighting, cache invalidation, and stale remeshes on each claimed target.
