---
name: minedart-web-runtime
description: "Implement or debug Minedart's browser runtime: WebGPU, Pointer Lock, time-sliced meshing, platform facades, Flutter Wasm packaging, headers, and live Web behavior."
---

# Minedart Web Runtime

Keep Web differences behind conditional-import facades; shared core/widgets must not depend on DOM, JS interop, `dart:io`, or native channels.

- Web meshing runs on the main thread through a deterministic priority queue. Preserve nearest priority, stable ties, newest-generation-per-chunk coalescing, progress/retry after failure, and safe disposal. Coalesce dirty chunk indices before expensive `ChunkSnapshot.capture` where the current architecture permits.
- Do not treat a fixed 6 ms slice as permanent. The approved scheduler target is roughly 1–3 ms while moving/interacting and up to 6 ms while loading/idle, with at least one-job progress and no unbounded timer churn. Verify what is actually implemented before claiming dynamic budgets.
- Request Pointer Lock from a gesture; the capture click must not edit. While locked, prevent default `pointerdown`/`contextmenu`, keep LMB break, deduplicate RMB placement, and avoid Flutter/DOM double delivery.
- Preserve non-inverted `movementX/Y`; Escape, focus loss, modal UI, and disposal must release or suspend capture.
- Web uses `WebVoxelMaterial` and its WGSL bundle; native shader evidence is insufficient. Keep the shared vertex ABI, baked color, and alpha cutout.
- Do not lower render scale by default. Expose real DPR/effective target size and cache/mesh telemetry before adding any explicit fallback.
- IndexedDB stays behind `WorldRepository`. Use `minedart-world-storage` for format work.
- Build releases with `app/tool/build_web_release.sh`; preserve Wasm, JS fallback, local renderer resources, COEP/COOP, and Wasm MIME. Deployment remains a separate action.

Live-check capture-without-edit, cursor/look, LMB, single RMB, no context menu, modal and Escape release, recapture, visible WebGPU, console, and F3 after meshing settles. Report browser and build mode; a build alone is not runtime proof.
