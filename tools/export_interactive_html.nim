## export_interactive_html.nim -- Pure Nim (--mm:arc) builder that compiles all 9
## UIRelays applications with `nim js --mm:arc -d:danger --opt:size -d:html` and
## packages them into standalone, self-contained, responsive interactive HTML files
## (Zero <canvas>, Zero WASM, Zero external network dependencies).

import std/[os, strutils]

type
  AppEntry = object
    id: string
    tabLabel: string
    title: string
    desc: string
    srcPath: string

const Apps = [
  AppEntry(
    id: "calculator",
    tabLabel: "1. Calculator",
    title: "Minimalist Calculator + Live Paper Tape",
    desc: "Click any calculator button (0-9, +, -, ×, ÷, =, ±, %, ⌫, C, AC) or type on your keyboard; resize the window to watch the keypad and paper tape stretch dynamically.",
    srcPath: "/home/user/uirelays/examples/calculator.nim"
  ),
  AppEntry(
    id: "snake",
    tabLabel: "2. Snake",
    title: "Minimalist Snake Game",
    desc: "Use Arrow keys / WASD or click the on-screen D-pad buttons ([▲], [▼], [◄], [►], [Pause], [Restart]) to steer the animated snake; resize the window to scale the arena.",
    srcPath: "/home/user/uirelays/examples/snake.nim"
  ),
  AppEntry(
    id: "twenty48",
    tabLabel: "3. 2048",
    title: "Minimalist 2048 Puzzle",
    desc: "Use Arrow keys / WASD or click the on-screen [▲ Up], [▼ Down], [◄ Left], [► Right], and [New Game] buttons to slide and merge tiles; resize the window to scale the board.",
    srcPath: "/home/user/uirelays/examples/twenty48.nim"
  ),
  AppEntry(
    id: "focim",
    tabLabel: "4. Focim IDE",
    title: "Focim — The Focussed Nim Editor",
    desc: "Click tabs ([config], [layout], README.md, calculator.nim, snake.nim), click Explorer actions ([Theme: paper], [Theme: amber], [Split Editor]), edit code or #RRGGBB colors live, or drag panel borders!",
    srcPath: "/home/user/uirelays/focim_web_port/focim_browser.nim"
  ),
  AppEntry(
    id: "web_showcase",
    tabLabel: "5. Web Showcase",
    title: "UIRelays Web Backend Showcase",
    desc: "Switch between Overview, Controls, Graphics, Paint Pad, and Events tabs; click [+1], [-1], [Reset], toggles, drag the slider, paint with the mouse, or type text.",
    srcPath: "/home/user/uirelays/examples/web_showcase.nim"
  ),
  AppEntry(
    id: "todo",
    tabLabel: "6. Todo App",
    title: "Todo App (uirelays/layout)",
    desc: "Type a task and press Enter or click [+ Add], click tasks to toggle completion, click [x] to delete, or filter by All / Active / Completed in the sidebar.",
    srcPath: "/home/user/uirelays/examples/todo.nim"
  ),
  AppEntry(
    id: "paint",
    tabLabel: "7. Paint",
    title: "Minimalist Paint Pad",
    desc: "Click and drag on the drawing surface to paint, click the 6 color swatches, or click [Brush -], [Brush +], and [Clear]; resize the window to expand the canvas.",
    srcPath: "/home/user/uirelays/examples/paint.nim"
  ),
  AppEntry(
    id: "layout_demo",
    tabLabel: "8. Layout Demo",
    title: "Interactive NIF Layout & Splitter Demo",
    desc: "Drag any border between cells to resize panels live, or click [+ Split Right], [+ Split Down], [- Remove Pane], and [Reset Layout] in the toolbar.",
    srcPath: "/home/user/uirelays/examples/layout_demo.nim"
  ),
  AppEntry(
    id: "hello",
    tabLabel: "9. Hello",
    title: "Hello UIRelays + Live Animation",
    desc: "Click anywhere to place the crosshair, click [Accent], [Pink], [Green], or [Anim: ON/OFF] to control the animated diagonal ray wave, and resize the window.",
    srcPath: "/home/user/uirelays/examples/hello.nim"
  )
]

const CommonCss = """
*, *::before, *::after { box-sizing: border-box; }
html, body {
  margin: 0;
  padding: 0;
  width: 100%;
  height: 100%;
  background: #11111b;
  color: #cdd6f4;
  font-family: ui-monospace, "JetBrains Mono", "Fira Code", "Cascadia Mono", "SFMono-Regular", Menlo, Consolas, monospace;
  overflow: hidden;
  user-select: none;
  -webkit-user-select: none;
}
#uir-shell {
  display: flex;
  flex-direction: column;
  width: 100vw;
  height: 100vh;
}
#uir-hud {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  padding: 6px 12px;
  background: #181825;
  border-bottom: 1px solid #313244;
  font-size: 12px;
  flex-shrink: 0;
  flex-wrap: wrap;
}
.uir-hud-group {
  display: flex;
  align-items: center;
  gap: 6px;
  flex-wrap: wrap;
}
.uir-badge {
  padding: 2px 7px;
  border-radius: 4px;
  font-weight: 600;
  background: #313244;
  color: #89b4fa;
  border: 1px solid #45475a;
  font-size: 11px;
}
.uir-badge.ok {
  background: rgba(166, 227, 161, 0.14);
  color: #a6e3a1;
  border-color: rgba(166, 227, 161, 0.4);
}
.uir-btn, .app-tab {
  background: #313244;
  color: #cdd6f4;
  border: 1px solid #45475a;
  border-radius: 5px;
  padding: 4px 9px;
  font-size: 11px;
  font-family: inherit;
  cursor: pointer;
  transition: all 0.12s ease;
}
.uir-btn:hover, .app-tab:hover {
  background: #45475a;
  border-color: #89b4fa;
}
.app-tab.active {
  background: #89b4fa;
  color: #11111b;
  border-color: #89b4fa;
  font-weight: 700;
}
.uir-input {
  background: #1e1e2e;
  color: #cdd6f4;
  border: 1px solid #45475a;
  border-radius: 4px;
  padding: 2px 6px;
  font-size: 11px;
  font-family: inherit;
  width: 130px;
}
#uir-desc-bar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  padding: 4px 12px;
  background: #141421;
  border-bottom: 1px solid #26273a;
  font-size: 11px;
  color: #a6adc8;
  flex-shrink: 0;
}
#uir-stage {
  position: relative;
  flex: 1;
  display: flex;
  align-items: center;
  justify-content: center;
  overflow: hidden;
  background: radial-gradient(circle at center, #1e1e2e 0%, #11111b 100%);
  padding: 2px;
}
#uir-viewport {
  position: relative;
  overflow: hidden;
  background: #1e1e2e;
  box-shadow: 0 8px 28px rgba(0, 0, 0, 0.55), 0 0 0 1px #313244;
  outline: none;
  contain: layout style paint;
}
.uir-rect, .uir-point, .uir-line-h, .uir-line-v, .uir-svg-line, .uir-text, .uir-img-crop, .uir-blit-clip, .uir-clip {
  position: absolute;
  pointer-events: none;
}
.uir-text {
  white-space: pre;
  line-height: 1;
  font-variant-ligatures: none;
}
.uir-clip {
  overflow: hidden;
}
.uir-img, .uir-blit {
  image-rendering: pixelated;
}
"""

proc sanitizeJsForHtml(jsCode: string): string =
  jsCode.replace("</script", "<\\/script").replace("</SCRIPT", "<\\/SCRIPT")

proc buildStandaloneHtml(app: AppEntry; jsCode: string): string =
  result = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>""" & app.title & """ — UIRelays Pure HTML/CSS DOM</title>
<style>""" & CommonCss & """</style>
</head>
<body>
<div id="uir-shell">
  <div id="uir-hud">
    <div class="uir-hud-group">
      <span class="uir-badge ok">PURE HTML5 + CSS3 DOM (NO CANVAS · NO WASM)</span>
      <strong id="uir-win-title">""" & app.title & """</strong>
      <span class="uir-badge" id="uir-stat-size">Auto</span>
      <span class="uir-badge" id="uir-stat-frame">frame: 0</span>
      <span class="uir-badge" id="uir-stat-nodes">DOM nodes: 0</span>
      <span class="uir-badge" id="uir-stat-cursor">cursor: default</span>
    </div>
    <div class="uir-hud-group">
      <label for="uir-clipboard-input">Clipboard:</label>
      <input id="uir-clipboard-input" class="uir-input" type="text" placeholder="Clipboard text..." />
      <button id="uir-btn-clip-sync" class="uir-btn" type="button">Sync</button>
      <button id="uir-btn-resize-auto" class="uir-btn" type="button">Auto Fit</button>
      <button id="uir-btn-resize-960" class="uir-btn" type="button">960×640</button>
      <button id="uir-btn-resize-800" class="uir-btn" type="button">800×600</button>
    </div>
  </div>
  <div id="uir-desc-bar">
    <span>""" & app.desc & """</span>
  </div>
  <div id="uir-stage">
    <div id="uir-viewport" tabindex="0" aria-label="UIRelays Pure HTML Viewport"></div>
  </div>
</div>
<script>
(function() {
""" & sanitizeJsForHtml(jsCode) & """
})();
</script>
</body>
</html>
"""

proc buildAllAppsBundleHtml(compiledJs: seq[tuple[app: AppEntry, js: string]]): string =
  var tabButtons = ""
  for i, item in compiledJs:
    let activeCls = if i == 0: " active" else: ""
    tabButtons.add "<button class=\"app-tab" & activeCls & "\" id=\"tab-btn-" & item.app.id &
      "\" type=\"button\" onclick=\"switchUirApp('" & item.app.id & "')\">" & item.app.tabLabel & "</button>\n"

  var jsAppMap = "window.UIR_APP_META = {\n"
  for item in compiledJs:
    jsAppMap.add "  \"" & item.app.id & "\": { title: \"" & item.app.title.replace("\"", "\\\"") &
      "\", desc: \"" & item.app.desc.replace("\"", "\\\"") & "\" },\n"
  jsAppMap.add "};\nwindow.UIR_APPS = {\n"
  for item in compiledJs:
    jsAppMap.add "  \"" & item.app.id & "\": function() {\n" & sanitizeJsForHtml(item.js) & "\n  },\n"
  jsAppMap.add "};\n"

  result = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>UIRelays — All 9 Interactive Pure HTML/CSS DOM Applications (Nim --mm:arc)</title>
<style>""" & CommonCss & """</style>
</head>
<body>
<div id="uir-shell">
  <div id="uir-hud">
    <div class="uir-hud-group" id="uir-tab-list">
""" & tabButtons & """
    </div>
    <div class="uir-hud-group">
      <span class="uir-badge ok">NO CANVAS · NO WASM · NIM --mm:arc</span>
      <span class="uir-badge" id="uir-stat-size">Auto</span>
      <span class="uir-badge" id="uir-stat-frame">frame: 0</span>
      <span class="uir-badge" id="uir-stat-nodes">DOM nodes: 0</span>
      <button id="uir-btn-resize-auto" class="uir-btn" type="button">Auto Fit</button>
      <button id="uir-btn-resize-960" class="uir-btn" type="button">960×640</button>
      <button id="uir-btn-resize-800" class="uir-btn" type="button">800×600</button>
    </div>
  </div>
  <div id="uir-desc-bar">
    <div><strong id="uir-win-title" style="color:#89b4fa;margin-right:8px;"></strong><span id="uir-app-desc"></span></div>
    <div class="uir-hud-group">
      <span id="uir-stat-cursor" style="margin-right:6px;">cursor: default</span>
      <input id="uir-clipboard-input" class="uir-input" type="text" placeholder="Clipboard..." />
      <button id="uir-btn-clip-sync" class="uir-btn" type="button">Sync Clip</button>
    </div>
  </div>
  <div id="uir-stage">
    <div id="uir-viewport" tabindex="0" aria-label="UIRelays Pure HTML Viewport"></div>
  </div>
</div>
<script>
""" & jsAppMap & """
function switchUirApp(appId) {
  var tabs = document.querySelectorAll(".app-tab");
  for (var i = 0; i < tabs.length; i++) {
    tabs[i].classList.remove("active");
  }
  var btn = document.getElementById("tab-btn-" + appId);
  if (btn) btn.classList.add("active");
  var meta = window.UIR_APP_META[appId];
  if (meta) {
    var descEl = document.getElementById("uir-app-desc");
    if (descEl) descEl.textContent = meta.desc;
  }
  var vp = document.getElementById("uir-viewport");
  if (vp) {
    vp.innerHTML = "";
    vp.focus();
  }
  if (window.UIR_APPS && window.UIR_APPS[appId]) {
    window.UIR_APPS[appId]();
  }
}
window.addEventListener("DOMContentLoaded", function() {
  switchUirApp("calculator");
});
</script>
</body>
</html>
"""

proc main() =
  createDir("/tmp/uir_js")
  createDir("/home/user/uirelays/exported_html")

  var compiled: seq[tuple[app: AppEntry, js: string]] = @[]
  for app in Apps:
    let outJs = "/tmp/uir_js/" & app.id & ".js"
    let cmd = "/tmp/nim-2.2.2/bin/nim js --mm:arc -d:danger --opt:size -d:html " &
              "--path:/home/user/uirelays/src --path:/home/user/focim/src " &
              "-o:" & outJs & " " & app.srcPath
    echo "Compiling JS for ", app.id, " ..."
    let code = execShellCmd(cmd)
    doAssert code == 0, "Failed compiling JS for " & app.id
    let jsContent = readFile(outJs)
    doAssert "<canvas" notin jsContent.toLowerAscii(), "Forbidden <canvas> found in " & app.id
    doAssert "WebAssembly" notin jsContent, "Forbidden WebAssembly found in " & app.id
    compiled.add((app: app, js: jsContent))

    let standaloneHtml = buildStandaloneHtml(app, jsContent)
    let standalonePath = "/home/user/uirelays/exported_html/" & app.id & ".html"
    writeFile(standalonePath, standaloneHtml)
    echo "  -> Wrote ", standalonePath, " (", standaloneHtml.len div 1024, " KB)"

  let bundleHtml = buildAllAppsBundleHtml(compiled)
  writeFile("/home/user/uirelays_all_apps.html", bundleHtml)
  writeFile("/home/user/uirelays/exported_html/uirelays_all_apps.html", bundleHtml)
  echo "  -> Wrote /home/user/uirelays_all_apps.html (", bundleHtml.len div 1024, " KB)"

main()
