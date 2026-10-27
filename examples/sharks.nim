## sharks.nim -- "Hammerhead reef": four hammerhead sharks gliding over a
## pre-baked seabed, drawn strictly with primitives uirelays actually has.
##
##   blitRGBA   one call per frame. The whole static world (dithered water
##              clusters, layered sand, reef boulders, tall kelp with carved
##              leaves, starfish, fan shells, bioluminescent polyps) is baked
##              once into a 32-bit pixel buffer and republished as one blit,
##              so the seabed costs the CPU nothing per frame.
##   fillRect   the sharks. An 18-joint spine becomes a set of capsules
##              (body, T-shaped hammer, pectoral/pelvic/tail fins), sampled on
##              a 10 px grid, Bayer-dithered into a 6-step palette and drawn
##              as 1..4 small rects per occupied cell. The HUD and the "honest
##              UI" panel are flat rects with a checkerboard dither shadow --
##              uirelays has no alpha blending, so a shadow is a pattern.
##   drawLine   the 1 px frames of the HUD, of the panel and of the buttons.
##   drawText   HUD readouts, panel labels, the caret, the typed text.
##
## Nothing else is used: no CSS, no blur, no alpha, no images, no timers, no
## threads. Everything below is expressible on every uirelays backend.
##
## Determinism
## -----------
## The scene is driven by a frame counter -- never by the wall clock and never
## by a RNG -- so every backend on every OS must emit the very same primitive
## stream. `-d:sharksSelftest` renders `-d:sharksFrames` frames (default 120)
## at a fixed `-d:sharksSceneW` x `-d:sharksSceneH` (default 1024x640) and
## prints one `SHARKS_DIGEST` line, which CI compares across operating
## systems and backends:
##
##   geom  mix over every fillRect/drawLine/blit argument   -> must be equal
##   bake  mix over the baked seabed pixel buffer           -> must be equal
##   txt   mix over drawText strings and colours            -> must be equal
##   sc    mix over quantised shark joint positions         -> must be equal
##   pos   mix over drawText coordinates                    -> reported only
##
## `pos` is reported, not gated: uirelays ships no font of its own, so
## `measureText` (used to centre the title) legitimately lands on different
## pixels under Xft, CoreText, GDI, Pango, SDL_ttf and the browser's CSS font
## stack. Everything the app itself computes is bit-identical.
##
## Two portability traps this file works around, both measured rather than
## assumed (see tests/portability_math_test.nim):
##
##   * a 32-bit multiply is NOT portable: `nim js` computes it in a double and
##     loses every bit above 2^53, so the reference demo's `x * 374761393`
##     hash yields a different reef in the browser than natively. `mul32`
##     below splits the multiply into 16-bit halves; that is bit-identical on
##     the C and the JS backend.
##   * `float32` is NOT portable either: the C backend rounds to 32 bits, the
##     JS backend keeps the full double. The reference demo stores densities
##     in a Float32Array; here they are `float`, so the same colour index is
##     chosen everywhere.
##
## Compile:
##   nim c --mm:arc examples/sharks.nim                       # native backend
##   nim c --mm:arc -d:html examples/sharks.nim               # web: DOM
##   nim c --mm:arc -d:canvas examples/sharks.nim             # web: canvas
##   nim js --jsbigint64:off -d:nimStringHash2 -d:html \
##       examples/sharks.nim                                  # standalone page
##   nim c --mm:arc -d:sharksSelftest -r examples/sharks.nim  # digest for CI

import std/math
import uirelays

# ---------------------------------------------------------------------------
# Compile-time knobs
# ---------------------------------------------------------------------------

const
  Selftest {.booldefine: "sharksSelftest".}: bool = false
  SelftestFrames {.intdefine: "sharksFrames".}: int = 120
  SceneW {.intdefine: "sharksSceneW".}: int = 1024
  SceneH {.intdefine: "sharksSceneH".}: int = 640

const
  CellSize = 10        ## px per mosaic cell, as in the reference demo
  NumJoints = 18       ## spine samples per shark
  GlowPeriod = 54      ## frames between bioluminescence ticks (900 ms @60fps)
  CaretPeriod = 30     ## frames per caret blink half-period (500 ms @60fps)
  MinW = 480           ## interactive floor; the scene stays legible here
  MinH = 320

when defined(html):
  const BackendName = "html"
elif defined(canvas):
  const BackendName = "canvas"
elif defined(sdl3):
  const BackendName = "sdl3"
elif defined(sdl2):
  const BackendName = "sdl2"
elif defined(gtk4):
  const BackendName = "gtk4"
elif defined(figDrawWindy):
  const BackendName = "figdraw-windy"
elif defined(figDrawSiwin):
  const BackendName = "figdraw-siwin"
elif defined(macosx):
  const BackendName = "cocoa"
elif defined(windows):
  const BackendName = "winapi"
elif defined(js):
  const BackendName = "js"
else:
  const BackendName = "x11"

# ---------------------------------------------------------------------------
# Portable integer arithmetic
# ---------------------------------------------------------------------------

proc mul32(a, b: uint32): uint32 {.inline.} =
  ## The low 32 bits of `a * b`, computed so that no intermediate exceeds
  ## 2^53. Plain `a * b` is exact on the C backend and lossy on the JS one,
  ## because there a uint32 lives in a double.
  let lo = (a and 0xFFFF'u32) * b
  let hi = ((a shr 16) * b) and 0xFFFF'u32
  (lo and 0xFFFFFFFF'u32) + (hi shl 16)

const MixBias = 20_000_000

proc mix(h: uint32; v: int): uint32 {.inline.} =
  ## Folds one bounded integer into the running digest. `v` must stay inside
  ## -MixBias .. MixBias so that the int -> uint32 conversion cannot overflow
  ## an int32 (which is all `nim js --jsbigint64:off` has).
  var x = h xor uint32(v + MixBias)
  x = mul32(x, 16777619'u32)
  x xor (x shr 15)

const OffsetBasis = 2166136261'u32

proc quant(x: float): int {.inline.} =
  ## Quantises a scene coordinate to 1/1024 px. `int(floor(...))` is
  ## bit-identical on the C and the JS backend; `cast[uint64](float)` is not.
  int(floor(x * 1024.0))

proc jsRound(x: float): int {.inline.} =
  ## `Math.round` semantics (half towards +inf), which Nim's `round` does not
  ## have -- it rounds half away from zero.
  int(floor(x + 0.5))

# ---------------------------------------------------------------------------
# Palette (verbatim from the reference demo)
# ---------------------------------------------------------------------------

const
  BgHex = 0xf4f6f6
  PaletteHex: array[7, array[6, int]] = [
    # 0 warm grey-brown   (hammerhead #1)
    [0xe4e3dc, 0xd0cec4, 0xb6b1a5, 0x948e80, 0x706a5c, 0x4f493e],
    # 1 cold steel blue   (hammerhead #2)
    [0xdfe5ec, 0xc6d0dc, 0xa5b4c6, 0x7f92a8, 0x5c6f86, 0x3d4d61],
    # 2 sand-olive        (hammerhead #3)
    [0xe6e4da, 0xd2cdc0, 0xb8b09c, 0x968c75, 0x746a54, 0x504837],
    # 3 deep sage-emerald (kelp)
    [0xdfeae2, 0xc2d8c8, 0x9abca4, 0x729b80, 0x4f795e, 0x33553f],
    # 4 layered limestone (seabed, boulders)
    [0xe8e5df, 0xd6d1c7, 0xbdb6a8, 0x9e9686, 0x7d7566, 0x5c5549],
    # 5 terracotta-coral  (shells, starfish)
    [0xefe2dd, 0xdec6be, 0xc7a398, 0xab7f72, 0x8c5e50, 0x694135],
    # 6 glowing turquoise (bioluminescent polyps)
    [0xd8f3f0, 0xb0e8e2, 0x7cd9cf, 0x48c5b8, 0x26a699, 0x137a6f]
  ]
  Bayer4x4: array[4, array[4, float]] = [
    [0.0 / 16, 8.0 / 16, 2.0 / 16, 10.0 / 16],
    [12.0 / 16, 4.0 / 16, 14.0 / 16, 6.0 / 16],
    [3.0 / 16, 11.0 / 16, 1.0 / 16, 9.0 / 16],
    [15.0 / 16, 7.0 / 16, 13.0 / 16, 5.0 / 16]
  ]
  HammerProfile: array[NumJoints, int] =
    [12, 15, 20, 24, 26, 25, 22, 19, 16, 14, 11, 9, 8, 6, 5, 4, 3, 2]

proc rgbOf(v: int): Color {.inline.} =
  color(uint8((v shr 16) and 0xFF), uint8((v shr 8) and 0xFF), uint8(v and 0xFF))

proc wordOf(v: int): uint32 {.inline.} =
  ## 0xAARRGGBB, the layout `blitRGBA` documents.
  (0xFF'u32 shl 24) or (uint32((v shr 16) and 0xFF) shl 16) or
    (uint32((v shr 8) and 0xFF) shl 8) or uint32(v and 0xFF)

var
  Pal: array[7, array[6, Color]]
  PalWord: array[7, array[6, uint32]]
  BgCol: Color
  BgWord: uint32

proc initPalette() =
  BgCol = rgbOf(BgHex)
  BgWord = wordOf(BgHex)
  for p in 0 .. 6:
    for i in 0 .. 5:
      Pal[p][i] = rgbOf(PaletteHex[p][i])
      PalWord[p][i] = wordOf(PaletteHex[p][i])

# ---------------------------------------------------------------------------
# Instrumentation
# ---------------------------------------------------------------------------

type Stats = object
  rects, lines, texts, blits, cells, bakeRects: int  ## totals over the run
  frameRects, frameLines, frameTexts: int            ## last frame, for the HUD
  geom, txt, pos, sc, bake: uint32
  blitOk, blitTried: bool

var st = Stats(geom: OffsetBasis, txt: OffsetBasis, pos: OffsetBasis,
               sc: OffsetBasis, bake: OffsetBasis)

proc hex8(x: uint32): string =
  const digits = "0123456789abcdef"
  result = newString(8)
  for i in 0 .. 7:
    result[i] = digits[(x shr (28 - i * 4)) and 0xF'u32]

# ---------------------------------------------------------------------------
# Drawing wrappers: every primitive goes through here, so the digest below is
# a hash of exactly what the app asked the backend to draw.
# ---------------------------------------------------------------------------

var
  baking = false
  bufW = 0
  bufH = 0
  buf: seq[uint32]

proc bakeFill(x, y, w, h: int; word: uint32) =
  let x0 = max(0, x)
  let y0 = max(0, y)
  let x1 = min(bufW, x + w)
  let y1 = min(bufH, y + h)
  if x1 <= x0 or y1 <= y0: return
  for yy in y0 ..< y1:
    let row = yy * bufW
    for xx in x0 ..< x1:
      buf[row + xx] = word

proc cellRect(x, y, w, h: int; pal, idx: int) =
  ## One mosaic rect: into the bake buffer while baking, onto the screen
  ## otherwise. Both paths see the same coordinates and the same colour.
  if baking:
    inc st.bakeRects
    bakeFill(x, y, w, h, PalWord[pal][idx])
  else:
    inc st.rects
    inc st.frameRects
    st.geom = mix(st.geom, 1)
    st.geom = mix(st.geom, x)
    st.geom = mix(st.geom, y)
    st.geom = mix(st.geom, w)
    st.geom = mix(st.geom, h)
    st.geom = mix(st.geom, PaletteHex[pal][idx] and 0xFFFFFF)
    fillRect(rect(x, y, w, h), Pal[pal][idx])

proc cellRectBg(x, y, w, h: int) =
  ## The holes inside dense cells are painted with the background colour, so
  ## they need their own path: they are not a palette entry.
  if baking:
    inc st.bakeRects
    bakeFill(x, y, w, h, BgWord)
  else:
    inc st.rects
    inc st.frameRects
    st.geom = mix(st.geom, 1)
    st.geom = mix(st.geom, x)
    st.geom = mix(st.geom, y)
    st.geom = mix(st.geom, w)
    st.geom = mix(st.geom, h)
    st.geom = mix(st.geom, BgHex and 0xFFFFFF)
    fillRect(rect(x, y, w, h), BgCol)

proc uiRect(x, y, w, h: int; hexCol: int) =
  inc st.rects
  inc st.frameRects
  st.geom = mix(st.geom, 1)
  st.geom = mix(st.geom, x)
  st.geom = mix(st.geom, y)
  st.geom = mix(st.geom, w)
  st.geom = mix(st.geom, h)
  st.geom = mix(st.geom, hexCol and 0xFFFFFF)
  fillRect(rect(x, y, w, h), rgbOf(hexCol))

proc uiLine(x1, y1, x2, y2: int; hexCol: int) =
  inc st.lines
  inc st.frameLines
  st.geom = mix(st.geom, 2)
  st.geom = mix(st.geom, x1)
  st.geom = mix(st.geom, y1)
  st.geom = mix(st.geom, x2)
  st.geom = mix(st.geom, y2)
  st.geom = mix(st.geom, hexCol and 0xFFFFFF)
  drawLine(x1, y1, x2, y2, rgbOf(hexCol))

const Transparent = color(0, 0, 0, 0)

proc uiText(f: Font; x, y: int; text: string; hexCol: int;
            digest = true) =
  ## `digest = false` is for the one label that deliberately names the running
  ## backend: its text differs per backend by design, so folding it into `txt`
  ## would make a digest that is supposed to compare backends unequal for a
  ## reason that has nothing to do with rendering.
  inc st.texts
  inc st.frameTexts
  st.pos = mix(st.pos, x)
  st.pos = mix(st.pos, y)
  if digest:
    st.txt = mix(st.txt, text.len)
    for ch in text:
      st.txt = mix(st.txt, int(ch))
    st.txt = mix(st.txt, hexCol and 0xFFFFFF)
  discard drawText(f, x, y, text, rgbOf(hexCol), Transparent)

proc uiBlit() =
  ## Publishes the baked seabed: the demo's single `blitRGBA` per frame.
  if buf.len == 0 or bufW <= 0 or bufH <= 0: return
  inc st.blits
  st.blitTried = true
  st.geom = mix(st.geom, 3)
  st.geom = mix(st.geom, bufW)
  st.geom = mix(st.geom, bufH)
  let ok = blitRGBA(cast[ptr UncheckedArray[uint32]](addr buf[0]), bufW, bufH,
                    rect(0, 0, bufW, bufH))
  st.blitOk = ok

# ---------------------------------------------------------------------------
# Deterministic hash (uint32 + logical shifts, `mul32` based)
# ---------------------------------------------------------------------------

proc hash2D(x, y: int): float =
  ## Uniform in [0, 1]. `x` and `y` must be non-negative: the reference demo
  ## hashes signed int32 with arithmetic shifts, which the JS backend cannot
  ## reproduce bit for bit.
  var n = (mul32(uint32(x), 374761393'u32) +
           mul32(uint32(y), 668265263'u32)) xor 0x5bf03635'u32
  n = mul32(n xor (n shr 13), 1274126177'u32)
  n = n xor (n shr 16)
  float(n) / 4294967295.0

proc hash1D(x: int): float = hash2D(x, 918273)

# ---------------------------------------------------------------------------
# Mosaic cell, verbatim from the reference demo
# ---------------------------------------------------------------------------

proc drawMosaicCell(gx, gy: int; density: float; pal: int) =
  let x = gx * CellSize
  let y = gy * CellSize
  let bayer = Bayer4x4[gy and 3][gx and 3]
  var dithered = density + (bayer - 0.5) * 0.22
  dithered = min(0.99, max(0.0, dithered))
  let idx = min(5, int(floor(dithered * 6.0)))
  let darkIdx = min(5, idx + 1)

  if density < 0.20:
    cellRect(x + 4, y + 4, 2, 2, pal, idx)
  elif density < 0.34:
    if ((gx + gy) and 1) == 1:
      cellRect(x + 2, y + 2, 2, 2, pal, idx)
      cellRect(x + 6, y + 6, 2, 2, pal, idx)
    else:
      cellRect(x + 4, y + 2, 2, 5, pal, idx)
  elif density < 0.50:
    cellRect(x + 2, y + 2, 2, 2, pal, idx)
    cellRect(x + 6, y + 2, 2, 2, pal, idx)
    cellRect(x + 2, y + 6, 2, 2, pal, idx)
    cellRect(x + 6, y + 6, 2, 2, pal, idx)
  elif density < 0.68:
    cellRect(x + 1, y + 1, 8, 8, pal, idx)
    cellRectBg(x + 3, y + 3, 4, 4)
    if bayer > 0.5:
      cellRect(x + 4, y + 4, 2, 2, pal, darkIdx)
  elif density < 0.84:
    cellRect(x + 1, y + 1, 8, 8, pal, idx)
    cellRectBg(x + 4, y + 4, 2, 2)
  else:
    cellRect(x + 1, y + 1, 8, 8, pal, idx)
    cellRect(x + 3, y + 3, 4, 4, pal, darkIdx)

# ---------------------------------------------------------------------------
# Scene state
# ---------------------------------------------------------------------------

type GlowNode = object
  gx, gy, phase: int

var
  gridCols = 0
  gridRows = 0
  sharkDens: seq[float]
  sharkPal: seq[uint8]
  staticDens: seq[float]
  staticPal: seq[uint8]
  glowNodes: seq[GlowNode]

proc setStaticCell(gx, gy: int; dens: float; pal: int) =
  if gx < 0 or gx >= gridCols or gy < 0 or gy >= gridRows: return
  let idx = gy * gridCols + gx
  if dens > staticDens[idx]:
    staticDens[idx] = dens
    staticPal[idx] = uint8(pal)

# ---------------------------------------------------------------------------
# Baking the static underwater world
# ---------------------------------------------------------------------------

proc bakeStaticUnderwaterWorld(w, h: int) =
  bufW = w
  bufH = h
  buf.setLen(w * h)
  gridCols = (w + CellSize - 1) div CellSize
  gridRows = (h + CellSize - 1) div CellSize
  let total = gridCols * gridRows
  sharkDens = newSeq[float](total)
  sharkPal = newSeq[uint8](total)
  staticDens = newSeq[float](total)
  staticPal = newSeq[uint8](total)
  glowNodes.setLen(0)

  # 1. Background dither clusters floating in the water column.
  let clusters = [
    (x: float(w) * 0.06, y: float(h) * 0.45, rx: 115.0, ry: 170.0),
    (x: float(w) * 0.93, y: float(h) * 0.60, rx: 120.0, ry: 145.0),
    (x: float(w) * 0.86, y: float(h) * 0.18, rx: 95.0, ry: 90.0)
  ]
  for cl in clusters:
    let sGx = max(0, int(floor((cl.x - cl.rx) / float(CellSize))))
    let eGx = min(gridCols - 1, int(ceil((cl.x + cl.rx) / float(CellSize))))
    let sGy = max(0, int(floor((cl.y - cl.ry) / float(CellSize))))
    let eGy = min(gridRows - 1, int(ceil((cl.y + cl.ry) / float(CellSize))))
    for gy in sGy .. eGy:
      for gx in sGx .. eGx:
        if ((gx + gy) and 1) != 0: continue
        let dx = (float(gx * CellSize) - cl.x) / cl.rx
        let dy = (float(gy * CellSize) - cl.y) / cl.ry
        let d = dx * dx + dy * dy
        if d < 1.0 and Bayer4x4[gy and 3][gx and 3] > d * 0.85:
          setStaticCell(gx, gy, 0.15, 1)

  # 2. Layered sand relief on the seabed, deterministic per column.
  for gx in 0 ..< gridCols:
    let sandHeight = 2.5 + sin(float(gx) * 0.11) * 1.2 + cos(float(gx) * 0.04) * 0.9
    let maxGy = int(ceil(sandHeight))
    for dy in 0 .. maxGy:
      let gy = gridRows - 1 - dy
      let d = min(0.92, 0.35 + (1.0 - float(dy) / (sandHeight + 0.5)) * 0.58)
      setStaticCell(gx, gy, d, 4)

  # 3. Reef boulders and flat stones along the seabed.
  const rockStep = 9
  let numRockSlots = (gridCols + rockStep - 1) div rockStep + 2
  for slot in 0 ..< numRockSlots:
    let rHash = hash1D(slot * 17)
    let centerGx = slot * rockStep + int(floor((rHash - 0.5) * 5.0))
    let rxCells = 3.5 + hash1D(slot * 31) * 6.5
    let ryCells = 2.0 + hash1D(slot * 47) * 4.2
    let centerGy = gridRows - 1 - int(floor(ryCells * 0.25))
    let sGx = max(0, int(floor(float(centerGx) - rxCells)))
    let eGx = min(gridCols - 1, int(ceil(float(centerGx) + rxCells)))
    let sGy = max(0, int(floor(float(centerGy) - ryCells)))
    let eGy = gridRows - 1
    for gy in sGy .. eGy:
      for gx in sGx .. eGx:
        let dx = (float(gx) - float(centerGx)) / rxCells
        let dy = (float(gy) - float(centerGy)) / ryCells
        let distSq = dx * dx + dy * dy
        if distSq < 1.0:
          setStaticCell(gx, gy, (1.0 - sqrt(distSq)) * 0.94, 4)

  # 4. Tall branching kelp with carved leaves and glowing bulbs.
  const kelpStep = 7
  let numKelpSlots = (gridCols + kelpStep - 1) div kelpStep
  for slot in 0 ..< numKelpSlots:
    if hash1D(slot * 101) < 0.22: continue  # natural gaps between bushes
    let baseGx = slot * kelpStep + int(floor((hash1D(slot * 103) - 0.5) * 4.0))
    let heightCells = 10 + int(floor(hash1D(slot * 107) * 18.0))
    let curvePhase = hash1D(slot * 109) * PI * 2.0
    let curveDir = if hash1D(slot * 113) > 0.5: 1.0 else: -1.0
    for s in 0 ..< heightCells:
      let t = float(s) / float(heightCells)
      let bend = jsRound(sin(curvePhase + float(s) * 0.26) * (t * 2.2) + curveDir * t * 1.4)
      let gx = baseGx + bend
      let gy = gridRows - 2 - s
      let stemDensity = 0.86 - t * 0.42
      setStaticCell(gx, gy, stemDensity, 3)
      if s > 2 and s < heightCells - 1:
        if s mod 2 == 0:
          setStaticCell(gx + 1, gy, stemDensity * 0.72, 3)
          if s mod 4 == 0 and t < 0.75:
            setStaticCell(gx + 2, gy + 1, stemDensity * 0.42, 3)
        else:
          setStaticCell(gx - 1, gy, stemDensity * 0.72, 3)
          if s mod 3 == 0 and t < 0.75:
            setStaticCell(gx - 2, gy + 1, stemDensity * 0.42, 3)
      if s == heightCells - 1 and hash1D(slot * 127) > 0.45:
        setStaticCell(gx, gy, 0.78, 6)
        setStaticCell(gx, gy - 1, 0.30, 6)
        glowNodes.add GlowNode(gx: gx, gy: gy,
                               phase: int(floor(hash1D(slot * 131) * 100.0)))

  # 5. Shells, starfish and glowing bottom crystals.
  const decoStep = 11
  let numDecoSlots = (gridCols + decoStep - 1) div decoStep
  for slot in 0 ..< numDecoSlots:
    let cx = slot * decoStep + 3 + int(floor(hash1D(slot * 211) * 5.0))
    let cy = gridRows - 2 - int(floor(hash1D(slot * 223) * 2.5))
    case slot mod 3
    of 0:  # five-ray starfish
      setStaticCell(cx, cy, 0.90, 5)
      setStaticCell(cx - 1, cy, 0.62, 5)
      setStaticCell(cx + 1, cy, 0.62, 5)
      setStaticCell(cx, cy - 1, 0.62, 5)
      setStaticCell(cx - 1, cy + 1, 0.52, 5)
      setStaticCell(cx + 1, cy + 1, 0.52, 5)
    of 1:  # spiral fan shell
      setStaticCell(cx, cy, 0.88, 5)
      setStaticCell(cx + 1, cy, 0.74, 5)
      setStaticCell(cx, cy - 1, 0.70, 5)
      setStaticCell(cx + 1, cy - 1, 0.48, 5)
      setStaticCell(cx - 1, cy, 0.42, 5)
    else:  # bioluminescent coral polyp
      setStaticCell(cx, cy, 0.85, 6)
      setStaticCell(cx - 1, cy - 1, 0.58, 6)
      setStaticCell(cx + 1, cy - 1, 0.58, 6)
      setStaticCell(cx, cy - 2, 0.42, 6)
      glowNodes.add GlowNode(gx: cx, gy: cy - 2, phase: slot * 19)

  # Rasterise the whole static world into the buffer, once.
  baking = true
  bakeFill(0, 0, w, h, BgWord)
  for gy in 0 ..< gridRows:
    let rowOff = gy * gridCols
    for gx in 0 ..< gridCols:
      let d = staticDens[rowOff + gx]
      if d > 0.08:
        drawMosaicCell(gx, gy, d, int(staticPal[rowOff + gx]))
  baking = false

  # Digest of the baked pixels: this is what `blitRGBA` publishes, so it is
  # the strongest statement that the seabed is the same on every backend.
  st.bake = OffsetBasis
  for i in 0 ..< buf.len:
    st.bake = mix(st.bake, int((buf[i] shr 16) and 0xFFFF'u32))
    st.bake = mix(st.bake, int(buf[i] and 0xFFFF'u32))

# ---------------------------------------------------------------------------
# Capsules and sharks
# ---------------------------------------------------------------------------

type
  Capsule = object
    x1, y1, x2, y2, r: float
    taper: bool
  Joint = object
    x, y, angle: float
  Shark = object
    paletteIndex: int
    scale, baseSpeed: float
    angle, targetAngle: float
    swimPhase: float
    turnTimer: int
    jointDist: float
    joints: array[NumJoints, Joint]

proc capsuleDensity(px, py: float; c: Capsule): float =
  let vx = c.x2 - c.x1
  let vy = c.y2 - c.y1
  let lenSq = vx * vx + vy * vy
  var t = 0.0
  if lenSq > 0.0001:
    t = ((px - c.x1) * vx + (py - c.y1) * vy) / lenSq
    if t < 0.0: t = 0.0
    elif t > 1.0: t = 1.0
  let dx = px - (c.x1 + t * vx)
  let dy = py - (c.y1 + t * vy)
  let distSq = dx * dx + dy * dy
  let effR = if c.taper: c.r * (1.0 - t * 0.65) else: c.r
  let effRSq = effR * effR
  if distSq >= effRSq: return 0.0
  1.0 - (sqrt(distSq) / effR)

proc newShark(x, y, angle: float; pal: int; scale, speed: float): Shark =
  result.paletteIndex = pal
  result.scale = scale
  result.baseSpeed = speed
  result.angle = angle
  result.targetAngle = angle
  result.swimPhase = float(pal) * 2.1
  result.turnTimer = 90 + pal * 45
  result.jointDist = 16.5 * scale
  for i in 0 ..< NumJoints:
    result.joints[i] = Joint(
      x: x - cos(angle) * float(i) * result.jointDist,
      y: y - sin(angle) * float(i) * result.jointDist,
      angle: angle)

proc update(s: var Shark; width, height: int; mouseX, mouseY: float;
            followMouse: bool) =
  # A very slow, meditative tail rhythm.
  s.swimPhase += 0.032
  let seaFloorMargin = max(200.0, float(height) - 165.0)

  if followMouse and mouseX > 0.0 and mouseY > 0.0:
    let dx = mouseX - s.joints[0].x
    let dy = min(mouseY, seaFloorMargin) - s.joints[0].y
    if dx * dx + dy * dy > 6400.0:
      s.targetAngle = arctan2(dy, dx)
  else:
    dec s.turnTimer
    if s.turnTimer <= 0:
      s.targetAngle += sin(s.swimPhase * 3.7) * 0.65
      s.turnTimer = 140 + int(floor(abs(cos(s.swimPhase)) * 120.0))
    const margin = 160.0
    if s.joints[0].x < -margin: s.targetAngle = 0.0
    if s.joints[0].x > float(width) + margin: s.targetAngle = PI
    if s.joints[0].y < 95.0: s.targetAngle = PI * 0.30
    if s.joints[0].y > seaFloorMargin: s.targetAngle = -PI * 0.30

  var diff = s.targetAngle - s.angle
  while diff < -PI: diff += PI * 2.0
  while diff > PI: diff -= PI * 2.0
  s.angle += diff * 0.014

  # Calm head sway.
  let moveAngle = s.angle + sin(s.swimPhase) * 0.032
  s.joints[0].x += cos(moveAngle) * s.baseSpeed
  s.joints[0].y += sin(moveAngle) * s.baseSpeed
  s.joints[0].angle = moveAngle

  # A soft wave travelling down the spine to the tail.
  for i in 1 ..< NumJoints:
    let prev = s.joints[i - 1]
    var segAngle = arctan2(prev.y - s.joints[i].y, prev.x - s.joints[i].x)
    segAngle += sin(s.swimPhase - float(i) * 0.34) * (float(i) / float(NumJoints)) * 0.075
    s.joints[i].x = prev.x - cos(segAngle) * s.jointDist
    s.joints[i].y = prev.y - sin(segAngle) * s.jointDist
    s.joints[i].angle = segAngle

proc fillCapsules(s: Shark; caps: var seq[Capsule]) =
  let k = s.scale
  caps.setLen(0)
  for i in 0 ..< NumJoints - 1:
    caps.add Capsule(x1: s.joints[i].x, y1: s.joints[i].y,
                     x2: s.joints[i + 1].x, y2: s.joints[i + 1].y,
                     r: float(HammerProfile[i]) * k, taper: false)

  # The T-shaped hammer on the head.
  let h0 = s.joints[0]
  let perpH = h0.angle + PI / 2.0
  let hammerW = 39.0 * k
  caps.add Capsule(x1: h0.x - cos(perpH) * hammerW, y1: h0.y - sin(perpH) * hammerW,
                   x2: h0.x + cos(perpH) * hammerW, y2: h0.y + sin(perpH) * hammerW,
                   r: 11.5 * k, taper: false)

  # Wide pectoral fins.
  let jPec = s.joints[4]
  let pecLen = 68.0 * k
  caps.add Capsule(x1: jPec.x, y1: jPec.y,
                   x2: jPec.x + cos(jPec.angle - 1.95) * pecLen,
                   y2: jPec.y + sin(jPec.angle - 1.95) * pecLen,
                   r: 13.5 * k, taper: true)
  caps.add Capsule(x1: jPec.x, y1: jPec.y,
                   x2: jPec.x + cos(jPec.angle + 1.95) * pecLen,
                   y2: jPec.y + sin(jPec.angle + 1.95) * pecLen,
                   r: 13.5 * k, taper: true)

  # Pelvic fins.
  let jPelv = s.joints[9]
  let pelvLen = 29.0 * k
  caps.add Capsule(x1: jPelv.x, y1: jPelv.y,
                   x2: jPelv.x + cos(jPelv.angle - 2.1) * pelvLen,
                   y2: jPelv.y + sin(jPelv.angle - 2.1) * pelvLen,
                   r: 8.5 * k, taper: true)
  caps.add Capsule(x1: jPelv.x, y1: jPelv.y,
                   x2: jPelv.x + cos(jPelv.angle + 2.1) * pelvLen,
                   y2: jPelv.y + sin(jPelv.angle + 2.1) * pelvLen,
                   r: 8.5 * k, taper: true)

  # Tail fin.
  let jTail = s.joints[NumJoints - 1]
  let tailLen = 48.0 * k
  caps.add Capsule(x1: jTail.x, y1: jTail.y,
                   x2: jTail.x - cos(jTail.angle - 0.55) * tailLen,
                   y2: jTail.y - sin(jTail.angle - 0.55) * tailLen,
                   r: 9.5 * k, taper: true)
  caps.add Capsule(x1: jTail.x, y1: jTail.y,
                   x2: jTail.x - cos(jTail.angle + 0.65) * (tailLen * 0.65),
                   y2: jTail.y - sin(jTail.angle + 0.65) * (tailLen * 0.65),
                   r: 7.5 * k, taper: true)

# ---------------------------------------------------------------------------
# The honest UI panel and the monitor HUD
# ---------------------------------------------------------------------------

type HudButton = object
  x, y, w, h: int
  id: int

const
  BtnToggleUi = 0
  BtnFollow = 1
  HudButtons: array[2, HudButton] = [
    HudButton(x: 16, y: 128, w: 185, h: 26, id: BtnToggleUi),
    HudButton(x: 210, y: 128, w: 215, h: 26, id: BtnFollow)
  ]

proc strokeBox(x, y, w, h: int; hexCol: int) =
  ## The 1 px frame of a panel or a button. Named `strokeBox`, not
  ## `drawFrame`, so it cannot be confused with uirelays' own `drawFrame`.
  uiLine(x, y, x + w, y, hexCol)
  uiLine(x, y + h, x + w, y + h, hexCol)
  uiLine(x, y, x, y + h, hexCol)
  uiLine(x + w, y, x + w, y + h, hexCol)

proc drawHonestUi(w, h: int; frame: int; fontUi, fontTitle, fontSmall,
                  fontBtn: Font; typed: string) =
  let cx = w div 2
  let cy = h div 2

  # 1. The "History v" button on top.
  const histW = 96
  const histH = 30
  let histX = cx - (histW shr 1)
  let histY = 26
  # Checkerboard dither shadow: uirelays has no alpha shadow.
  uiRect(histX + 2, histY + 2, histW, histH, 0xe5e5e0)
  uiRect(histX, histY, histW, histH, 0xf0f0ec)
  strokeBox(histX, histY, histW, histH, 0xdcdcd6)
  uiText(fontSmall, histX + 18, histY + 8, "History  v", 0x787872)

  # 2. The title, centred with `measureText`.
  const titleText = "what's on your mind?"
  let ext = measureText(fontTitle, titleText)
  uiText(fontTitle, cx - (ext.w div 2), cy - 68, titleText, 0x454540)

  # 3. The input panel. No backdrop blur without `blitRGBA` of the backdrop,
  # so: a solid plate with a pixel-shifted dither shadow.
  let boxW = min(540, w - 40)
  const boxH = 82
  let boxX = cx - (boxW shr 1)
  let boxY = cy - 12
  uiRect(boxX + 4, boxY + 4, boxW, boxH, 0xe4e4df)
  uiRect(boxX, boxY, boxW, boxH, 0xefefeb)
  strokeBox(boxX, boxY, boxW, boxH, 0xd8d8d2)

  # Typed text or the placeholder, then the blinking caret.
  if typed.len == 0:
    uiText(fontUi, boxX + 18, boxY + 16, "Ask hai anything...", 0x9e9e98)
  else:
    uiText(fontUi, boxX + 18, boxY + 16, typed, 0x35352f)
  let caretX = boxX + 16 +
    (if typed.len == 0: 0 else: measureText(fontUi, typed).w + 4)
  if (frame div CaretPeriod) mod 2 == 0:
    uiRect(caretX, boxY + 15, 1, 16, 0x555550)

  # The "+" icon (two lines) and the hints at the bottom of the plate.
  let plusX = boxX + 22
  let plusY = boxY + 56
  uiLine(plusX - 5, plusY, plusX + 5, plusY, 0x787872)
  uiLine(plusX, plusY - 5, plusX, plusY + 5, 0x787872)
  uiText(fontBtn, boxX + boxW - 165, boxY + 52, "send / newline", 0xa0a09a)
  let btnX = boxX + boxW - 38
  let btnY = boxY + 44
  uiRect(btnX, btnY, 24, 24, 0xdcdcd6)
  uiText(fontBtn, btnX + 6, btnY + 5, "^", 0x555550)

proc drawHud(fps: int; fontHud, fontSmall, fontBtn: Font; showUi, follow: bool;
             blitOk: bool) =
  const x = 16
  const y = 16
  const w = 465
  const h = 148
  uiRect(x, y, w, h, 0xebebe6)
  strokeBox(x, y, w, h, 0xc8c8c0)
  uiText(fontHud, x + 12, y + 10,
         "UIRELAYS MONITOR (STATIC SEABED + DYNAMIC SHARKS)", 0x2b2b26)
  uiText(fontHud, x + 12, y + 30,
         "FPS: " & $fps & " | Shark cells this frame: " & $st.frameRects, 0x4f4f48)
  uiText(fontHud, x + 12, y + 48,
         "fillRect per frame : " & $st.frameRects, 0x2e6f40)
  uiText(fontHud, x + 12, y + 66,
         "blitRGBA (seabed)  : " & $st.blits & (if blitOk: " ok" else: " REFUSED"),
         0x2b5b84)
  uiText(fontBtn, x + 12, y + 84,
         "resize: deterministic hash, zero RNG", 0x8c583a)
  uiText(fontBtn, x + 12, y + 102,
         "scene: 4 hammerheads + rare polyp glow", 0x5a6b7c)

  let labels = [
    "[UI panel: " & (if showUi: "ON" else: "OFF") & "]",
    "[Follow mouse: " & (if follow: "ON" else: "OFF") & "]"
  ]
  for i in 0 .. 1:
    let b = HudButtons[i]
    uiRect(b.x, b.y, b.w, b.h, 0xdcdcd4)
    strokeBox(b.x, b.y, b.w, b.h, 0xb8b8b0)
    uiText(fontBtn, b.x + 10, b.y + 7, labels[i], 0x2b2b26)
  discard fontSmall

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

proc main() {.uirApp.} =
  initPalette()
  let layout = createWindow(SceneW, SceneH)
  setMinViewport(SceneW, SceneH)
  setWindowTitle("uirelays -- Hammerhead reef (blitRGBA seabed + mosaic sharks)")

  var fmTitle = FontMetrics()
  var fmUi = FontMetrics()
  var fmHud = FontMetrics()
  var fmSmall = FontMetrics()
  var fmBtn = FontMetrics()
  let fontTitle = openFont("", layout.scaled(32), fmTitle)
  let fontUi = openFont("", layout.scaled(14), fmUi)
  let fontHud = openFont("", layout.scaled(12), fmHud)
  let fontSmall = openFont("", layout.scaled(12), fmSmall)
  let fontBtn = openFont("", layout.scaled(11), fmBtn)

  # The scene is generated at a fixed size so that the digest CI compares does
  # not depend on the window a backend happened to hand us.
  let sceneW = SceneW
  let sceneH = SceneH
  var winW = max(MinW, layout.width)
  var winH = max(MinH, layout.height)

  bakeStaticUnderwaterWorld(sceneW, sceneH)

  var sharks = [
    newShark(float(sceneW) * 0.28, float(sceneH) * 0.55, -0.45, 0, 1.38, 0.72),
    newShark(float(sceneW) * 0.75, float(sceneH) * 0.30, -2.55, 1, 1.44, 0.65),
    newShark(float(sceneW) * 0.18, float(sceneH) * 0.22, 0.32, 2, 1.25, 0.68),
    newShark(float(sceneW) * 0.68, float(sceneH) * 0.68, 2.65, 0, 1.18, 0.70)
  ]
  var caps: seq[Capsule] = newSeqOfCap[Capsule](32)

  var running = true
  var frame = 0
  var showUi = true
  var followCursor = false
  var mouseX = -1.0
  var mouseY = -1.0
  var typed = ""
  var sent = 0
  var fps = 60
  var fpsFrames = 0
  var fpsMark = getTicks()

  while running:
    var e = Event()
    while pollEvent(e):
      case e.kind
      of QuitEvent, WindowCloseEvent:
        running = false
      of WindowResizeEvent, WindowMetricsEvent:
        # In selftest the scene size is pinned, so a resize must not change
        # what CI compares. Interactively the world is re-baked, exactly like
        # the reference demo does.
        if not Selftest:
          let nw = max(MinW, e.x)
          let nh = max(MinH, e.y)
          if nw != winW or nh != winH:
            winW = nw
            winH = nh
            bakeStaticUnderwaterWorld(winW, winH)
      of MouseMoveEvent:
        mouseX = float(e.x)
        mouseY = float(e.y)
      of MouseDownEvent:
        for b in HudButtons:
          if e.x >= b.x and e.x <= b.x + b.w and e.y >= b.y and e.y <= b.y + b.h:
            if b.id == BtnToggleUi: showUi = not showUi
            elif b.id == BtnFollow: followCursor = not followCursor
      of TextInputEvent:
        if typed.len < 48:
          var ch = ""
          for c in e.text:
            if c == '\0': break
            ch.add c
          typed.add ch
      of KeyDownEvent:
        case e.key
        of KeyEsc:
          running = false
        of KeyU:
          showUi = not showUi
        of KeyF:
          followCursor = not followCursor
        of KeyEnter:
          if typed.len > 0:
            inc sent
            typed.setLen(0)
        of KeyBackspace:
          if typed.len > 0: typed.setLen(typed.len - 1)
        else: discard
      else: discard

    st.frameRects = 0
    st.frameLines = 0
    st.frameTexts = 0

    # 1. One blit publishes the whole baked seabed.
    uiBlit()

    # 2. Rare, slow shimmer on a few bottom polyps.
    let slowTick = frame div GlowPeriod
    for node in glowNodes:
      if (slowTick + node.phase) mod 7 == 0:
        let px = node.gx * CellSize
        let py = node.gy * CellSize
        uiRect(px + 3, py + 3, 4, 4, 0x26a699)
        uiRect(px + 4, py + 4, 2, 2, 0xd8f3f0)

    # 3. Clear the fast shark grid.
    for i in 0 ..< sharkDens.len:
      sharkDens[i] = 0.0

    # 4. Physics, then rasterise each shark's capsules into the grid.
    for sIdx in 0 ..< sharks.len:
      update(sharks[sIdx], sceneW, sceneH, mouseX, mouseY,
             followCursor and sIdx == 0)
      fillCapsules(sharks[sIdx], caps)
      let pal = sharks[sIdx].paletteIndex

      var minX = Inf; var minY = Inf
      var maxX = -Inf; var maxY = -Inf
      for c in caps:
        let r = c.r + 4.0
        minX = min(minX, min(c.x1, c.x2) - r)
        minY = min(minY, min(c.y1, c.y2) - r)
        maxX = max(maxX, max(c.x1, c.x2) + r)
        maxY = max(maxY, max(c.y1, c.y2) + r)

      let startGx = max(0, int(floor(minX / float(CellSize))))
      let endGx = min(gridCols - 1, int(ceil(maxX / float(CellSize))))
      let startGy = max(0, int(floor(minY / float(CellSize))))
      let endGy = min(gridRows - 1, int(ceil(maxY / float(CellSize))))

      for gy in startGy .. endGy:
        let py = float(gy * CellSize) + float(CellSize) * 0.5
        let rowOff = gy * gridCols
        for gx in startGx .. endGx:
          let px = float(gx * CellSize) + float(CellSize) * 0.5
          var maxDens = 0.0
          for c in caps:
            let d = capsuleDensity(px, py, c)
            if d > maxDens: maxDens = d
          if maxDens > 0.08:
            let idx = rowOff + gx
            if maxDens > sharkDens[idx]:
              sharkDens[idx] = maxDens
              sharkPal[idx] = uint8(pal)

      # Joint positions feed the scene digest: this is the float path whose
      # portability CI actually has to prove.
      for j in sharks[sIdx].joints:
        st.sc = mix(st.sc, quant(j.x))
        st.sc = mix(st.sc, quant(j.y))

    # 5. Draw only the sharks' cells on top of the static world.
    var cells = 0
    for gy in 0 ..< gridRows:
      let rowOff = gy * gridCols
      for gx in 0 ..< gridCols:
        let d = sharkDens[rowOff + gx]
        if d > 0.08:
          inc cells
          drawMosaicCell(gx, gy, d, int(sharkPal[rowOff + gx]))
    inc st.cells, cells

    # 6. Interface on top, then the monitor.
    if showUi:
      drawHonestUi(sceneW, sceneH, frame, fontUi, fontTitle, fontSmall,
                   fontBtn, typed)
    drawHud(if Selftest: 0 else: fps, fontHud, fontSmall, fontBtn, showUi,
            followCursor, st.blitOk)
    uiText(fontBtn, 16, sceneH - 24,
           "ESC quit | U panel | F follow | type + Enter to send (" & $sent &
             ") | backend " & BackendName & " | cells " & $cells, 0x2b2b26,
           digest = false)

    inc frame
    inc fpsFrames
    if not Selftest:
      let now = getTicks()
      if now - fpsMark >= 500:
        fps = (fpsFrames * 1000) div max(1, now - fpsMark)
        fpsFrames = 0
        fpsMark = now
    if Selftest and frame >= SelftestFrames:
      running = false

    refresh()
    if not Selftest:
      sleep(16)

  if Selftest:
    echo "SHARKS_DIGEST backend=", BackendName,
         " frames=", frame, " w=", sceneW, " h=", sceneH,
         " rects=", st.rects, " lines=", st.lines, " texts=", st.texts,
         " blits=", st.blits, " cells=", st.cells,
         " bakeRects=", st.bakeRects,
         " blitTried=", st.blitTried, " blitOk=", st.blitOk,
         " geom=", hex8(st.geom), " bake=", hex8(st.bake),
         " txt=", hex8(st.txt), " pos=", hex8(st.pos), " sc=", hex8(st.sc)

  closeFont(fontTitle)
  closeFont(fontUi)
  closeFont(fontHud)
  closeFont(fontSmall)
  closeFont(fontBtn)
  shutdown()

main()
