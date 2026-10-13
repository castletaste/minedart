# s7_flutter_scene — minedart на flutter_scene 0.24.3

Одноразовый спайк: ответ на вопрос, переносим ли рендер minedart на
[flutter_scene](https://pub.dev/packages/flutter_scene). Отчёт и вердикт — в
[REPORT.md](REPORT.md). В production переносятся только выводы, не код.

## Что внутри

- `lib/main.dart` — arm **flutter_scene**. Мир islands `seed=0x5eed`
  генерируется и мешится production-кодом `packages/core`. Каждый непустой
  проход чанка (opaque/translucent) — `UnskinnedGeometry` +
  `uploadVertexStreams` с layout под мешер (80 байт на вершину, без
  перепаковки). Мир висит под Z-зеркалом: flutter_scene левосторонний.
- `assets/materials/voxel_{opaque,translucent}.fmat` — unlit-материалы с теми
  же формулами, что `app/shaders/voxel_material.frag` (атлас × запечённый свет,
  cutout `a < 0.5`, debug views, линейный туман).
- `lib/flame_arm.dart` — контрольный arm **flame_3d**: та же статичная сцена
  через production `PackedSurface` + `VoxelMaterial`/`WebVoxelMaterial`
  (копии в `lib/flame_arm/`).
- `lib/src/frame_probe.dart` — percentiles кадра/CPU render/update, строки
  `S7 {json}` в консоль.
- `tool/run_probe.mjs` — раздаёт web-сборку с production COOP/COEP,
  гоняет её в headless Chromium (SwiftShader WebGL2 + WebGPU), собирает
  телеметрию, занятость main thread (CDP `TaskDuration`/`ScriptDuration` на
  rAF-кадр) и счётчики создания/освобождения GPU-буферов.
- `tool/baseline_perf_log.patch` — временный патч к `app`, печатающий
  `PerformanceSnapshot` полной игры как `MDPERF {json}`.

## Запуск

Flutter 3.47.7 (`.fvmrc`).

```sh
flutter pub get
# flutter_scene arm
flutter build web --wasm --release --no-web-resources-cdn
# flame_3d control arm
flutter build web --wasm --release --no-web-resources-cdn \
  -t lib/flame_arm.dart -o build/web_flame
node tool/run_probe.mjs build/web --seconds=120 --warm=25 --viewport=480x300
node tool/run_probe.mjs build/web_flame --seconds=120 --warm=25 --viewport=480x300
```

Параметры flutter_scene arm (web — query, native — `--dart-define`):
`?rd=6|10` (`S7_RD`), `?upload=streams|arrays` (`S7_UPLOAD`),
`?churn=N` — N перезагрузок проходов за кадр (`S7_CHURN`).

macOS: `flutter run -d macos --release` и
`flutter run -d macos --release -t lib/flame_arm.dart`
(`FLTEnableImpeller` и `FLTEnableFlutterGPU` уже в `Info.plist`).
