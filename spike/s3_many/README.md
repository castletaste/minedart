# S3: many mesh components

Disposable macOS Flame 3D spike for a chunk-like scene: each `MeshComponent`
owns a different `Mesh` and one different `Surface` of 1,000 quads.

## Profiles

The release default is 1,350 components. Use exactly one of `100`, `400`,
`800`, or `1350` at compile time:

```sh
/Users/savva/fvm/versions/stable/bin/flutter run -d macos --release --dart-define=MESH_COUNT=1350
```

The upper-left overlay has EMA FPS, total components and `Visible / draws`.
The console additionally prints these values every two seconds. `Visible /
draws` is the preceding frame's `RenderContext3D.drawCount`; because this
spike has one Surface per component, it equals the actual draw-call count.

For a repeatable manual comparison, run each profile after a 10-second warmup,
then record 30 seconds of the two-second console samples. Keep window size,
power state and other GPU-heavy applications unchanged.

## Build

```sh
cd /Users/savva/code/minedart/spike/s3_many
/Users/savva/fvm/versions/stable/bin/flutter analyze
/Users/savva/fvm/versions/stable/bin/flutter build macos --release
open build/macos/Build/Products/Release/s3_many.app
```
