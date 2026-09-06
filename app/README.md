# Minedart

Minedart 0.2 is a finite Minecraft Classic-style world implemented in Flutter
and `flame_3d`, using Metal on macOS and WebGPU in the browser. Multiplayer is
not part of this build.

## Local run

The repository `.fvmrc` selects the locally working stable SDK; CI pins
Flutter 3.44.4 exactly.

```sh
fvm flutter pub get --enforce-lockfile
fvm flutter run -d macos
fvm flutter run -d chrome
```

The Alpha-like atlas is the default. To run with the immutable legacy atlas,
pass the compile-time selector explicitly:

```sh
fvm flutter run -d macos --dart-define=MINEDART_ATLAS=legacy
```

The only accepted values are `alpha` and `legacy`; invalid values fail before
the texture asset is loaded and never fall back silently.

Main controls:

- WASD + Space: move and jump; double-tap and hold W to sprint.
- Mouse: look; left click breaks, right click places.
- 1–9 / wheel: hotbar.
- F: fog/render-distance preset; F3: metrics and frame-time graph.
- E: compact block inventory; Enter: Save Teleport; R: Teleport; N: noclip.
- Blocks are broken with LMB and placed with RMB; Q has no action.
- Escape: release Pointer Lock and open Pause/Options.
- Cmd/Ctrl+Z and Cmd/Ctrl+Y: grouped undo/redo.

Portable launch links accept `seed` and `preset=classic|flat|islands`. Edited
worlds are shared with MDRT2 export/import rather than in the URL.

The production web target is `https://minedart.castletaste.dev`, served as a
static Flutter WebAssembly application from Cloudflare Pages. Dokploy is not in
the static delivery path.

## Build the web release

Use Flutter 3.44.4, then run from this directory:

```sh
flutter pub get --enforce-lockfile
bash tool/build_web_release.sh
```

The build script creates a `--wasm --release` bundle, keeps Flutter's JavaScript
fallback, packages the renderer locally instead of loading it from a third-party
CDN, copies the Cloudflare `_headers` file, and checks the current Pages limits.

## Cloudflare Pages deployment

The manual GitHub Actions workflow at `.github/workflows/deploy-web.yml` expects:

- a Direct Upload Pages project named `castletaste-minedart` with production
  branch `main`;
- the custom domain `minedart.castletaste.dev` attached to that project;
- repository secrets `CLOUDFLARE_ACCOUNT_ID` and `CLOUDFLARE_API_TOKEN`; the
  token only needs `Account > Cloudflare Pages > Edit`.

The workflow is intentionally manual. Creating the Pages project, configuring
DNS/secrets, and running the first deployment are external production actions.

After deployment, verify that the document response includes
`Cross-Origin-Embedder-Policy: credentialless` and
`Cross-Origin-Opener-Policy: same-origin`, the Wasm response uses
`Content-Type: application/wasm`, `window.crossOriginIsolated` is `true`, and
the browser fetches `main.dart.wasm` rather than falling back to `main.dart.js`.

Touch controls, ownership boundaries, and validation are described in
[`docs/touch-controls.md`](../docs/touch-controls.md).
