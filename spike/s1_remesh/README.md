# S1: flame_3d 0.3.0 chunk remesh benchmark

## Verdict

- Stock `List<Vertex> -> Surface`: **NO** for a 4 ms in-frame budget.
  Exact flame_3d JIT total: **22.108 ms median / 28.229 ms p99**.
  CPU-faithful Dart AOT mirror: **17.897 / 22.894 ms**.
- Direct `Float32List` public API: **NO**. `Surface` exposes no raw-buffer
  constructor and its packed fields are library-private.
- `PackedSurface extends Surface` workaround: **YES, but fragile**.
  Exact flame_3d JIT full remesh: **0.294 / 1.593 ms**. AOT mirror:
  **0.611 / 1.182 ms**. It is under 4 ms in these CPU measurements.
- Actual Flutter release AOT and real GPU rendering: **NOT MEASURED** because
  the sandbox blocked Xcode DerivedData, SwiftPM cache and CoreSimulator.
  The ready app benchmarks at startup and renders the packed chunk manually.

## Geometry and method

- Flutter 3.44.4 stable, Dart 3.12.2, macOS arm64.
- `flame_3d 0.3.0`, `flame 1.38.0`.
- Deterministic `Uint16List` chunk: 16x16x16, 646 solid blocks.
- Culled (not greedy) mesh: 3244 visible quads, 12976 vertices, 19464
  uint16 indices.
- Packed vertex layout is flame_3d's 20 floats: position 3, UV 2, color 4,
  normal 3, joints 4, weights 4.
- Vertex buffer: 1,038,080 bytes; index buffer: 38,928 bytes.
- Each metric used 20 warmups followed by 100 isolated timed iterations.
- median is the usual middle value; p99 is nearest-rank. Stopwatch frequency
  was 1 GHz.
- The tables report the median of three independent process-level results.
  Each process still contains its own 100 samples.

## Exact flame_3d measurements (`flutter test`, JIT)

| Stage | median ms | p99 ms |
|---|---:|---:|
| A: generate packed face/index data | 0.237 | 1.246 |
| B: construct `List<Vertex>` | 9.471 | 17.869 |
| C: default `Surface(...)` | 6.178 | 20.270 |
| C with `calculateNormals: false` | 6.167 | 19.684 |
| `PackedSurface` constructor | 0.047 | 0.078 |
| Stock A+B+C | 22.108 | 28.229 |
| Packed A+hack | 0.294 | 1.593 |

The normal-presence scan is not the problem. Disabling it changes median C by
only 0.011 ms. The expensive operations are per-vertex construction and the
`fold([], addAll)` plus typed copies inside `Surface`.

## `dart compile exe` measurements (AOT CPU mirror)

The actual package cannot be compiled by `dart compile exe`: importing
flame_3d pulls in `dart:ui` and `flutter_gpu`; Dart 3.12.2 fails AOT compilation.
The mirror reproduces vector typed storage, immutable vertex records, null
joint/weight zero vectors, `fold/addAll`, positions/index copies and AABB work,
but it is not the real flame_3d class.

| Stage | median ms | p99 ms |
|---|---:|---:|
| A: generate packed face/index data | 0.538 | 1.609 |
| B: construct mirrored vertices | 6.516 | 9.294 |
| C: mirrored Surface CPU work | 6.993 | 7.890 |
| Packed constructor CPU work | 0.049 | 0.067 |
| Stock A+B+C | 17.897 | 22.894 |
| Packed A+hack | 0.611 | 1.182 |

## Allocation count

For each of 12,976 stock vertices, the pinned source explicitly creates:

- one `Vertex`, one 20-float storage and three immutable records;
- five temporary vector objects and five typed backing lists: position, UV,
  normal, zero joints and zero weights;
- the aggregate list literal and the nested color list literal.

That is **17 source-level objects per vertex**, or **220,592 objects**, plus
the `List<Vertex>` and Surface-level work. The VM may scalar-replace some
temporaries, while spread iterators and growable-list backing reallocations can
add objects, so this is an analytical source count rather than profiler data.

Stage C also creates a 259,520-element growable `List<double>`, then copies it
to a 1,038,080-byte `Float32List`, creates a 155,712-byte positions array,
copies indices, and constructs AABB vectors.

The packed path has no per-vertex objects. Including mesh output and the
unavoidable one-vertex dummy `super` call, it has approximately **47 explicit
source-level objects per chunk**, constant O(1), rather than O(vertices).

## Workaround contract

`PackedSurface` overrides every property consumed by
`GraphicsDevice.bindGeometry`: resource creation, byte sizes, counts, positions,
indices, AABB and resource invalidation. A fake backend test verified two GPU
buffer writes:

- 1,038,080 vertex bytes at offset 0;
- 38,928 index bytes at offset 1,038,080.

The superclass still performs a fixed dummy construction because Dart requires
calling `Surface`'s only constructor. This is implementation-sensitive and must
be revisited when flame_3d changes.

## Commands

```sh
cd /Users/savva/code/minedart/spike/s1_remesh

/Users/savva/fvm/versions/stable/bin/flutter analyze
/Users/savva/fvm/versions/stable/bin/flutter test test/flame_benchmark_test.dart --reporter expanded

/Users/savva/fvm/versions/stable/bin/dart compile exe bin/aot_benchmark.dart -o build/s1_aot_benchmark
./build/s1_aot_benchmark
```

Manual release/GPU check outside the sandbox:

```sh
cd /Users/savva/code/minedart/spike/s1_remesh
/Users/savva/fvm/versions/stable/bin/flutter build macos --release
./build/macos/Build/Products/Release/s1_remesh.app/Contents/MacOS/s1_remesh
```

The app prints exact release-AOT JSON between
`S1_FLAME_BENCHMARK_BEGIN/END` and renders the same chunk through
`PackedSurface`. Verify that the green sparse voxel chunk appears without
corruption or GPU errors.
