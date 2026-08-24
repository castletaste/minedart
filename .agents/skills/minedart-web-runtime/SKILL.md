---
name: minedart-web-runtime
description: "Implement or debug Minedart's browser runtime: WebGPU, Pointer Lock, time-sliced meshing, platform facades, Flutter Wasm packaging, headers, and live Web behavior."
---

# Minedart Web Runtime

Keep Web differences behind conditional-import facades; shared core/widgets must not depend on DOM, JS interop, `dart:io`, or native channels.

- Web meshing runs on the main thread with a 6 ms budget. Preserve nearest priority, newest-job-per-chunk coalescing, monotonic mesh generations, queue progress after job failure, and safe disposal.
- Request Pointer Lock from a gesture; the capture click must not edit. While locked, prevent default `pointerdown`/`contextmenu`, keep LMB break, deduplicate RMB placement, and avoid Flutter/DOM double delivery.
- Preserve non-inverted `movementX/Y`; Escape, focus loss, modal UI, and disposal must release or suspend capture.
- Web uses `WebVoxelMaterial` and its WGSL bundle; native shader evidence is insufficient. Keep the shared vertex ABI, baked color, and alpha cutout.
- IndexedDB stays behind `WorldRepository`. Use `minedart-world-storage` for format work.
- Build releases with `app/tool/build_web_release.sh`; preserve Wasm, JS fallback, local renderer resources, COEP/COOP, and Wasm MIME. Deployment remains a separate action.

Live-check capture-without-edit, cursor/look, LMB, single RMB, no context menu, Escape/recapture, visible WebGPU, console, and F3 after meshing settles. Report browser and build mode; a build alone is not runtime proof.
