---
name: minedart-release-qa
description: Validate Minedart changes across core tests, Flutter, macOS Impeller, WebGPU/Wasm, persistence, input, visuals, and frame performance. Does not authorize release actions.
---

# Minedart Release QA

Match evidence to the claim: inspection proves code paths; tests prove exercised contracts; builds prove packaging; live targets prove only the observed target/mode. Persistence E2E needs restart/reload. Performance needs warmed release-mode percentiles, not spike history.

- Core: `dart analyze && dart test` in `packages/core`.
- App: `flutter analyze && flutter test` in `app`; check resolved renderer versions when relevant.
- macOS rendering/input claims require a live release target.
- Web claims require `bash tool/build_web_release.sh` plus a real WebGPU browser; verify Wasm, headers, console, and visible output.
- Live input checks: capture click does not edit, look orientation, LMB, single RMB, Escape/focus/modal release.
- Live visual checks: atlas orientation/seams, cutout/depth, fluids/fog, neighboring remesh, F3 p50/p95/p99 after meshing settles.
- Persistence claims require create/edit/save/reload and the affected library operations.

Report command/scenario, target, mode, pass/fail, and untested scope. Separate pre-existing failures. Deployment, publication, signing, and external release actions remain separate approvals.
