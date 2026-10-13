# Live QA and performance baseline 0.5

This checkout now has a repeatable baseline collector at
[`app/tool/collect_qa_baseline.sh`](../app/tool/collect_qa_baseline.sh). It
records the exact checkout, core/app analysis and tests, the Wasm release build,
and a CSV for live target measurements. It does not invent GPU or device data.

Run it from the repository root:

```sh
bash app/tool/collect_qa_baseline.sh
```

The generated directory is intentionally ignored from the source change. Keep
the directory as review evidence when a target run is available.

For WebGPU, use the release Wasm output in foreground Chrome with a fixed
viewport, `devicePixelRatio == 2`, `crossOriginIsolated == true`, and the
default scene. Run render distance 6 and 10 separately. Wait for mesh queue zero
and at least 120 stable frames, then record three 60-second runs in A/B/A order.
Fill `live-metrics.csv` with p50/p95/p99 wall-frame, update, CPU-render, and
CPU mesh-drain values, plus draw count, target dimensions, retained mesh bytes,
cache counters, and a stated memory/GC or long-task proxy. Keep cache-on and
cache-off builds as separate arms:

```sh
(cd app && bash tool/build_web_release.sh)
(cd app && fvm flutter build web --wasm --release --no-web-resources-cdn \
  --dart-define=FLAME_3D_WEBGPU_BIND_CACHE=false)
```

The Web run also checks visible textured output, cutouts, fluids, fog, Pointer
Lock, LMB/RMB, Escape, modal recapture, and a clean browser console.

For macOS, use a release Impeller build and repeat startup, pause/resume,
inventory, world replacement, save/reload, close, and fullscreen/window
transitions. Record the same frame and mesh fields where the native HUD exposes
them. Persistence evidence must include a restart; a single process run is not
enough.

The automated collector is evidence for code, tests, and packaging. A real
WebGPU adapter and a macOS window remain live-target evidence and must be
marked untested when those targets are unavailable.
