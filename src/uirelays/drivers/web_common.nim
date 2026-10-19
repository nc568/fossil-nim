# Shared pure-Nim (--mm:arc) web protocol, non-blocking HTTP/SSE server,
# input queue, font/image/PNG helpers, and state management for UIRelays
# Web Backends (html_driver and canvas_driver).
#
# Zero external dependencies, zero WebAssembly, 100% Nim standard library.

import std/[strutils, base64]
when not defined(js):
  import std/[json, monotimes, times, os, nativesockets, posix]
import ../coords, ../input, ../screen

type
  WebBackendKind* = enum
    wbkHtml = "html"       ## Pure Vanilla HTML5 + CSS3 + JS DOM (NO Canvas, NO WASM)
    wbkCanvas = "canvas"   ## Separate HTML5 <canvas> 2D Backend (NO WASM)

  WebClipState* = object
    enabled*: bool
    rect*: Rect

  WebFontSlot* = object
    active*: bool
    path*: string
    family*: string
    size*: int
    style*: FontStyles
    metrics*: FontMetrics
    charWidth*: int

  WebImageSlot* = object
    active*: bool
    path*: string
    w*, h*: int
    mime*: string
    dataUri*: string

when not defined(js):
  type
    SseClient = object
      fd: SocketHandle
      lastSentFrame: int
      alive: bool

type
  WebCoreState* = object
    backendKind*: WebBackendKind
    initialized*: bool
    when not defined(js):
      startMono*: MonoTime
    else:
      startMs*: float
    layout*: ScreenLayout
    windowTitle*: string
    currentCursor*: CursorKind
    clipboardText*: string
    wantTextInput*: bool
    clipStack*: seq[WebClipState]
    currentClip*: WebClipState
    fonts*: seq[WebFontSlot]
    images*: seq[WebImageSlot]
    eventQueue*: seq[Event]
    frameId*: int
    lastPayloadHash*: uint64
    lastFrameJson*: string
    pageHtml*: string
    # Metrics for diagnostics & monkey tests
    totalFramesRendered*: int
    totalEventsProcessed*: int
    domNodeCount*: int
    canvasCommandCount*: int
    monkeyReportJson*: string
    # Embedded non-blocking HTTP/SSE server
    serverEnabled*: bool
    serverPort*: int
    when not defined(js):
      listenFd*: SocketHandle
      sseClients*: seq[SseClient]

var webCore*: WebCoreState

# ---------------------------------------------------------------------------
# Fast FNV-1a hash for frame deduplication
# ---------------------------------------------------------------------------

proc fnv1a64*(s: string): uint64 {.inline.} =
  when defined(js):
    var h = 2166136261'u32
    for i in 0 ..< s.len:
      h = h xor uint32(ord(s[i]))
      h = uint32((uint64(h) * 16777619'u64) and 0xFFFFFFFF'u64)
    result = uint64(h)
  else:
    result = 14695981039346656037'u64
    for i in 0 ..< s.len:
      result = (result xor uint64(ord(s[i]))) * 1099511628211'u64

# ---------------------------------------------------------------------------
# Color & CSS formatting helpers
# ---------------------------------------------------------------------------

proc toCssRgba*(c: Color): string {.inline.} =
  if c.a == 255'u8:
    result = "rgb(" & $c.r & "," & $c.g & "," & $c.b & ")"
  elif c.a == 0'u8:
    result = "rgba(0,0,0,0)"
  else:
    let alpha = formatFloat(float(c.a) / 255.0, ffDecimal, 3)
    result = "rgba(" & $c.r & "," & $c.g & "," & $c.b & "," & alpha & ")"

proc htmlEscape*(s: string): string =
  result = newStringOfCap(s.len + 8)
  for ch in s:
    case ch
    of '&': result.add "&amp;"
    of '<': result.add "&lt;"
    of '>': result.add "&gt;"
    of '"': result.add "&quot;"
    of '\'': result.add "&#39;"
    else: result.add ch

proc cursorToCss*(c: CursorKind): string {.inline.} =
  case c
  of curDefault, curArrow: "default"
  of curIbeam: "text"
  of curWait: "wait"
  of curCrosshair: "crosshair"
  of curHand: "pointer"
  of curSizeNS: "ns-resize"
  of curSizeWE: "ew-resize"

# ---------------------------------------------------------------------------
# Pure-Nim CRC32, Adler32 & Uncompressed PNG Encoder (for blitRGBA without Canvas)
# ---------------------------------------------------------------------------

proc crc32Compute(data: openArray[uint8]): uint32 =
  var crc = 0xFFFFFFFF'u32
  for b in data:
    crc = crc xor uint32(b)
    for _ in 0 ..< 8:
      if (crc and 1'u32) != 0'u32:
        crc = (crc shr 1) xor 0xEDB88320'u32
      else:
        crc = crc shr 1
  result = not crc

proc adler32Compute(data: openArray[uint8]): uint32 =
  var s1 = 1'u32
  var s2 = 0'u32
  for b in data:
    s1 = (s1 + uint32(b)) mod 65521'u32
    s2 = (s2 + s1) mod 65521'u32
  result = (s2 shl 16) or s1

proc addBe32(buf: var seq[uint8]; val: uint32) {.inline.} =
  buf.add uint8((val shr 24) and 0xFF'u32)
  buf.add uint8((val shr 16) and 0xFF'u32)
  buf.add uint8((val shr 8) and 0xFF'u32)
  buf.add uint8(val and 0xFF'u32)

proc addPngChunk(png: var seq[uint8]; chunkType: string; payload: openArray[uint8]) =
  png.addBe32(uint32(payload.len))
  var crcBuf = newSeqOfCap[uint8](4 + payload.len)
  for i in 0 ..< 4:
    crcBuf.add uint8(ord(chunkType[i]))
  for b in payload:
    crcBuf.add b
  for b in crcBuf:
    png.add b
  png.addBe32(crc32Compute(crcBuf))

proc encodeRgbaToPngBytes*(pixels: ptr UncheckedArray[uint32]; w, h: int): seq[uint8] =
  ## Encodes a `w x h` buffer of 32-bit pixels (`0xAARRGGBB` or `0x00RRGGBB`
  ## as passed to `blitRGBA` in uirelays) into a valid PNG byte stream in pure Nim.
  when defined(js):
    discard pixels; discard w; discard h
    return @[]
  else:
    if pixels == nil or w <= 0 or h <= 0:
      return @[]

    # Raw scanlines: each row starts with filter byte 0 (None) + 4 bytes/pixel (RGBA)
    let rowStride = 1 + w * 4
    let rawLen = h * rowStride
    var raw = newSeq[uint8](rawLen)
    var pos = 0
    for y in 0 ..< h:
      raw[pos] = 0'u8 # Filter type 0 (None)
      inc pos
      let rowOffset = y * w
      for x in 0 ..< w:
        let word = pixels[rowOffset + x]
        let a = uint8((word shr 24) and 0xFF'u32)
        let r = uint8((word shr 16) and 0xFF'u32)
        let g = uint8((word shr 8) and 0xFF'u32)
        let b = uint8(word and 0xFF'u32)
        raw[pos] = r
        raw[pos + 1] = g
        raw[pos + 2] = b
        raw[pos + 3] = if a == 0'u8 and word != 0'u32: 255'u8 else: (if word == 0'u32: 255'u8 else: a)
        pos += 4

    # Wrap raw scanlines in zlib stored deflate blocks (max 65535 bytes per block)
    var zlibData = newSeqOfCap[uint8](rawLen + (rawLen div 65535 + 2) * 5 + 6)
    zlibData.add 0x78'u8 # CMF (Deflate, 32K window)
    zlibData.add 0x01'u8 # FLG (No dict, check bits)

    var offset = 0
    while offset < rawLen:
      let chunkLen = min(65535, rawLen - offset)
      let isLast = (offset + chunkLen) >= rawLen
      zlibData.add(if isLast: 0x01'u8 else: 0x00'u8) # BFINAL + BTYPE=00 (stored)
      let len16 = uint16(chunkLen)
      let nlen16 = not len16
      zlibData.add uint8(len16 and 0xFF'u16)
      zlibData.add uint8((len16 shr 8) and 0xFF'u16)
      zlibData.add uint8(nlen16 and 0xFF'u16)
      zlibData.add uint8((nlen16 shr 8) and 0xFF'u16)
      for i in 0 ..< chunkLen:
        zlibData.add raw[offset + i]
      offset += chunkLen

    zlibData.addBe32(adler32Compute(raw))

    # Assemble PNG file
    result = newSeqOfCap[uint8](zlibData.len + 64)
    for sigByte in [137'u8, 80'u8, 78'u8, 71'u8, 13'u8, 10'u8, 26'u8, 10'u8]:
      result.add sigByte

    var ihdr = newSeqOfCap[uint8](13)
    ihdr.addBe32(uint32(w))
    ihdr.addBe32(uint32(h))
    ihdr.add 8'u8 # Bit depth 8
    ihdr.add 6'u8 # Color type 6 (RGBA)
    ihdr.add 0'u8 # Compression
    ihdr.add 0'u8 # Filter
    ihdr.add 0'u8 # Interlace
    result.addPngChunk("IHDR", ihdr)
    result.addPngChunk("IDAT", zlibData)
    let empty: seq[uint8] = @[]
    result.addPngChunk("IEND", empty)

proc encodeRgbaToPngDataUri*(pixels: ptr UncheckedArray[uint32]; w, h: int): string =
  let pngBytes = encodeRgbaToPngBytes(pixels, w, h)
  if pngBytes.len == 0:
    return ""
  var s = newString(pngBytes.len)
  for i in 0 ..< pngBytes.len:
    s[i] = char(pngBytes[i])
  result = "data:image/png;base64," & base64.encode(s)

# ---------------------------------------------------------------------------
# Pure-Nim Image Dimension & MIME Parser (PNG, BMP, GIF, JPEG, SVG)
# ---------------------------------------------------------------------------

proc readBe32At(data: string; idx: int): int {.inline.} =
  if idx + 3 >= data.len: return 0
  (ord(data[idx]) shl 24) or (ord(data[idx + 1]) shl 16) or
    (ord(data[idx + 2]) shl 8) or ord(data[idx + 3])

proc readLe32At(data: string; idx: int): int {.inline.} =
  if idx + 3 >= data.len: return 0
  ord(data[idx]) or (ord(data[idx + 1]) shl 8) or
    (ord(data[idx + 2]) shl 16) or (ord(data[idx + 3]) shl 24)

proc readLe16At(data: string; idx: int): int {.inline.} =
  if idx + 1 >= data.len: return 0
  ord(data[idx]) or (ord(data[idx + 1]) shl 8)

proc readBe16At(data: string; idx: int): int {.inline.} =
  if idx + 1 >= data.len: return 0
  (ord(data[idx]) shl 8) or ord(data[idx + 1])

proc parseImageDimensions*(data: string; path: string): tuple[w, h: int, mime: string] =
  # 1. PNG
  if data.len >= 24 and data[0] == '\x89' and data[1] == 'P' and data[2] == 'N' and data[3] == 'G':
    let w = readBe32At(data, 16)
    let h = readBe32At(data, 20)
    return (max(0, w), max(0, h), "image/png")

  # 2. BMP
  if data.len >= 26 and data[0] == 'B' and data[1] == 'M':
    let w = readLe32At(data, 18)
    let hRaw = readLe32At(data, 22)
    let h = abs(int(cast[int32](uint32(hRaw))))
    return (max(0, w), max(0, h), "image/bmp")

  # 3. GIF
  if data.len >= 10 and data.startsWith("GIF8"):
    let w = readLe16At(data, 6)
    let h = readLe16At(data, 8)
    return (max(0, w), max(0, h), "image/gif")

  # 4. JPEG
  if data.len >= 4 and ord(data[0]) == 0xFF and ord(data[1]) == 0xD8:
    var i = 2
    while i + 8 < data.len:
      if ord(data[i]) != 0xFF:
        inc i
        continue
      let marker = ord(data[i + 1])
      if marker == 0xFF:
        inc i
        continue
      if marker in {0xC0, 0xC1, 0xC2, 0xC3}:
        let h = readBe16At(data, i + 5)
        let w = readBe16At(data, i + 7)
        return (max(0, w), max(0, h), "image/jpeg")
      let segLen = readBe16At(data, i + 2)
      if segLen < 2:
        break
      i += 2 + segLen
    return (64, 64, "image/jpeg")

  # 5. SVG
  let lower = data[0 ..< min(data.len, 512)].toLowerAscii()
  if "<svg" in lower or path.toLowerAscii().endsWith(".svg"):
    return (128, 128, "image/svg+xml")

  return (0, 0, "application/octet-stream")

# ---------------------------------------------------------------------------
# Font Management (Deterministic Monospace Metrics + Unicode Rune Width)
# ---------------------------------------------------------------------------

proc webOpenFont*(path: string; size: int; style: FontStyles;
                  metrics: var FontMetrics): Font =
  let pxSize = max(6, size)
  let baseCharW = max(4, int(float(pxSize) * 0.6 + 0.5))
  let charW = if FontStyle.bold in style: baseCharW + max(0, pxSize div 24) else: baseCharW
  let ascent = max(4, int(float(pxSize) * 0.8 + 0.5))
  let descent = max(2, int(float(pxSize) * 0.25 + 0.5))
  let lineHeight = ascent + descent + max(2, pxSize div 8)

  metrics = FontMetrics(
    ascent: ascent,
    descent: descent,
    lineHeight: lineHeight
  )

  let family =
    if path.len == 0:
      "'DejaVu Sans Mono', 'JetBrains Mono', 'Fira Code', 'Liberation Mono', Consolas, monospace"
    elif '/' in path or '\\' in path or path.toLowerAscii().endsWith(".ttf") or path.toLowerAscii().endsWith(".otf"):
      "'DejaVu Sans Mono', 'Liberation Mono', Consolas, monospace"
    else:
      path & ", monospace"

  webCore.fonts.add WebFontSlot(
    active: true,
    path: path,
    family: family,
    size: pxSize,
    style: style,
    metrics: metrics,
    charWidth: charW
  )
  result = Font(webCore.fonts.len)

proc webCloseFont*(f: Font) =
  let idx = int(f) - 1
  if idx >= 0 and idx < webCore.fonts.len:
    webCore.fonts[idx].active = false

proc webGetFontSlot*(f: Font): WebFontSlot {.inline.} =
  let idx = int(f) - 1
  if idx >= 0 and idx < webCore.fonts.len and webCore.fonts[idx].active:
    return webCore.fonts[idx]
  result = WebFontSlot(
    active: true,
    family: "'DejaVu Sans Mono', Consolas, monospace",
    size: 15,
    metrics: FontMetrics(ascent: 12, descent: 4, lineHeight: 18),
    charWidth: 9
  )

proc webGetFontMetrics*(f: Font): FontMetrics =
  let idx = int(f) - 1
  if idx >= 0 and idx < webCore.fonts.len and webCore.fonts[idx].active:
    return webCore.fonts[idx].metrics
  FontMetrics()

proc utf8RuneLenAt*(s: string; i: int): int {.inline.} =
  if i < 0 or i >= s.len: return 1
  let b = ord(s[i])
  if b < 0x80: 1
  elif (b and 0xE0) == 0xC0: 2
  elif (b and 0xF0) == 0xE0: 3
  elif (b and 0xF8) == 0xF0: 4
  else: 1

proc utf8CodeAt(s: string; i: int): tuple[code, step: int] {.inline.} =
  let b0 = ord(s[i])
  if b0 < 0x80:
    return (b0, 1)
  elif (b0 and 0xE0) == 0xC0 and i + 1 < s.len:
    return (((b0 and 0x1F) shl 6) or (ord(s[i + 1]) and 0x3F), 2)
  elif (b0 and 0xF0) == 0xE0 and i + 2 < s.len:
    return (((b0 and 0x0F) shl 12) or ((ord(s[i + 1]) and 0x3F) shl 6) or (ord(s[i + 2]) and 0x3F), 3)
  elif (b0 and 0xF8) == 0xF0 and i + 3 < s.len:
    return (((b0 and 0x07) shl 18) or ((ord(s[i + 1]) and 0x3F) shl 12) or ((ord(s[i + 2]) and 0x3F) shl 6) or (ord(s[i + 3]) and 0x3F), 4)
  else:
    return (b0, 1)

proc isWideCode(code: int): bool {.inline.} =
  (code >= 0x1100 and code <= 0x115F) or
  (code >= 0x2E80 and code <= 0xA4CF) or
  (code >= 0xAC00 and code <= 0xD7A3) or
  (code >= 0xF900 and code <= 0xFAFF) or
  (code >= 0xFE10 and code <= 0xFE6F) or
  (code >= 0xFF00 and code <= 0xFF60) or
  (code >= 0x1F300 and code <= 0x1FAFF)

proc webMeasureText*(f: Font; text: string): TextExtent =
  let idx = int(f) - 1
  if idx < 0 or idx >= webCore.fonts.len or not webCore.fonts[idx].active or text.len == 0:
    return TextExtent(w: 0, h: 0)
  let slot = webCore.fonts[idx]
  var cols = 0
  var i = 0
  while i < text.len:
    let (code, step) = utf8CodeAt(text, i)
    if isWideCode(code):
      cols += 2
    else:
      cols += 1
    i += step
  TextExtent(w: cols * slot.charWidth, h: slot.metrics.lineHeight)

# ---------------------------------------------------------------------------
# Image Management
# ---------------------------------------------------------------------------

proc webRegisterMemoryImage*(path: string; w, h: int; mime, dataUri: string): Image =
  for i in 0 ..< webCore.images.len:
    if webCore.images[i].active and webCore.images[i].path == path:
      return Image(i + 1)
  webCore.images.add WebImageSlot(
    active: true,
    path: path,
    w: w,
    h: h,
    mime: mime,
    dataUri: dataUri
  )
  result = Image(webCore.images.len)

proc webLoadImage*(path: string): Image =
  if path.len == 0:
    return Image(0)
  for i in 0 ..< webCore.images.len:
    if webCore.images[i].active and
       (webCore.images[i].path == path or path.endsWith(webCore.images[i].path)):
      return Image(i + 1)
  when defined(js):
    return Image(0)
  else:
    if not fileExists(path):
      return Image(0)
    var data = ""
    try:
      data = readFile(path)
    except CatchableError:
      return Image(0)
    if data.len == 0:
      return Image(0)
    let info = parseImageDimensions(data, path)
    if info.w <= 0 or info.h <= 0:
      return Image(0)
    let dataUri = "data:" & info.mime & ";base64," & base64.encode(data)
    webCore.images.add WebImageSlot(
      active: true,
      path: path,
      w: info.w,
      h: info.h,
      mime: info.mime,
      dataUri: dataUri
    )
    result = Image(webCore.images.len)

proc webFreeImage*(img: Image) =
  let idx = int(img) - 1
  if idx >= 0 and idx < webCore.images.len:
    webCore.images[idx].active = false
    webCore.images[idx].dataUri = ""
    webCore.images[idx].w = 0
    webCore.images[idx].h = 0

proc webImageSize*(img: Image): tuple[w, h: int] =
  let idx = int(img) - 1
  if idx >= 0 and idx < webCore.images.len and webCore.images[idx].active:
    return (webCore.images[idx].w, webCore.images[idx].h)
  (0, 0)

proc webGetImageSlot*(img: Image): WebImageSlot {.inline.} =
  let idx = int(img) - 1
  if idx >= 0 and idx < webCore.images.len and webCore.images[idx].active:
    return webCore.images[idx]
  WebImageSlot()

# ---------------------------------------------------------------------------
# Window State & Clip Stack
# ---------------------------------------------------------------------------

proc webSaveState*() =
  webCore.clipStack.add webCore.currentClip

proc webRestoreState*() =
  if webCore.clipStack.len == 0:
    return
  webCore.currentClip = webCore.clipStack[^1]
  webCore.clipStack.setLen(webCore.clipStack.len - 1)

proc webSetClipRect*(r: Rect) =
  webCore.currentClip = WebClipState(enabled: true, rect: r)

proc webSetCursor*(c: CursorKind) =
  webCore.currentCursor = c

proc webSetWindowTitle*(title: string) =
  webCore.windowTitle = title

proc webGetWindowLayout*(): ScreenLayout =
  webCore.layout

proc webGetClipboardText*(): string =
  webCore.clipboardText

proc webPutClipboardText*(text: string) =
  webCore.clipboardText = text

# ---------------------------------------------------------------------------
# Keyboard & Mouse Event Translation + Programmatic Injection
# ---------------------------------------------------------------------------

proc translateWebKey*(keyStr, codeStr: string): KeyCode =
  let k = strutils.strip(keyStr)
  let c = strutils.strip(codeStr)

  # Check exact KeyboardEvent.code first for layout-independent physical keys
  case c
  of "KeyA": return KeyA
  of "KeyB": return KeyB
  of "KeyC": return KeyC
  of "KeyD": return KeyD
  of "KeyE": return KeyE
  of "KeyF": return KeyF
  of "KeyG": return KeyG
  of "KeyH": return KeyH
  of "KeyI": return KeyI
  of "KeyJ": return KeyJ
  of "KeyK": return KeyK
  of "KeyL": return KeyL
  of "KeyM": return KeyM
  of "KeyN": return KeyN
  of "KeyO": return KeyO
  of "KeyP": return KeyP
  of "KeyQ": return KeyQ
  of "KeyR": return KeyR
  of "KeyS": return KeyS
  of "KeyT": return KeyT
  of "KeyU": return KeyU
  of "KeyV": return KeyV
  of "KeyW": return KeyW
  of "KeyX": return KeyX
  of "KeyY": return KeyY
  of "KeyZ": return KeyZ
  of "Digit0", "Numpad0": return Key0
  of "Digit1", "Numpad1": return Key1
  of "Digit2", "Numpad2": return Key2
  of "Digit3", "Numpad3": return Key3
  of "Digit4", "Numpad4": return Key4
  of "Digit5", "Numpad5": return Key5
  of "Digit6", "Numpad6": return Key6
  of "Digit7", "Numpad7": return Key7
  of "Digit8", "Numpad8": return Key8
  of "Digit9", "Numpad9": return Key9
  of "F1": return KeyF1
  of "F2": return KeyF2
  of "F3": return KeyF3
  of "F4": return KeyF4
  of "F5": return KeyF5
  of "F6": return KeyF6
  of "F7": return KeyF7
  of "F8": return KeyF8
  of "F9": return KeyF9
  of "F10": return KeyF10
  of "F11": return KeyF11
  of "F12": return KeyF12
  of "Enter", "NumpadEnter": return KeyEnter
  of "Space": return KeySpace
  of "Escape": return KeyEsc
  of "Tab": return KeyTab
  of "Backspace": return KeyBackspace
  of "Delete": return KeyDelete
  of "Insert": return KeyInsert
  of "ArrowLeft": return KeyLeft
  of "ArrowRight": return KeyRight
  of "ArrowUp": return KeyUp
  of "ArrowDown": return KeyDown
  of "PageUp": return KeyPageUp
  of "PageDown": return KeyPageDown
  of "Home": return KeyHome
  of "End": return KeyEnd
  of "CapsLock": return KeyCapslock
  of "Comma": return KeyComma
  of "Period", "NumpadDecimal": return KeyPeriod
  of "Slash", "NumpadDivide": return KeySlash
  of "Minus", "NumpadSubtract": return KeyMinus
  of "NumpadAdd": return KeyPlus
  of "Equal":
    if k == "+": return KeyPlus
    return KeyEqual
  else:
    discard

  # Fallback to KeyboardEvent.key
  if k.len == 1:
    let ch = k[0]
    case ch
    of 'a', 'A': return KeyA
    of 'b', 'B': return KeyB
    of 'c', 'C': return KeyC
    of 'd', 'D': return KeyD
    of 'e', 'E': return KeyE
    of 'f', 'F': return KeyF
    of 'g', 'G': return KeyG
    of 'h', 'H': return KeyH
    of 'i', 'I': return KeyI
    of 'j', 'J': return KeyJ
    of 'k', 'K': return KeyK
    of 'l', 'L': return KeyL
    of 'm', 'M': return KeyM
    of 'n', 'N': return KeyN
    of 'o', 'O': return KeyO
    of 'p', 'P': return KeyP
    of 'q', 'Q': return KeyQ
    of 'r', 'R': return KeyR
    of 's', 'S': return KeyS
    of 't', 'T': return KeyT
    of 'u', 'U': return KeyU
    of 'v', 'V': return KeyV
    of 'w', 'W': return KeyW
    of 'x', 'X': return KeyX
    of 'y', 'Y': return KeyY
    of 'z', 'Z': return KeyZ
    of '0': return Key0
    of '1': return Key1
    of '2': return Key2
    of '3': return Key3
    of '4': return Key4
    of '5': return Key5
    of '6': return Key6
    of '7': return Key7
    of '8': return Key8
    of '9': return Key9
    of ' ': return KeySpace
    of ',': return KeyComma
    of '.': return KeyPeriod
    of '/': return KeySlash
    of '-': return KeyMinus
    of '=': return KeyEqual
    of '+': return KeyPlus
    else: return KeyNone

  case k.toLowerAscii()
  of "enter", "return": KeyEnter
  of "escape", "esc": KeyEsc
  of "tab": KeyTab
  of "backspace": KeyBackspace
  of "delete", "del": KeyDelete
  of "insert", "ins": KeyInsert
  of "arrowleft", "left": KeyLeft
  of "arrowright", "right": KeyRight
  of "arrowup", "up": KeyUp
  of "arrowdown", "down": KeyDown
  of "pageup", "pgup": KeyPageUp
  of "pagedown", "pgdn": KeyPageDown
  of "home": KeyHome
  of "end": KeyEnd
  of "capslock": KeyCapslock
  of "f1": KeyF1
  of "f2": KeyF2
  of "f3": KeyF3
  of "f4": KeyF4
  of "f5": KeyF5
  of "f6": KeyF6
  of "f7": KeyF7
  of "f8": KeyF8
  of "f9": KeyF9
  of "f10": KeyF10
  of "f11": KeyF11
  of "f12": KeyF12
  of "space": KeySpace
  else: KeyNone

proc makeTextInputEvent*(utf8Rune: string): Event =
  result = Event(kind: TextInputEvent)
  let n = min(4, utf8Rune.len)
  for i in 0 ..< n:
    result.text[i] = utf8Rune[i]

proc webInjectEvent*(e: Event) =
  if e.kind == MouseMoveEvent and webCore.eventQueue.len > 0 and
     webCore.eventQueue[^1].kind == MouseMoveEvent:
    webCore.eventQueue[^1] = e
  elif webCore.eventQueue.len < 4096:
    webCore.eventQueue.add e

proc utf8RuneCount(s: string): int {.inline.} =
  var i = 0
  while i < s.len:
    i += utf8RuneLenAt(s, i)
    inc result

proc webInjectText*(utf8Text: string) =
  var i = 0
  while i < utf8Text.len:
    let rLen = utf8RuneLenAt(utf8Text, i)
    let slice = utf8Text[i ..< min(utf8Text.len, i + rLen)]
    webInjectEvent(makeTextInputEvent(slice))
    i += max(1, rLen)

proc webInjectKey*(key: KeyCode; mods: set[Modifier] = {}; text = "") =
  webInjectEvent(Event(kind: KeyDownEvent, key: key, mods: mods))
  if text.len > 0 and not isCommandChord(mods):
    webInjectText(text)
  webInjectEvent(Event(kind: KeyUpEvent, key: key, mods: mods))

proc webInjectMouse*(kind: EventKind; x, y: int; button = LeftButton; clicks = 1) =
  webInjectEvent(Event(
    kind: kind,
    x: clamp(x, -4096, 8192),
    y: clamp(y, -4096, 8192),
    button: button,
    clicks: clamp(clicks, 1, 10)
  ))

proc webInjectResize*(w, h: int; uiScale = 100) =
  let clampedW = clamp(w, 120, 4096)
  let clampedH = clamp(h, 120, 4096)
  let clampedScale = clamp(uiScale, 50, 400)
  webCore.layout.width = clampedW
  webCore.layout.height = clampedH
  webCore.layout.uiScale = clampedScale
  webInjectEvent(Event(
    kind: WindowResizeEvent,
    x: clampedW,
    y: clampedH,
    scaleX: webCore.layout.scaleX,
    scaleY: webCore.layout.scaleY,
    uiScale: clampedScale
  ))

when not defined(js):
  proc parseSingleJsonEvent(node: JsonNode) =
    if node.kind != JObject:
      return
    let evType = node.getOrDefault("type").getStr("").toLowerAscii()
    var mods: set[Modifier] = {}
    if node.getOrDefault("shift").getBool(false): mods.incl ShiftPressed
    if node.getOrDefault("ctrl").getBool(false): mods.incl CtrlPressed
    if node.getOrDefault("alt").getBool(false): mods.incl AltPressed
    if node.getOrDefault("meta").getBool(false) or node.getOrDefault("gui").getBool(false):
      mods.incl GuiPressed

    case evType
    of "mousedown":
      let btnNum = node.getOrDefault("button").getInt(0)
      let btn = case btnNum
        of 1: MiddleButton
        of 2: RightButton
        else: LeftButton
      webInjectEvent(Event(
        kind: MouseDownEvent,
        x: clamp(node.getOrDefault("x").getInt(0), -4096, 8192),
        y: clamp(node.getOrDefault("y").getInt(0), -4096, 8192),
        button: btn,
        clicks: clamp(node.getOrDefault("clicks").getInt(1), 1, 10),
        mods: mods
      ))
    of "mouseup":
      let btnNum = node.getOrDefault("button").getInt(0)
      let btn = case btnNum
        of 1: MiddleButton
        of 2: RightButton
        else: LeftButton
      webInjectEvent(Event(
        kind: MouseUpEvent,
        x: clamp(node.getOrDefault("x").getInt(0), -4096, 8192),
        y: clamp(node.getOrDefault("y").getInt(0), -4096, 8192),
        button: btn,
        clicks: clamp(node.getOrDefault("clicks").getInt(1), 1, 10),
        mods: mods
      ))
    of "mousemove":
      webInjectEvent(Event(
        kind: MouseMoveEvent,
        x: clamp(node.getOrDefault("x").getInt(0), -4096, 8192),
        y: clamp(node.getOrDefault("y").getInt(0), -4096, 8192),
        mods: mods
      ))
    of "wheel", "mousewheel":
      webInjectEvent(Event(
        kind: MouseWheelEvent,
        x: clamp(node.getOrDefault("dx").getInt(node.getOrDefault("x").getInt(0)), -100, 100),
        y: clamp(node.getOrDefault("dy").getInt(node.getOrDefault("y").getInt(0)), -100, 100),
        mods: mods
      ))
    of "keydown":
      let keyStr = node.getOrDefault("key").getStr("")
      let codeStr = node.getOrDefault("code").getStr("")
      let kc = translateWebKey(keyStr, codeStr)
      if kc != KeyNone:
        webInjectEvent(Event(kind: KeyDownEvent, key: kc, mods: mods))
      let textField = node.getOrDefault("text").getStr("")
      let candidateText =
        if textField.len > 0: textField
        elif utf8RuneCount(keyStr) == 1 and keyStr[0] >= ' ' and ord(keyStr[0]) != 127: keyStr
        else: ""
      if candidateText.len > 0 and not isCommandChord(mods) and
         node.getOrDefault("emitText").getBool(true):
        webInjectText(candidateText)
    of "keyup":
      let keyStr = node.getOrDefault("key").getStr("")
      let codeStr = node.getOrDefault("code").getStr("")
      let kc = translateWebKey(keyStr, codeStr)
      if kc != KeyNone:
        webInjectEvent(Event(kind: KeyUpEvent, key: kc, mods: mods))
    of "textinput", "text":
      let txt = node.getOrDefault("text").getStr("")
      if txt.len > 0 and not isCommandChord(mods):
        webInjectText(txt)
    of "resize", "metrics":
      let w = node.getOrDefault("width").getInt(node.getOrDefault("x").getInt(webCore.layout.width))
      let h = node.getOrDefault("height").getInt(node.getOrDefault("y").getInt(webCore.layout.height))
      let uiScale = node.getOrDefault("uiScale").getInt(webCore.layout.uiScale)
      webInjectResize(w, h, uiScale)
    of "focus":
      webInjectEvent(Event(kind: WindowFocusGainedEvent))
    of "blur":
      webInjectEvent(Event(kind: WindowFocusLostEvent))
    of "clipboard":
      webCore.clipboardText = node.getOrDefault("text").getStr("")
    of "close":
      webInjectEvent(Event(kind: WindowCloseEvent))
    of "quit":
      webInjectEvent(Event(kind: QuitEvent))
    else:
      discard

  proc parseIncomingInputJson*(body: string): int =
    if body.len == 0:
      return 0
    let beforeLen = webCore.eventQueue.len
    try:
      let parsed = parseJson(body)
      if parsed.kind == JArray:
        for item in parsed:
          parseSingleJsonEvent(item)
      elif parsed.kind == JObject:
        if parsed.hasKey("events") and parsed["events"].kind == JArray:
          for item in parsed["events"]:
            parseSingleJsonEvent(item)
        else:
          parseSingleJsonEvent(parsed)
    except CatchableError:
      discard
    result = webCore.eventQueue.len - beforeLen

# ---------------------------------------------------------------------------
# Non-blocking POSIX HTTP + SSE Server (when not defined(js))
# & Direct In-Browser DOM/Canvas Event Bridge (when defined(js))
# ---------------------------------------------------------------------------

when defined(js):
  proc jsPerformanceNow(): float {.importjs: "performance.now()".}

  proc uirJsMouseEvent*(evType: cstring; x, y, button, clicks: int;
                        shift, ctrl, alt, meta: bool) {.exportc.} =
    var mods: set[Modifier] = {}
    if shift: mods.incl ShiftPressed
    if ctrl: mods.incl CtrlPressed
    if alt: mods.incl AltPressed
    if meta: mods.incl GuiPressed
    let btn = case button
      of 1: MiddleButton
      of 2: RightButton
      else: LeftButton
    let t = ($evType).toLowerAscii()
    if t == "mousedown":
      webInjectEvent(Event(
        kind: MouseDownEvent,
        x: clamp(x, -4096, 8192),
        y: clamp(y, -4096, 8192),
        button: btn,
        clicks: clamp(clicks, 1, 10),
        mods: mods
      ))
    elif t == "mouseup":
      webInjectEvent(Event(
        kind: MouseUpEvent,
        x: clamp(x, -4096, 8192),
        y: clamp(y, -4096, 8192),
        button: btn,
        clicks: clamp(clicks, 1, 10),
        mods: mods
      ))
    elif t == "mousemove":
      webInjectEvent(Event(
        kind: MouseMoveEvent,
        x: clamp(x, -4096, 8192),
        y: clamp(y, -4096, 8192),
        mods: mods
      ))

  proc uirJsWheelEvent*(dx, dy: int; shift, ctrl, alt, meta: bool) {.exportc.} =
    var mods: set[Modifier] = {}
    if shift: mods.incl ShiftPressed
    if ctrl: mods.incl CtrlPressed
    if alt: mods.incl AltPressed
    if meta: mods.incl GuiPressed
    webInjectEvent(Event(
      kind: MouseWheelEvent,
      x: clamp(dx, -100, 100),
      y: clamp(dy, -100, 100),
      mods: mods
    ))

  proc uirJsKeyEvent*(evType, keyStr, codeStr: cstring;
                      shift, ctrl, alt, meta: bool) {.exportc.} =
    var mods: set[Modifier] = {}
    if shift: mods.incl ShiftPressed
    if ctrl: mods.incl CtrlPressed
    if alt: mods.incl AltPressed
    if meta: mods.incl GuiPressed
    let ks = $keyStr
    let cs = $codeStr
    let kc = translateWebKey(ks, cs)
    let t = ($evType).toLowerAscii()
    if t == "keydown":
      if kc != KeyNone:
        webInjectEvent(Event(kind: KeyDownEvent, key: kc, mods: mods))
      if utf8RuneCount(ks) == 1 and ks[0] >= ' ' and ord(ks[0]) != 127 and not isCommandChord(mods):
        webInjectText(ks)
    elif t == "keyup":
      if kc != KeyNone:
        webInjectEvent(Event(kind: KeyUpEvent, key: kc, mods: mods))

  proc uirJsResizeEvent*(w, h, uiScale: int) {.exportc.} =
    if w != webCore.layout.width or h != webCore.layout.height or uiScale != webCore.layout.uiScale:
      webInjectResize(w, h, uiScale)

  proc uirJsClipboardEvent*(txt: cstring) {.exportc.} =
    webCore.clipboardText = $txt

  proc bindJsBrowserListeners() =
    {.emit: """
    window.__uirRunId = (window.__uirRunId || 0) + 1;
    if (window.__uirTimerId) {
      clearTimeout(window.__uirTimerId);
      window.__uirTimerId = 0;
    }
    window.__uirScheduleFrame = function(cb) {
      window.__uirStepNow = function() { cb(performance.now()); };
      if (window.__uirTimerId) clearTimeout(window.__uirTimerId);
      window.__uirTimerId = setTimeout(function() {
        cb(performance.now());
      }, 16);
    };
    window.__uirActive = {
      mouse: function(evType, x, y, button, clicks, shift, ctrl, alt, meta) {
        uirJsMouseEvent(evType, x, y, button, clicks, shift, ctrl, alt, meta);
        if (evType !== "mousemove" && window.__uirStepNow) window.__uirStepNow();
      },
      wheel: function(dx, dy, shift, ctrl, alt, meta) {
        uirJsWheelEvent(dx, dy, shift, ctrl, alt, meta);
        if (window.__uirStepNow) window.__uirStepNow();
      },
      key: function(evType, keyStr, codeStr, shift, ctrl, alt, meta) {
        uirJsKeyEvent(evType, keyStr, codeStr, shift, ctrl, alt, meta);
        if (window.__uirStepNow) window.__uirStepNow();
      },
      resize: function(w, h, uiScale) {
        uirJsResizeEvent(w, h, uiScale);
        if (window.__uirStepNow) window.__uirStepNow();
      },
      clip: function(txt) {
        uirJsClipboardEvent(txt);
        if (window.__uirStepNow) window.__uirStepNow();
      }
    };
    if (!window.__uirBrowserBound) {
      window.__uirBrowserBound = true;
      var getVp = function() {
        return document.getElementById("uir-viewport") || document.getElementById("uir-canvas");
      };
      var getStage = function() {
        return document.getElementById("uir-stage") || getVp() || document.body;
      };
      var relPos = function(e, el) {
        if (!el) return { x: 0, y: 0 };
        var r = el.getBoundingClientRect();
        return {
          x: Math.round(e.clientX - r.left),
          y: Math.round(e.clientY - r.top)
        };
      };
      var syncViewportSize = function() {
        var st = getStage();
        var vp = getVp();
        if (!vp || !window.__uirActive) return;
        if (window.__uirFixedSizeMode) return;
        var w = st ? (st.clientWidth - 4) : (window.innerWidth - 16);
        var h = st ? (st.clientHeight - 4) : (window.innerHeight - 60);
        w = Math.max(360, Math.floor(w));
        h = Math.max(280, Math.floor(h));
        vp.style.width = w + "px";
        vp.style.height = h + "px";
        if (vp.tagName === "CANVAS") {
          if (vp.width !== w) vp.width = w;
          if (vp.height !== h) vp.height = h;
        }
        window.__uirActive.resize(w, h, 100);
      };
      window.__uirSyncViewportSize = syncViewportSize;

      document.addEventListener("mousedown", function(e) {
        var vp = getVp();
        if (!vp || !window.__uirActive) return;
        if (e.target !== vp && !vp.contains(e.target)) return;
        if (vp.focus) vp.focus();
        var p = relPos(e, vp);
        window.__uirActive.mouse("mousedown", p.x, p.y, e.button || 0, e.detail || 1,
                                 !!e.shiftKey, !!e.ctrlKey, !!e.altKey, !!e.metaKey);
      });
      document.addEventListener("mouseup", function(e) {
        var vp = getVp();
        if (!vp || !window.__uirActive) return;
        var p = relPos(e, vp);
        window.__uirActive.mouse("mouseup", p.x, p.y, e.button || 0, e.detail || 1,
                                 !!e.shiftKey, !!e.ctrlKey, !!e.altKey, !!e.metaKey);
      });
      document.addEventListener("mousemove", function(e) {
        var vp = getVp();
        if (!vp || !window.__uirActive) return;
        var p = relPos(e, vp);
        window.__uirActive.mouse("mousemove", p.x, p.y, e.button || 0, 1,
                                 !!e.shiftKey, !!e.ctrlKey, !!e.altKey, !!e.metaKey);
      });
      document.addEventListener("contextmenu", function(e) {
        var vp = getVp();
        if (vp && (e.target === vp || vp.contains(e.target))) {
          e.preventDefault();
        }
      });
      document.addEventListener("wheel", function(e) {
        var vp = getVp();
        if (!vp || !window.__uirActive || (e.target !== vp && !vp.contains(e.target))) return;
        e.preventDefault();
        var dy = e.deltaY < 0 ? 1 : (e.deltaY > 0 ? -1 : 0);
        var dx = e.deltaX < 0 ? 1 : (e.deltaX > 0 ? -1 : 0);
        window.__uirActive.wheel(dx, dy, !!e.shiftKey, !!e.ctrlKey, !!e.altKey, !!e.metaKey);
      }, { passive: false });

      window.addEventListener("keydown", function(e) {
        if (!window.__uirActive) return;
        var clipIn = document.getElementById("uir-clipboard-input");
        if (clipIn && document.activeElement === clipIn) return;
        if (["Tab", "ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight", "Space", "Backspace"].indexOf(e.code) !== -1) {
          e.preventDefault();
        }
        window.__uirActive.key("keydown", e.key || "", e.code || "",
                               !!e.shiftKey, !!e.ctrlKey, !!e.altKey, !!e.metaKey);
      });
      window.addEventListener("keyup", function(e) {
        if (!window.__uirActive) return;
        var clipIn = document.getElementById("uir-clipboard-input");
        if (clipIn && document.activeElement === clipIn) return;
        window.__uirActive.key("keyup", e.key || "", e.code || "",
                               !!e.shiftKey, !!e.ctrlKey, !!e.altKey, !!e.metaKey);
      });

      var btnClip = document.getElementById("uir-btn-clip-sync");
      if (btnClip) {
        btnClip.addEventListener("click", function() {
          var clipIn = document.getElementById("uir-clipboard-input");
          if (clipIn && window.__uirActive) window.__uirActive.clip(clipIn.value || "");
        });
      }
      var btn960 = document.getElementById("uir-btn-resize-960");
      if (btn960) {
        btn960.addEventListener("click", function() {
          window.__uirFixedSizeMode = true;
          var vp = getVp();
          if (vp) { vp.style.width = "960px"; vp.style.height = "640px"; }
          if (window.__uirActive) window.__uirActive.resize(960, 640, 100);
        });
      }
      var btn800 = document.getElementById("uir-btn-resize-800");
      if (btn800) {
        btn800.addEventListener("click", function() {
          window.__uirFixedSizeMode = true;
          var vp = getVp();
          if (vp) { vp.style.width = "800px"; vp.style.height = "600px"; }
          if (window.__uirActive) window.__uirActive.resize(800, 600, 100);
        });
      }
      var btnAuto = document.getElementById("uir-btn-resize-auto");
      if (btnAuto) {
        btnAuto.addEventListener("click", function() {
          window.__uirFixedSizeMode = false;
          syncViewportSize();
        });
      }

      window.addEventListener("resize", function() {
        window.__uirFixedSizeMode = false;
        syncViewportSize();
      });
      if (typeof ResizeObserver !== "undefined") {
        var ro = new ResizeObserver(function() { syncViewportSize(); });
        var st = getStage();
        if (st) ro.observe(st);
      }
    }
    if (window.__uirSyncViewportSize) {
      setTimeout(window.__uirSyncViewportSize, 0);
    }
    """.}

  proc broadcastSseFrame*() = discard
  proc startWebServer*(preferredPort = 0) =
    discard preferredPort
    bindJsBrowserListeners()
  proc webPumpServer*() = discard
  proc stopWebServer*() = discard
  proc webServerPort*(): int {.inline.} = 0

else:
  proc sleepNs(ns: int) {.inline.} =
    var req = Timespec(
      tv_sec: posix.Time(ns div 1_000_000_000),
      tv_nsec: clong(ns mod 1_000_000_000)
    )
    var rem = Timespec(tv_sec: posix.Time(0), tv_nsec: clong(0))
    discard nanosleep(req, rem)

  proc setFdNonBlocking(fd: SocketHandle) =
    let flags = fcntl(cint(fd), F_GETFL, 0)
    if flags >= 0:
      discard fcntl(cint(fd), F_SETFL, flags or O_NONBLOCK)

  proc sendAllNonBlocking(fd: SocketHandle; data: string): bool =
    if data.len == 0:
      return true
    var sent = 0
    var retries = 0
    while sent < data.len:
      let n = posix.send(fd, unsafeAddr data[sent], data.len - sent,
        when declared(MSG_NOSIGNAL): cint(MSG_NOSIGNAL) else: 0'i32)
      if n > 0:
        sent += n
        retries = 0
      elif n < 0 and (errno == EAGAIN or errno == EWOULDBLOCK):
        inc retries
        if retries > 200:
          return false
        sleepNs(250_000)
      else:
        return false
    result = true

  proc writeHttpResponse(fd: SocketHandle; status: string; contentType: string;
                         body: string; extraHeaders = "") =
    var hdr = "HTTP/1.1 " & status & "\r\n" &
              "Content-Type: " & contentType & "\r\n" &
              "Content-Length: " & $body.len & "\r\n" &
              "Access-Control-Allow-Origin: *\r\n" &
              "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n" &
              "Access-Control-Allow-Headers: Content-Type\r\n" &
              "Cache-Control: no-store, no-cache, must-revalidate\r\n" &
              extraHeaders &
              "Connection: close\r\n\r\n"
    discard sendAllNonBlocking(fd, hdr)
    if body.len > 0:
      discard sendAllNonBlocking(fd, body)

  proc broadcastSseFrame*() =
    if webCore.sseClients.len == 0 or webCore.lastFrameJson.len == 0:
      return
    let msg = "data: " & webCore.lastFrameJson & "\n\n"
    var i = 0
    while i < webCore.sseClients.len:
      if not webCore.sseClients[i].alive:
        discard posix.close(cint(webCore.sseClients[i].fd))
        webCore.sseClients.delete(i)
        continue
      if webCore.sseClients[i].lastSentFrame != webCore.frameId:
        if sendAllNonBlocking(webCore.sseClients[i].fd, msg):
          webCore.sseClients[i].lastSentFrame = webCore.frameId
          inc i
        else:
          discard posix.close(cint(webCore.sseClients[i].fd))
          webCore.sseClients.delete(i)
      else:
        inc i

  proc handleHttpClient(clientFd: SocketHandle) =
    setFdNonBlocking(clientFd)
    var rawReq = newStringOfCap(4096)
    var buf: array[4096, char]
    var headerEnd = -1
    var contentLength = 0

    for attempt in 0 ..< 40:
      let n = posix.recv(clientFd, addr buf[0], buf.len, 0)
      if n > 0:
        let oldLen = rawReq.len
        rawReq.setLen(oldLen + n)
        for i in 0 ..< n:
          rawReq[oldLen + i] = buf[i]
        if headerEnd < 0:
          headerEnd = rawReq.find("\r\n\r\n")
          if headerEnd >= 0:
            let hdrPart = rawReq[0 ..< headerEnd]
            for line in hdrPart.splitLines():
              let lower = line.toLowerAscii()
              if lower.startsWith("content-length:"):
                try:
                  contentLength = parseInt(strutils.strip(line[15 .. ^1]))
                except ValueError:
                  contentLength = 0
        if headerEnd >= 0 and rawReq.len >= headerEnd + 4 + contentLength:
          break
      elif n == 0:
        break
      else:
        if errno == EAGAIN or errno == EWOULDBLOCK:
          if headerEnd >= 0 and rawReq.len >= headerEnd + 4 + contentLength:
            break
          sleepNs(200_000)
        else:
          break

    if rawReq.len == 0:
      discard posix.close(cint(clientFd))
      return

    let firstLineEnd = rawReq.find("\r\n")
    let firstLine = if firstLineEnd >= 0: rawReq[0 ..< firstLineEnd] else: rawReq
    let parts = strutils.splitWhitespace(firstLine)
    if parts.len < 2:
      discard posix.close(cint(clientFd))
      return

    let httpMethod = parts[0].toUpperAscii()
    let fullPath = parts[1]
    let qIdx = fullPath.find('?')
    let pathOnly = if qIdx >= 0: fullPath[0 ..< qIdx] else: fullPath
    let body = if headerEnd >= 0 and headerEnd + 4 <= rawReq.len:
                 rawReq[headerEnd + 4 .. ^1]
               else:
                 ""

    if httpMethod == "OPTIONS":
      writeHttpResponse(clientFd, "204 No Content", "text/plain", "")
      discard posix.close(cint(clientFd))
      return

    case pathOnly
    of "/", "/index.html":
      writeHttpResponse(clientFd, "200 OK", "text/html; charset=utf-8", webCore.pageHtml)
      discard posix.close(cint(clientFd))

    of "/state", "/frame":
      let payload = if webCore.lastFrameJson.len > 0:
                      webCore.lastFrameJson
                    else:
                      """{"frameId":0,"backend":"""" & $webCore.backendKind & """"}"""
      writeHttpResponse(clientFd, "200 OK", "application/json; charset=utf-8", payload)
      discard posix.close(cint(clientFd))

    of "/health":
      let healthObj = %*{
        "ok": true,
        "backend": $webCore.backendKind,
        "port": webCore.serverPort,
        "frameId": webCore.frameId,
        "totalFramesRendered": webCore.totalFramesRendered,
        "totalEventsProcessed": webCore.totalEventsProcessed,
        "queuedEvents": webCore.eventQueue.len,
        "width": webCore.layout.width,
        "height": webCore.layout.height,
        "uiScale": webCore.layout.uiScale,
        "title": webCore.windowTitle,
        "cursor": cursorToCss(webCore.currentCursor),
        "clipboard": webCore.clipboardText,
        "wantTextInput": webCore.wantTextInput,
        "domNodeCount": webCore.domNodeCount,
        "canvasCommandCount": webCore.canvasCommandCount
      }
      writeHttpResponse(clientFd, "200 OK", "application/json; charset=utf-8", $healthObj)
      discard posix.close(cint(clientFd))

    of "/input":
      if httpMethod == "POST":
        let added = parseIncomingInputJson(body)
        let resp = """{"ok":true,"added":""" & $added & ""","queued":""" & $webCore.eventQueue.len & "}"
        writeHttpResponse(clientFd, "200 OK", "application/json; charset=utf-8", resp)
      else:
        writeHttpResponse(clientFd, "405 Method Not Allowed", "application/json", """{"error":"Use POST"}""")
      discard posix.close(cint(clientFd))

    of "/monkey-report":
      if httpMethod == "POST":
        webCore.monkeyReportJson = body
        writeHttpResponse(clientFd, "200 OK", "application/json; charset=utf-8", """{"ok":true}""")
      else:
        let rep = if webCore.monkeyReportJson.len > 0: webCore.monkeyReportJson else: """{"ready":false}"""
        writeHttpResponse(clientFd, "200 OK", "application/json; charset=utf-8", rep)
      discard posix.close(cint(clientFd))

    of "/events":
      let sseHdr = "HTTP/1.1 200 OK\r\n" &
                   "Content-Type: text/event-stream; charset=utf-8\r\n" &
                   "Cache-Control: no-cache, no-transform\r\n" &
                   "Connection: keep-alive\r\n" &
                   "Access-Control-Allow-Origin: *\r\n\r\n"
      if sendAllNonBlocking(clientFd, sseHdr):
        var sentFrame = 0
        if webCore.lastFrameJson.len > 0:
          if sendAllNonBlocking(clientFd, "data: " & webCore.lastFrameJson & "\n\n"):
            sentFrame = webCore.frameId
        webCore.sseClients.add SseClient(
          fd: clientFd,
          lastSentFrame: sentFrame,
          alive: true
        )
      else:
        discard posix.close(cint(clientFd))

    else:
      writeHttpResponse(clientFd, "404 Not Found", "application/json; charset=utf-8",
        """{"error":"Not found","path":"""" & htmlEscape(pathOnly) & """"}""")
      discard posix.close(cint(clientFd))

  proc startWebServer*(preferredPort = 0) =
    if webCore.listenFd != osInvalidSocket and cint(webCore.listenFd) > 0:
      return

    if getEnv("UIRELAYS_NO_SERVER", "") == "1":
      webCore.serverEnabled = false
      return

    var basePort = preferredPort
    if basePort <= 0:
      let envPort = getEnv("UIRELAYS_PORT", "")
      if envPort.len > 0:
        try:
          basePort = parseInt(envPort)
        except ValueError:
          basePort = 8080
      else:
        basePort = 8080

    let sock = createNativeSocket(Domain.AF_INET, SockType.SOCK_STREAM, Protocol.IPPROTO_TCP)
    if sock == osInvalidSocket:
      webCore.serverEnabled = false
      return

    var optVal: cint = 1
    discard posix.setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, addr optVal, SockLen(sizeof(optVal)))
    setFdNonBlocking(sock)

    var boundPort = 0
    for offset in 0 ..< 30:
      let candidate = basePort + offset
      var sa: Sockaddr_in
      zeroMem(addr sa, sizeof(sa))
      sa.sin_family = typeof(sa.sin_family)(AF_INET)
      sa.sin_port = posix.htons(uint16(candidate))
      sa.sin_addr.s_addr = posix.htonl(INADDR_ANY)
      if bindSocket(sock, cast[ptr SockAddr](addr sa), SockLen(sizeof(sa))) == 0'i32:
        if posix.listen(sock, SOMAXCONN) == 0'i32:
          boundPort = candidate
          break

    if boundPort == 0:
      discard posix.close(cint(sock))
      webCore.serverEnabled = false
      return

    webCore.listenFd = sock
    webCore.serverPort = boundPort
    webCore.serverEnabled = true

  proc webPumpServer*() =
    if not webCore.serverEnabled or webCore.listenFd == osInvalidSocket:
      return
    for _ in 0 ..< 16:
      var clientSa: Sockaddr_in
      var clientLen = SockLen(sizeof(clientSa))
      let clientFd = posix.accept(webCore.listenFd, cast[ptr SockAddr](addr clientSa), addr clientLen)
      if clientFd == osInvalidSocket or cint(clientFd) < 0:
        break
      handleHttpClient(clientFd)

  proc stopWebServer*() =
    for c in webCore.sseClients:
      if c.alive and c.fd != osInvalidSocket:
        discard posix.close(cint(c.fd))
    webCore.sseClients.setLen(0)
    if webCore.listenFd != osInvalidSocket and cint(webCore.listenFd) > 0:
      discard posix.close(cint(webCore.listenFd))
      webCore.listenFd = osInvalidSocket
    webCore.serverEnabled = false

  proc webServerPort*(): int {.inline.} =
    webCore.serverPort

# ---------------------------------------------------------------------------
# Shared Timing & Event Loop Relays
# ---------------------------------------------------------------------------

proc webGetTicks*(): int =
  when defined(js):
    int(jsPerformanceNow() - webCore.startMs)
  else:
    let elapsedNs = (getMonoTime() - webCore.startMono).inNanoseconds
    int(elapsedNs div 1_000_000)

proc webSleep*(ms: int) =
  when defined(js):
    discard ms
  else:
    if ms <= 0:
      webPumpServer()
      return
    let deadline = webGetTicks() + ms
    while true:
      webPumpServer()
      let remaining = deadline - webGetTicks()
      if remaining <= 0:
        break
      let stepMs = min(remaining, 2)
      sleepNs(stepMs * 1_000_000)

proc popNextMatchingEvent(e: var Event; flags: set[InputFlag]): bool =
  webCore.wantTextInput = WantTextInput in flags
  var idx = 0
  while idx < webCore.eventQueue.len:
    let ev = webCore.eventQueue[idx]
    webCore.eventQueue.delete(idx)
    if ev.kind == TextInputEvent and WantTextInput notin flags:
      continue
    e = ev
    inc webCore.totalEventsProcessed
    return true
  return false

proc webPollEvent*(e: var Event; flags: set[InputFlag]): bool =
  webPumpServer()
  popNextMatchingEvent(e, flags)

proc webWaitEvent*(e: var Event; timeoutMs: int; flags: set[InputFlag]): bool =
  when defined(js):
    discard timeoutMs
    return webPollEvent(e, flags)
  else:
    if webPollEvent(e, flags):
      return true
    if timeoutMs == 0:
      return false
    let deadline = if timeoutMs < 0: high(int) else: webGetTicks() + timeoutMs
    while true:
      webPumpServer()
      if popNextMatchingEvent(e, flags):
        return true
      if timeoutMs >= 0 and webGetTicks() >= deadline:
        return false
      sleepNs(1_000_000)

proc initWebCore*(kind: WebBackendKind; pageHtml: string) =
  stopWebServer()
  when defined(js):
    webCore = WebCoreState(
      backendKind: kind,
      initialized: true,
      startMs: jsPerformanceNow(),
      layout: ScreenLayout(width: 800, height: 600, scaleX: 1, scaleY: 1, uiScale: 100),
      windowTitle: "UIRelays Web (" & $kind & ")",
      currentCursor: curDefault,
      clipboardText: "",
      wantTextInput: false,
      clipStack: @[],
      currentClip: WebClipState(enabled: false),
      fonts: @[],
      images: @[],
      eventQueue: @[],
      frameId: 0,
      lastPayloadHash: 0'u64,
      lastFrameJson: "",
      pageHtml: pageHtml
    )
  else:
    webCore = WebCoreState(
      backendKind: kind,
      initialized: true,
      startMono: getMonoTime(),
      layout: ScreenLayout(width: 800, height: 600, scaleX: 1, scaleY: 1, uiScale: 100),
      windowTitle: "UIRelays Web (" & $kind & ")",
      currentCursor: curDefault,
      clipboardText: "",
      wantTextInput: false,
      clipStack: @[],
      currentClip: WebClipState(enabled: false),
      fonts: @[],
      images: @[],
      eventQueue: @[],
      frameId: 0,
      lastPayloadHash: 0'u64,
      lastFrameJson: "",
      pageHtml: pageHtml,
      listenFd: osInvalidSocket,
      sseClients: @[]
    )

proc webCreateWindowCommon*(layout: var ScreenLayout; icon: pointer; iconLen: int) =
  discard icon
  discard iconLen
  var reqW = if layout.width <= 0: 1024 else: layout.width
  var reqH = if layout.height <= 0: 768 else: layout.height
  when defined(js):
    {.emit: """
    var st = document.getElementById("uir-stage");
    if (st && st.clientWidth > 300 && st.clientHeight > 220 && !window.__uirFixedSizeMode) {
      `reqW` = Math.floor(st.clientWidth - 4);
      `reqH` = Math.floor(st.clientHeight - 4);
    }
    """.}
  layout.width = reqW
  layout.height = reqH
  if layout.scaleX <= 0: layout.scaleX = 1
  if layout.scaleY <= 0: layout.scaleY = 1
  if layout.uiScale <= 0: layout.uiScale = 100
  webCore.layout = layout
  webCore.clipStack.setLen(0)
  webCore.currentClip = WebClipState(enabled: false)
  startWebServer()

proc webShutdownCommon*() =
  stopWebServer()
  webCore.clipStack.setLen(0)
  webCore.currentClip = WebClipState(enabled: false)
  webCore.fonts.setLen(0)
  webCore.images.setLen(0)
  webCore.eventQueue.setLen(0)
