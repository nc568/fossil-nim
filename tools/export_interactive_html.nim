## export_interactive_html.nim -- Pure Nim (--mm:arc) builder that compiles all 10
## UIRelays applications with `nim js --mm:arc -d:danger --opt:size -d:html` and
## packages them into standalone, self-contained, responsive interactive HTML files
## (Zero <canvas>, Zero WASM, Zero external network dependencies).

import std/[os, strutils, osproc]

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
    srcPath: "examples/calculator.nim"
  ),
  AppEntry(
    id: "snake",
    tabLabel: "2. Snake",
    title: "Minimalist Snake Game",
    desc: "Use Arrow keys / WASD or click the on-screen D-pad buttons ([▲], [▼], [◄], [►], [Pause], [Restart]) to steer the animated snake; resize the window to scale the arena.",
    srcPath: "examples/snake.nim"
  ),
  AppEntry(
    id: "twenty48",
    tabLabel: "3. 2048",
    title: "Minimalist 2048 Puzzle",
    desc: "Use Arrow keys / WASD or click the on-screen [▲ Up], [▼ Down], [◄ Left], [► Right], and [New Game] buttons to slide and merge tiles; resize the window to scale the board.",
    srcPath: "examples/twenty48.nim"
  ),
  AppEntry(
    id: "focim",
    tabLabel: "4. Focim IDE",
    title: "Focim — The Focussed Nim Editor",
    desc: "Click tabs ([config], [layout], README.md, calculator.nim, snake.nim), click Explorer actions ([Theme: paper], [Theme: amber], [Split Editor]), edit code or #RRGGBB colors live, or drag panel borders!",
    srcPath: "focim_web_port/focim_browser.nim"
  ),
  AppEntry(
    id: "web_showcase",
    tabLabel: "5. Web Showcase",
    title: "UIRelays Web Backend Showcase",
    desc: "Switch between Overview, Controls, Graphics, Paint Pad, and Events tabs; click [+1], [-1], [Reset], toggles, drag the slider, paint with the mouse, or type text.",
    srcPath: "examples/web_showcase.nim"
  ),
  AppEntry(
    id: "todo",
    tabLabel: "6. Todo App",
    title: "Todo App (uirelays/layout)",
    desc: "Type a task and press Enter or click [+ Add], click tasks to toggle completion, click [x] to delete, or filter by All / Active / Completed in the sidebar.",
    srcPath: "examples/todo.nim"
  ),
  AppEntry(
    id: "paint",
    tabLabel: "7. Paint",
    title: "Minimalist Paint Pad",
    desc: "Click and drag on the drawing surface to paint, click the 6 color swatches, or click [Brush -], [Brush +], and [Clear]; resize the window to expand the canvas.",
    srcPath: "examples/paint.nim"
  ),
  AppEntry(
    id: "layout_demo",
    tabLabel: "8. Layout Demo",
    title: "Interactive NIF Layout & Splitter Demo",
    desc: "Drag any border between cells to resize panels live, or click [+ Split Right], [+ Split Down], [- Remove Pane], and [Reset Layout] in the toolbar.",
    srcPath: "examples/layout_demo.nim"
  ),
  AppEntry(
    id: "hello",
    tabLabel: "9. Hello",
    title: "Hello UIRelays + Live Animation",
    desc: "Click anywhere to place the crosshair, click [Accent], [Pink], [Green], or [Anim: ON/OFF] to control the animated diagonal ray wave, and resize the window.",
    srcPath: "examples/hello.nim"
  ),
  AppEntry(
    id: "sharks",
    tabLabel: "10. Hammerhead Reef",
    title: "Hammerhead Reef (blitRGBA seabed + mosaic sharks)",
    desc: "Four hammerhead sharks over a seabed that is baked once and republished with a single blitRGBA per frame. Click [UI panel: ON/OFF] and [Follow mouse: ON/OFF], move the mouse, type into the panel and press Enter, or press U / F / ESC.",
    srcPath: "examples/sharks.nim"
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
  if (btn) {
    btn.classList.add("active");
    if (btn.blur) btn.blur();
  }
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
  setTimeout(function() {
    var v = document.getElementById("uir-viewport");
    if (v && v.focus) v.focus();
  }, 10);
}
window.addEventListener("DOMContentLoaded", function() {
  switchUirApp("calculator");
});
</script>
</body>
</html>
"""

proc repoRoot(): string =
  ## Directory of this checkout, found without assuming where it was cloned
  ## (`/home/user/uirelays` in the original version of this tool) and without
  ## assuming what the working directory is when it runs.
  let envRoot = getEnv("UIRELAYS_ROOT", "")
  if envRoot.len > 0 and dirExists(envRoot / "src" / "uirelays"):
    return envRoot
  for start in [getCurrentDir(), getAppDir()]:
    var dir = start
    for _ in 0 ..< 8:
      if dirExists(dir / "src" / "uirelays"):
        return dir
      let parent = parentDir(dir)
      if parent == dir:
        break
      dir = parent
  getCurrentDir()

proc checkZeroCanvasPolicy(js: string): string =
  ## What the policy really forbids is *using* a canvas or WebAssembly, not
  ## the letters: an app that embeds a README mentioning `<canvas>` (the
  ## Focim demo does exactly that with this repository's README) is still a
  ## pure-DOM app. So look for API calls, not for substrings -- the page
  ## template itself is checked for `<canvas>` markup in `web_html_test.nim`,
  ## which is where a stray element would actually render.
  const forbidden = [
    "getContext(\"2d\")", "getContext('2d')", "getContext(`2d`)",
    "createElement(\"canvas\")", "createElement('canvas')",
    "WebAssembly.", "WebAssembly(", "new WebAssembly"
  ]
  for needle in forbidden:
    if needle in js:
      return needle
  ""

proc main() =
  let root = repoRoot()
  let outDir = getEnv("UIRELAYS_EXPORT_DIR", root / "exported_html")
  let bundleOut = getEnv("UIRELAYS_BUNDLE_OUT", outDir / "uirelays_all_apps.html")
  let workDir = getEnv("UIRELAYS_TMPDIR", getTempDir() / "uir_js")

  createDir(workDir)
  createDir(outDir)

  let nimBin = block:
    let fromEnv = getEnv("NIM", "")
    if fromEnv.len > 0: fromEnv
    else:
      let found = findExe("nim")
      if found.len > 0: found else: "nim"

  # `UIRELAYS_ONLY_SELFTEST=1` builds just the selftest page below and skips
  # the ten application pages and the bundle: CI runs the digest check on three
  # operating systems and does not need to re-export the whole gallery there.
  let onlySelftest = getEnv("UIRELAYS_ONLY_SELFTEST", "") == "1"

  var appList: seq[AppEntry] = @[]
  if not onlySelftest:
    for a in Apps: appList.add a

  var compiled: seq[tuple[app: AppEntry, js: string]] = @[]
  for app in appList:
    let srcPath = root / app.srcPath
    if not fileExists(srcPath):
      echo "  SKIP  ", app.id, " (", app.srcPath, " not in this checkout)"
      continue
    let outJs = workDir / app.id & ".js"
    # `--jsbigint64:off -d:nimStringHash2` keeps `nim js` away from BigInt,
    # which `std/times` and friends mix with plain numbers and crash on.
    let cmd = nimBin & " js --mm:arc -d:danger --opt:size -d:html " &
              "--jsbigint64:off -d:nimStringHash2 " &
              "--path:" & quoteShell(root / "src") & " " &
              "--path:" & quoteShell(root / "focim_web_port") & " " &
              "-o:" & quoteShell(outJs) & " " & quoteShell(srcPath)
    echo "Compiling JS for ", app.id, " ..."
    let code = execShellCmd(cmd)
    if code != 0:
      quit "Failed compiling JS for " & app.id & " (command: " & cmd & ")", 1
    let jsContent = readFile(outJs)
    let violation = checkZeroCanvasPolicy(jsContent)
    doAssert violation.len == 0, "Zero <canvas>/WASM policy violated in " &
      app.id & ": " & violation
    compiled.add((app: app, js: jsContent))

    let standaloneHtml = buildStandaloneHtml(app, jsContent)
    let standalonePath = outDir / app.id & ".html"
    writeFile(standalonePath, standaloneHtml)
    echo "  -> Wrote ", standalonePath, " (", standaloneHtml.len div 1024, " KB)"

  # A page whose app is compiled with `-d:sharksSelftest`: it renders a fixed
  # number of frames of a fixed-size scene and prints one `SHARKS_DIGEST` line
  # through `console.log`. That line is what lets CI compare the *browser*
  # rendering against the native one bit for bit, so it is built outside
  # `exported_html/` and never shipped: the pages users get must keep
  # animating.
  let selftestOut = getEnv("UIRELAYS_SELFTEST_OUT", "")
  if selftestOut.len > 0:
    let selftestSrc = root / getEnv("UIRELAYS_SELFTEST_SRC", "examples/sharks.nim")
    let frames = getEnv("UIRELAYS_SELFTEST_FRAMES", "120")
    let outJs = workDir / "selftest_sharks.js"
    let cmd = nimBin & " js --mm:arc -d:danger --opt:size -d:html " &
              "--jsbigint64:off -d:nimStringHash2 " &
              "-d:sharksSelftest -d:sharksFrames=" & frames & " " &
              "--path:" & quoteShell(root / "src") & " " &
              "-o:" & quoteShell(outJs) & " " & quoteShell(selftestSrc)
    echo "Compiling JS selftest page ..."
    if execShellCmd(cmd) != 0:
      quit "Failed compiling the selftest page (command: " & cmd & ")", 1
    let jsContent = readFile(outJs)
    let violation = checkZeroCanvasPolicy(jsContent)
    doAssert violation.len == 0,
      "Zero <canvas>/WASM policy violated in the selftest page: " & violation
    let entry = AppEntry(
      id: "sharks_selftest",
      tabLabel: "Hammerhead Reef selftest",
      title: "Hammerhead Reef selftest (" & frames & " frames)",
      desc: "Renders a deterministic scene and logs SHARKS_DIGEST for CI to compare against the native backends.",
      srcPath: "examples/sharks.nim")
    createDir(parentDir(selftestOut))
    writeFile(selftestOut, buildStandaloneHtml(entry, jsContent))
    echo "  -> Wrote ", selftestOut

  if onlySelftest:
    if not fileExists(getEnv("UIRELAYS_SELFTEST_OUT", "")):
      quit "UIRELAYS_ONLY_SELFTEST=1 but no selftest page was written", 1
    return

  if compiled.len == 0:
    quit "No application sources found under " & root, 1

  let bundleHtml = buildAllAppsBundleHtml(compiled)
  writeFile(bundleOut, bundleHtml)
  echo "  -> Wrote ", bundleOut, " (", bundleHtml.len div 1024, " KB)"

main()
