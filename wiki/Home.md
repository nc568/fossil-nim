# UIRelays Wiki — Главная страница (Home)

Добро пожаловать в Wiki проекта **UIRelays Web Backends (Nim `--mm:arc`)**!

## Разделы Wiki

1. **[HtmlDomBackend](HtmlDomBackend.md)** — Чистый Vanilla HTML5 + CSS3 + JS (DOM) бэкенд (`-d:html`), работающий **строго без `<canvas>` и без WebAssembly**, с поддержкой как серверного режима (`nim c -d:html`), так и автономной компиляции в `.html` (`nim js --mm:arc -d:html`).
2. **[Canvas2DBackend](Canvas2DBackend.md)** — Отдельный HTML5 `<canvas>` 2D бэкенд (`-d:canvas`), работающий через `CanvasRenderingContext2D` **без WebAssembly**.
3. **[MonkeyTesting](MonkeyTesting.md)** — Методология и результаты модульного, протокольного и браузерного «обезьяньего» (Monkey) тестирования в реальном Chromium (`tester.nim`, `standalone_html_monkey_test.nim`, `monkey_browser_test.nim`).

## Ключевые возможности

- **100% Nim с `--mm:arc`**: весь серверный, браузерный (`nim js`), графический и тестовый код написан исключительно на языке Nim с детерминированным управлением памятью ARC (`--mm:arc`).
- **Два режима исполнения**:
  - **Автономные интерактивные `.html` файлы (`exported_html/*.html`, `uirelays_all_apps.html`)**: работают офлайн через `file://` без сервера, поддерживают все нажатия кнопок, ввод текста, анимации и динамическое изменение размера интерфейса от окна браузера (`ResizeObserver`).
  - **Серверный режим (`nim c --mm:arc -d:html` / `-d:canvas`)**: встроенный неблокирующий HTTP + SSE сервер.
- **Точное выравнивание моноширинных символов (`0.000px` погрешность)**: использование `font-variant-ligatures:none;letter-spacing:calc(<charWidth>px - 1ch)` гарантирует идеальное совпадение ширины символов DOM с метриками `measureText` и отсутствие сдвига строк при выделении текста в `Focim IDE` и `Todo`.
- **9 интерактивных приложений**: `calculator`, `snake`, `twenty48`, `focim` (`Araq/focim` IDE), `web_showcase`, `todo` (с навигацией курсора и выделением текста мышью/клавиатурой), `paint`, `layout_demo`, `hello`.
