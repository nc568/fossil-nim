## Regression tests for the web backends: one check per defect that was fixed,
## written so that the defect cannot come back unnoticed.
##
## Compile & run:
##   nim c --mm:arc -d:html   --outdir:/tmp/uirelays_bins -r tests/web_backend_regression_test.nim
##   nim c --mm:arc -d:canvas --outdir:/tmp/uirelays_bins -r tests/web_backend_regression_test.nim

import std/[strutils, os, osproc]
import uirelays
import uirelays/drivers/[web_common, html_driver]

var passes = 0
var failures = 0

proc check(name: string; cond: bool; detail = "") =
  if cond:
    inc passes
    echo "  PASS  ", name
  else:
    inc failures
    echo "  FAIL  ", name, (if detail.len > 0: "  -- " & detail else: "")

proc countOccurrences(s, needle: string): int =
  var i = 0
  while true:
    let idx = s.find(needle, i)
    if idx < 0: break
    inc result
    i = idx + needle.len

proc repoRoot(): string =
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

echo "=== UIRelays Web Backend Regression Tests (", $webCore.backendKind, ") ==="

let win = createWindow(800, 600)

# ---------------------------------------------------------------------------
# D2 -- proportional fonts are measured, monospace keeps its exact cell
# ---------------------------------------------------------------------------

var fmProp, fmMono: FontMetrics
let fMono = openFont("", 16, fmMono)
let fProp = openFont("DejaVu Sans", 16, fmProp)
let fSerif = openFont("serif", 16, fmProp)

check("D2 empty font path stays monospace", webGetFontSlot(fMono).isMonospace)
check("D2 'monospace' path stays monospace", webGetFontSlot(openFont("monospace", 14, fmMono)).isMonospace)
check("D2 sans-serif is recognised as proportional", not webGetFontSlot(fProp).isMonospace)
check("D2 serif is recognised as proportional", not webGetFontSlot(fSerif).isMonospace)

let wMono = measureText(fMono, "Hello, World!")
let wProp = measureText(fProp, "Hello, World!")
check("D2 monospace width is columns x charWidth",
      wMono.w == 13 * webGetFontSlot(fMono).charWidth, $wMono.w)
check("D2 proportional width is measured, not counted",
      wProp.w > 0 and wProp.w != wMono.w,
      "mono=" & $wMono.w & " prop=" & $wProp.w)
check("D2 a wide letter is wider than a narrow one",
      measureText(fProp, "MMM").w > measureText(fProp, "iii").w,
      "MMM=" & $measureText(fProp, "MMM").w & " iii=" & $measureText(fProp, "iii").w)
check("D2 measuring the same string twice is stable",
      measureText(fProp, "Repeat me").w == measureText(fProp, "Repeat me").w)
check("D2 proportional text is never reported as zero width",
      measureText(fProp, "x").w > 0)

when defined(html):
  discard drawText(fMono, 0, 0, "mono text", color(255, 255, 255), color(0, 0, 0, 0))
  discard drawText(fProp, 0, 30, "proportional text", color(255, 255, 255), color(0, 0, 0, 0))
  refresh()
  let frame1 = lastPublishedHtml
  check("D2 monospace spans keep the 1ch cell correction",
        frame1.contains("letter-spacing:calc("), frame1[0 ..< min(400, frame1.len)])
  check("D2 proportional spans drop the 1ch correction",
        frame1.contains("letter-spacing:normal"),
        "no 'letter-spacing:normal' in the frame")

# ---------------------------------------------------------------------------
# D10 -- a full-window opaque fill is only a background when it comes first
# ---------------------------------------------------------------------------

when defined(html):
  refresh()  # clears the frame buffer for the next case
  fillRect(rect(10, 10, 40, 40), color(255, 0, 0))
  fillRect(rect(0, 0, win.width, win.height), color(0, 0, 255)) # overlay, mid-frame
  refresh()
  let overlayFrame = lastPublishedHtml
  check("D10 a full-window opaque overlay keeps what was drawn before it",
        overlayFrame.countOccurrences("class=\"uir-rect\"") == 2,
        "rects=" & $overlayFrame.countOccurrences("class=\"uir-rect\""))

  fillRect(rect(0, 0, win.width, win.height), color(0, 0, 255)) # background, first
  fillRect(rect(10, 10, 40, 40), color(255, 0, 0))
  refresh()
  let bgFrame = lastPublishedHtml
  check("D10 a background fill still draws on top of nothing",
        bgFrame.countOccurrences("class=\"uir-rect\"") == 2,
        "rects=" & $bgFrame.countOccurrences("class=\"uir-rect\""))

# ---------------------------------------------------------------------------
# Event queue: a full queue must not swallow the event that releases a button
# ---------------------------------------------------------------------------

webCore.eventQueue.setLen(0)
webCore.droppedEvents = 0
for i in 0 ..< webEventQueueLimit:
  webInjectEvent(Event(kind: KeyDownEvent, key: KeyA))
webInjectEvent(Event(kind: MouseUpEvent, x: 7, y: 9))
check("queue is capped at its limit", webCore.eventQueue.len == webEventQueueLimit,
      $webCore.eventQueue.len)
check("a full queue reports what it dropped", webCore.droppedEvents == 1,
      $webCore.droppedEvents)

webCore.eventQueue.setLen(0)
webCore.droppedEvents = 0
for i in 0 ..< webEventQueueLimit:
  webInjectEvent(Event(kind: MouseMoveEvent, x: i mod 100, y: i mod 50))
check("consecutive mouse moves coalesce into one", webCore.eventQueue.len == 1,
      $webCore.eventQueue.len)
webInjectEvent(Event(kind: MouseUpEvent, x: 3, y: 4))
check("a mouseup is never displaced by a mouse move",
      webCore.eventQueue.len == 2 and
      webCore.eventQueue[^1].kind == MouseUpEvent, $webCore.eventQueue.len)

webCore.eventQueue.setLen(0)
for i in 0 ..< webEventQueueLimit:
  webInjectEvent(Event(kind: MouseMoveEvent, x: i mod 100, y: i mod 50))
  if webCore.eventQueue.len > 1:
    webCore.eventQueue[^1].kind = MouseMoveEvent
# Fill the queue with moves that do not coalesce, then release the button.
webCore.eventQueue.setLen(0)
for i in 0 ..< webEventQueueLimit:
  webInjectEvent(Event(kind: MouseMoveEvent, x: i mod 100, y: i mod 50))
  if webCore.eventQueue.len >= 2:
    webCore.eventQueue[^2].kind = KeyDownEvent
    webCore.eventQueue[^2].key = KeyB
webInjectEvent(Event(kind: MouseUpEvent, x: 5, y: 6))
check("a mouseup still arrives when the queue is full of moves",
      webCore.eventQueue[^1].kind == MouseUpEvent, $webCore.eventQueue[^1].kind)

# ---------------------------------------------------------------------------
# Malformed input is rejected, counted, and does not kill the queue
# ---------------------------------------------------------------------------

when not defined(js):
  webCore.eventQueue.setLen(0)
  webCore.inputParseErrors = 0
  let added = parseIncomingInputJson("{ this is not json")
  check("malformed input adds nothing", added == 0, $added)
  check("malformed input is counted", webCore.inputParseErrors == 1,
        $webCore.inputParseErrors)
  let added2 = parseIncomingInputJson("""{"events":[{"type":"mouseup","x":1,"y":2}]}""")
  check("well-formed input still works afterwards", added2 == 1, $added2)

# ---------------------------------------------------------------------------
# Resize clamping
# ---------------------------------------------------------------------------

webCore.eventQueue.setLen(0)
webInjectResize(10, 10)
check("resize is clamped to a usable minimum",
      webCore.layout.width >= 120 and webCore.layout.height >= 120,
      $webCore.layout.width & "x" & $webCore.layout.height)
webInjectResize(99999, 99999)
check("resize is clamped to a usable maximum",
      webCore.layout.width <= 4096 and webCore.layout.height <= 4096,
      $webCore.layout.width & "x" & $webCore.layout.height)
var drained = Event()
while pollEvent(drained):
  discard

# ---------------------------------------------------------------------------
# D4 -- {.uirApp.} picks the loop that drives the relays, or says so
# ---------------------------------------------------------------------------

proc compileJsExpect(src: string; expectSuccess: bool; needle: string): bool =
  let root = repoRoot()
  let nimBin = block:
    let e = getEnv("NIM", "")
    if e.len > 0: e else: "nim"
  let dir = getTempDir() / "uir_uirapp_test"
  createDir(dir)
  let srcPath = dir / "uirapp_case.nim"
  writeFile(srcPath, src)
  let outJs = dir / "uirapp_case.js"
  let cmd = nimBin & " js --mm:arc -d:html --jsbigint64:off -d:nimStringHash2 " &
            "--path:" & quoteShell(root / "src") & " -o:" & quoteShell(outJs) & " " &
            quoteShell(srcPath)
  let (outp, code) = execCmdEx(cmd)
  if expectSuccess:
    result = code == 0
    if not result:
      echo "      compile failed: ", outp.strip().splitLines()[^1 .. ^1][0]
  else:
    result = code != 0 and needle in outp
    if code == 0:
      echo "      expected a compile error, but it compiled"

const InitLoopBeforeMainLoop = """
import uirelays

proc main() {.uirApp.} =
  let win = createWindow(320, 240)
  var n = 0
  while n < 3:            # an initialisation loop, not the frame loop
    inc n
  var running = true
  while running:
    var e = Event()
    while pollEvent(e):
      if e.kind == KeyDownEvent and e.key == KeyEsc:
        running = false
    fillRect(rect(0, 0, 10, 10), color(255, 0, 0))
    refresh()
    sleep(16)

main()
"""

const NoLoopAtAll = """
import uirelays

proc main() {.uirApp.} =
  let win = createWindow(320, 240)
  refresh()

main()
"""

check("D4 {.uirApp.} still compiles a normal main loop",
      compileJsExpect(InitLoopBeforeMainLoop, true, ""))
check("D4 {.uirApp.} fails loudly when there is no loop at all",
      compileJsExpect(NoLoopAtAll, false, "uirApp"))

echo "-------------------------------------------------------------------"
echo "Passed: ", passes, " | Failed: ", failures
if failures == 0:
  echo "ALL PASS (Web backend regressions)"
else:
  echo "FAILURES: ", failures
  quit 1
