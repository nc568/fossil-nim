# Fossil-Nim Новый Web UI - Современный, Модульный, Vanilla JS

Полная перепись Web UI Fossil на vanilla JS, без фреймворков, с библиотекой xhttp/htmx-like в стиле Nim.

## Обзор

- **Vanilla JS, без фреймворков** - <10KB ядро, без React/Vue, чистый JS
- **xhttp-like библиотека** - Минималистичная htmx-inspired, `data-get`, `data-post`, `data-target`, `data-swap`
- **Красивый современный минимализм** - CSS переменные, карточки, blur navbar, responsive
- **Легкое редактирование палитры тем** - Редактируй палитру в Nim или через UI редактор, JSON импорт/экспорт
- **Модульная архитектура** - Каждый компонент независим, легко добавлять
- **Декуплирован от web** - Ядро на Nim платформенно-независимо, готово для TUI/desktop/mobile

## Архитектура

### Nim Backend - Платформенно-независимо

```
src/fossil/ui/
├── core.nim       - UiPlatform (web/tui/desktop/mobile/cli), UiRoute (22 маршрута), UiState, ApiResponse, чистые функции навигации
├── theme.nim      - ColorPalette, Theme, 6 палитр, paletteToCssVariables, themeToCss, generateAllThemesCss, JSON
├── api_client.nim - HttpMethod, ApiRequest, ApiClientConfig, типизированные параметры, generateJsApiClient
├── component.nim  - Component база, реестр, List/Detail/Form, generateJsComponentBase
├── frontend.nim   - FrontendConfig, generateIndexHtml, buildFrontend, Nim->JS
└── README.md
```

Ядро - чистые функции, без зависимости от DOM:

```nim
let state = newUiState(Web)
let newState = navigate(state, "/timeline")
let css = themeToCss(myTheme)
let js = generateJsApiClient()
```

Одно ядро для всех платформ:
- Web (текущий)
- TUI (будущее, используя illwill)
- Desktop (Tauri/Electron)
- Mobile
- CLI

### Frontend - Vanilla JS

```
web_new/
├── index.html              - SPA вход, критический CSS inline, navbar с data-link/data-get
├── css/
│   ├── app.css             - 15KB современный CSS, переменные, grid, карточки, timeline, graph, chat, modal
│   └── themes.css          - 6 тем: light/dark/solarized-light/nord/monokai/github-light, data-theme
└── js/
    ├── lib/
    │   ├── xhttp.js        - ~5KB, htmx-like, data-get/post/target/swap/trigger, fetch, history
    │   ├── theme.js        - Переключение тем, localStorage, редактор с color pickers, import/export
    │   └── component.js    - Component база, mount/update/setError/fetchData, реестр
    ├── api.js              - ApiClient класс, fetch, token localStorage, 20+ эндпоинтов
    ├── app.js              - Router, SPA навигация, data-link intercept, popstate, state
    └── components/         - 12 модульных компонентов
        ├── navbar.js
        ├── timeline.js     - Timeline с фильтром, load more, badges
        ├── file.js         - File browser + file-history
        ├── info.js         - Check-in info
        ├── graph.js        - Commit graph
        ├── wiki.js         - Wiki + wiki-list + wiki-edit с live markdown preview
        ├── ticket.js       - Ticket + list + new
        ├── forum.js        - Forum threads + pinned + search + pin/unpin
        ├── chat.js         - Chat rooms + presence + typing indicator + attachments
        ├── search.js       - FTS5 live search с debounce
        ├── login.js
        ├── setup.js
        └── diff.js         - Diff + blame
```

## xhttp.js - Минималистичный htmx-like

Вдохновлен htmx, написан в стиле Nim, <5KB:

```html
<!-- SPA навигация -->
<a href="/timeline" data-link>Timeline</a>

<!-- Server-driven фрагмент -->
<a data-get="/api/v1/timeline?limit=20" data-target="#main" data-swap="innerHTML">Load</a>

<!-- Form POST -->
<form data-post="/api/v1/wiki/save" data-target="#main">
  <input name="name">
  <textarea name="content"></textarea>
  <button>Save</button>
</form>

<!-- Swap режимы -->
<div data-get="/api/v1/status" data-target="#status" data-swap="beforeend">Load more</div>
```

Атрибуты:
- `data-get`, `data-post`, `data-put`, `data-delete` - HTTP метод + URL
- `data-target` - CSS селектор для swap target
- `data-swap` - `innerHTML`, `outerHTML`, `beforeend`, `afterbegin`, `beforebegin`, `afterend`, `none`
- `data-link` - SPA навигация с pushState
- `data-indicator` - Loading индикатор селектор
- `data-trigger` - Event триггер (click, submit, etc)

События:
- `xhttp:afterRequest`
- `xhttp:afterSwap`
- `xhttp:error`

## Система Тем - Легкое Редактирование Палитры

### В Nim - `src/fossil/ui/theme.nim`

```nim
let light = ColorPalette(
  primary: "#0d6efd",
  primaryHover: "#0b5ed7",
  primaryLight: "#cfe2ff",
  secondary: "#6c757d",
  success: "#198754",
  danger: "#dc3545",
  warning: "#ffc107",
  info: "#0dcaf0",
  bg: "#f8f9fa",
  bgSecondary: "#e9ecef",
  bgCard: "#ffffff",
  bgCode: "#f1f3f5",
  bgHover: "#e9ecef",
  text: "#212529",
  textSecondary: "#495057",
  textMuted: "#6c757d",
  textInverse: "#ffffff",
  border: "#dee2e6",
  borderLight: "#e9ecef",
  borderDark: "#343a40",
  shadow: "0 1px 3px rgba(0,0,0,0.1)",
  shadowLg: "0 4px 12px rgba(0,0,0,0.15)",
  radius: "6px",
  radiusLg: "12px"
)

let myTheme = Theme(name: "my-custom", displayName: "My Custom", description: "...", isDark: false, palette: light)
let css = themeToCss(myTheme) # генерирует [data-theme="my-custom"] { --color-primary: ... }
let allCss = generateAllThemesCss() # все темы
let json = themeToJson(myTheme) # для экспорта
```

### В CSS - `web_new/css/themes.css`

```css
[data-theme="light"] {
  --color-primary: #0d6efd;
  --color-bg: #f8f9fa;
  /* ... */
}
[data-theme="dark"] {
  --color-primary: #3b82f6;
  --color-bg: #111827;
}
```

### В UI - Редактор Тем

Клик 🎨 кнопка:
- Presets grid - клик для переключения темы
- Color grid - color pickers для каждой записи палитры
- Save Custom - сохраняет в localStorage
- Reset - сброс к дефолту
- Export JSON - скачать тему JSON
- Import JSON - загрузить тему JSON

Все темы используют CSS переменные, поэтому изменение палитры мгновенно обновляет UI.

6 встроенных тем:
- light - Дефолт, чистый минимализм
- dark - Темная для слабого освещения
- solarized-light - Solarized light, приятна для глаз
- nord - Nord dark, арктическая синеватая
- monokai - Яркая темная
- github-light - GitHub light

Добавить новую тему: скопировать шаблон в `themes.css`, отредактировать цвета, добавить в `theme.nim` и `theme.js`.

## Система Компонентов

```js
registerComponent('my-component', (props) => {
  const c = new Component('my-component', props);
  
  c.fetch = async (query) => {
    const res = await api.timeline(20);
    return res.data;
  };
  
  c.render = () => {
    const data = c.props.data;
    return `<div class="card"><h1>My</h1></div>`;
  };
  
  c.afterRender = () => {
    // Bind events, process xhttp
  };
  
  return c;
});
```

Базовые классы:
- `Component` - база с init/render/update/destroy/handleEvent
- `ListComponent` - для списков с renderList
- `DetailComponent` - для детальных views
- `FormComponent` - для форм

Реестр: `window.components`, `registerComponent(name, factory)`, `createComponent(name, props)`

## Router - `app.js`

- Перехватывает `data-link` клики
- `history.pushState` для SPA
- `popstate` для back/forward
- Загружает компонент или fallback к server HTML
- Обновляет active nav
- Обрабатывает xhttp атрибуты в новом контенте

Маршруты (22):
- `/` - Home
- `/timeline` - Timeline
- `/file`, `/finfo`, `/info`, `/graph`, `/diff`, `/blame`
- `/wiki`, `/wiki/list`, `/wiki/new`, `/wiki/edit`
- `/ticket`, `/ticket/list`, `/ticket/new`
- `/forum`, `/forum/list`, `/forum/new`
- `/chat`, `/chat/rooms`
- `/search`, `/login`, `/setup`

## Интеграция API

`api.js` - Vanilla JS ApiClient:

```js
const api = new ApiClient();

// VCS
await api.timeline(20, 'trunk')
await api.fileList('*.nim', 100)
await api.fileGet('src/main.nim')
await api.graph('trunk', 100)
await api.info(rid)
await api.diff(from, to)
await api.branches()

// Wiki
await api.wikiList()
await api.wikiGet('Home')
await api.wikiSave('Home', '# Content', 'update')

// Tickets
await api.ticketList(20)
await api.ticketGet(id)
await api.ticketCreate(title, desc, type, priority)

// Forum
await api.forumList(50)
await api.forumGet(id)
await api.forumCreate(title, content, user)
await api.forumPost(threadId, content, user)
await api.forumPin(id, pinned)
await api.forumSearch(query)

// Chat
await api.chatList('main', 50)
await api.chatSend('main', 'hello', 'user')
await api.chatRooms()
await api.chatPresence('main')
await api.chatPresenceUpdate('main', 'user', true)

// Search
await api.search('bug', 20, 'ticket')
await api.searchReindex()

// Other
await api.status()
await api.markdown(text)
await api.th1(code)
await api.login(user, pass)
```

Backend отдает и API и frontend: `src/fossil/api/rest.nim`

## Сборка и Запуск

```bash
# Собрать бинарник с новым UI
nim c -d:release -o:fossil src/fossil/cli/main.nim

# Запустить сервер - новый UI автоматически отдается если web_new/ существует
./fossil server --repo repo.fossil --port 8080

# Открыть http://localhost:8080/
# Новый UI на /, API на /api/v1/*

# Frontend bundle через Nim
nim c -r src/fossil/ui/frontend.nim
# Генерирует HTML/CSS/JS bundle info

# Опционально: компилировать frontend в JS
nim js -o:web_new/js/app.nim.js src/fossil/ui/frontend.nim
```

## Декуплирован - Будущий TUI/Desktop

Ядро платформенно-независимо:

```nim
# Одно ядро для всех
let state = newUiState(Web) # или Tui, Desktop, Mobile, Cli
let newState = navigate(state, "/timeline")

# Тема для web
let css = themeToCss(myTheme)

# Будущий TUI
# let tuiColors = paletteToTuiColors(myPalette)

# API клиент работает везде
let client = newApiClient("http://localhost:8080")
let req = timelineRequest(TimelineParams(limit: 20))
```

Будущее:
- `src/fossil/ui/tui.nim` - Terminal UI используя illwill
- Desktop - Tauri с тем же ядром
- Mobile - Тот же API клиент

## Красивый Современный Минимализм

- CSS переменные для всех цветов - легкая темизация
- Card с shadow, скругленными углами, hover lift
- Sticky navbar с blur, active индикатор
- Timeline с dot + line
- Graph nodes с hover scale
- Editor с split view, toolbar
- Chat с avatar, flex column, typing индикатор
- Search с иконкой, скругленным input
- Modal с backdrop blur
- Spinner анимация
- Responsive grid, mobile burger меню

Без фреймворков, чистый CSS, <20KB всего CSS.

## Структура Файлов - Легко Расширять

- Добавить тему: Редактировать `theme.nim` + `themes.css` + `theme.js`
- Добавить компонент: Создать `web_new/js/components/my.js`, зарегистрировать в `app.js` и `core.nim`
- Добавить API: Редактировать `api_client.nim` + `rest.nim`
- Без lock-in, модульно, vanilla JS
