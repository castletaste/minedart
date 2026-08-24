# WebGPU performance evidence — 2026-08-25

## Evidence scope

These measurements were captured while `e3b0162` was HEAD, with later audio
work still present as uncommitted working-tree changes. Subsequent eviction,
audio, hotbar, and modal-input commits were not part of this capture. The data
is retained as directional bind-cache evidence, not as a current-HEAD release
performance pass. A release claim must rerun the complete benchmark contract
from `web_performance_0_4.md` on a recorded clean commit.

## Method

- Flutter Wasm release in Chrome's WebGPU backend.
- Deterministic scene: `seed=0x5eed`, `preset=islands`, unchanged camera.
- Effective 3D target: 2976x1966 pixels at DPR 2.00.
- Each measured arm started only after `mesh queue 0`.
- Each row is a 7200-frame window, approximately 60 seconds at 120 Hz.
- Percentiles are nearest-rank values from allocation-stable retained rings.
- Build defines used only for evidence collection:
  - `MINEDART_PERF_SAMPLE_CAPACITY=7200`
  - `MINEDART_PERF_SNAPSHOT_INTERVAL_MS=1000`
- Cache-off arms additionally used
  `FLAME_3D_WEBGPU_BIND_CACHE=false`.
- Ordering was A/B/A at both render distances: cache on, cache off, cache on.

The reported render channel is CPU render submission time, not GPU execution
time. F3 remained enabled in every arm so measurement overhead was symmetric.

## Results

All timing cells are p50 / p95 / p99 milliseconds.

| RD | Arm | Wall frame | Update | CPU render | Draws | Uniform hit/miss | Bind-group hit/miss |
|---:|:---|:---|:---|:---|---:|:---|:---|
| 6 | on A | 8.3 / 10.3 / 10.3 | 0.1 / 0.1 / 0.2 | 2.4 / 2.7 / 2.9 | 183 | 364 / 2 | 182 / 1 |
| 6 | off B | 8.3 / 10.3 / 10.3 | 0.1 / 0.1 / 0.3 | 2.9 / 3.3 / 3.7 | 183 | 0 / 366 | 0 / 183 |
| 6 | on A2 | 8.3 / 10.3 / 10.3 | 0.1 / 0.1 / 0.2 | 2.4 / 2.8 / 3.0 | 183 | 364 / 2 | 182 / 1 |
| 10 | on A | 8.3 / 10.2 / 10.3 | 0.1 / 0.3 / 0.3 | 3.8 / 4.3 / 5.2 | 304 | 606 / 2 | 303 / 1 |
| 10 | off B | 8.3 / 10.3 / 16.8 | 0.2 / 0.3 / 0.4 | 4.9 / 7.6 / 8.5 | 304 | 0 / 608 | 0 / 304 |
| 10 | on A2 | 8.3 / 10.1 / 10.3 | 0.1 / 0.3 / 0.3 | 3.9 / 4.4 / 5.7 | 304 | 606 / 2 | 303 / 1 |

## Directional result against the cache threshold

- RD 6 CPU-render median reduction: 17.2% in both on arms versus off.
- RD 10 CPU-render median reduction: 22.4% (A) and 20.4% (A2) versus off.
- Frame p95 did not regress: it was unchanged at RD 6 and 0.1-0.2 ms lower
  in both RD 10 cache-on arms.
- This capture crosses the >=15% median CPU-render threshold at both
  distances; current-HEAD acceptance remains unclaimed for the scope reason
  above.
- Cache-off counters prove the kill-switch arm performed no cache hits.
- Chrome console was empty after every captured arm.

## Retention and memory proxy

| RD | Loaded/visible chunks | Retained components | Retained packed mesh bytes |
|---:|:---|---:|---:|
| 6 | 499 / 499 | 599 | 61,774,908 |
| 10 | 700 / 700 | 906 | 100,974,812 |

These retained packed bytes and the wall-frame tail are the available stable
memory/GC proxies. Chrome JS-heap/GC events were not captured, so this document
does not claim a heap or GC improvement. Main-thread mesh-drain percentiles were
startup/load samples rather than 7200 steady-state samples and are therefore
not used for the bind-cache claim.

## Live functional evidence

- The default Alpha-like atlas rendered in the same Wasm/WebGPU build.
- Pointer Lock was acquired by a trusted canvas click.
- F3 displayed real draw, target, retention, queue, and cache counters.
- Pause and compact inventory opened and accepted clicks.
- Grass/log direction, cutout leaves, fog, depth, and minimap rendered without
  console errors.

Synthetic browser automation could not reliably deliver LMB/RMB events while
Pointer Lock was active, so final manual break/place confirmation remains a
separate release-QA item rather than a passed claim here.
