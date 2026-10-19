## Comprehensive unit & HTTP integration tests for the separate HTML5 <canvas>
## 2D Backend (`-d:canvas`, `src/uirelays/drivers/canvas_driver.nim`).
##
## Compile & run:
##   nim c --mm:arc -d:canvas --outdir:/tmp/uirelays_bins -r tests/web_canvas_test.nim

import std/[strutils, json, os, net]
import uirelays
import uirelays/drivers/[web_common, canvas_driver]

var failures = 0
var passes = 0

proc check(name: string; cond: bool; detail = "") =
  if cond:
    inc passes
    echo "  PASS  ", name
  else:
    inc failures
    echo "  FAIL  ", name, (if detail.len > 0: "  -- " & detail else: "")

echo "=== UIRelays HTML5 Canvas 2D Backend Tests (--mm:arc) ==="

# 1. Initialization & Backend Identity
let win = createWindow(900, 640)
check("backend is wbkCanvas", webCore.backendKind == wbkCanvas)
check("window dimensions 900x640", win.width == 900 and win.height == 640)

let pageLower = webCore.pageHtml.toLowerAscii()
check("Canvas page has <canvas id=\"uir-canvas\"", "<canvas id=\"uir-canvas\"" in pageLower)
check("Canvas page uses getContext(\"2d\")", "getcontext(\"2d\")" in pageLower)
check("Canvas page has ZERO WebAssembly", "webassembly" notin pageLower and ".wasm" notin pageLower)

# 2. Fonts, Drawing, Clipping, Images, Blit -> 2D Command Stream Verification
setWindowTitle("Canvas 2D Test Suite")
setCursor(curCrosshair)

var fm: FontMetrics
let font = openFont("", 15, fm, {FontStyle.bold, FontStyle.italics})
check("openFont returns valid handle", int(font) > 0)

fillRect(rect(0, 0, 900, 640), color(24, 24, 37))
drawPoint(100, 120, color(255, 100, 50))
drawLine(10, 20, 300, 20, color(100, 200, 255))
drawLine(10, 20, 200, 180, color(255, 200, 100))
discard drawText(font, 40, 50, "Canvas 2D Text", color(255, 255, 255), color(40, 50, 60))

let mExt = measureText(font, "Pre-measured")
discard drawText(font, 40, 80, "Pre-measured", color(200, 255, 200), color(0, 0, 0, 0), known = mExt)

saveState()
setClipRect(rect(30, 30, 200, 150))
fillRect(rect(0, 0, 400, 400), color(120, 80, 200))
restoreState()

let tmpPng = getTempDir() / "uirelays_canvas_test_img.png"
var pxBuf = newSeq[uint32](20 * 16)
for i in 0 ..< pxBuf.len:
  pxBuf[i] = 0xFFAA4488'u32
let pngBytes = encodeRgbaToPngBytes(cast[ptr UncheckedArray[uint32]](addr pxBuf[0]), 20, 16)
var pngStr = newString(pngBytes.len)
for i in 0 ..< pngBytes.len: pngStr[i] = char(pngBytes[i])
writeFile(tmpPng, pngStr)

let img = loadImage(tmpPng)
check("loadImage 20x16 on Canvas backend", int(img) > 0 and imageSize(img) == (20, 16))
drawImage(img, rect(0, 0, 20, 16), rect(320, 50, 40, 32))
check("blitRGBA succeeds on Canvas backend",
      blitRGBA(cast[ptr UncheckedArray[uint32]](addr pxBuf[0]), 20, 16, rect(380, 50, 20, 16)))

refresh()

let cmdsJson = parseJson(lastPublishedCanvasJson)
check("Canvas command array is non-empty JArray", cmdsJson.kind == JArray and cmdsJson.len >= 10, $cmdsJson.len)

var sawRect, sawPoint, sawLine, sawText, sawSave, sawClip, sawRestore, sawImg, sawBlit = false
for cmd in cmdsJson:
  case cmd["op"].getStr()
  of "rect": sawRect = true
  of "point": sawPoint = true
  of "line": sawLine = true
  of "text": sawText = true
  of "save": sawSave = true
  of "clip": sawClip = true
  of "restore": sawRestore = true
  of "img": sawImg = true
  of "blit": sawBlit = true
  else: discard

check("2D command stream contains rect", sawRect)
check("2D command stream contains point", sawPoint)
check("2D command stream contains line", sawLine)
check("2D command stream contains text", sawText)
check("2D command stream contains save/clip/restore", sawSave and sawClip and sawRestore)
check("2D command stream contains img", sawImg)
check("2D command stream contains blit", sawBlit)

# 3. Frame deduplication check
let frame1 = webCore.frameId
fillRect(rect(0, 0, 900, 640), color(24, 24, 37))
refresh()
let frame2 = webCore.frameId
check("Changed frame increments frameId", frame2 == frame1 + 1)

fillRect(rect(0, 0, 900, 640), color(24, 24, 37))
refresh()
let frame3 = webCore.frameId
check("Identical frame is deduplicated (frameId unchanged)", frame3 == frame2, $frame3 & " vs " & $frame2)

# 4. Live HTTP Server & Input Translation Verification
let port = webServerPort()
check("Canvas HTTP server listening on port > 0", port > 0)

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
check("HTTP GET /health returns backend canvas",
      "200 OK" in healthResp and "\"backend\":\"canvas\"" in healthResp)

let stateResp = httpGet(port, "/state")
check("HTTP GET /state returns commands array",
      "200 OK" in stateResp and "\"commands\":" in stateResp)

let postResp = httpPost(port, "/input",
  """{"events":[{"type":"wheel","dx":0,"dy":3},{"type":"clipboard","text":"CanvasClip"},{"type":"close"}]}""")
check("HTTP POST /input succeeds", "200 OK" in postResp)

var ev: Event
check("poll MouseWheelEvent dy=3", pollEvent(ev, {}) and ev.kind == MouseWheelEvent and ev.y == 3)
check("clipboard updated via /input", getClipboardText() == "CanvasClip")
check("poll WindowCloseEvent", pollEvent(ev, {}) and ev.kind == WindowCloseEvent)

freeImage(img)
closeFont(font)
shutdown()
try: removeFile(tmpPng) except CatchableError: discard

echo "-------------------------------------------------------------------"
echo "Passed: ", passes, " | Failed: ", failures
if failures > 0:
  quit(1)
echo "ALL PASS (HTML5 Canvas 2D Backend)"
