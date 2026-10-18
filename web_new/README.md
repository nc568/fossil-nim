# Fossil-Nim New Web UI - web_new/

Modern, modular, vanilla JS frontend, no frameworks.

## Quick Start

```bash
# Build fossil binary
nim c -d:release -o:fossil src/fossil/cli/main.nim

# Run server - serves web_new/ automatically
./fossil server --repo repo.fossil --port 8080

# Open http://localhost:8080/
```

## Structure

- `index.html` - SPA entry, critical CSS, navbar, #main target, theme editor modal, scripts
- `css/app.css` - Modern minimal CSS, variables, responsive, 15KB
- `css/themes.css` - 6 themes: light/dark/solarized/nord/monokai/github-light
- `js/lib/xhttp.js` - Minimal htmx-like, data-get/post/target/swap
- `js/lib/theme.js` - Theme switching, editor, import/export JSON
- `js/lib/component.js` - Component base, registry
- `js/api.js` - ApiClient, fetch, token
- `js/app.js` - Router, SPA, state
- `js/components/*.js` - 12 modular components

## Themes - Easy Editing

Edit `src/fossil/ui/theme.nim` palette, then regenerate `css/themes.css` via:

```nim
let css = generateAllThemesCss()
writeFile("web_new/css/themes.css", css)
```

Or via UI: Click 🎨 -> Edit colors -> Save/Export JSON.

## xhttp.js Usage

```html
<a href="/timeline" data-link>Timeline</a>
<div data-get="/api/v1/timeline" data-target="#main" data-swap="innerHTML">Load</div>
<form data-post="/api/v1/wiki/save" data-target="#main">...</form>
```

## Components

Each component: `render()`, optional `fetch(query)`, `afterRender()`, registered via `registerComponent(name, factory)`.

Add new component: create `js/components/my.js`, register route in `js/app.js` and `src/fossil/ui/core.nim`.

## Decoupled

Core in `src/fossil/ui/` is platform agnostic, ready for TUI/desktop.

See `src/fossil/ui/README.md` and `docs/UI_NEW.md` for details.
