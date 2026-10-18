## frontend.nim - Nim to JS compilation for UI, platform agnostic
## This module can be compiled to JS via `nim js -o:web_new/js/app.nim.js src/fossil/ui/frontend.nim`
## But primary frontend is vanilla JS in web_new/js/, this file documents architecture and provides Nim APIs

import ./core, ./theme, ./api_client, ./component
import std/[json, tables, strutils]

type
  FrontendConfig* = object
    ## Config for frontend build
    baseUrl*: string
    theme*: string
    enableXhttp*: bool
    enableThemeEditor*: bool
    debug*: bool

  FrontendBundle* = object
    ## Represents built frontend bundle
    html*: string
    css*: string
    js*: string
    themes*: Table[string, string]

proc defaultFrontendConfig*(): FrontendConfig =
  FrontendConfig(
    baseUrl: "",
    theme: "light",
    enableXhttp: true,
    enableThemeEditor: true,
    debug: false
  )

proc getTheme*(name: string): Theme =
  for th in defaultThemes():
    if th.name == name:
      return th
  defaultThemes()[0]

proc getPlatform*(): string =
  when defined(js):
    "web"
  elif defined(windows):
    "windows"
  elif defined(macosx):
    "macos"
  else:
    "linux"

var DefaultRoutes* = defaultRoutes()

proc generateIndexHtml*(config: FrontendConfig = defaultFrontendConfig()): string =
  ## Generate index.html from Nim, using theme system
  let t = getTheme(config.theme)
  result = """
<!DOCTYPE html>
<html lang="en" data-theme="""" & config.theme & """">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Fossil-Nim</title>
  <link rel="stylesheet" href="/assets/app.css">
  <link rel="stylesheet" href="/assets/themes.css">
</head>
<body>
  <div id="app">
    <nav id="navbar" class="navbar"></nav>
    <main id="main" class="main"></main>
    <footer class="footer"></footer>
  </div>
  <script src="/assets/lib/xhttp.js"></script>
  <script src="/assets/lib/theme.js"></script>
  <script src="/assets/api.js"></script>
  <script src="/assets/lib/component.js"></script>
  <script src="/assets/app.js"></script>
</body>
</html>
"""

proc generateAppJs*(config: FrontendConfig = defaultFrontendConfig()): string =
  ## Generate app.js that initializes xhttp, theme, api, router
  result = """
// Generated from src/fossil/ui/frontend.nim
// Vanilla JS, no frameworks, modular
(function(){
  console.log('Fossil-Nim Frontend - Nim generated');
  if(window.app) window.app.init();
})();
"""

proc buildFrontend*(config: FrontendConfig = defaultFrontendConfig()): FrontendBundle =
  ## Build complete frontend bundle
  FrontendBundle(
    html: generateIndexHtml(config),
    css: generateAllThemesCss(),
    js: generateJsApiClient() & "\n" & generateJsComponentBase() & "\n" & generateAppJs(config),
    themes: initTable[string, string]()
  )

when isMainModule:
  # When compiled as JS or native, output bundle info
  echo "Frontend builder - platform: " & $getPlatform()
  let cfg = defaultFrontendConfig()
  let bundle = buildFrontend(cfg)
  echo "HTML size: " & $bundle.html.len
  echo "CSS size: " & $bundle.css.len
  echo "JS size: " & $bundle.js.len
  echo "Routes: " & $DefaultRoutes.len
  for r in DefaultRoutes:
    echo "  " & r.path & " -> " & r.component

# JS export when compiled to JS
when defined(js):
  import std/[jsffi]
  proc initFrontend*() {.exportc.} =
    echo "Frontend initialized via Nim JS"
