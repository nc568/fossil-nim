# UIRelays Wiki — Главная страница (Home)

Добро пожаловать в Wiki проекта **UIRelays Web Backends (Nim `--mm:arc`)**!

## Разделы Wiki

1. **[HtmlDomBackend](HtmlDomBackend.md)** — Чистый Vanilla HTML5 + CSS3 + JS (DOM) бэкенд (`-d:html`), работающий **строго без `<canvas>` и без WebAssembly**.
2. **[Canvas2DBackend](Canvas2DBackend.md)** — Отдельный HTML5 `<canvas>` 2D бэкенд (`-d:canvas`), работающий через `CanvasRenderingContext2D` **без WebAssembly**.
3. **[MonkeyTesting](MonkeyTesting.md)** — Методология и результаты модульного, протокольного и браузерного «обезьяньего» (Monkey) тестирования в реальном Chromium.

## Ключевые принципы реализации

- **100% Nim с `--mm:arc`**: весь серверный, сетевой, графический и тестовый код написан исключительно на языке Nim с детерминированным управлением памятью ARC (`--mm:arc`).
- **Нулевые внешние зависимости**: используются только стандартные модули Nim (`std/nativesockets`, `std/posix`, `std/json`, `std/monotimes`, `std/unicode`, `std/base64`).
- **Полная совместимость с `uirelays` v0.11.0**: реализованы все 5 групп релеев (`WindowRelays`, `FontRelays`, `DrawRelays`, `InputRelays`, `ClipboardRelays`).
