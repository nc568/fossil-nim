# Fossil-Nim UI - Modular, Decoupled, Beautiful

Modern vanilla JS frontend with Nim backend, decoupled from web for future TUI/desktop.

## Architecture

```
src/fossil/ui/
├── core.nim       - Platform agnostic UI core, routes, state, pure functions
├── theme.nim      - Theme system, palette, CSS variables generation
├── api_client.nim - API client abstraction, typed requests, JS generation
├── component.nim  - Component base, registry, List/Detail/Form
├── frontend.nim   - Nim->JS build, bundle generation
└── README.md      - This file

web_new/
├── index.html     - SPA entry, critical CSS inline, xhttp attributes
├── css/
│   ├── app.css    - Modern minimal CSS, variables, responsive
│   └── themes.css - 6 themes: light/dark/solarized/nord/monokai/github-light
└── js/
    ├── lib/
    │   ├── xhttp.js     - Minimal htmx-like (~5KB), data-get/post/target/swap
    │   ├── theme.js     - Theme switching, editor, import/export JSON
    │   └── component.js - Component base, registry
    ├── api.js           - Vanilla JS ApiClient, fetch, token
    ├── app.js           - Router, SPA navigation, state
    └── components/
        ├── navbar.js
        ├── timeline.js
        ├── file.js (file + file-history)
        ├── info.js
        ├── graph.js
        ├── wiki.js (wiki + wiki-list + wiki-edit)
        ├── ticket.js (ticket + list + edit)
        ├── forum.js (forum + list + edit)
        ├── chat.js (chat + chat-rooms)
        ├── search.js
        ├── login.js
        ├── setup.js
        └── diff.js (diff + blame)
```

## Principles

1. **Vanilla JS, no frameworks** - No React/Vue/Angular, just vanilla JS <10KB core
2. **xhttp-like** - Server-driven HTML fragments via `data-get`, `data-post`, `data-target`, `data-swap` (htmx inspiration, Nim implementation)
3. **Modular** - Each component is independent, `render()`, `fetch()`, `afterRender()`
4. **Easy theme palette editing** - Edit `theme.nim` palette, regenerate CSS variables, or use UI editor 🎨
5. **Decoupled from web** - Core in `core.nim` is platform agnostic, can be used for TUI/desktop/mobile/CLI
6. **Beautiful modern minimalistic** - CSS variables, card shadows, rounded corners, blur navbar

## Theme System - Easy Palette Editing

Edit in `src/fossil/ui/theme.nim`:

```nim
let myPalette = ColorPalette(
  primary: "#your-color",
  bg: "#your-bg",
  text: "#your-text",
  # ... 20+ colors
)
let myTheme = Theme(name: "my-custom", displayName: "My Custom", palette: myPalette, isDark: false)
```

Or via UI: Click 🎨 -> Edit colors -> Save Custom -> Export JSON.

JSON format:
```json
{
  "name": "custom",
  "displayName": "Custom",
  "isDark": false,
  "palette": {
    "primary": "#0d6efd",
    "bg": "#f8f9fa",
    "text": "#212529",
    ...
  }
}
```

CSS variables generated: `--color-primary`, `--color-bg`, etc. Used in `app.css`.

## xhttp.js - Minimal htmx-like

~100 lines, vanilla JS:

```html
<!-- GET request, swap innerHTML into #main -->
<a href="/timeline" data-link data-get="/api/v1/timeline" data-target="#main">Timeline</a>

<!-- POST form -->
<form data-post="/api/v1/wiki/save" data-target="#main">
  <input name="name">
  <textarea name="content"></textarea>
  <button>Save</button>
</form>

<!-- Swap modes: innerHTML, outerHTML, beforeend, afterbegin, beforebegin, afterend, none -->
<div data-get="/api/v1/status" data-target="#status" data-swap="innerHTML">Load</div>
```

Features:
- `data-get`, `data-post`, `data-put`, `data-delete`
- `data-target` CSS selector
- `data-swap` swap mode
- `data-link` SPA navigation with pushState
- `data-indicator` loading indicator
- Auto process new content for xhttp attributes
- Events: `xhttp:afterRequest`, `xhttp:afterSwap`, `xhttp:error`

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
    return `<div class="card"><h1>My Component</h1></div>`;
  };
  
  c.afterRender = () => {
    // Bind events
  };
  
  return c;
});
```

## Router

`app.js` router:
- Intercepts `data-link` clicks
- `pushState` for SPA navigation
- `popstate` for back/forward
- Loads component or falls back to server HTML
- Updates active nav state

## Build & Serve

```bash
# Dev server
nim c -r src/fossil/cli/main.nim ui serve --port 8080

# Or via API server
nim c -r src/fossil/cli/main.nim api serve --port 8080
# Then open http://localhost:8080/

# Build frontend bundle via Nim
nim c -r src/fossil/ui/frontend.nim
# Generates HTML/CSS/JS bundle

# Compile frontend to JS (optional)
nim js -o:web_new/js/app.nim.js src/fossil/ui/frontend.nim
```

## Platform Agnostic - Future TUI/Desktop

Core is decoupled:

```nim
# Same core for all platforms
let state = newUiState(Web) # or Tui, Desktop, Mobile, Cli
let newState = navigate(state, "/timeline")

# Theme works for all
let css = themeToCss(myTheme) # web
let tuiColors = paletteToTuiColors(myPalette) # future TUI

# API client works for all
let client = newApiClient("http://localhost:8080")
let req = timelineRequest(TimelineParams(limit: 20))
```

Future:
- TUI: `src/fossil/ui/tui.nim` using `illwill` or `termbox`
- Desktop: Tauri/Electron with same core
- Mobile: Same API client

## API Integration

All components use `api.js`:

```js
await api.timeline(20, 'trunk')
await api.fileList('*.nim', 100)
await api.fileGet('src/main.nim')
await api.search('bug', 20, 'ticket')
await api.wikiList()
await api.wikiGet('Home')
await api.wikiSave('Home', '# Content', 'update')
await api.ticketList(20)
await api.forumList(50)
await api.chatList('main', 50)
await api.chatSend('main', 'hello', 'user')
```

Backend: `src/fossil/api/rest.nim` serves both API (`/api/v1/*`) and frontend (`/`).

## File Structure - Modular

- Add new theme: Edit `theme.nim` + `themes.css`
- Add new component: Create `web_new/js/components/my.js` + register route in `app.js` + `core.nim`
- Add new API endpoint: Edit `api_client.nim` + `rest.nim`
- Easy to extend, no framework lock-in
