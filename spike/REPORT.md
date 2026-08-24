# Spike Report — minedart на flame_3d 0.3.0

Дата: 2026-08-24. Машина: Apple Silicon, macOS, Flutter 3.44.4 stable (fvm), flame_3d 0.3.0 / flame 1.38.0.
Вопрос спайка: пригоден ли flame_3d как рендер-слой воксельной игры. Ответ: **ДА, с двумя обязательными обходами** (см. вердикт).

## Сводка вердиктов

| # | Вопрос | Вердикт | Число |
|---|---|---|---|
| S1 | Ремеш чанка через штатный API в бюджете 4мс | **НЕТ** — 20.9мс median (release AOT) | штатно 20.9/29.7мс p99 |
| S1 | Обход PackedSurface (Float32List напрямую) | **ДА** — 0.52мс median, 40x быстрее | 0.52/1.6мс p99, ~47 аллокаций вместо 220k |
| S2 | Кастомный шейдер с vertex color (AO) на Metal | **ДА** — работает, скриншот подтверждён | сборка bundle ~1с, naga НЕ нужен для Metal |
| S3 | 1350 уникальных мешей по 1000 квадов, все видимые | **ДА** — 70–73 fps стабильно | 2.7M треугольников; N=400 → 120fps (потолок дисплея) |
| S4 | Захват мыши на macOS (platform channel) | **СОБРАНО** — ручная GUI-проверка осталась | Swift: NSEvent monitor + CGAssociate |
| S5 | Web/WebGPU | **СБОРКА ДА, рендер не подтверждён** | headless Chrome не выдаёт device; нужен ручной запуск |
| S6 | Frustum culling в flame_3d | **ЕСТЬ**, иерархический | критики ошиблись; но flush() = insertion sort O(V²) |

## Ключевые факты

### S1 — ремеш (морально главный результат)
- Штатный путь `List<Vertex> → Surface(...)` непригоден: 20.9мс median на чанк 16³ (3244 квада) в release AOT. Враги: 220 592 объектов на чанк (Vertex/Vector3/...) и `fold(addAll)` с промежуточным списком 259k элементов.
- Обход: `PackedSurface extends Surface` — мешер пишет сразу в Float32List (layout 20 float/вершину), переопределяет createResource/AABB/counts. 0.52мс total. GPU-контракт проверен fake-бэкендом и живым рендером чанка (зелёный воксельный чанк на экране, без GPU-ошибок).
- Риск: опора на внутренний контракт экспериментального пакета — при обновлении flame_3d пересматривать.

### S2 — шейдер/AO
- Штатные материалы НЕ читают vertex color (проверено по GLSL: `outColor = texColor * albedoColor`). AO требует свой материал.
- Кастомный VoxelMaterial (texture × fragColor): работает на Metal. Сборка: `dart run flame_3d:build_shaders` (impellerc из Flutter SDK, naga не нужен). Для web-варианта шейдера нужен naga-cli (в системе нет) — факт, не блокер macOS.
- КАПКАН: без `FLTEnableImpeller` + `FLTEnableFlutterGPU` в macos/Runner/Info.plist приложение падает на GpuBackend.initialize().
- Vertex layout жёсткий (20 float, имена атрибутов фикс.); в slots шейдера перечислять ВСЕ uniform-блоки; цвет линейный float RGBA без sRGB.

### S3 — масштаб сцены
- 1350 уникальных Surface × 1000 квадов, ВСЕ в кадре: 70–73 fps (release, live). Draw path: ~15k bind/draw команд на кадр — Metal тянет.
- Culling иерархический (outside → поддерево отсекается; inside → дети без тестов). Пул draw-заявок без аллокаций.
- Минусы пути: back-to-front insertion sort всех видимых (O(V²), анти-early-z для opaque), clearBindings+bindPipeline на каждый Surface, батчинга нет.
- Вывод: component-per-chunk ЖИЗНЕСПОСОБЕН для MVP-масштаба (~1350 чанков). Запас по сортировке проверять при >2–3k видимых.

### S4 — мышь
- MethodChannel capture/release + EventChannel дельт; курсор скрывается, CGAssociateMouseAndMouseCursorPosition(false). Сборка чистая, universal binary. Дельты — ускоренные macOS, не raw HID.
- Ручной чек-лист в spike/s4_mouse/README.md (фокус, Spaces, мультимонитор).

### S5 — web
- Web-бэкенд настоящий (~810 строк WebGPU), выбирается условным импортом js_interop; wgslbundle встроенных материалов в пакете есть.
- flutter build web проходит (js 1.9MB, wasm 1.6MB). Сервер поднят, ассеты 200.
- HUD-виджеты — тот же канвас (3D → ui.Image → drawImageRect), platform view нет. Но: каждый кадр блит WebGPU-канвас → 2D-канвас → ImageBitmap (воркэраунд крэша CanvasKit) — цена не измерена.
- Headless Chrome: adapter OK (metal-3), device НЕ выдаёт — рендер в браузере подтверждать вручную: http://127.0.0.1:8757/ + chrome://gpu.

## Вердикт по kill-критериям

S1 пройден через PackedSurface (0.52мс << 4мс бюджета), S3 пройден (70fps при worst-case). **flame_3d принимается** как рендер-слой со следующими обязательствами архитектуры:
1. PackedSurface-путь (мешер пишет Float32List, никакого List<Vertex> в горячем пути) — и пин версии flame_3d.
2. Кастомный VoxelMaterial с fragColor — с фазы рендера, не «потом».
3. Info.plist-ключи в шаблоне проекта.
4. Мешинг в изоляте возвращает готовые Float32List/Uint16List (transferable) — они входят в PackedSurface без переупаковки.
5. Web остаётся экспериментальным треком (blit-цена + naga для кастомных шейдеров + отсутствие изолятов). Обещаний по web-перфу не даём.
6. Мышь: platform channel из s4 переносится в проект; GUI-проверка Spaces/мультимонитор — вручную.

## Ручные проверки — ЗАКРЫТЫ (подтверждено пользователем 2026-08-24)

1. s4_mouse.app: захват мыши работает — S4 подтверждён E2E.
2. Chrome, http://127.0.0.1:8757/: сцена рендерится, клик по HUD-кнопке работает — S5 (WebGPU-рендер + hit-testing поверх сцены) подтверждён E2E.

Спайк закрыт полностью: все шесть вопросов имеют проверенный ответ.

## Артефакты

- spike/base_app — минимальный рабочий скаффолд (собран, .app на месте)
- spike/s1_remesh — бенчмарк+рендер PackedSurface (собран; лог замера: /private/tmp/s1.log)
- spike/s2_shader — VoxelMaterial + AO-куб (собран)
- spike/s3_many — сцена N мешей, N через --dart-define (собран с N=1350)
- spike/s4_mouse — захват мыши (собран)
- spike/s5_web — web-сборка + WebGPU-зонд (build/web готов)
- spike/NOTES-s6-culling.md — разбор culling/draw path по исходникам

Весь спайк одноразовый: в production-код переносим только знания и контракты, не файлы.
