# Minedart Web performance 0.4

Status: design revision after cross-brand rejection; no production cache code
has been implemented yet.

## Baseline and non-goals

- Target `flame_3d 0.3.0`, pub.dev SHA-256
  `45310da41e63a690d79514b24f890b28251c3066aa0986db29ef48283541af0a`.
- Preserve the 20-float voxel vertex ABI, native FlutterGPU behavior,
  WebGPU water/cutout/depth/fog rendering and default render scale `1.0`.
- Never patch the global pub cache and never copy the disposable spike into
  production.
- Removing the unused 1024-byte joint-matrix upload is explicitly outside this
  change; it needs its own approval and evidence.

## Vendored upstream integrity

Production will use a direct path dependency at `third_party/flame_3d`, copied
from the exact hosted package, not `dependency_overrides`.

The vendored package must:

- retain the upstream MIT `LICENSE`;
- remove `resolution: workspace` from its pubspec;
- use an analysis configuration available in this repository;
- include `UPSTREAM.md` with package/version/pub.dev SHA-256, import date and a
  complete allow-list of intentionally changed files;
- include a deterministic drift test that hashes every non-allow-listed file
  and fails if it differs from the recorded upstream manifest.

The allowed diff must also prove that every non-web backend file is unchanged
except for the optional identity/revision signature that native ignores. The
project accepts that a vendored fork no longer receives upstream fixes
automatically; upgrading it is an explicit reviewed operation.

`app/bin/build_web_voxel_shader.dart` must be rerun after switching the path
dependency. The regenerated committed WGSL bundle must be byte-identical; any
difference blocks the optimization as an unrelated shader change.

## Cache lifetime contract

Persistent for resource lifetime:

- `_WebGpuPipeline`: sorted immutable shader-slot grouping plan only;
- `_WebGpuSampledTexture`: exactly one `GPUTextureView` for that backend texture
  lifetime;
- existing sampler object: stable identity for its own resource lifetime.

Strictly frame-local:

- uniform upload reuse;
- any cache entry containing a pooled uniform buffer/offset/size;
- bind groups, because they refer to frame-rotated uniform suballocations.

No bind group survives `_WebGpuFrame.end()`. This prevents frame N entries
from pointing at storage overwritten when the three uniform pools rotate.
Swapchain `getCurrentTexture().createView()` and depth views remain per-frame
and are never routed through sampled-texture view caching.

Within one frame a bind-group hit requires equality of:

- concrete `GPURenderPipeline` and its auto-layout identity;
- group index;
- every uniform upload buffer, offset, size and content revision;
- every texture-view identity;
- every sampler identity.

Any mismatch is a miss. Texture recreation creates a new backend texture/view.
Pipeline recreation creates a new concrete pipeline/layout. Both invalidate by
identity without global eviction logic.

## Uniform identity and revision

Each retained shader uniform binding has stable identity and a monotonic
revision. Setters compare the incoming Float32/byte content before writing:

- identical bytes perform no write and do not bump revision;
- any changed byte writes the new content and bumps revision exactly once;
- raw/matrix/vector/color/scalar setters share this rule;
- material and camera bindings remain independent identities.

The compare uses a retained byte copy, never mutable `Float32List`, matrix
storage or color-cache identity. `Shader.createResource()` resets binding
identities/revisions and begins with empty frame-local caches.

This is required because material `apply()` runs per surface every frame. A
revision that increments per setter call would intentionally produce zero
cache hits.

Native FlutterGPU accepts the optional identity/revision metadata and ignores
it. A compile-time `FLAME_3D_WEBGPU_BIND_CACHE` switch defaults to `true`; when
false the Web backend follows the upstream allocation/bind path.

The production default is `const bool.fromEnvironment(...)`. An internal
constructor override exists only for fake-device tests, so enabled and disabled
paths run in one VM suite. Benchmark arms remain separate release builds:

- cache on: default build;
- cache off: `--dart-define=FLAME_3D_WEBGPU_BIND_CACHE=false`.

## Deterministic cache tests

- Idempotent uniform set keeps revision; changed bytes increment it.
- Different pipeline/layout, group, uniform revision, texture view or sampler
  each force a bind-group miss.
- Repeated texture binds call `createView()` once; recreated texture uses a new
  view and misses.
- A fake four-frame run proves no bind group or pooled uniform allocation is
  reused across frames, including frame N+3 pool rotation.
- With the kill switch off, the observed upload/bind-group call sequence equals
  upstream.
- Native analyze/tests prove the metadata-only API addition is inert.

### Executable test seam and CI

The vendored package adds one platform-neutral internal module under
`lib/src/graphics/backend/web_gpu/cache_policy.dart`. It imports neither
`dart:js_interop` nor `dart:ui_web`; the real Web backend supplies opaque
pipeline/layout/buffer/view/sampler tokens and allocation/create callbacks.
The module owns frame-local keys, hit/miss accounting and frame reset. It is
public only under `src/` with `@visibleForTesting` types and is not exported by
the package facade.

The intentional upstream-diff allow-list therefore includes only:

- retained shader binding/revision code;
- generic `GraphicsDevice` metadata plumbing;
- inert native backend signatures;
- Web backend integration plus `cache_policy.dart`;
- vendored pubspec/analysis/provenance/test files.

Test routing is explicit:

- VM tests: provenance SHA-256 drift, compare-before-write revisions, partial
  setters, fake four-frame pool rotation, complete bind keys, texture-view
  lifetime tokens, fallback resources, enabled/disabled call sequences and
  bounded cache counters;
- headless Chrome test: conditional Web import/compile smoke plus the fake-token
  cache suite; it does not request a real adapter/device;
- live foreground Chrome release QA: actual adapter/device, real createView /
  upload / bind hit counters, 60-second bounded-memory soak and visual parity.

The project CI must add `third_party/flame_3d` analyze + VM tests + focused
`flutter test --platform chrome` before app analyze/tests. A real WebGPU device
is explicitly not claimed by headless CI; that remains release evidence.

## Allocation-stable telemetry

Use preallocated fixed-capacity rings for independent wall-frame, update,
CPU-render and main-thread-mesh samples. Reused stopwatches feed the rings.
GPU execution time is not claimed.

- `drawCount` comes from the live render context after rendering.
- DPR and effective 3D target dimensions are reported together.
- Mesh queue and retained component/mesh-byte counts are snapshots.
- The HUD computes one percentile snapshot at most four times per second; each
  metric is copied/sorted once for p50/p95/p99.
- Web telemetry reports per-frame upload and bind-group cache hit/miss counts so
  map churn and actual reuse are measured, not inferred.
- The 60-second benchmark uses separate preallocated capture buffers, not the
  short HUD ring.
- Main-thread mesh time is accumulated by the web drain and atomically consumed
  into the next frame sample; it is labelled CPU drain time, not GPU/frame
  overlap.

## Web mesh scheduling

- Coalesce to the newest generation per chunk before `ChunkSnapshot.capture`.
- Use an indexed min-heap with deterministic distance/tie ordering and lazy
  stale-node removal.
- Rebuild priorities when the priority origin changes chunk.
- Budget adapts downward from a hard 6 ms ceiling: about 1.5 ms during active
  movement/look, 3 ms idle and up to 6 ms initial loading.
- A single non-interruptible mesh may exceed the target; record max-job time.
- Failure drops only the failed attempt and schedules a bounded retry when it
  is still the newest generation; the queue continues making progress.
- Dispose suppresses later timers/results and closes the stream once.
- Native isolates implement the same request/generation contract.

Tests cover nearest order, deterministic ties, latest-only capture, origin
rebuild, stale result rejection, failure progress/retry cap, budget boundaries,
queue overflow recovery and disposal.

## PackedSurface and measured-only work

When a chunk AABB is supplied, `PackedSurface` does not materialize a separate
positions array. A lazy public getter remains correct if read; eager AABB and
Uint16 indices are unchanged.

Retained-chunk eviction is telemetry-first. Implement eviction only after an
rd10 -> rd6 or travel comparison proves retained bytes/components are material.
Do not add a public GPU buffer-disposal contract without a separate decision.

Audio preload changes are gated on a fresh Chrome network trace after the
parallel audio work lands. They are startup claims, never FPS claims.

## Benchmark contract

Use a clean known commit containing current production worldgen and no dirty
audio or unrelated code. Never benchmark the disposable spike world.

For cache off/on at rd6 and rd10:

1. Release Wasm in foreground Chrome WebGPU, DPR exactly 2, with no render-scale
   feature introduced (native target equals CSS viewport times DPR),
   `crossOriginIsolated=true` and constant viewport.
2. Assert visible document and the requested render distance/draw count.
3. Wait for mesh queue zero plus at least 120 stable frames.
4. Capture at least 60 seconds, three runs per arm in A/B/A order.
5. Report p50/p95/p99 wall-frame/update/CPU-render/mesh, draw count, target
   dimensions, queue, retained mesh bytes and JS-memory/long-task proxy.
6. Exclude load/decode/warm-up. Keep F3 state identical between arms.
7. Success requires at least 15% lower CPU-render median and no frame-p95
   regression larger than `max(0.2 ms, 3%)`.
8. After each pass's first miss, group-1 bind-group hit rate must be at least
   90%; otherwise the cache target or telemetry is wrong and the perf claim is
   rejected even if timing noise looks favorable.

Screenshots and live checks cover fog, alpha cutout, water, depth, Pointer Lock,
LMB/RMB, Escape/re-capture and a clean release console. The fixed WebGPU to 2D
blit remains in both arms and is reported as an unisolated fixed cost.

The current voxel bundle was inspected: group 0 contains `JointMatrices` plus
per-draw `VertexInfo`; group 1 contains the atlas texture/sampler plus stable
`Material` and `Camera`. Therefore the first production target is group-1
reuse within each frame. Group 0 is expected to miss when model bytes change,
and no win is claimed for removing its joint upload in this scope.
