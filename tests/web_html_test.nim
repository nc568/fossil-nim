## Comprehensive unit & HTTP integration tests for the Pure Vanilla HTML/CSS/JS
## DOM Backend (`-d:html`, `src/uirelays/drivers/html_driver.nim`).
##
## Compile & run:
##   nim c --mm:arc -d:html --outdir:/tmp/uirelays_bins -r tests/web_html_test.nim

import std/[strutils, os, net]
import uirelays
import uirelays/drivers/[web_common, html_driver]

var failures = 0
var passes = 0

proc check(name: string; cond: bool; detail = "") =
  if cond:
    inc passes
    echo "  PASS  ", name
  else:
    inc failures
    echo "  FAIL  ", name, (if detail.len > 0: "  -- " & detail else: "")

echo "=== UIRelays Pure HTML/CSS/JS DOM Backend Tests (--mm:arc) ==="

# 1. Initialization & Backend Identity
let win = createWindow(820, 620)
check("backend is wbkHtml", webCore.backendKind == wbkHtml)
check("window width initialized", win.width == 820, $win.width)
check("window height initialized", win.height == 620, $win.height)
check("uiScale initialized to 100", win.uiScale == 100, $win.uiScale)
check("getWindowLayout matches", getWindowLayout().width == 820 and getWindowLayout().height == 620)

# 2. Strictly NO <canvas> and NO WASM in HTML page template
let pageLower = webCore.pageHtml.toLowerAscii()
check("HTML page has #uir-viewport", "<div id=\"uir-viewport\"" in pageLower)
check("HTML page has ZERO <canvas> elements", "<canvas" notin pageLower and "getcontext(\"2d\")" notin pageLower)
check("HTML page has ZERO WebAssembly", "webassembly" notin pageLower and ".wasm" notin pageLower)

# 3. Window Title & Cursor Relays
setWindowTitle("DOM Test Window <&>")
check("window title stored", webCore.windowTitle == "DOM Test Window <&>")
for ck in CursorKind:
  setCursor(ck)
  check("cursor CSS mapping for " & $ck, cursorToCss(ck).len > 0)

# 4. Font Relays (openFont, getFontMetrics, measureText, drawText, drawMeasuredText, closeFont)
var fmReg, fmBold, fmItal: FontMetrics
let fReg = openFont("", 16, fmReg)
let fBold = openFont("", 18, fmBold, {FontStyle.bold})
let fItal = openFont("monospace", 14, fmItal, {FontStyle.italics})

check("openFont returns non-zero handle", int(fReg) > 0 and int(fBold) > 0 and int(fItal) > 0)
check("font metrics populated", fmReg.ascent > 0 and fmReg.descent > 0 and fmReg.lineHeight > fmReg.ascent)
check("getFontMetrics matches", getFontMetrics(fReg).lineHeight == fmReg.lineHeight)

let extAscii = measureText(fReg, "Hello")
let extWide = measureText(fReg, "Привет")
let extEmpty = measureText(fReg, "")
check("measureText empty is 0x0", extEmpty.w == 0 and extEmpty.h == 0)
check("measureText ASCII width > 0", extAscii.w == 5 * webGetFontSlot(fReg).charWidth)
check("measureText UTF-8 Cyrillic counts 6 runes, not 12 bytes",
      extWide.w == 6 * webGetFontSlot(fReg).charWidth, $extWide.w)

# 5. Draw Relays -> Pure DOM Output Verification
fillRect(rect(10, 20, 200, 100), color(30, 40, 50, 255))
fillRect(rect(0, 0, 0, 50), color(255, 0, 0)) # zero width ignored
fillRect(rect(10, 10, 50, 50), color(255, 0, 0, 0)) # transparent ignored
drawPoint(15, 25, color(255, 128, 0))
drawLine(10, 50, 110, 50, color(0, 255, 0)) # horizontal line -> div.uir-line-h
drawLine(50, 10, 50, 110, color(0, 0, 255)) # vertical line -> div.uir-line-v
drawLine(10, 10, 90, 70, color(255, 255, 0)) # diagonal line -> svg.uir-svg-line

discard drawText(fReg, 24, 32, "Hello <DOM> & CSS", color(240, 240, 255), color(30, 40, 50))
let mExt = measureText(fBold, "Measured Bold")
discard drawText(fBold, 24, 60, "Measured Bold", color(255, 200, 100), color(0, 0, 0, 0), known = mExt)
discard drawText(fItal, 24, 88, "Italic Text", color(180, 255, 180), color(20, 20, 30, 128))

# 6. Clipping & State Stack (saveState, setClipRect, restoreState)
saveState()
setClipRect(rect(50, 50, 120, 80))
fillRect(rect(40, 40, 200, 200), color(100, 150, 250))
saveState()
setClipRect(rect(60, 60, 50, 40))
fillRect(rect(0, 0, 100, 100), color(250, 100, 150))
restoreState()
fillRect(rect(55, 55, 20, 20), color(100, 250, 150))
restoreState()

# 7. Image Loading, Sizing, Cropping & RGBA Blitting (without Canvas!)
let tmpPng = getTempDir() / "uirelays_html_test_img.png"
var testPixels = newSeq[uint32](16 * 12)
for i in 0 ..< testPixels.len:
  testPixels[i] = 0xFF336699'u32
let pngBytes = encodeRgbaToPngBytes(cast[ptr UncheckedArray[uint32]](addr testPixels[0]), 16, 12)
check("pure-Nim PNG encoder produces valid PNG header",
      pngBytes.len > 32 and pngBytes[0] == 137'u8 and pngBytes[1] == 80'u8)
var pngStr = newString(pngBytes.len)
for i in 0 ..< pngBytes.len: pngStr[i] = char(pngBytes[i])
writeFile(tmpPng, pngStr)

let img = loadImage(tmpPng)
check("loadImage succeeds on PNG", int(img) > 0)
let (iw, ih) = imageSize(img)
check("imageSize parses PNG IHDR 16x12", iw == 16 and ih == 12, $iw & "x" & $ih)
drawImage(img, rect(0, 0, 16, 12), rect(300, 40, 32, 24))
drawImage(img, rect(4, 2, 8, 6), rect(340, 40, 16, 12))

let blitOk = blitRGBA(cast[ptr UncheckedArray[uint32]](addr testPixels[0]), 16, 12, rect(400, 40, 16, 12))
let blitClipOk = blitRGBA(cast[ptr UncheckedArray[uint32]](addr testPixels[0]), 16, 12, rect(420, 40, 8, 6))
let blitBad = blitRGBA(nil, 16, 12, rect(0, 0, 10, 10))
check("blitRGBA succeeds and returns true", blitOk and blitClipOk)
check("blitRGBA rejects nil pixels", not blitBad)

# Publish frame via refresh()
refresh()

check("lastPublishedHtml is non-empty", lastPublishedHtml.len > 0)
check("DOM contains uir-rect", "class=\"uir-rect\"" in lastPublishedHtml)
check("DOM contains uir-point", "class=\"uir-point\"" in lastPublishedHtml)
check("DOM contains uir-line-h", "class=\"uir-line-h\"" in lastPublishedHtml)
check("DOM contains uir-line-v", "class=\"uir-line-v\"" in lastPublishedHtml)
check("DOM contains uir-svg-line for diagonal", "class=\"uir-svg-line\"" in lastPublishedHtml)
check("DOM escapes HTML entities in drawText", "Hello &lt;DOM&gt; &amp; CSS" in lastPublishedHtml)
check("DOM contains bold & italic styles", "font-weight:700;" in lastPublishedHtml and "font-style:italic;" in lastPublishedHtml)
check("DOM contains uir-clip polygon", "class=\"uir-clip\"" in lastPublishedHtml and "clip-path:polygon(" in lastPublishedHtml)
check("DOM contains uir-img-crop", "class=\"uir-img-crop\"" in lastPublishedHtml)
check("DOM contains uir-blit with PNG data URI", "class=\"uir-blit\" src=\"data:image/png;base64," in lastPublishedHtml)
check("DOM frame has ZERO <canvas>", "<canvas" notin lastPublishedHtml.toLowerAscii())

# 8. Clipboard & Input Queue Tests
putClipboardText("Copied Nim ARC Text")
check("clipboard roundtrip", getClipboardText() == "Copied Nim ARC Text")

webInjectMouse(MouseDownEvent, 120, 240, LeftButton, 2)
webInjectKey(KeyA, {ShiftPressed}, "A")
webInjectKey(KeyC, {CtrlPressed}, "c") # command chord -> should NOT emit TextInputEvent!
webInjectResize(1024, 768, 125)

var ev: Event
check("poll MouseDownEvent", pollEvent(ev, {WantTextInput}) and ev.kind == MouseDownEvent and ev.x == 120 and ev.y == 240 and ev.clicks == 2)
check("poll KeyDownEvent KeyA", pollEvent(ev, {WantTextInput}) and ev.kind == KeyDownEvent and ev.key == KeyA and ShiftPressed in ev.mods)
check("poll TextInputEvent 'A'", pollEvent(ev, {WantTextInput}) and ev.kind == TextInputEvent and ev.text[0] == 'A')
check("poll KeyUpEvent KeyA", pollEvent(ev, {WantTextInput}) and ev.kind == KeyUpEvent and ev.key == KeyA)
check("poll KeyDownEvent Ctrl+C", pollEvent(ev, {WantTextInput}) and ev.kind == KeyDownEvent and ev.key == KeyC and CtrlPressed in ev.mods)
check("Ctrl+C did NOT emit TextInputEvent, next is KeyUpEvent", pollEvent(ev, {WantTextInput}) and ev.kind == KeyUpEvent and ev.key == KeyC)
check("poll WindowResizeEvent", pollEvent(ev, {WantTextInput}) and ev.kind == WindowResizeEvent and ev.x == 1024 and ev.y == 768 and ev.uiScale == 125)

# Test WantTextInput filtering: when WantTextInput is omitted, TextInputEvent is skipped
webInjectText("Z")
webInjectKey(KeyEnter)
check("without WantTextInput, TextInputEvent is skipped and KeyEnter arrives",
      pollEvent(ev, {}) and ev.kind == KeyDownEvent and ev.key == KeyEnter)
discard pollEvent(ev, {})

# 9. Live Embedded HTTP Server Integration Test
let port = webServerPort()
check("embedded HTTP server listening on port > 0", port > 0, "port=" & $port)

proc httpGet(p: int; path: string): string =
  let client = newSocket()
  defer: client.close()
  client.connect("127.0.0.1", Port(p))
  let req = "GET " & path & " HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n"
  client.send(req)
  webPumpServer()
  input.sleep(10)
  webPumpServer()
  result = ""
  while true:
    var chunk = newString(4096)
    let n = client.recv(addr chunk[0], 4096, 50)
    if n <= 0: break
    chunk.setLen(n)
    result.add chunk

proc httpPost(p: int; path, body: string): string =
  let client = newSocket()
  defer: client.close()
  client.connect("127.0.0.1", Port(p))
  let req = "POST " & path & " HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nContent-Length: " &
            $body.len & "\r\nConnection: close\r\n\r\n" & body
  client.send(req)
  webPumpServer()
  input.sleep(10)
  webPumpServer()
  result = ""
  while true:
    var chunk = newString(4096)
    let n = client.recv(addr chunk[0], 4096, 50)
    if n <= 0: break
    chunk.setLen(n)
    result.add chunk

let healthResp = httpGet(port, "/health")
check("HTTP GET /health returns 200 OK and backend html",
      "200 OK" in healthResp and "\"backend\":\"html\"" in healthResp)

let stateResp = httpGet(port, "/state")
check("HTTP GET /state returns frame HTML",
      "200 OK" in stateResp and "\"html\":" in stateResp)

let postResp = httpPost(port, "/input",
  """{"events":[{"type":"mousedown","x":42,"y":84,"button":0,"clicks":1},{"type":"keydown","key":"x","code":"KeyX"}]}""")
check("HTTP POST /input queues events", "200 OK" in postResp and "\"ok\":true" in postResp)
check("HTTP-posted mousedown received by pollEvent",
      pollEvent(ev, {WantTextInput}) and ev.kind == MouseDownEvent and ev.x == 42 and ev.y == 84)
check("HTTP-posted keydown received by pollEvent",
      pollEvent(ev, {WantTextInput}) and ev.kind == KeyDownEvent and ev.key == KeyX)
check("HTTP-posted textinput received by pollEvent",
      pollEvent(ev, {WantTextInput}) and ev.kind == TextInputEvent and ev.text[0] == 'x')

freeImage(img)
check("freeImage resets imageSize to 0x0", imageSize(img) == (0, 0))
closeFont(fReg)
closeFont(fBold)
closeFont(fItal)
shutdown()
try: removeFile(tmpPng) except CatchableError: discard

echo "-------------------------------------------------------------------"
echo "Passed: ", passes, " | Failed: ", failures
if failures > 0:
  quit(1)
echo "ALL PASS (Pure HTML/CSS/JS DOM Backend)"
