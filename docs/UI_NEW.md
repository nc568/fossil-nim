# Fossil-Nim New Web UI - Modern, Modular, Vanilla JS

Complete rewrite of Fossil web UI on vanilla JS, no frameworks, with xhttp/htmx-like library in Nim style.

## Overview

- **Vanilla JS, no frameworks** - <10KB core, no React/Vue, pure JS
- **xhttp-like library** - Minimal htmx-inspired, `data-get`, `data-post`, `data-target`, `data-swap`
- **Beautiful modern minimalistic** - CSS variables, cards, blur navbar, responsive
- **Easy theme palette editing** - Edit palette in Nim or via UI editor, JSON import/export
- **Modular architecture** - Each component independent, easy to add
- **Decoupled from web** - Core in Nim is platform agnostic, ready for TUI/desktop/mobile

## Architecture

### Nim Backend - Platform Agnostic

```
src/fossil/ui/
├── core.nim       - UiPlatform (web/tui/desktop/mobile/cli), UiRoute (22 routes), UiState, ApiResponse, pure navigation
├── theme.nim      - ColorPalette, Theme, 6 palettes, paletteToCssVariables, themeToCss, generateAllThemesCss, JSON
├── api_client.nim - HttpMethod, ApiRequest, ApiClientConfig, typed params, generateJsApiClient
├── component.nim  - Component base, registry, List/Detail/Form, generateJsComponentBase
├── frontend.nim   - FrontendConfig, generateIndexHtml, buildFrontend, Nim->JS
└── README.md
```

Core is pure functions, no DOM dependency:

```nim
let state = newUiState(Web)
let newState = navigate(state, "/timeline")
let css = themeToCss(myTheme)
let js = generateJsApiClient()
```

Same core can be used for:
- Web (current)
- TUI (future, using illwill)
- Desktop (Tauri/Electron)
- Mobile
- CLI

### Frontend - Vanilla JS

```
web_new/
├── index.html              - SPA entry, critical CSS inline, navbar with data-link/data-get
├── css/
│   ├── app.css             - 15KB modern CSS, variables, grid, cards, timeline, graph, chat, modal
│   └── themes.css          - 6 themes: light/dark/solarized-light/nord/monokai/github-light, data-theme
└── js/
    ├── lib/
    │   ├── xhttp.js        - ~5KB, htmx-like, data-get/post/target/swap/trigger, fetch, history
    │   ├── theme.js        - Theme switching, localStorage, editor with color pickers, import/export
    │   └── component.js    - Component base, mount/update/setError/fetchData, registry
    ├── api.js              - ApiClient class, fetch, token localStorage, 20+ endpoints
    ├── app.js              - Router, SPA navigation, data-link intercept, popstate, state
    └── components/         - 12 modular components
        ├── navbar.js
        ├── timeline.js     - Timeline with filter, load more, badges
        ├── file.js         - File browser + file-history
        ├── info.js         - Check-in info
        ├── graph.js        - Commit graph
        ├── wiki.js         - Wiki + wiki-list + wiki-edit with live markdown preview
        ├── ticket.js       - Ticket + list + new
        ├── forum.js        - Forum threads + pinned + search + pin/unpin
        ├── chat.js         - Chat rooms + presence + typing indicator + attachments
        ├── search.js       - FTS5 live search with debounce
        ├── login.js
        ├── setup.js
        └── diff.js         - Diff + blame
```

## xhttp.js - Minimal htmx-like

Inspired by htmx, written in Nim-style, <5KB:

```html
<!-- SPA navigation -->
<a href="/timeline" data-link>Timeline</a>

<!-- Server-driven fragment -->
<a data-get="/api/v1/timeline?limit=20" data-target="#main" data-swap="innerHTML">Load</a>

<!-- Form POST -->
<form data-post="/api/v1/wiki/save" data-target="#main">
  <input name="name">
  <textarea name="content"></textarea>
  <button>Save</button>
</form>

<!-- Swap modes -->
<div data-get="/api/v1/status" data-target="#status" data-swap="beforeend">Load more</div>
```

Attributes:
- `data-get`, `data-post`, `data-put`, `data-delete` - HTTP method + URL
- `data-target` - CSS selector for swap target
- `data-swap` - `innerHTML`, `outerHTML`, `beforeend`, `afterbegin`, `beforebegin`, `afterend`, `none`
- `data-link` - SPA navigation with pushState
- `data-indicator` - Loading indicator selector
- `data-trigger` - Event trigger (click, submit, etc)

Events:
- `xhttp:afterRequest`
- `xhttp:afterSwap`
- `xhttp:error`

## Theme System - Easy Palette Editing

### In Nim - `src/fossil/ui/theme.nim`

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
let css = themeToCss(myTheme) # generates [data-theme="my-custom"] { --color-primary: ... }
let allCss = generateAllThemesCss() # all themes
let json = themeToJson(myTheme) # for export
```

### In CSS - `web_new/css/themes.css`

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

### In UI - Theme Editor

Click 🎨 button:
- Presets grid - click to switch theme
- Color grid - color pickers for each palette entry
- Save Custom - saves to localStorage
- Reset - reset to default
- Export JSON - download theme JSON
- Import JSON - upload theme JSON

All themes use CSS variables, so changing palette instantly updates UI.

6 built-in themes:
- light - Default, clean minimal
- dark - Dark for low light
- solarized-light - Solarized light, easy on eyes
- nord - Nord dark, arctic bluish
- monokai - Vibrant dark
- github-light - GitHub light

Add new theme: copy template in `themes.css`, edit colors, add to `theme.nim` and `theme.js`.

## Component System

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

Base classes:
- `Component` - base with init/render/update/destroy/handleEvent
- `ListComponent` - for lists with renderList
- `DetailComponent` - for detail views
- `FormComponent` - for forms

Registry: `window.components`, `registerComponent(name, factory)`, `createComponent(name, props)`

## Router - `app.js`

- Intercepts `data-link` clicks
- `history.pushState` for SPA
- `popstate` for back/forward
- Loads component or falls back to server HTML
- Updates active nav
- Processes xhttp attributes in new content

Routes (22):
- `/` - Home
- `/timeline` - Timeline
- `/file`, `/finfo`, `/info`, `/graph`, `/diff`, `/blame`
- `/wiki`, `/wiki/list`, `/wiki/new`, `/wiki/edit`
- `/ticket`, `/ticket/list`, `/ticket/new`
- `/forum`, `/forum/list`, `/forum/new`
- `/chat`, `/chat/rooms`
- `/search`, `/login`, `/setup`

## API Integration

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

Backend serves both API and frontend: `src/fossil/api/rest.nim`

## Build & Serve

```bash
# Build binary with new UI
nim c -d:release -o:fossil src/fossil/cli/main.nim

# Run server - new UI automatically served if web_new/ exists
./fossil server --repo repo.fossil --port 8080

# Open http://localhost:8080/
# New UI at /, API at /api/v1/*

# Frontend bundle via Nim
nim c -r src/fossil/ui/frontend.nim
# Generates HTML/CSS/JS bundle info

# Optional: compile frontend to JS
nim js -o:web_new/js/app.nim.js src/fossil/ui/frontend.nim
```

## Decoupled - Future TUI/Desktop

Core is platform agnostic:

```nim
# Same core for all
let state = newUiState(Web) # or Tui, Desktop, Mobile, Cli
let newState = navigate(state, "/timeline")

# Theme for web
let css = themeToCss(myTheme)

# Future TUI
# let tuiColors = paletteToTuiColors(myPalette)

# API client works everywhere
let client = newApiClient("http://localhost:8080")
let req = timelineRequest(TimelineParams(limit: 20))
```

Future:
- `src/fossil/ui/tui.nim` - Terminal UI using illwill
- Desktop - Tauri with same core
- Mobile - Same API client

## Beautiful Modern Minimalistic

- CSS variables for all colors - easy theming
- Card with shadow, rounded corners, hover lift
- Sticky navbar with blur, active indicator
- Timeline with dot + line
- Graph nodes with hover scale
- Editor with split view, toolbar
- Chat with avatar, flex column, typing indicator
- Search with icon, rounded input
- Modal with backdrop blur
- Spinner animation
- Responsive grid, mobile burger menu

No frameworks, pure CSS, <20KB total CSS.

## File Structure - Easy to Extend

- Add theme: Edit `theme.nim` + `themes.css` + `theme.js`
- Add component: Create `web_new/js/components/my.js`, register in `app.js` and `core.nim`
- Add API: Edit `api_client.nim` + `rest.nim`
- No lock-in, modular, vanilla JS
