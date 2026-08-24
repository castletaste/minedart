# Spike S2: кастомный материал с vertex color (AO-путь)

Кастомный `VoxelMaterial` (`lib/voxel_material.dart`):
`outColor = texture * fragColor * albedoColor` — в отличие от штатных
материалов flame_3d 0.3.0, читает интерполированный per-vertex color,
то есть AO можно запекать в `Vertex.color`.

## Сборка шейдера (Metal / macOS)

GLSL-исходники: `shaders/voxel_material.{vert,frag}` (vert скопирован из
unlit_material пакета, frag добавляет умножение на fragColor).

```sh
cd spike/s2_shader
/Users/savva/fvm/versions/stable/bin/dart run flame_3d:build_shaders
# -> assets/shaders/voxel_material.shaderbundle (impellerc из кеша Flutter SDK)
```

В pubspec: `assets: [assets/shaders/]`. naga НЕ нужен для Metal-пути;
нужен только для `--with-web-gpu` (wgslbundle, web).

## Обязательные ключи Info.plist (macos/Runner/Info.plist)

```xml
<key>FLTEnableImpeller</key><true/>
<key>FLTEnableFlutterGPU</key><true/>
```

Без них GpuBackend.initialize() падает на старте (проверено).
В base_app этих ключей нет — то приложение соберётся, но упадёт при запуске.

## Запуск

```sh
/Users/savva/fvm/versions/stable/bin/flutter build macos --release
open build/macos/Build/Products/Release/spike_s2_shader.app
```

Ожидаемая картинка: вращающаяся камера, слева куб с AO-градиентом
(тёмные нижние углы, светлый верх), справа зелёный референс-куб
(штатный UnlitMaterial). Проверено скриншотом 2026-08-24.
