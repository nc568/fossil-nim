# Веб-бэкенды UIRelays: Pure HTML/CSS/JS (DOM) и HTML5 Canvas 2D (Nim `--mm:arc`)

Библиотека `uirelays` включает два независимых веб-бэкенда, написанных **исключительно на Nim с управлением памятью ARC (`--mm:arc`)**, **без использования WebAssembly (WASM)** и **без внешних зависимостей**:

1. **Бэкенд 1: `html_driver` (`-d:html` / `-d:uirelaysHtml` / `--define:"features.uirelays.html"`)**
   - Чистый **Vanilla HTML5 + CSS3 + JS (DOM)**.
   - **Полностью без `<canvas>` и без WASM** (`document.querySelectorAll("canvas").length === 0`).
   - Все примитивы (`fillRect`, `drawLine`, `drawPoint`, `drawText`, `drawMeasuredText`, `drawImage`, `blitRGBA`, `setClipRect`) транслируются в семантические элементы DOM (`<div>`, `<span>`, `<svg>/<line>`, `<img>`) с абсолютным CSS-позиционированием и CSS3 `clip-path: polygon(...)`.
   - Попиксельный блиттинг `blitRGBA` работает без `<canvas>` за счёт встроенного в `web_common.nim` **чисто-Nim кодировщика RGBA → PNG** (формирует валидные чанки `IHDR`, `IDAT` с deflate stored-блоками, контрольными суммами `Adler-32` и `CRC-32`, и `IEND`, отдавая `data:image/png;base64,...` в `<img>`).

2. **Бэкенд 2: `canvas_driver` (`-d:canvas` / `-d:uirelaysCanvas` / `--define:"features.uirelays.canvas"`)**
   - Отдельный **HTML5 `<canvas>` 2D бэкенд** (`canvas.getContext("2d")`).
   - **Без WASM**.
   - Формирует компактный JSON-поток 2D-команд (`rect`, `point`, `line`, `text`, `save`, `restore`, `clip`, `img`, `blit`), исполняемый в браузере через нативный Canvas 2D API с кэшированием декодированных объектов `Image`.

---

## Архитектура (`src/uirelays/drivers/`)

| Файл | Назначение |
|------|------------|
| `src/uirelays/drivers/web_common.nim` | Общее ядро (`--mm:arc`): неблокирующий POSIX HTTP/SSE сервер (`0.0.0.0`), очередь событий `Event`, трансляция клавиатуры/мыши/колеса, фильтрация `WantTextInput` и `isCommandChord`, метрики моноширинных шрифтов, парсер размеров изображений (PNG/BMP/GIF/JPEG/SVG), кодировщик `encodeRgbaToPngDataUri`, дедупликация кадров `fnv1a64`. |
| `src/uirelays/drivers/html_driver.nim` | Драйвер чистого DOM (`-d:html`): генерация HTML5/CSS3 DOM-сцены без `<canvas>`, поддержка вложенных областей отсечения через CSS `clip-path: polygon(...)`, встроенный клиентский JS-мост и автономный агент обезьяньего тестирования (`?monkey=1`). |
| `src/uirelays/drivers/canvas_driver.nim` | Драйвер HTML5 Canvas 2D (`-d:canvas`): сериализация команд 2D-контекста, стек состояний `save`/`restore`/`clip`, встроенный клиентский рендерер `<canvas>` и автономный агент обезьяньего тестирования (`?monkey=1`) с проверкой реальных пикселей через `ctx.getImageData()`. |

---

## Сборка и запуск

```bash
# Сборка примеров с чистым HTML/CSS/JS DOM бэкендом (без Canvas и без WASM):
nim c --mm:arc -d:html examples/hello.nim
nim c --mm:arc -d:html examples/paint.nim
nim c --mm:arc -d:html examples/layout_demo.nim
nim c --mm:arc -d:html examples/todo.nim
nim c --mm:arc -d:html examples/web_showcase.nim

# Сборка примеров с отдельным HTML5 Canvas 2D бэкендом (без WASM):
nim c --mm:arc -d:canvas examples/hello.nim
nim c --mm:arc -d:canvas examples/paint.nim
nim c --mm:arc -d:canvas examples/layout_demo.nim
nim c --mm:arc -d:canvas examples/todo.nim
nim c --mm:arc -d:canvas examples/web_showcase.nim
```

По умолчанию встроенный веб-сервер слушает `0.0.0.0:8080` (или следующий свободный порт `8081..8109`). Порт можно задать через переменную окружения `UIRELAYS_PORT`:

```bash
UIRELAYS_PORT=9000 ./examples/web_showcase
```

---

## HTTP / SSE Протокол

| Эндпоинт | Метод | Описание |
|----------|-------|----------|
| `/` | `GET` | Отдаёт полную интерактивную HTML-страницу выбранного бэкенда (`html` или `canvas`). |
| `/events` | `GET` | Поток Server-Sent Events (`text/event-stream`), мгновенно доставляющий новые кадры при вызове `refresh()`. |
| `/state`, `/frame` | `GET` | Возвращает JSON текущего кадра (`frameId`, `title`, `cursor`, `width`, `height`, `clipboard`, `html` или `commands`). |
| `/input` | `POST` | Принимает одиночное событие или пакет `{"events":[...]}` (`mousedown`, `mouseup`, `mousemove`, `wheel`, `keydown`, `keyup`, `textinput`, `resize`, `focus`, `blur`, `clipboard`, `close`, `quit`). |
| `/health` | `GET` | Диагностический JSON (`backend`, `port`, `frameId`, `totalFramesRendered`, `totalEventsProcessed`, `domNodeCount`, `canvasCommandCount`). |
| `/monkey-report` | `GET` / `POST` | Приём и чтение телеметрии браузерного обезьяньего тестирования (`?monkey=1`). |

---

## Тестирование и браузерные «обезьяньи» (Monkey) тесты

```bash
# 1. Полный прогон всех модульных и интеграционных тестов (Nim --mm:arc):
nim c --mm:arc -r tests/tester.nim

# 2. Модульные и HTTP тесты чистого HTML/CSS/JS DOM бэкенда (57 проверок):
nim c --mm:arc -d:html -r tests/web_html_test.nim

# 3. Модульные и HTTP тесты HTML5 Canvas 2D бэкенда (25 проверок):
nim c --mm:arc -d:canvas -r tests/web_canvas_test.nim

# 4. Браузерные «обезьяньи» (Monkey) тесты в реальном Headless Chromium (120 проверок):
nim c --mm:arc -r tests/monkey_browser_test.nim
```
