---
name: minedart-release-qa
description: Validate Minedart changes across core tests, Flutter, macOS Impeller, WebGPU/Wasm, persistence, input, visuals, and frame performance. Does not authorize release actions.
---

# Minedart Release QA

Match evidence to the claim: inspection proves code paths; tests prove exercised contracts; builds prove packaging; live targets prove only the observed target/mode. Record the checkout/dirty state and separate unrelated WIP. Persistence E2E needs restart/reload. Performance needs warmed release-mode percentiles, not spike history.

- Core: `fvm dart analyze` and `fvm dart test` in `packages/core`.
- App: `fvm flutter analyze` and `fvm flutter test` in `app`; check resolved renderer source/version when relevant.
- macOS rendering/input claims require a live release target, including window/fullscreen transitions.
- Web claims require `fvm exec bash tool/build_web_release.sh` plus a foreground real WebGPU browser; verify Wasm, COOP/COEP, MIME, `crossOriginIsolated`, console, and visible output.
- Live input checks: gameplay-surface capture click does not edit, non-inverted look, LMB, single RMB, Escape/focus/modal release, clickable Pause/inventory, and one clean recapture.
- Live visual checks: default and legacy atlas orientation/seams, cutout/depth, fluids/fog, neighboring remesh, hotbar scaling, and F3 after meshing settles.
- Persistence claims require create/edit/save/reload and the affected library operations.
- Performance claims use the deterministic scene and protocol in `docs/web_performance_0_4.md`: release Wasm, DPR 2, rd6/rd10, queue zero plus warm-up, at least 60 seconds, p50/p95/p99 update/render/frame/mesh, draw count, target dimensions, cache counters, and memory/GC proxy. Report cache-off/on arms separately.

Report command/scenario, target, mode, pass/fail, and untested scope. Separate pre-existing failures. Deployment, publication, signing, and external release actions remain separate approvals.
