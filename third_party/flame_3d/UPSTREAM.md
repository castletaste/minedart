# Vendored flame_3d provenance

- Package: `flame_3d`
- Version: `0.3.0`
- Source: hosted package from `https://pub.dev`
- Pub package SHA-256: `45310da41e63a690d79514b24f890b28251c3066aa0986db29ef48283541af0a`
- Imported: `2026-08-25`
- Upstream license: MIT; retained byte-for-byte in `LICENSE`

`UPSTREAM_MANIFEST.sha256` records all 179 files from the exact hosted package,
including the original hashes for intentionally changed files. The drift test
checks the complete vendored file set and hashes every file outside the explicit
allow-list below. Generated dependency/build artifacts are excluded by name.

## Intentional change allow-list

Keep this list sorted. It is the machine-readable source of truth used by
`test/provenance/upstream_drift_test.dart`.

<!-- BEGIN INTENTIONAL CHANGE ALLOWLIST -->
- `UPSTREAM.md`
- `UPSTREAM_MANIFEST.sha256`
- `analysis_options.yaml`
- `example/analysis_options.yaml`
- `example/pubspec.yaml`
- `lib/graphics.dart`
- `lib/src/camera/camera_component_3d.dart`
- `lib/src/camera/world_3d.dart`
- `lib/src/components/object_3d.dart`
- `lib/src/graphics/backend/flutter_gpu/gpu_backend.dart`
- `lib/src/graphics/backend/gpu_backend.dart`
- `lib/src/graphics/backend/gpu_bind_cache_counters.dart`
- `lib/src/graphics/backend/web_gpu/cache_policy.dart`
- `lib/src/graphics/backend/web_gpu/gpu_backend.dart`
- `lib/src/graphics/graphics_device.dart`
- `lib/src/graphics/render_context_3d.dart`
- `lib/src/resources/shader/shader.dart`
- `pubspec.yaml`
- `test/camera/camera_component_3d_test.dart`
- `test/components/object_3d_test.dart`
- `test/graphics/backend/web_gpu/cache_policy_chrome_test.dart`
- `test/graphics/backend/web_gpu/cache_policy_define_off_chrome_test.dart`
- `test/graphics/backend/web_gpu/cache_policy_test_suite.dart`
- `test/graphics/backend/web_gpu/cache_policy_vm_test.dart`
- `test/graphics/render_context_3d_test.dart`
- `test/provenance/upstream_drift_test.dart`
- `test/resources/shader/shader_binding_revision_test.dart`
<!-- END INTENTIONAL CHANGE ALLOWLIST -->

## Purpose of the allowed changes

- `pubspec.yaml` removes `resolution: workspace`, and the analysis/dev setup is
  standalone for this repository.
- Generic shader/device/backend files carry stable uniform identity and
  monotonic byte-content revision metadata. The native FlutterGPU backend only
  accepts and ignores those optional parameters.
- Camera/component/render-context files cache one frustum per render traversal
  and restore deferred-draw and culling state after component exceptions.
- The WebGPU backend adds a persistent sorted slot plan, sampled-texture view
  lifetime, and group-1-only frame-local uniform/bind-group reuse. Swapchain and
  depth views stay on their direct per-pass path.
- `cache_policy.dart` is platform-neutral and contains the fake-token seam,
  complete identity keys, frame reset, kill switch, and bounded counters.
- Focused VM and headless-Chrome tests cover the cache contract. A real WebGPU
  adapter/device and visual parity remain foreground release QA, as specified
  in the repository's `docs/web_performance_0_4.md`.

## Verification routes

From this directory with Flutter 3.44.9:

```sh
flutter pub get
flutter analyze
flutter test
flutter test --platform chrome test/graphics/backend/web_gpu/cache_policy_chrome_test.dart
flutter test --platform chrome --dart-define=FLAME_3D_WEBGPU_BIND_CACHE=false test/graphics/backend/web_gpu/cache_policy_define_off_chrome_test.dart
```

The cache-off benchmark arm uses the same define on the app's release build.
Neither headless route claims a real WebGPU device.
