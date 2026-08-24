# S5 — web / WebGPU reality check (flame_3d 0.3.0)

Spike-каталог: `/Users/savva/code/minedart/spike/s5_web`

## Что здесь

- `lib/main.dart` — сцена из `base_app` (вращающаяся камера + куб) ПЛЮС
  Flutter-HUD (`Stack` поверх `GameWidget`): текст, счётчик и кнопка.
  Нужен, чтобы проверить композитинг Flutter-виджетов поверх 3D на вебе.
- `webgpu_probe/probe3.html` — чистый JS-зонд WebGPU (adapter/device/
  OffscreenCanvas+blit), повторяющий пайплайн flame_3d web-бэкенда.
  Репортит стадии через `GET /REPORT/<stage>` в лог http-сервера.

## Сборка

    /Users/savva/fvm/versions/stable/bin/flutter build web --release
    # опционально:
    /Users/savva/fvm/versions/stable/bin/flutter build web --wasm --release

Обе проходят (измерено: 18.8 s JS / 18.7 s wasm).

## Локальный сервер

    cd /Users/savva/code/minedart/spike/s5_web/build/web
    python3 -m http.server 8757 --bind 127.0.0.1

Проверка: `curl -I http://127.0.0.1:8757/index.html` -> 200.

## Ручной шаг в GUI (обязателен)

1. Открыть `chrome://gpu`, найти строку **WebGPU** — должно быть
   `Hardware accelerated`. Также проверить `chrome://gpu` -> "Graphics Feature
   Status" -> WebGPU.
2. Открыть http://127.0.0.1:8757/ в обычном (НЕ headless) Chrome.
3. Ожидаемое: зелёный куб, камера вращается, поверх — HUD-панель слева сверху
   (`kIsWeb = true`) и кнопка справа снизу. Нажатие кнопки увеличивает счётчик.
4. Если WebGPU нет, приложение покажет красный текст
   `GpuBackend.initialize() failed: UnsupportedError...` вместо чёрного экрана.
5. Отдельно http://127.0.0.1:8757/probe3.html — стадии в логе сервера.

## Проверено headless (измерено)

- `navigator.gpu` есть, `requestAdapter()` -> OK за ~1.0 s,
  `adapter.info` = `vendor:apple, arch:metal-3`.
- `adapter.requestDevice()` в headless НЕ резолвится (ни `--headless=new`,
  ни `--headless=old`, ни с доп. флагами). Поэтому реальный рендер куба
  headless-ом подтвердить нельзя — нужен GUI-Chrome.

