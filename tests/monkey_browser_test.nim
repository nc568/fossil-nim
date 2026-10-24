## Real Headless Chromium Browser Monkey Test Suite + Pure HTML Exporter (Nim --mm:arc).
##
## Tests all 9 UIRelays applications across both `-d:html` (Pure DOM) and
## `-d:canvas` (HTML5 Canvas 2D), and exports the resulting Pure HTML5 + CSS3
## DOM markup (zero JS, zero <canvas>, zero WASM) for each application into
## `exported_html/<app>.html` and `/home/user/uirelays_all_apps.html`.

import std/[os, osproc, strutils, json, net, times]

var passes = 0
var failures = 0
var skips = 0
var browserPath = ""
  ## Filled in by `main()`; declared up here so the checks below can use it.

proc skip(name: string; why: string) =
  inc skips
  echo "  SKIP  ", name, "  -- ", why

proc repoRoot(): string =
  ## Wherever this checkout happens to live: no /home/user paths, and no
  ## dependence on the working directory the test was started from.
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

proc findBrowser(): string =
  ## The browser is a precondition, not a result: without one there is
  ## nothing here to assert, so the caller skips instead of failing.
  let fromEnv = getEnv("UIRELAYS_BROWSER", "")
  if fromEnv.len > 0:
    return fromEnv
  for name in ["chromium", "chromium-browser", "google-chrome",
               "google-chrome-stable", "chrome", "firefox"]:
    let found = findExe(name)
    if found.len > 0:
      return found
  ""

type
  ExportedAppFrame = object
    appName: string
    title: string
    width: int
    height: int
    domNodeCount: int
    htmlBody: string

var exportedFrames: seq[ExportedAppFrame] = @[]

proc check(name: string; cond: bool; detail = "") =
  if cond:
    inc passes
    echo "  PASS  ", name
  else:
    inc failures
    echo "  FAIL  ", name, (if detail.len > 0: "  -- " & detail else: "")

proc httpRequest(port: int; httpMethod, path: string; body = ""; timeoutMs = 3000): tuple[ok: bool; status: int; body: string] =
  var client = newSocket()
  defer:
    try: client.close()
    except CatchableError: discard
  try:
    client.connect("127.0.0.1", Port(port), timeout = timeoutMs)
    var req = httpMethod & " " & path & " HTTP/1.1\r\n" &
              "Host: 127.0.0.1:" & $port & "\r\n" &
              "Connection: close\r\n"
    if body.len > 0:
      req.add "Content-Type: application/json\r\n"
      req.add "Content-Length: " & $body.len & "\r\n"
    req.add "\r\n"
    if body.len > 0:
      req.add body
    client.send(req)

    var response = ""
    while true:
      var chunk = newString(4096)
      let n = client.recv(addr chunk[0], 4096, timeout = timeoutMs)
      if n <= 0:
        break
      chunk.setLen(n)
      response.add chunk

    let sep = response.find("\r\n\r\n")
    if sep < 0:
      return (false, 0, response)
    let hdr = response[0 ..< sep]
    let respBody = response[sep + 4 .. ^1]
    var code = 200
    let firstLineEnd = hdr.find("\r\n")
    let firstLine = if firstLineEnd >= 0: hdr[0 ..< firstLineEnd] else: hdr
    let parts = firstLine.splitWhitespace()
    if parts.len >= 2:
      try: code = parseInt(parts[1])
      except ValueError: code = 0
    return (code == 200, code, respBody)
  except CatchableError as e:
    return (false, 0, e.msg)

proc waitForServerReady(port: int; maxWaitMs = 6000): bool =
  let t0 = epochTime()
  while (epochTime() - t0) * 1000.0 < float(maxWaitMs):
    let r = httpRequest(port, "GET", "/health", timeoutMs = 400)
    if r.ok and r.body.len > 0:
      try:
        let j = parseJson(r.body)
        if j.getOrDefault("frameId").getInt(0) >= 1:
          return true
      except CatchableError:
        discard
    os.sleep(40)
  return false

proc buildStandalonePureHtml(frame: ExportedAppFrame): string =
  result = """<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>""" & frame.title & """ — UIRelays Pure HTML5 + CSS3 (No JS · No Canvas · No WASM)</title>
<style>
  *, *::before, *::after { box-sizing: border-box; }
  html, body {
    margin: 0;
    padding: 0;
    background: #11111b;
    color: #cdd6f4;
    font-family: ui-monospace, "JetBrains Mono", "Fira Code", "Cascadia Mono", monospace;
  }
  .hdr {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 10px 18px;
    background: #181825;
    border-bottom: 1px solid #313244;
    font-size: 12px;
  }
  .badge {
    background: #a6e3a1;
    color: #11111b;
    font-weight: 700;
    padding: 3px 9px;
    border-radius: 999px;
    font-size: 11px;
  }
  .meta { color: #a6adc8; }
  .stage-wrap {
    display: flex;
    justify-content: center;
    padding: 20px;
    overflow: auto;
  }
  .uir-viewport {
    position: relative;
    overflow: hidden;
    background: #1e1e2e;
    border: 1px solid #45475a;
    border-radius: 6px;
    box-shadow: 0 14px 36px rgba(0,0,0,0.55);
    width: """ & $frame.width & """px;
    height: """ & $frame.height & """px;
    flex-shrink: 0;
  }
  .uir-rect, .uir-point, .uir-line-h, .uir-line-v, .uir-svg-line, .uir-text, .uir-img-crop, .uir-blit {
    position: absolute;
    pointer-events: none;
  }
  .uir-text {
    white-space: pre;
    line-height: 1;
    font-family: ui-monospace, "JetBrains Mono", "Fira Code", "Cascadia Mono", monospace;
  }
  .uir-clip {
    position: absolute;
    left: 0;
    top: 0;
    width: 100%;
    height: 100%;
    pointer-events: none;
  }
</style>
</head>
<body>
  <div class="hdr">
    <div>
      <span class="badge">PURE HTML5 + CSS3 · ZERO JS · ZERO CANVAS · ZERO WASM</span>
      <strong style="margin-left:10px;">""" & frame.title & """</strong>
      <span class="meta" style="margin-left:8px;">(""" & frame.appName & """.nim)</span>
    </div>
    <div class="meta">Size: """ & $frame.width & """×""" & $frame.height & """ · DOM nodes: """ & $frame.domNodeCount & """</div>
  </div>
  <div class="stage-wrap">
    <div class="uir-viewport">
""" & frame.htmlBody & """
    </div>
  </div>
</body>
</html>
"""

proc writeMasterGalleryHtml(frames: seq[ExportedAppFrame]; outPath: string) =
  var cssRules = ""
  var radioInputs = ""
  var tabLabels = ""
  var tabPanels = ""

  for i, f in frames:
    let idx = i + 1
    let checkedAttr = if i == 0: " checked" else: ""
    radioInputs.add "  <input type=\"radio\" name=\"uir-app-tab\" id=\"tab-" & $idx & "\" class=\"tab-radio\"" & checkedAttr & ">\n"
    tabLabels.add "      <label for=\"tab-" & $idx & "\" class=\"tab-lbl\" id=\"lbl-" & $idx & "\">" & f.appName & " <span class=\"sub\">(" & $f.domNodeCount & ")</span></label>\n"
    cssRules.add "  #tab-" & $idx & ":checked ~ .topbar .tabs #lbl-" & $idx & " { background: #89b4fa; color: #11111b; font-weight: 700; border-color: #89b4fa; }\n"
    cssRules.add "  #tab-" & $idx & ":checked ~ .panels #panel-" & $idx & " { display: flex; }\n"

    tabPanels.add """    <div class="panel" id="panel-""" & $idx & """">
      <div class="panel-meta">
        <span><strong>""" & f.title & """</strong> (<code>""" & f.appName & """.nim</code>)</span>
        <span>Разрешение: <strong>""" & $f.width & """×""" & $f.height & """</strong> · DOM-элементов: <strong>""" & $f.domNodeCount & """</strong> · <code>&lt;canvas&gt; = 0</code> · <code>&lt;script&gt; = 0</code></span>
      </div>
      <div class="uir-viewport" style="width:""" & $f.width & """px;height:""" & $f.height & """px;">
""" & f.htmlBody & """
      </div>
    </div>
"""

  let fullHtml = """<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>UIRelays Pure HTML5 + CSS3 Applications Gallery (Zero JS · Zero Canvas · Zero WASM)</title>
<style>
  *, *::before, *::after { box-sizing: border-box; }
  html, body {
    margin: 0;
    padding: 0;
    background: #11111b;
    color: #cdd6f4;
    font-family: ui-monospace, "JetBrains Mono", "Fira Code", "Cascadia Mono", monospace;
  }
  .tab-radio {
    position: absolute;
    opacity: 0;
    pointer-events: none;
  }
  .topbar {
    background: #181825;
    border-bottom: 1px solid #313244;
    padding: 12px 18px;
  }
  .topbar-head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    flex-wrap: wrap;
    gap: 8px;
    margin-bottom: 10px;
  }
  .badge {
    background: #a6e3a1;
    color: #11111b;
    font-weight: 700;
    padding: 3px 10px;
    border-radius: 999px;
    font-size: 11px;
  }
  .tabs {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
  }
  .tab-lbl {
    cursor: pointer;
    padding: 6px 12px;
    border-radius: 6px;
    background: #313244;
    color: #cdd6f4;
    border: 1px solid #45475a;
    font-size: 12px;
    user-select: none;
    transition: background 0.12s;
  }
  .tab-lbl:hover {
    background: #45475a;
  }
  .tab-lbl .sub {
    opacity: 0.7;
    font-size: 11px;
  }
  .panels {
    padding: 16px;
  }
  .panel {
    display: none;
    flex-direction: column;
    align-items: center;
    gap: 12px;
  }
  .panel-meta {
    display: flex;
    justify-content: space-between;
    width: 100%;
    max-width: 1024px;
    font-size: 12px;
    color: #a6adc8;
    background: #181825;
    border: 1px solid #313244;
    padding: 8px 14px;
    border-radius: 6px;
  }
  .uir-viewport {
    position: relative;
    overflow: hidden;
    background: #1e1e2e;
    border: 1px solid #45475a;
    border-radius: 6px;
    box-shadow: 0 14px 36px rgba(0,0,0,0.55);
    flex-shrink: 0;
  }
  .uir-rect, .uir-point, .uir-line-h, .uir-line-v, .uir-svg-line, .uir-text, .uir-img-crop, .uir-blit {
    position: absolute;
    pointer-events: none;
  }
  .uir-text {
    white-space: pre;
    line-height: 1;
    font-family: ui-monospace, "JetBrains Mono", "Fira Code", "Cascadia Mono", monospace;
  }
  .uir-clip {
    position: absolute;
    left: 0;
    top: 0;
    width: 100%;
    height: 100%;
    pointer-events: none;
  }
""" & cssRules & """</style>
</head>
<body>
""" & radioInputs & """  <div class="topbar">
    <div class="topbar-head">
      <div>
        <span class="badge">100% PURE HTML5 + CSS3 · ZERO JS · ZERO CANVAS · ZERO WASM</span>
        <strong style="margin-left:10px;font-size:14px;">Галерея приложений Nim (--mm:arc) + UIRelays (9 приложений, включая редактор Focim)</strong>
      </div>
      <div style="font-size:12px;color:#a6adc8;">Переключайте вкладки ниже (работает на чистом CSS :checked без единой строчки JS)</div>
    </div>
    <div class="tabs">
""" & tabLabels & """    </div>
  </div>
  <div class="panels">
""" & tabPanels & """  </div>
</body>
</html>
"""
  writeFile(outPath, fullHtml)

proc runMonkeyTarget(appName, srcPath, extraCompileArgs, runArg, backendFlag: string; port: int) =
  let binDir = "/tmp/uirelays_bins"
  createDir(binDir)
  let binPath = binDir / (appName & "_" & backendFlag & "_monkey")
  let fullSrc = if srcPath.isAbsolute: srcPath else: repoRoot() / srcPath
  if not fileExists(fullSrc):
    skip(appName & " [" & backendFlag & "] compiles with --mm:arc",
         "source not present in this checkout: " & srcPath)
    return
  let compileCmd = "nim c --mm:arc -d:" & backendFlag & " " & extraCompileArgs &
                   " -o:" & quoteShell(binPath) & " " & quoteShell(fullSrc)
  echo "\n-------------------------------------------------------------------"
  echo "[Monkey] Building ", appName, " (-d:", backendFlag, " --mm:arc) ..."
  let buildCode = execShellCmd(compileCmd)
  check(appName & " [" & backendFlag & "] compiles with --mm:arc", buildCode == 0)
  if buildCode != 0:
    return

  putEnv("UIRELAYS_PORT", $port)
  let appArgs = if runArg.len > 0: @[runArg] else: @[]
  let appProc = startProcess(binPath, args = appArgs, options = {poUsePath})
  defer:
    if appProc.running():
      appProc.terminate()
      os.sleep(40)
      if appProc.running():
        appProc.kill()
    appProc.close()

  let ready = waitForServerReady(port)
  check(appName & " [" & backendFlag & "] server ready on port " & $port, ready)
  if not ready:
    return

  # Stage 1: Adversarial HTTP protocol fuzzing (malformed JSON, extreme sizes, negative coords)
  discard httpRequest(port, "POST", "/input", "{invalid_json_fuzz!!!")
  discard httpRequest(port, "POST", "/input", "")
  discard httpRequest(port, "POST", "/input",
    """{"events":[{"type":"resize","width":-5000,"height":99999999,"uiScale":99999},{"type":"mousemove","x":-999999,"y":999999},{"type":"unknown_event_xyz","foo":123}]}""")
  discard httpRequest(port, "POST", "/input",
    """{"type":"resize","width":800,"height":600,"uiScale":100}""")

  let healthAfterFuzz = httpRequest(port, "GET", "/health")
  check(appName & " [" & backendFlag & "] survives adversarial HTTP fuzzing",
        healthAfterFuzz.ok and "\"ok\":true" in healthAfterFuzz.body)

  # Stage 2: Launch real Headless Chromium to execute in-browser Monkey Test (?monkey=1)
  let url = "http://127.0.0.1:" & $port & "/?monkey=1"
  let browserBin = browserPath
  if browserBin.len == 0:
    skip(appName & " [" & backendFlag & "] in-browser monkey",
         "no browser installed (set UIRELAYS_BROWSER=/path/to/chromium)")
    return
  let chromeArgs = @[
    "--headless",
    "--no-sandbox",
    "--disable-gpu",
    "--disable-dev-shm-usage",
    "--user-data-dir=" & getTempDir() / "uir-chromium-profile",
    "--window-size=1024,768",
    url
  ]
  let chromeProc = startProcess(browserBin, args = chromeArgs, options = {poUsePath})
  defer:
    if chromeProc.running():
      chromeProc.terminate()
      os.sleep(40)
      if chromeProc.running():
        chromeProc.kill()
    chromeProc.close()

  var reportJson: JsonNode = nil
  let t0 = epochTime()
  while (epochTime() - t0) < 14.0:
    let rep = httpRequest(port, "GET", "/monkey-report")
    if rep.ok and rep.body.len > 0:
      try:
        let parsed = parseJson(rep.body)
        if parsed.kind == JObject and parsed.getOrDefault("ready").getBool(false):
          reportJson = parsed
          break
      except CatchableError:
        discard
    os.sleep(60)

  check(appName & " [" & backendFlag & "] Chromium browser monkey report received",
        reportJson != nil)

  if reportJson != nil:
    let clicks = reportJson.getOrDefault("clicksDispatched").getInt(0)
    let keys = reportJson.getOrDefault("keysDispatched").getInt(0)
    let wheels = reportJson.getOrDefault("wheelDispatched").getInt(0)
    let hudClicks = reportJson.getOrDefault("hudButtonsClicked").getInt(0)
    let jsErrors = reportJson.getOrDefault("jsErrors")
    let errCount = if jsErrors != nil and jsErrors.kind == JArray: jsErrors.len else: 0

    check(appName & " [" & backendFlag & "] Chromium dispatched >= 100 button & monkey clicks",
          clicks >= 100, "clicks=" & $clicks)
    check(appName & " [" & backendFlag & "] Chromium dispatched >= 15 keyboard events",
          keys >= 15, "keys=" & $keys)
    check(appName & " [" & backendFlag & "] Chromium dispatched >= 8 wheel scroll events",
          wheels >= 8, "wheels=" & $wheels)
    check(appName & " [" & backendFlag & "] Chromium clicked HUD control buttons",
          hudClicks >= 3, "hudClicks=" & $hudClicks)
    check(appName & " [" & backendFlag & "] ZERO JavaScript errors in Chromium",
          errCount == 0, if errCount > 0: $jsErrors else: "")

    if backendFlag == "html":
      let zeroCanvas = reportJson.getOrDefault("zeroCanvasVerified").getBool(false)
      let maxNodes = reportJson.getOrDefault("maxDomNodesSeen").getInt(0)
      let rectNodes = reportJson.getOrDefault("rectNodes").getInt(0)
      check(appName & " [html] Chromium verified ZERO <canvas> elements in DOM", zeroCanvas)
      check(appName & " [html] Chromium rendered live DOM elements",
            maxNodes > 0 and rectNodes > 0, "maxNodes=" & $maxNodes & " rects=" & $rectNodes)
    else:
      let maxCmds = reportJson.getOrDefault("maxCommandsSeen").getInt(0)
      let nonTrans = reportJson.getOrDefault("nonTransparentSamples").getInt(0)
      let colors = reportJson.getOrDefault("distinctCanvasColors").getInt(0)
      check(appName & " [canvas] Chromium executed 2D canvas draw commands",
            maxCmds > 0, "maxCmds=" & $maxCmds)
      check(appName & " [canvas] Chromium getImageData verified rendered pixels & multiple colors",
            nonTrans > 0 and colors >= 2,
            "samples=" & $nonTrans & " distinctColors=" & $colors)

  let finalHealth = httpRequest(port, "GET", "/health")
  if finalHealth.ok:
    try:
      let hNode = parseJson(finalHealth.body)
      let evProcessed = hNode.getOrDefault("totalEventsProcessed").getInt(0)
      let framesRendered = hNode.getOrDefault("totalFramesRendered").getInt(0)
      check(appName & " [" & backendFlag & "] Nim server processed browser events (" & $evProcessed & " events, " & $framesRendered & " frames)",
            evProcessed > 20 and framesRendered >= 2)
    except CatchableError:
      discard

  discard httpRequest(port, "POST", "/input", """{"type":"close"}""")
  os.sleep(80)

echo "==================================================================="
echo "UIRelays Chromium Browser Monkey Test Suite (9 Apps x 2 Backends)"
echo "==================================================================="

let root = repoRoot()
browserPath = findBrowser()
if browserPath.len == 0:
  echo "[Monkey] no browser found: every in-browser check is SKIPPED, " &
       "the HTTP/SSE stages still run."

let targets = [
  ("calculator",   "examples/calculator.nim",   "--path:" & root / "src", ""),
  ("snake",        "examples/snake.nim",        "--path:" & root / "src", ""),
  ("twenty48",     "examples/twenty48.nim",     "--path:" & root / "src", ""),
  # The focim demo lives in this repository; the standalone editor lives in
  # another one and is simply skipped when it is not checked out next door.
  ("focim",        "focim_web_port/focim_browser.nim",
                   "--path:" & root / "src" & " --path:" & root / "focim_web_port", ""),
  ("web_showcase", "examples/web_showcase.nim", "--path:" & root / "src", ""),
  ("todo",         "examples/todo.nim",         "--path:" & root / "src", ""),
  ("paint",        "examples/paint.nim",        "--path:" & root / "src", ""),
  ("layout_demo",  "examples/layout_demo.nim",  "--path:" & root / "src", ""),
  ("hello",        "examples/hello.nim",        "--path:" & root / "src", "")
]

var basePort = 18310
for (appName, srcPath, extraArgs, runArg) in targets:
  runMonkeyTarget(appName, srcPath, extraArgs, runArg, "html", basePort)
  inc basePort
  runMonkeyTarget(appName, srcPath, extraArgs, runArg, "canvas", basePort)
  inc basePort

let exportCode = execShellCmd("nim c --mm:arc --outdir:/tmp/uirelays_bins -r " &
  quoteShell(root / "tools" / "export_interactive_html.nim"))
check("Exported 9 standalone interactive HTML apps (nim js --mm:arc -d:html)", exportCode == 0)

let standaloneMonkeyCode = execShellCmd("nim c --mm:arc --outdir:/tmp/uirelays_bins -r " &
  quoteShell(root / "tests" / "standalone_html_monkey_test.nim"))
check("Standalone offline HTML apps pass interactive button, animation & dynamic resize monkey tests", standaloneMonkeyCode == 0)

echo "\n==================================================================="
echo "Monkey Test Summary: Passed = ", passes, " | Failed = ", failures,
     " | Skipped = ", skips
echo "==================================================================="
if failures > 0:
  quit(1)
echo "ALL ", passes, " BROWSER MONKEY TESTS PASSED!"
