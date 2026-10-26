## Regression tests for the web backends: one check per defect that was fixed,
## written so that the defect cannot come back unnoticed.
##
## Compile & run:
##   nim c --mm:arc -d:html   --outdir:/tmp/uirelays_bins -r tests/web_backend_regression_test.nim
##   nim c --mm:arc -d:canvas --outdir:/tmp/uirelays_bins -r tests/web_backend_regression_test.nim

import std/[strutils, os, osproc]
import uirelays
import uirelays/drivers/[web_common, html_driver]

export html_driver.HtmlPrim, html_driver.HtmlPrimKind

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
# D3 -- the frame is a list of primitives, and the model is faithful
# ---------------------------------------------------------------------------

when defined(html):
  fillRect(rect(0, 0, 4, 4), color(1, 2, 3))
  drawLine(0, 0, 40, 40, color(4, 5, 6))      # diagonal -> svg
  drawLine(0, 8, 40, 8, color(7, 8, 9))       # horizontal -> div
  drawPoint(2, 2, color(10, 11, 12))
  discard drawText(fMono, 0, 20, "prim model", color(255, 255, 255), color(0, 0, 0, 0))
  let model = htmlPrimsSnapshot()
  check("D3 the frame is a list of primitives, not a string", model.len == 5,
        $model.len)
  check("D3 each primitive keeps its kind",
        model.len == 5 and
        model[0].kind == hpRect and model[1].kind == hpSvgLine and
        model[2].kind == hpLineH and model[3].kind == hpPoint and
        model[4].kind == hpText,
        (if model.len == 5: $model[0].kind & "," & $model[1].kind & "," &
           $model[2].kind & "," & $model[3].kind & "," & $model[4].kind
         else: "len=" & $model.len))
  check("D3 a diagonal line carries its own viewBox",
        model[1].extra == "0 0 42 42", model[1].extra)
  check("D3 a text primitive carries its text verbatim",
        model[4].text == "prim model", model[4].text)
  let modelHtml = htmlRenderPrims(model)
  check("D3 serialising the primitives produces real elements",
        modelHtml.countOccurrences("class=\"uir-rect\"") == 1 and
        modelHtml.countOccurrences("class=\"uir-svg-line\"") == 1 and
        modelHtml.countOccurrences("class=\"uir-line-h\"") == 1 and
        modelHtml.countOccurrences("class=\"uir-point\"") == 1 and
        modelHtml.countOccurrences("class=\"uir-text\"") == 1, modelHtml)
  refresh()
  check("D3 what the driver publishes is exactly what the model serialises",
        lastPublishedHtml == modelHtml,
        "published " & $lastPublishedHtml.len & " vs model " & $modelHtml.len)

  # A clip is a container, so it is emitted as a balanced pair: an unpaired
  # marker would corrupt the DOM nesting on the next frame.
  # `saveState`/`restoreState` is how a clip is closed -- see the check on
  # the zero-area rect below for why `setClipRect` is not.
  saveState()
  setClipRect(rect(10, 10, 20, 20))
  fillRect(rect(11, 11, 4, 4), color(20, 21, 22))
  restoreState()
  fillRect(rect(40, 40, 4, 4), color(30, 31, 32))
  let clipped = htmlPrimsSnapshot()
  check("D3 a clip opens and closes around its contents",
        clipped.len == 4 and clipped[0].kind == hpClipOpen and
        clipped[1].kind == hpRect and clipped[2].kind == hpClipClose and
        clipped[3].kind == hpRect,
        (if clipped.len == 4: $clipped[0].kind & "," & $clipped[1].kind & "," &
           $clipped[2].kind & "," & $clipped[3].kind else: "len=" & $clipped.len))
  check("D3 the clip marker carries the rect it was opened with",
        clipped[0].extra == "10,10,20,20", clipped[0].extra)
  refresh()
  let clippedHtml = lastPublishedHtml
  check("D3 a clipped frame nests and stays balanced",
        clippedHtml.countOccurrences("<div class=\"uir-clip\"") == 1 and
        clippedHtml.countOccurrences("<div") ==
          clippedHtml.countOccurrences("</div>"),
        "open " & $clippedHtml.countOccurrences("<div") & " close " &
          $clippedHtml.countOccurrences("</div>") & ": " & clippedHtml)
  check("D3 only what was drawn inside the clip is inside the clip",
        clippedHtml.contains("pointer-events:none;\"><div class=\"uir-rect\"") and
        clippedHtml.contains("</div><div class=\"uir-rect\" style=\"left:40px"),
        clippedHtml)

  # A zero-area clip rect is *not* a reset: it clips everything away. That is
  # what X11, WinAPI and SDL do too, so a web backend that "helpfully"
  # treated it as "no clip" would render differently from the same app run
  # natively. Pinned here so nobody fixes it in one backend only.
  saveState()
  setClipRect(rect(0, 0, 0, 0))
  fillRect(rect(0, 0, 10, 10), color(40, 41, 42))
  restoreState()
  let zeroClip = htmlPrimsSnapshot()
  check("D3 a zero-area clip stays a clip, like every other backend",
        zeroClip.len == 2 and zeroClip[0].kind == hpClipOpen and
        zeroClip[0].extra == "0,0,0,0",
        (if zeroClip.len == 2: $zeroClip[0].kind & " " & zeroClip[0].extra
         else: "len=" & $zeroClip.len))
  refresh()
  check("D3 a zero-area clip collapses to an empty polygon and still closes",
        lastPublishedHtml.contains(
          "clip-path:polygon(0px 0px,0px 0px,0px 0px,0px 0px)") and
        lastPublishedHtml.countOccurrences("<div") ==
          lastPublishedHtml.countOccurrences("</div>"),
        lastPublishedHtml)

  # The hash now runs over the primitives. Frame deduplication is the one
  # externally visible consequence, so it is the thing to assert on: an
  # identical frame must still be dropped, a changed one must still go out.
  proc frameIdNow(): int =
    webCore.frameId
  proc drawStaticFrame() =
    fillRect(rect(0, 0, 60, 40), color(70, 80, 90))
    fillRect(rect(4, 4, 8, 8), color(91, 92, 93))
    discard drawText(fMono, 6, 20, "dedup", color(255, 255, 255), color(0, 0, 0, 0))
  drawStaticFrame()
  refresh()
  let idAfterFirst = frameIdNow()
  drawStaticFrame()
  refresh()
  check("D3 an identical frame is still deduplicated", frameIdNow() == idAfterFirst,
        $frameIdNow() & " vs " & $idAfterFirst)
  drawStaticFrame()
  fillRect(rect(20, 20, 3, 3), color(101, 102, 103))
  refresh()
  check("D3 a changed frame still goes out", frameIdNow() == idAfterFirst + 1,
        $frameIdNow() & " vs " & $(idAfterFirst + 1))
  drawStaticFrame()
  refresh()
  check("D3 removing the change changes the frame back",
        frameIdNow() == idAfterFirst + 2, $frameIdNow())

  # The published node count is what the browser is told to expect in the
  # viewport, and a jsdom monkey compares it with the live element count every
  # sample -- so it has to be exact, including the clip containers.
  proc elementCount(prims: seq[HtmlPrim]): int =
    ## One element per primitive, except `hpClipClose`, which only closes the
    ## container its `hpClipOpen` already counted.
    for p in prims:
      if p.kind != hpClipClose: inc result

  drawStaticFrame()
  let counted = htmlPrimsSnapshot()
  refresh()
  check("D3 the published DOM node count matches the primitive count",
        webCore.domNodeCount == elementCount(counted),
        $webCore.domNodeCount & " vs " & $elementCount(counted))

  saveState()
  setClipRect(rect(5, 5, 30, 30))
  fillRect(rect(6, 6, 4, 4), color(11, 12, 13))
  fillRect(rect(12, 12, 4, 4), color(14, 15, 16))
  restoreState()
  let withClip = htmlPrimsSnapshot()
  refresh()
  check("D3 a clip container counts as the element it becomes",
        webCore.domNodeCount == elementCount(withClip),
        "domNodeCount=" & $webCore.domNodeCount & " prims=" & $withClip.len &
        " expected=" & $elementCount(withClip))
  # The same number the browser is handed, counted the way the browser would
  # count it: one per opening tag, ignoring the `<img>`/`<line>` that live
  # *inside* a primitive. This is exactly what the jsdom monkey compares
  # against `viewport.querySelectorAll("*").length` on every sample.
  let openedTags = lastPublishedHtml.countOccurrences("<div") +
                   lastPublishedHtml.countOccurrences("<span") +
                   lastPublishedHtml.countOccurrences("<svg")
  check("D3 the published count equals the number of elements in the markup",
        webCore.domNodeCount == openedTags,
        "domNodeCount=" & $webCore.domNodeCount & " tags=" & $openedTags)
  check("D3 a clipped frame really does contain a clip container",
        lastPublishedHtml.countOccurrences("class=\"uir-clip\"") == 1,
        lastPublishedHtml)

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
# N6 -- an application can declare the smallest window it can be drawn in.
#
# Without this the app could only clamp its own layout variable, which leaves
# the viewport smaller than the interface: `overflow:hidden` does not make the
# clipped part reachable, it hides it. Every shipped example hit exactly that.
# ---------------------------------------------------------------------------

setMinViewport(700, 500)
check("N6 the declared floor is recorded",
      webCore.minViewportW == 700 and webCore.minViewportH == 500,
      $webCore.minViewportW & "x" & $webCore.minViewportH)

proc drainResizes(): tuple[n: int; w, h: int] =
  ## Drains the queue and reports the last resize the app would have seen.
  var ev = Event()
  while pollEvent(ev):
    if ev.kind == WindowResizeEvent:
      result.n += 1
      result.w = ev.x
      result.h = ev.y

webCore.eventQueue.setLen(0)
webInjectResize(100, 100)
check("N6 a window below the floor is raised to it",
      webCore.layout.width == 700 and webCore.layout.height == 500,
      $webCore.layout.width & "x" & $webCore.layout.height)
let r1 = drainResizes()
check("N6 the app is told the floored size, not the raw one",
      r1.n == 1 and r1.w == 700 and r1.h == 500, $r1)

webInjectResize(900, 700)
check("N6 a window above the floor is left alone",
      webCore.layout.width == 900 and webCore.layout.height == 700,
      $webCore.layout.width & "x" & $webCore.layout.height)
let r2 = drainResizes()
check("N6 a comfortable size is passed through unchanged",
      r2.n == 1 and r2.w == 900 and r2.h == 700, $r2)

webInjectResize(99999, 99999)
check("N6 the floor does not lift the built-in maximum",
      webCore.layout.width == 4096 and webCore.layout.height == 4096,
      $webCore.layout.width & "x" & $webCore.layout.height)
let r3 = drainResizes()
check("N6 an absurd size is still clamped to the maximum",
      r3.n == 1 and r3.w == 4096 and r3.h == 4096, $r3)

setMinViewport(0, 0)
webInjectResize(10, 10)
check("N6 clearing the floor restores the built-in minimum",
      webCore.layout.width == 120 and webCore.layout.height == 120,
      $webCore.layout.width & "x" & $webCore.layout.height)
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


# ---------------------------------------------------------------------------
# N10 -- text carrying `&`, `<` or `>` must not be double-encoded
# ---------------------------------------------------------------------------

when defined(html):
  refresh()
  const RawText = "A & B < C > D"
  discard drawText(fMono, 0, 0, RawText, color(255, 255, 255), color(0, 0, 0, 0))
  # No refresh() here: publishing a frame clears the primitive list, so the
  # snapshot has to be taken while the frame is still being built.
  let encodedModel = htmlPrimsSnapshot()
  var primText = ""
  for p in encodedModel:
    if p.kind == hpText: primText = p.text
  # The DOM path assigns a primitive's text with `textContent`, which decodes
  # nothing, so whatever is stored here is literally what the user reads. Real
  # headless Chrome is what exposed this: web_showcase's sidebar tab said
  # "Graphics, Clip &amp; Blit" on screen because the primitive carried the
  # markup-escaped form.
  check("N10 the primitive carries the raw text the DOM path assigns verbatim",
        primText == RawText, primText)
  # The serializer is the other consumer and it writes into markup, so escaping
  # is its job and only its job -- a raw `<` there would open a tag.
  let encodedHtml = htmlRenderPrims(encodedModel)
  check("N10 the serialized markup escapes it exactly once",
        "A &amp; B &lt; C &gt; D" in encodedHtml and "&amp;amp;" notin encodedHtml,
        encodedHtml[0 ..< min(400, encodedHtml.len)])


# ---------------------------------------------------------------------------
# N9 -- both web backends must still compile for Windows
# ---------------------------------------------------------------------------

proc checkTargetSemantics(osName, backendFlag: string): (bool, string) =
  ## `nim check` runs the full semantic analysis without invoking a C compiler,
  ## so it can verify a target this machine cannot build for. The server used to
  ## import std/posix unconditionally; on Windows that collides with the
  ## std/winlean that nativesockets already pulls in, both define SocketHandle,
  ## and every socket symbol turns ambiguous -- neither web backend compiled at
  ## all. A windows-latest runner caught it. This catches it anywhere, in about
  ## a second, and without one.
  let root = repoRoot()
  let nimBin = block:
    let e = getEnv("NIM", "")
    if e.len > 0: e else: "nim"
  let cmd = nimBin & " check --os:" & osName & " --mm:arc " & backendFlag &
            " --path:" & quoteShell(root / "src") & " " &
            quoteShell(root / "examples" / "todo.nim")
  let (outp, code) = execCmdEx(cmd)
  if code != 0:
    # The last line of `nim check` output is its progress dots; the first line
    # carrying "Error:" is the thing a reader actually needs.
    for ln in outp.splitLines():
      if "Error:" in ln:
        return (false, ln.strip())
    let ls = outp.strip().splitLines()
    return (false, if ls.len > 0: ls[^1].strip() else: "exit code " & $code)
  (true, "")

for (targetOs, flag) in [("windows", "-d:html"), ("windows", "-d:canvas")]:
  let (ok, why) = checkTargetSemantics(targetOs, flag)
  check("N9 the " & flag & " backend passes semantic analysis for --os:" &
        targetOs, ok, why)

echo "-------------------------------------------------------------------"
echo "Passed: ", passes, " | Failed: ", failures
if failures == 0:
  echo "ALL PASS (Web backend regressions)"
else:
  echo "FAILURES: ", failures
  quit 1
