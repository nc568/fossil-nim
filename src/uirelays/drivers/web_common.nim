# Shared pure-Nim (--mm:arc) web protocol, non-blocking HTTP/SSE server,
# input queue, font/image/PNG helpers, and state management for UIRelays
# Web Backends (html_driver and canvas_driver).
#
# Zero external dependencies, zero WebAssembly, 100% Nim standard library.

import std/[strutils, base64]
when not defined(js):
  import std/[json, monotimes, times, os, nativesockets]
  # posix and winlean both define SocketHandle, so importing posix on Windows
  # makes every socket symbol ambiguous and the web backends do not compile
  # there at all. Each platform imports its own; the remaining differences
  # (names, argument types, error reporting, byte order) are collected in the
  # shim below instead of being scattered through the server as `when`s.
  when defined(windows):
    import std/winlean
  else:
    import std/posix
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
    cssFont*: string
    size*: int
    style*: FontStyles
    metrics*: FontMetrics
    charWidth*: int
    isMonospace*: bool

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
    minViewportW*: int          ## floor the application asked for (0 = none)
    minViewportH*: int
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
    droppedEvents*: int
    inputParseErrors*: int
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

proc fnv1a64Step*(h: uint64; s: string): uint64 {.inline.} =
  ## Folds `s` into a running FNV-1a hash. Lets a caller hash a structured
  ## frame without concatenating it into one throwaway string first.
  when defined(js):
    var g = uint32(h and 0xFFFFFFFF'u64)
    for i in 0 ..< s.len:
      g = g xor uint32(ord(s[i]))
      g = uint32((uint64(g) * 16777619'u64) and 0xFFFFFFFF'u64)
    result = uint64(g)
  else:
    result = h
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

# ---------------------------------------------------------------------------
# blitRGBA: PNG payload, and the two reasons it is not written the obvious way
# ---------------------------------------------------------------------------
#
# 1. The JS backend cannot index a `ptr UncheckedArray[T]` at all: it is an
#    internal compiler error, `expr(nkBracketExpr, tyUncheckedArray)`. That is
#    why this encoder used to start with `when defined(js): return @[]`, which
#    made `blitRGBA` a silent no-op in every standalone (`nim js`) page: the
#    relay reported `false` and drew nothing, so an app that bakes a
#    background once and blits it per frame had no background at all in the
#    browser while working natively. On the JS backend a pointer *parameter*
#    is split into two ABI slots -- the base array and the element offset --
#    and `arguments` is the only place where both are visible, so
#    `jsPixelWords` reads them from there and hands the encoder a plain
#    `seq[uint32]`. The encoder itself is generic over the pixel accessor, so
#    the C path still indexes the pointer with zero copy.
#    `tests/portability_math_test.nim` pins the produced PNG bytes to one
#    golden digest on both backends: a Nim upgrade that moves this ABI fails a
#    test instead of quietly blitting garbage.
#
# 2. "Bake it once, blit it every frame" is the only sane way to draw a rich
#    static background with `blitRGBA`, and it used to cost a full PNG +
#    base64 encode *per call*: 90 ms and a 3,496,486 character string for a
#    1024x640 buffer, measured, every frame, forever -- and in server mode
#    that string was additionally JSON escaped and pushed over SSE to every
#    client on every frame. The bytes cannot have changed unless the pixels
#    changed, so the payload is keyed by a fingerprint of the content and
#    reused. Fingerprinting costs under a millisecond, ~100x less.

proc mul32(a, b: uint32): uint32 {.inline.} =
  ## The low 32 bits of `a * b`, computed so that no intermediate exceeds
  ## 2^53. A bare `a * b` is exact on the C backend and *lossy* on the JS one,
  ## because there a uint32 lives in a double: measured, the same expression
  ## yields 4262848038 natively and 2293536820 in the browser. Every hash in
  ## this file goes through here for that reason.
  let lo = (a and 0xFFFF'u32) * b
  let hi = ((a shr 16) * b) and 0xFFFF'u32
  (lo and 0xFFFFFFFF'u32) + (hi shl 16)

when defined(js):
  proc jsPixelWords(p: pointer; n: int): seq[uint32] =
    ## Materialises the `n` pixels a JS pointer pair refers to. `arguments[0]`
    ## is the base array, `arguments[1]` the element offset and
    ## `arguments[2]` the next Nim parameter (`n`), because the JS backend
    ## passes a pointer as two slots.
    result = newSeq[uint32](n)
    {.emit: """
      var base = arguments[0];
      var off  = arguments[1];
      var cnt  = arguments[2];
      if (base && typeof off === "number") {
        for (var i = 0; i < cnt; ++i) { `result`[i] = base[off + i]; }
      }
    """.}

type BlitFp = tuple[a, b: uint32; w, h: int]

proc blitFingerprintCore[P](px: P; w, h: int): BlitFp =
  ## Two independent 32-bit hashes over the buffer. One would not do: a
  ## collision means silently publishing a stale picture, and 2^-32 per blit
  ## is far too likely to ignore. Together they are 2^-64.
  var a = 2166136261'u32
  var b = 2166136261'u32 xor 0x9E3779B9'u32
  let n = w * h
  for i in 0 ..< n:
    let word = px[i]
    a = mul32(a xor word, 16777619'u32)
    a = a xor (a shr 13)
    b = mul32(b xor ((word shr 16) or ((word and 0xFFFF'u32) shl 16)),
              1099511629'u32)
    b = b xor (b shr 17)
  result = (a, b, w, h)

type BlitCacheEntry = object
  fp: BlitFp
  uri: string
  live: bool

# Two slots: one covers the ordinary "single baked background" app, the second
# covers an app alternating between two buffers. Anything past that thrashes
# and simply re-encodes, which is exactly the old behaviour -- never worse.
var
  blitCache: array[2, BlitCacheEntry]
  blitCacheNext = 0
  blitCacheHitsTotal = 0
  blitCacheMissTotal = 0

proc encodePngCore[P](px: P; w, h: int): seq[uint8] =
  ## `w x h` 32-bit pixels (`0xAARRGGBB`, or `0x00RRGGBB` which is treated as
  ## opaque) into an uncompressed PNG byte stream, in pure Nim.
  if w <= 0 or h <= 0:
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
      let word = px[rowOffset + x]
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

# ---------------------------------------------------------------------------
# blitRGBA payload cache
# ---------------------------------------------------------------------------
#
# "Bake it once, blit it every frame" is the only sane way to draw a rich
# static background with `blitRGBA`, and it used to cost a full PNG + base64
# encode *per call*: 90 ms and a 3,496,486 character string for a 1024x640
# buffer, measured, every single frame, forever. In server mode that string
# was additionally JSON-escaped and pushed over SSE to every client per frame.
# The bytes cannot have changed unless the pixels changed, so the payload is
# keyed by a fingerprint of the content and reused. Fingerprinting the same
# buffer costs under a millisecond, ~100x less than encoding it.
#
# The fingerprint deliberately never uses a bare 32-bit `*`. `nim js` computes
# uint32 multiplies in a double, so every bit above 2^53 is lost and a plain
# FNV would fingerprint the very same buffer differently in the browser and
# natively -- measured: 4262848038 vs 2293536820. `mul32` splits the multiply
# into 16-bit halves and is bit-identical on the C and the JS backend.

proc encodeRgbaToPngBytes*(pixels: ptr UncheckedArray[uint32]; w, h: int): seq[uint8] =
  ## Encodes a `w x h` buffer of 32-bit pixels (`0xAARRGGBB` or `0x00RRGGBB`
  ## as passed to `blitRGBA` in uirelays) into a valid PNG byte stream in pure
  ## Nim. Works on the C and on the JS backend.
  when not defined(js):
    if pixels == nil: return @[]
  if w <= 0 or h <= 0:
    return @[]
  when defined(js):
    encodePngCore(jsPixelWords(cast[pointer](pixels), w * h), w, h)
  else:
    encodePngCore(pixels, w, h)

proc dataUriCore[P](px: P; w, h: int): string =
  let fp = blitFingerprintCore(px, w, h)
  for i in 0 ..< blitCache.len:
    if blitCache[i].live and blitCache[i].fp == fp:
      inc blitCacheHitsTotal
      return blitCache[i].uri
  inc blitCacheMissTotal
  let pngBytes = encodePngCore(px, w, h)
  if pngBytes.len == 0:
    return ""
  var s = newString(pngBytes.len)
  for i in 0 ..< pngBytes.len:
    s[i] = char(pngBytes[i])
  result = "data:image/png;base64," & base64.encode(s)
  blitCache[blitCacheNext] = BlitCacheEntry(fp: fp, uri: result, live: true)
  blitCacheNext = (blitCacheNext + 1) mod blitCache.len

proc encodeRgbaToPngDataUri*(pixels: ptr UncheckedArray[uint32]; w, h: int): string =
  when not defined(js):
    if pixels == nil: return ""
  if w <= 0 or h <= 0:
    return ""
  when defined(js):
    dataUriCore(jsPixelWords(cast[pointer](pixels), w * h), w, h)
  else:
    dataUriCore(pixels, w, h)

proc blitCacheStats*(): tuple[hits, misses, live: int] =
  ## Test hook: proves the cache actually absorbs a repeated blit instead of
  ## re-encoding it, and that it never grows past its two slots.
  var live = 0
  for e in blitCache:
    if e.live: inc live
  (blitCacheHitsTotal, blitCacheMissTotal, live)


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

proc isMonospaceFontPath*(path: string): bool =
  if path.len == 0:
    return true
  let lp = path.toLowerAscii()
  if "mono" in lp or "consolas" in lp or "courier" in lp or
     "fira code" in lp or "jetbrains" in lp or "menlo" in lp or
     "iosevka" in lp or "hack" in lp or "source code" in lp or
     "fixed" in lp or "term" in lp:
    return true
  if "sans" in lp or "serif" in lp or "arial" in lp or "inter" in lp or
     "helvetica" in lp or "roboto" in lp or "segoe" in lp or "system-ui" in lp or
     "ubuntu" in lp or "noto" in lp or "cantarell" in lp or "georgia" in lp or
     "times" in lp or "verdana" in lp or "tahoma" in lp or "trebuchet" in lp:
    return false
  if '/' in path or '\\' in path or lp.endsWith(".ttf") or lp.endsWith(".otf"):
    return true
  return false

proc webOpenFont*(path: string; size: int; style: FontStyles;
                  metrics: var FontMetrics): Font =
  let pxSize = max(6, size)
  let baseCharW = max(4, int(float(pxSize) * 0.6 + 0.5))
  let charW = baseCharW
  let ascent = max(4, int(float(pxSize) * 0.8 + 0.5))
  let descent = max(2, int(float(pxSize) * 0.25 + 0.5))
  let lineHeight = ascent + descent + max(2, pxSize div 8)

  metrics = FontMetrics(
    ascent: ascent,
    descent: descent,
    lineHeight: lineHeight
  )

  let isMono = isMonospaceFontPath(path)
  let lp = path.toLowerAscii()
  let family =
    if isMono:
      if path.len == 0 or '/' in path or '\\' in path or lp.endsWith(".ttf") or lp.endsWith(".otf"):
        "'DejaVu Sans Mono', 'JetBrains Mono', 'Fira Code', 'Liberation Mono', Consolas, monospace"
      else:
        path & ", 'DejaVu Sans Mono', Consolas, monospace"
    else:
      if "serif" in lp and "sans" notin lp:
        path & ", 'DejaVu Serif', Georgia, serif"
      elif '/' in path or '\\' in path or lp.endsWith(".ttf") or lp.endsWith(".otf"):
        "'DejaVu Sans', 'Liberation Sans', Inter, system-ui, sans-serif"
      else:
        path & ", 'DejaVu Sans', 'Liberation Sans', Inter, system-ui, sans-serif"

  var cssFont = ""
  if FontStyle.italics in style:
    cssFont.add "italic "
  if FontStyle.bold in style:
    cssFont.add "700 "
  cssFont.add $pxSize & "px " & family

  webCore.fonts.add WebFontSlot(
    active: true,
    path: path,
    family: family,
    cssFont: cssFont,
    size: pxSize,
    style: style,
    metrics: metrics,
    charWidth: charW,
    isMonospace: isMono
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
    cssFont: "15px 'DejaVu Sans Mono', Consolas, monospace",
    size: 15,
    metrics: FontMetrics(ascent: 12, descent: 4, lineHeight: 18),
    charWidth: 9,
    isMonospace: true
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

proc proportionalCodePermille(code: int): int {.inline.} =
  ## Calibrated glyph advance in thousandths of em (1000 = 1.0 * pxSize)
  ## for proportional sans/serif fonts (DejaVu Sans / Liberation Sans / Inter).
  case code
  of ord(' '), ord('\t'): 318
  of ord('i'), ord('l'), ord('I'), ord('|'), ord('!'), ord('.'), ord(','),
     ord(':'), ord(';'), ord('\''), ord('`'): 295
  of ord('j'), ord('f'), ord('t'), ord('r'), ord('('), ord(')'),
     ord('['), ord(']'), ord('{'), ord('}'), ord('"'), ord('-'), ord('/'), ord('\\'): 375
  of ord('c'), ord('s'), ord('v'), ord('x'), ord('z'), ord('J'), ord('1'): 510
  of ord('m'), ord('w'): 920
  of ord('M'), ord('W'), ord('@'), ord('%'): 940
  of ord('G'), ord('O'), ord('Q'), ord('D'), ord('H'), ord('N'), ord('U'), ord('&'), ord('#'): 735
  of ord('A')..ord('C'), ord('E')..ord('F'), ord('K')..ord('L'), ord('P'),
     ord('R')..ord('T'), ord('V'), ord('X')..ord('Z'): 665
  else:
    if isWideCode(code): 1000
    elif code >= 0x0410 and code <= 0x042F:
      # Cyrillic uppercase (Ж, Ш, Щ, Ю, М, Ф are wider)
      if code in [0x0416, 0x041C, 0x0424, 0x0428, 0x0429, 0x042B, 0x042E]: 880
      else: 685
    elif code >= 0x0430 and code <= 0x044F:
      # Cyrillic lowercase (ж, ш, щ, ю, м, ф, ы are wider)
      if code in [0x0436, 0x043C, 0x0444, 0x0448, 0x0449, 0x044B, 0x044E]: 780
      else: 575
    else:
      570

proc measureProportionalFallback(text: string; pxSize: int; isBold: bool): int =
  var totalPermille = 0
  var i = 0
  while i < text.len:
    let (code, step) = utf8CodeAt(text, i)
    totalPermille += proportionalCodePermille(code)
    i += step
  if isBold:
    totalPermille = (totalPermille * 106) div 100
  result = (totalPermille * pxSize + 999) div 1000

when defined(js):
  proc jsMeasureProportionalText(fontCs, textCs: cstring): int =
    ## Real advance width of `text` in `font`, measured the way the browser is
    ## about to draw it: a hidden span, positioned off-screen, in the same
    ## font, measured with `getBoundingClientRect`. No <canvas> -- the HTML
    ## backend is not allowed one -- and no WebAssembly.
    ##
    ## Results are cached by (font, text): a layout pass measures thousands of
    ## strings per frame, and each cache miss costs a style recalculation.
    {.emit: """
    if (!window.__uirMeasureCache) {
      window.__uirMeasureCache = (typeof Map === "function") ? new Map() : null;
      window.__uirMeasureObj = {};
      window.__uirMeasureCount = 0;
    }
    var key = `fontCs` + "\x1f" + `textCs`;
    if (window.__uirMeasureCache) {
      var cached = window.__uirMeasureCache.get(key);
      if (cached !== undefined) { `result` = cached; return `result`; }
    } else if (window.__uirMeasureObj[key] !== undefined) {
      `result` = window.__uirMeasureObj[key];
      return `result`;
    }
    `result` = 0;
    try {
      var span = document.getElementById("uir-measure-span");
      if (!span) {
        span = document.createElement("span");
        span.id = "uir-measure-span";
        // off-screen, but laid out: visibility:hidden still measures,
        // display:none would not.
        span.setAttribute("style",
          "position:absolute;left:-9999px;top:0;visibility:hidden;" +
          "white-space:pre;font-variant-ligatures:none;letter-spacing:normal;" +
          "padding:0;margin:0;border:0;");
        if (document.body) document.body.appendChild(span);
      }
      span.style.font = `fontCs`;
      span.textContent = `textCs`;
      var rect = span.getBoundingClientRect();
      if (rect && rect.width > 0) `result` = Math.ceil(rect.width);
    } catch (_) { `result` = 0; }
    if (`result` > 0) {
      if (window.__uirMeasureCache) {
        if (window.__uirMeasureCache.size > 16384) window.__uirMeasureCache.clear();
        window.__uirMeasureCache.set(key, `result`);
      } else {
        if (window.__uirMeasureCount > 16384) { window.__uirMeasureObj = {}; window.__uirMeasureCount = 0; }
        window.__uirMeasureObj[key] = `result`;
        window.__uirMeasureCount++;
      }
    }
    """.}

proc webMeasureText*(f: Font; text: string): TextExtent =
  let idx = int(f) - 1
  if idx < 0 or idx >= webCore.fonts.len or not webCore.fonts[idx].active or text.len == 0:
    return TextExtent(w: 0, h: 0)
  let slot = webCore.fonts[idx]
  if not slot.isMonospace:
    when defined(js):
      let w = jsMeasureProportionalText(cstring(slot.cssFont), cstring(text))
      if w > 0:
        return TextExtent(w: w, h: slot.metrics.lineHeight)
    return TextExtent(
      w: measureProportionalFallback(text, slot.size, FontStyle.bold in slot.style),
      h: slot.metrics.lineHeight
    )
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

proc webSetMinViewport*(w, h: int) =
  ## Publishes the application's floor and re-measures at once, so the very
  ## first frame is drawn at a size the app can actually lay out.
  webCore.minViewportW = max(0, w)
  webCore.minViewportH = max(0, h)
  when defined(js):
    let wv = webCore.minViewportW
    let hv = webCore.minViewportH
    {.emit: """
    window.__uirAppMinViewport = { w: `wv`, h: `hv` };
    if (typeof window.__uirSyncViewportSize === "function") {
      window.__uirSyncViewportSize();
    }
    """.}

proc webSetCursor*(c: CursorKind) =
  webCore.currentCursor = c

proc webSetWindowTitle*(title: string) =
  webCore.windowTitle = title
  when defined(js):
    # The HUD label is only part of it: a browser tab that keeps showing the
    # initial title looks like a frozen app.
    let titleCs = cstring(title)
    {.emit: """
    if (typeof window.__uirSetTitle === "function") {
      window.__uirSetTitle(`titleCs`);
    } else if (typeof document !== "undefined") {
      document.title = `titleCs`;
    }
    """.}

proc webGetWindowLayout*(): ScreenLayout =
  webCore.layout

proc webGetClipboardText*(): string =
  webCore.clipboardText

proc webPutClipboardText*(text: string) =
  webCore.clipboardText = text
  when defined(js):
    # Copy has to leave the page: an app that calls `putClipboardText` on
    # Ctrl+C expects Ctrl+V in another program to paste it.
    let textCs = cstring(text)
    {.emit: """
    if (typeof window.__uirCopyToSystem === "function") window.__uirCopyToSystem(`textCs`);
    """.}

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

const webEventQueueLimit* = 4096
  ## How many events may wait for the app. Past that, something has to give.

proc webInjectEvent*(e: Event) =
  if e.kind == MouseMoveEvent and webCore.eventQueue.len > 0 and
     webCore.eventQueue[^1].kind == MouseMoveEvent:
    webCore.eventQueue[^1] = e
    return
  if webCore.eventQueue.len < webEventQueueLimit:
    webCore.eventQueue.add e
    return
  # The queue is full, so something has to be dropped. It must not be the
  # event that arrived: dropping a mouseup leaves the app convinced the button
  # is still held, and it stays stuck mid-drag for good. Position updates are
  # the cheapest thing to lose, so displace the oldest of those instead.
  for i in 0 ..< webCore.eventQueue.len:
    if webCore.eventQueue[i].kind == MouseMoveEvent:
      webCore.eventQueue.delete(i)
      webCore.eventQueue.add e
      inc webCore.droppedEvents
      return
  inc webCore.droppedEvents

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
  # The application's own floor raises the built-in one: a browser may offer
  # less room than the app can draw in, but the app still has to be handed a
  # size it can lay out, or it renders interface nobody can reach.
  let floorW = max(120, webCore.minViewportW)
  let floorH = max(120, webCore.minViewportH)
  let clampedW = clamp(w, floorW, max(floorW, 4096))
  let clampedH = clamp(h, floorH, max(floorH, 4096))
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
      # Swallowing a malformed body is right -- one bad POST must not kill the
      # app -- but silently is not: the client has no way to tell "rejected"
      # from "accepted and had no effect".
      inc webCore.inputParseErrors
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
    # Each backend owns a different viewport id, and an HTML page must never
    # be asked to provide a `<canvas>` it is not allowed to draw into.
    when defined(canvas):
      {.emit: """var __uirShellViewportId = "uir-canvas";""".}
    else:
      {.emit: """var __uirShellViewportId = "uir-viewport";""".}
    # The canvas build has to size a backing store; the HTML build is not
    # allowed to touch a canvas at all, so the two get different helpers.
    when defined(canvas):
      {.emit: """
    var __uirApplyViewportBox = function(vp, w, h) {
      // Retina: CSS pixels for layout, device pixels for the backing store.
      var dpr = window.devicePixelRatio || 1;
      if (!(dpr > 0)) dpr = 1;
      var bw = Math.max(1, Math.round(w * dpr));
      var bh = Math.max(1, Math.round(h * dpr));
      if (vp.width !== bw) vp.width = bw;
      if (vp.height !== bh) vp.height = bh;
      vp.style.width = w + "px";
      vp.style.height = h + "px";
      window.__uirDpr = dpr;
      var ctx = null;
      try { ctx = vp.__uirCtx || (vp.getContext ? vp.getContext("2d") : null); } catch (_) {}
      if (ctx && typeof ctx.setTransform === "function") ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    };
    """.}
    else:
      {.emit: """
    var __uirApplyViewportBox = function(vp, w, h) {
      vp.style.width = w + "px";
      vp.style.height = h + "px";
    };
    """.}
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
        window.__uirTimerId = 0;
        cb(performance.now());
      }, 16);
    };
    // At most one step per animation frame. Input arrives in bursts -- a wheel
    // spinning, a key held down, a fast drag -- and running a whole frame
    // synchronously per event makes the queue grow faster than it drains.
    window.__uirRequestStep = function() {
      if (window.__uirStepPending || !window.__uirStepNow) return;
      window.__uirStepPending = true;
      var run = function() {
        window.__uirStepPending = false;
        if (window.__uirStepNow) window.__uirStepNow();
      };
      if (typeof window.requestAnimationFrame === "function" && !document.hidden) {
        window.requestAnimationFrame(run);
      } else {
        setTimeout(run, 0);
      }
    };
    // `setWindowTitle` must reach the tab, not only the HUD label.
    window.__uirSetTitle = function(title) {
      var suffix = (typeof window.__uirTitleSuffix === "string") ? window.__uirTitleSuffix : "";
      var next = "" + title + suffix;
      if (typeof document !== "undefined" && document.title !== next) document.title = next;
    };
    // `putClipboardText` must reach the system clipboard, not only our state.
    window.__uirCopyFallback = function(txt) {
      try {
        var ta = document.getElementById("uir-clipboard-offscreen");
        if (!ta) {
          ta = document.createElement("textarea");
          ta.id = "uir-clipboard-offscreen";
          ta.setAttribute("style", "position:fixed;left:-9999px;top:0;width:1px;height:1px;opacity:0;");
          if (document.body) document.body.appendChild(ta);
        }
        ta.value = txt;
        if (ta.select) ta.select();
        if (document.execCommand) document.execCommand("copy");
      } catch (_) {}
    };
    window.__uirCopyToSystem = function(txt) {
      try {
        var el = document.getElementById("uir-clipboard-input");
        if (el && document.activeElement !== el) el.value = txt;
      } catch (_) {}
      try {
        if (typeof navigator !== "undefined" && navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard.writeText(txt).then(null, function() { window.__uirCopyFallback(txt); });
          return;
        }
      } catch (_) {}
      window.__uirCopyFallback(txt);
    };
    window.__uirActive = {
      mouse: function(evType, x, y, button, clicks, shift, ctrl, alt, meta) {
        uirJsMouseEvent(evType, x, y, button, clicks, shift, ctrl, alt, meta);
        window.__uirRequestStep();
      },
      wheel: function(dx, dy, shift, ctrl, alt, meta) {
        uirJsWheelEvent(dx, dy, shift, ctrl, alt, meta);
        window.__uirRequestStep();
      },
      key: function(evType, keyStr, codeStr, shift, ctrl, alt, meta) {
        uirJsKeyEvent(evType, keyStr, codeStr, shift, ctrl, alt, meta);
        window.__uirRequestStep();
      },
      resize: function(w, h, uiScale) {
        uirJsResizeEvent(w, h, uiScale);
        window.__uirRequestStep();
      },
      clip: function(txt) {
        uirJsClipboardEvent(txt);
        window.__uirRequestStep();
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
      // The shell contract is a handful of ids. When one is missing the
      // matching feature silently does nothing, which costs an evening to
      // find; say so once, on the console, at startup.
      (function reportShellContract() {
        // The two backends need different ids. Asking an HTML page for
        // `#uir-canvas` only ever produced a warning that made no sense --
        // and nudged embedders into shipping a canvas element the backend is
        // forbidden to use.
        // Required: without these a feature is dead, not merely inconvenient.
        var required = [__uirShellViewportId, "uir-stage", "uir-clipboard-input"];
        // Optional: a minimal embedder, or the exported app gallery, ships no
        // toolbar at all and that is perfectly fine.
        var optional = ["uir-win-title", "uir-btn-clip-sync", "uir-btn-resize-960",
                        "uir-btn-resize-800", "uir-btn-resize-auto", "uir-btn-close"];
        var collect = function(ids) {
          var out = [];
          for (var i = 0; i < ids.length; i++) {
            if (!document.getElementById(ids[i])) out.push("#" + ids[i]);
          }
          return out;
        };
        var missing = collect(required);
        window.__uirMissingElements = missing;
        window.__uirMissingOptional = collect(optional);
        var hasViewport = document.getElementById("uir-viewport") || document.getElementById("uir-canvas");
        if (typeof console !== "undefined" && console.warn) {
          if (!hasViewport) {
            console.warn("[uirelays] no #" + __uirShellViewportId + " in the page: nothing will be drawn.");
          } else if (missing.length > 0) {
            console.warn("[uirelays] shell contract incomplete: " + missing.join(", ") + ".");
          }
        }
      })();
      var relPos = function(e, el) {
        if (!el) return { x: 0, y: 0 };
        var r = el.getBoundingClientRect();
        return {
          x: Math.round(e.clientX - r.left),
          y: Math.round(e.clientY - r.top)
        };
      };
      var stagePadding = function(el) {
        if (!el || typeof window.getComputedStyle !== "function") return { x: 0, y: 0 };
        try {
          var cs = window.getComputedStyle(el);
          return {
            x: (parseFloat(cs.paddingLeft) || 0) + (parseFloat(cs.paddingRight) || 0),
            y: (parseFloat(cs.paddingTop) || 0) + (parseFloat(cs.paddingBottom) || 0)
          };
        } catch (_) { return { x: 0, y: 0 }; }
      };
      var viewportMin = function() {
        var m = window.__uirMinViewport;
        var a = window.__uirAppMinViewport;
        var w = (m && m.w > 0) ? m.w : 320;
        var h = (m && m.h > 0) ? m.h : 240;
        // The two floors combine by taking the larger of each. An embedder can
        // give an application more room than it needs; it can never take away
        // room the application declared it cannot draw without.
        if (a && a.w > w) w = a.w;
        if (a && a.h > h) h = a.h;
        return { w: w, h: h };
      };
      var viewportInset = function() {
        var i = window.__uirViewportInset;
        return { x: (i && typeof i.x === "number") ? i.x : 0,
                 y: (i && typeof i.y === "number") ? i.y : 0 };
      };
      var syncViewportSize = function() {
        var vp = getVp();
        if (!vp || !window.__uirActive) return;
        if (window.__uirFixedSizeMode) return;
        var st = document.getElementById("uir-stage");
        var box = st || vp;
        var cw = box.clientWidth;
        var ch = box.clientHeight;
        // A hidden stage (background tab, display:none iframe) measures 0x0.
        // Clamping that to the minimum would hand the app a size it never
        // asked for, so keep the previous size and wait for the observer.
        if (!cw || !ch) return;
        var pad = (box === vp) ? { x: 0, y: 0 } : stagePadding(box);
        var ins = viewportInset();
        var min = viewportMin();
        var w = Math.floor(cw - pad.x - ins.x);
        var h = Math.floor(ch - pad.y - ins.y);
        if (w < 1 || h < 1) return;
        w = Math.max(min.w, w);
        h = Math.max(min.h, h);
        __uirApplyViewportBox(vp, w, h);
        window.__uirActive.resize(w, h, 100);
      };
      window.__uirSyncViewportSize = syncViewportSize;

      document.addEventListener("mousedown", function(e) {
        var vp = getVp();
        if (!vp || !window.__uirActive) return;
        if (e.target !== vp && !vp.contains(e.target)) return;
        e.preventDefault();
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
        if (["Tab", "Enter", "ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight", "Space", "Backspace", "Delete", "Home", "End", "PageUp", "PageDown"].indexOf(e.code) !== -1 ||
            ((e.ctrlKey || e.metaKey) && ["KeyS", "KeyP", "KeyF", "KeyW", "KeyA", "KeyZ", "KeyY"].indexOf(e.code) !== -1)) {
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
      window.addEventListener("paste", function(e) {
        if (!window.__uirActive) return;
        var clipIn = document.getElementById("uir-clipboard-input");
        if (clipIn && document.activeElement === clipIn) return;
        var cd = e.clipboardData || window.clipboardData;
        if (cd) {
          var txt = cd.getData("text");
          if (txt) {
            window.__uirActive.clip(txt);
          }
        }
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
          if (vp) __uirApplyViewportBox(vp, 960, 640);
          if (window.__uirActive) window.__uirActive.resize(960, 640, 100);
        });
      }
      var btn800 = document.getElementById("uir-btn-resize-800");
      if (btn800) {
        btn800.addEventListener("click", function() {
          window.__uirFixedSizeMode = true;
          var vp = getVp();
          if (vp) __uirApplyViewportBox(vp, 800, 600);
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
  # -- platform shim: the whole of the platform dependence lives here -----

  proc sleepNs(ns: int) {.inline.} =
    when defined(windows):
      # Winsock has no nanosleep. The only caller is a retry backoff on a
      # non-blocking socket, where a millisecond is close enough to 0.2 ms.
      os.sleep(max(1, ns div 1_000_000))
    else:
      var req = Timespec(
        tv_sec: posix.Time(ns div 1_000_000_000),
        tv_nsec: clong(ns mod 1_000_000_000)
      )
      var rem = Timespec(tv_sec: posix.Time(0), tv_nsec: clong(0))
      discard nanosleep(req, rem)

  proc setFdNonBlocking(fd: SocketHandle) =
    when defined(windows):
      # nativesockets.setBlocking is ioctlsocket(FIONBIO) here and the very
      # same fcntl dance as below elsewhere; it raises instead of returning.
      try:
        setBlocking(fd, false)
      except CatchableError:
        discard
    else:
      let flags = fcntl(cint(fd), F_GETFL, 0)
      if flags >= 0:
        discard fcntl(cint(fd), F_SETFL, flags or O_NONBLOCK)

  proc sockClose(fd: SocketHandle): cint {.inline.} =
    when defined(windows): winlean.closesocket(fd)
    else: posix.close(cint(fd))

  proc sockRecv(fd: SocketHandle; buf: pointer; len: int; flags: cint): int {.inline.} =
    # winlean counts bytes in cint and returns cint, posix uses int for both.
    when defined(windows): int(winlean.recv(fd, buf, cint(len), flags))
    else: posix.recv(fd, buf, len, flags)

  proc sockSend(fd: SocketHandle; buf: pointer; len: int; flags: cint): int {.inline.} =
    when defined(windows): int(winlean.send(fd, buf, cint(len), flags))
    else: posix.send(fd, buf, len, flags)

  proc sockListen(fd: SocketHandle): cint {.inline.} =
    when defined(windows): winlean.listen(fd, cint(SOMAXCONN))
    else: posix.listen(fd, cint(SOMAXCONN))

  proc sockAccept(fd: SocketHandle): SocketHandle =
    var clientSa: Sockaddr_in
    var clientLen = SockLen(sizeof(clientSa))
    when defined(windows):
      winlean.accept(fd, cast[ptr SockAddr](addr clientSa), addr clientLen)
    else:
      posix.accept(fd, cast[ptr SockAddr](addr clientSa), addr clientLen)

  proc sockWouldBlock(): bool {.inline.} =
    ## Did the last socket call fail only because it would have blocked?
    ## Must be asked immediately after that call: both `errno` and
    ## GetLastError are overwritten by the next one.
    let e = int32(osLastError())
    when defined(windows):
      e == int32(WSAEWOULDBLOCK)
    else:
      e == int32(EAGAIN) or e == int32(EWOULDBLOCK)

  proc sockSetReuseAddr(fd: SocketHandle) =
    when defined(windows):
      try:
        setSockOptInt(fd, int(SOL_SOCKET), int(SO_REUSEADDR), 1)
      except CatchableError:
        discard
    else:
      var optVal: cint = 1
      discard posix.setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, addr optVal,
                               SockLen(sizeof(optVal)))

  proc sockBindAny(fd: SocketHandle; port: int): bool =
    ## Bind to the wildcard address on `port`. False when the port is taken.
    when defined(windows):
      # winlean ships neither htons nor htonl, so filling a Sockaddr_in by
      # hand is not available here; getaddrinfo does the byte-order work
      # portably and without assuming anything about the host endianness.
      try:
        let ai = getAddrInfo("0.0.0.0", Port(port))
        try:
          result = bindSocket(fd, ai.ai_addr, SockLen(ai.ai_addrlen)) == 0'i32
        finally:
          freeAddrInfo(ai)
      except CatchableError:
        result = false
    else:
      var sa: Sockaddr_in
      zeroMem(addr sa, sizeof(sa))
      sa.sin_family = typeof(sa.sin_family)(AF_INET)
      sa.sin_port = posix.htons(uint16(port))
      sa.sin_addr.s_addr = posix.htonl(INADDR_ANY)
      result = bindSocket(fd, cast[ptr SockAddr](addr sa),
                          SockLen(sizeof(sa))) == 0'i32

  proc sendAllNonBlocking(fd: SocketHandle; data: string): bool =
    if data.len == 0:
      return true
    var sent = 0
    var retries = 0
    while sent < data.len:
      let n = sockSend(fd, unsafeAddr data[sent], data.len - sent,
        when declared(MSG_NOSIGNAL): cint(MSG_NOSIGNAL) else: 0'i32)
      if n > 0:
        sent += n
        retries = 0
      elif n < 0 and sockWouldBlock():
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
        discard sockClose(webCore.sseClients[i].fd)
        webCore.sseClients.delete(i)
        continue
      if webCore.sseClients[i].lastSentFrame != webCore.frameId:
        if sendAllNonBlocking(webCore.sseClients[i].fd, msg):
          webCore.sseClients[i].lastSentFrame = webCore.frameId
          inc i
        else:
          discard sockClose(webCore.sseClients[i].fd)
          webCore.sseClients.delete(i)
      else:
        inc i

  proc handleHttpClient(clientFd: SocketHandle) =
    setFdNonBlocking(clientFd)
    var rawReq = newStringOfCap(4096)
    var buf: array[4096, char]
    var headerEnd = -1
    var contentLength = 0

    # Read the whole request. Counting attempts instead of bytes truncates any
    # body that arrives in more pieces than the budget allows -- a 600 KB batch
    # of input events, for one -- and then the handler acts on half a JSON
    # document, drops every event in it, and closes the connection while the
    # client is still writing. Read until the declared body is complete, a
    # deadline passes, or the request grows past what we will buffer.
    const
      maxRequestBytes = 8 * 1024 * 1024
      readDeadlineMs = 5000
    let readDeadline = getMonoTime() + initDuration(milliseconds = readDeadlineMs)
    var requestComplete = false
    var requestTooBig = false
    while true:
      let n = sockRecv(clientFd, addr buf[0], buf.len, 0)
      if n > 0:
        let oldLen = rawReq.len
        rawReq.setLen(oldLen + n)
        for i in 0 ..< n:
          rawReq[oldLen + i] = buf[i]
        if headerEnd < 0:
          # Only the tail can complete the terminator, so start looking there.
          headerEnd = rawReq.find("\r\n\r\n", max(0, oldLen - 3))
          if headerEnd >= 0:
            let hdrPart = rawReq[0 ..< headerEnd]
            for line in hdrPart.splitLines():
              let lower = line.toLowerAscii()
              if lower.startsWith("content-length:"):
                try:
                  contentLength = parseInt(strutils.strip(line[15 .. ^1]))
                except ValueError:
                  contentLength = 0
        if headerEnd >= 0:
          if rawReq.len >= headerEnd + 4 + contentLength:
            requestComplete = true
            break
          if rawReq.len > maxRequestBytes:
            requestTooBig = true
            break
      elif n == 0:
        break # peer closed
      else:
        if sockWouldBlock():
          if getMonoTime() >= readDeadline:
            break
          sleepNs(200_000) # 0.2 ms
        else:
          break

    if rawReq.len == 0:
      discard sockClose(clientFd)
      return

    if not requestComplete:
      # Half a request is not a request: acting on it would mean acting on
      # garbage, and the client deserves to hear that instead of a 200.
      let status = if requestTooBig: "413 Payload Too Large" else: "400 Bad Request"
      writeHttpResponse(clientFd, status, "application/json; charset=utf-8",
        """{"error":"incomplete request"}""")
      discard sockClose(clientFd)
      return

    let firstLineEnd = rawReq.find("\r\n")
    let firstLine = if firstLineEnd >= 0: rawReq[0 ..< firstLineEnd] else: rawReq
    let parts = strutils.splitWhitespace(firstLine)
    if parts.len < 2:
      discard sockClose(clientFd)
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
      discard sockClose(clientFd)
      return

    case pathOnly
    of "/", "/index.html":
      writeHttpResponse(clientFd, "200 OK", "text/html; charset=utf-8", webCore.pageHtml)
      discard sockClose(clientFd)

    of "/state", "/frame":
      let payload = if webCore.lastFrameJson.len > 0:
                      webCore.lastFrameJson
                    else:
                      """{"frameId":0,"backend":"""" & $webCore.backendKind & """"}"""
      writeHttpResponse(clientFd, "200 OK", "application/json; charset=utf-8", payload)
      discard sockClose(clientFd)

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
        "canvasCommandCount": webCore.canvasCommandCount,
        "sseClients": webCore.sseClients.len,
        "droppedEvents": webCore.droppedEvents,
        "inputParseErrors": webCore.inputParseErrors
      }
      writeHttpResponse(clientFd, "200 OK", "application/json; charset=utf-8", $healthObj)
      discard sockClose(clientFd)

    of "/input":
      if httpMethod == "POST":
        let added = parseIncomingInputJson(body)
        let resp = """{"ok":true,"added":""" & $added & ""","queued":""" & $webCore.eventQueue.len & "}"
        writeHttpResponse(clientFd, "200 OK", "application/json; charset=utf-8", resp)
      else:
        writeHttpResponse(clientFd, "405 Method Not Allowed", "application/json", """{"error":"Use POST"}""")
      discard sockClose(clientFd)

    of "/monkey-report":
      if httpMethod == "POST":
        webCore.monkeyReportJson = body
        writeHttpResponse(clientFd, "200 OK", "application/json; charset=utf-8", """{"ok":true}""")
      else:
        let rep = if webCore.monkeyReportJson.len > 0: webCore.monkeyReportJson else: """{"ready":false}"""
        writeHttpResponse(clientFd, "200 OK", "application/json; charset=utf-8", rep)
      discard sockClose(clientFd)

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
        discard sockClose(clientFd)

    else:
      writeHttpResponse(clientFd, "404 Not Found", "application/json; charset=utf-8",
        """{"error":"Not found","path":"""" & htmlEscape(pathOnly) & """"}""")
      discard sockClose(clientFd)

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

    sockSetReuseAddr(sock)
    setFdNonBlocking(sock)

    var boundPort = 0
    for offset in 0 ..< 30:
      let candidate = basePort + offset
      if sockBindAny(sock, candidate) and sockListen(sock) == 0'i32:
        boundPort = candidate
        break

    if boundPort == 0:
      discard sockClose(sock)
      webCore.serverEnabled = false
      return

    webCore.listenFd = sock
    webCore.serverPort = boundPort
    webCore.serverEnabled = true

  proc reapSseClients() =
    ## A browser that closed its tab sends nothing -- the socket just goes
    ## quiet, and the next frame we push at it may still be accepted by the
    ## kernel. Without looking for EOF here, every closed tab keeps its file
    ## descriptor until a send fails, and an app that has gone idle sends
    ## nothing at all, so they pile up until the process runs out of fds.
    var i = 0
    while i < webCore.sseClients.len:
      let fd = webCore.sseClients[i].fd
      if fd == osInvalidSocket or cint(fd) < 0:
        webCore.sseClients.delete(i)
        continue
      var probe: array[16, char]
      let flags = cint(MSG_PEEK) or
        (when declared(MSG_DONTWAIT): cint(MSG_DONTWAIT) else: 0'i32)
      let n = sockRecv(fd, addr probe[0], probe.len, flags)
      if n == 0 or (n < 0 and not sockWouldBlock()):
        discard sockClose(fd)
        webCore.sseClients[i].alive = false
        webCore.sseClients.delete(i)
      else:
        inc i

  proc webPumpServer*() =
    if not webCore.serverEnabled or webCore.listenFd == osInvalidSocket:
      return
    reapSseClients()
    for _ in 0 ..< 16:
      let clientFd = sockAccept(webCore.listenFd)
      if clientFd == osInvalidSocket or cint(clientFd) < 0:
        break
      handleHttpClient(clientFd)

  proc stopWebServer*() =
    for c in webCore.sseClients:
      if c.alive and c.fd != osInvalidSocket:
        discard sockClose(c.fd)
    webCore.sseClients.setLen(0)
    if webCore.listenFd != osInvalidSocket and cint(webCore.listenFd) > 0:
      discard sockClose(webCore.listenFd)
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
  if webCore.eventQueue.len > 0:
    e = webCore.eventQueue[0]
    webCore.eventQueue.delete(0)
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
      pageHtml: pageHtml,
      droppedEvents: 0
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
      sseClients: @[],
      droppedEvents: 0
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
