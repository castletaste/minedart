---
name: minedart-performance
description: "Measure or improve Minedart frame, render, mesh, GPU-binding, startup, and retained-memory performance with allocation-stable telemetry and reproducible macOS/WebGPU benchmarks."
---

# Minedart Performance

Start from current production code and one deterministic scene. Disposable spikes are evidence only: never copy their code or report their numbers as production results. Read `docs/web_performance_0_4.md` for the active benchmark/cache contract, then verify that its status still matches the checkout.

- Keep hot telemetry allocation-stable: fixed-capacity samples, independent wall/update/CPU-render/main-thread-mesh channels, and percentile publication no more than four times per second.
- Report actual draw count, mesh queue, DPR/effective 3D target size, retained components/mesh bytes, cache hit/miss counters, and a stated memory/GC proxy. Missing counters are unverified, not zero.
- WebGPU uniform uploads and bind groups containing pooled allocations are frame-local. Cache keys and invalidation must cover pipeline/layout, uniform identity/revision/allocation, and texture/sampler identity; keep an independently buildable cache-off arm.
- Web meshing changes require newest-generation-per-chunk coalescing, nearest deterministic priority, bounded dynamic budgets, retry/progress after failure, and disposal invariants. Avoid capturing snapshots for superseded dirty requests; verify these are implemented before reporting them.
- Known chunk AABBs may remove position copies only when they conservatively contain cubes, plants, and fluid geometry. Measure retained-component eviction, minimap work, audio preload, or bundle pruning before implementing or claiming benefit.
- Do not reduce default render scale without a separate GPU-bound benchmark and explicit product decision.

For Web cache A/B, use foreground release Wasm on the same visible scene at DPR 2 and rd6/rd10. Wait for queue zero plus at least 120 stable frames, record at least 60 seconds, and report p50/p95/p99 for frame/update/render/mesh with counter evidence. A cache success claim requires at least 15% lower CPU-render median, no worse frame p95, visual/input parity, clean console, and at least a 90% target-group hit rate. Use `minedart-web-runtime`, `minedart-flame-3d`, and `minedart-release-qa` for target-specific implementation and proof.
