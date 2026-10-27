# План реализации бэкенда совместимости (`-d:compat` / `compat_driver.nim`)

Этот документ фиксирует результаты исследования и архитектурный план для
**бэкенда режима совместимости (`-d:compat`)** в `uirelays`, рассчитанного на:
1. **Случай 1: Браузеры без JavaScript или с отключённым JS** (`Dillo`, `Links2`, `w3m`, `Lynx`, `NetSurf` в режиме по умолчанию `enable_javascript:0`, либо `Chromium`/`Servo`/`Firefox` с отключённым JS).
2. **Случай 2: Альтернативные браузеры с собственным рантаймом** (`Servo 0.7.0`, `NetSurf 3.11` с Duktape JS, `Ladybird` и др.).

---

## 1. Результаты эмпирической проверки реальных браузеров в песочнице

Были установлены и протестированы реальные браузеры:
- **Servo `0.7.0-23564ef62`** (`servoshell`, движок Stylo CSS + SpiderMonkey JS)
- **NetSurf `3.11`** (`netsurf-gtk`, движок Hubbub HTML + LibCSS + Duktape JS)
- **Dillo**, **Links2**, **w3m**, **Lynx** (браузеры без JS)

### Матрица возможностей (проверено автотестами в самих браузерах)

| Возможность | Servo 0.7.0 | NetSurf 3.11 (Duktape JS) | Браузеры без JS (`dillo`, `w3m`, JS-off) |
|---|---|---|---|
| `ES2015–ES2020` (`let`/`const`, `=>`, `class`, `Promise`, `async`/`await`, `Map`/`Set`, деструктуризация, шаблонные строки) | **Да (100%)** | **Нет (`SyntaxError` при парсинге скрипта)** — только ES5.1 | Нет |
| `BigInt` литералы (`0n` из `nim js`) | **Да** | **Нет (`SyntaxError: invalid number literal`)** — нужен `--jsbigint64:off -d:nimStringHash2` + полифилл `BigInt.asIntN` | Нет |
| `DOM`: `getElementById`, `createElement`, `textContent`, `innerHTML`, `classList`, `addEventListener` | **Да** | **Да** (но `addEventListener(t, fn, false)` требует 3-й `bool`-аргумент!) | Статический HTML |
| `DOM`: `querySelector`, `dataset`, `getBoundingClientRect`, `el.style.*` | **Да** | **Нет** (`undefined`; вместо `el.style.*` работает `el.setAttribute("style", ...)`) | Статический HTML |
| `fetch`, `XMLHttpRequest`, `URL`, `FormData` | **Да** (`fetch`, `XHR`, `URL`, `FormData`, `EventSource`) | `URL` — да; `fetch` и `XHR` — **нет** (`undefined`), работает динамическая подгрузка `<script src="...">` и отправка `<form>` | Отправка `<form method="GET/POST">` |
| Координаты клика мыши | `MouseEvent.clientX / clientY` | В JS `Event` нет `clientX/clientY`, но `<input type="image" name="p">` нативно шлёт точные координаты `?p.x=X&p.y=Y`! | `<input type="image" name="p">` шлёт `?p.x=X&p.y=Y` + кнопки `<button name="hit" value="x,y">` |
| Перерисовка экрана после загрузки | Динамический патч DOM на лету (60 FPS) | Layout (`box_construct`) выполняется при загрузке документа или навигации (`<form>` / `location.href`) | Серверная генерация нового HTML-кадра на каждый запрос |
| `CSS`: `position: absolute`, `#RRGGBB`, `monospace` | **Да** | **Да** | В графических (`NetSurf`, `Dillo`) — да; в текстовых (`w3m`) — потоковый режим |
| `CSS`: `flexbox`, `grid`, `var(--x)`, `@media`, `calc()` | **Да (100%)** | Частично (нет `grid`, `var(--x)`, `calc()`) | Нет |

---

## 2. Архитектура `src/uirelays/drivers/compat_driver.nim` (`-d:compat`)

1. **Серверная пред-отрисовка кадра (`SSR Frame-in-HTML`)**:
   - На каждый запрос `GET /` или `GET/POST /compat?...` сервер сначала инжектирует пришедшие события (`p.x`/`p.y`, `hit=x,y`, `txt=...`, `key=...`, `w=...&h=...`), выполняет шаг цикла `uirelays` и возвращает **полную HTML-страницу с уже отрисованным `#uir-viewport` внутри**.
   - Для максимальной совместимости с `LibCSS` (NetSurf) и старыми рендерами:
     - Непрозрачные цвета кодируются в `#RRGGBB` (а не `rgba(...)`).
     - Клиппинг (`setClipRect`) выполняется как на стороне Nim (математическая обрезка координат примитивов), так и через стандартный `overflow: hidden`.
     - Диагональные линии рисуются ступенчатыми `<div>`-отрезками (без зависимости от inline `<svg>`).
2. **Бесскриптовое управление (`No-JS` / Случай 1)**:
   - Поверх `#uir-viewport` внутри `<form method="GET" action="/compat">` размещается прозрачный `<input id="uir-hitmap" type="image" name="p" ...>`, который при клике в любую точку `(X, Y)` отправляет `GET /compat?p.x=X&p.y=Y` без единой строчки JS.
   - Под сценой генерируется панель быстрого ввода: поле текста `txt`, кнопки клавиш (`Enter`, `Backspace`, `Tab`, стрелки и т.д.), быстрые кнопки по всем интерактивным текстовым элементам экрана (`hit=cx,cy`) и переключатель автообновления (`<meta http-equiv="refresh">`).
3. **Двухуровневый клиентский рантайм для альтернативных браузеров (Случай 2)**:
   - **Уровень ES2015–ES2020 (Servo, Ladybird и др.)**: класс `UirCompatClient` на `let/const`, стрелочных функциях, `async/await`, `fetch`, `querySelector`, `dataset`, `classList`, `URL`, `FormData` и CSS-переменных `var(--x)` — перехватывает события без перезагрузки страницы и обновляет DOM инкрементально.
   - **Уровень ES5.1 (NetSurf Duktape)**: отдельный `<script>` без ES6-синтаксиса, использующий `addEventListener(..., false)`, `setAttribute("style", ...)`, полифилл `BigInt` и синхронизацию через `<input type="image">` / навигацию.
