## paint.nim -- Interactive drawing app using uirelays.
## Click and drag to paint. Click color swatches or top buttons (Brush -, Brush +, Clear).
## Right-click also clears. Scroll to change brush size. Adapts to window resize.
##
## Compile:
##   nim c --mm:arc -d:html examples/paint.nim
##   nim c --mm:arc -d:canvas examples/paint.nim

import uirelays/[coords, screen, input, backend]

const MaxStrokes = 100_000

type
  Stroke = object
    x, y, size: int
    col: Color

proc drawBorder(r: Rect; c: Color) =
  if r.w <= 0 or r.h <= 0: return
  drawLine(r.x, r.y, r.x + r.w - 1, r.y, c)
  drawLine(r.x, r.y, r.x, r.y + r.h - 1, c)
  drawLine(r.x + r.w - 1, r.y, r.x + r.w - 1, r.y + r.h - 1, c)
  drawLine(r.x, r.y + r.h - 1, r.x + r.w - 1, r.y + r.h - 1, c)

proc main() {.uirApp.} =
  initBackend()

  let layout = createWindow(800, 600)
  # The layout below is drawn for 800x600 and does not reflow below it:
  # declaring the floor keeps the viewport from shrinking into
  # territory where the interface is clipped away and unreachable.
  setMinViewport(800, 600)
  var width = layout.width
  var height = layout.height
  setWindowTitle("Paint - uirelays example")

  var fm: FontMetrics
  let font = openFont("", 13, fm, {FontStyle.bold})

  let palette = [
    color(137, 180, 250),  # blue
    color(245, 194, 231),  # pink
    color(166, 227, 161),  # green
    color(249, 226, 175),  # yellow
    color(243, 139, 168),  # red
    color(205, 214, 244),  # white
  ]

  var strokes = default(seq[Stroke])
  var brushSize = 6
  var brushColor = palette[0]
  var painting = false
  var running = true

  # Seed an initial colorful geometric wave so the canvas looks lively immediately
  for cIdx in 0 .. 3:
    let col = palette[cIdx]
    let yBase = 150 + cIdx * 70
    for step in 0 .. 18:
      let px = 110 + step * 28
      let py = yBase + (if step mod 2 == 0: -14 else: 14)
      strokes.add Stroke(x: px, y: py, size: 8, col: col)

  # The toolbar is anchored to the right edge and shrinks with the window.
  # It used to be three hardcoded rects at x=210/296/382 plus a readout at
  # x=474, which is fine in the 800px window the demo asks for and puts
  # "Clear" and the readout entirely past the edge in a 360px one -- where
  # `overflow:hidden` does not scroll them back into reach, it hides them.
  proc toolbarLayout(width, brushSize: int): tuple[minus, plus, clear: Rect;
      previewX, previewR, textX, textAvail: int] =
    let paletteRight = 10 + 4 * 30
    let previewR = min(brushSize, 14)
    let previewX = width - 12 - previewR
    let btnW = clamp((width - paletteRight - 40) div 4, 40, 78)
    let gap = 6
    let clearX = previewX - previewR - 12 - btnW
    let plusX = clearX - gap - btnW
    let minusX = plusX - gap - btnW
    (rect(minusX, 8, btnW, 24), rect(plusX, 8, btnW, 24),
     rect(clearX, 8, btnW, 24), previewX, previewR,
     paletteRight + 8, minusX - gap - (paletteRight + 8))

  ## Shortens `s` until it fits in `avail` pixels. Text that does not fit is
  ## not a layout problem the backend can solve: the window is the window.
  proc fitText(f: Font; s: string; avail: int): string =
    if avail <= 4: return ""
    result = s
    while result.len > 1 and measureText(f, result).w > avail:
      result.setLen(result.len - 1)
    if result.len < s.len and result.len > 1:
      result = result[0 ..< result.len - 1] & "\u2026"

  while running:
    let tb = toolbarLayout(width, brushSize)
    let btnMinus = tb.minus
    let btnPlus  = tb.plus
    let btnClear = tb.clear

    var e = Event()
    while pollEvent(e):
      case e.kind
      of QuitEvent, WindowCloseEvent:
        running = false
      of WindowResizeEvent, WindowMetricsEvent:
        width = max(800, e.x)
        height = max(600, e.y)
      of KeyDownEvent:
        if e.key == KeyEsc: running = false
        if e.key >= Key1 and e.key <= Key6:
          brushColor = palette[e.key.ord - Key1.ord]
        elif e.key == KeyC:
          strokes.setLen(0)
      of MouseDownEvent:
        if e.button == LeftButton:
          var handledUi = false
          for i, c in palette:
            let sx = 10 + i * 30
            if rect(sx, 8, 24, 24).contains(point(e.x, e.y)):
              brushColor = c
              handledUi = true
              break
          if not handledUi:
            if btnMinus.contains(point(e.x, e.y)):
              brushSize = clamp(brushSize - 2, 2, 40)
              handledUi = true
            elif btnPlus.contains(point(e.x, e.y)):
              brushSize = clamp(brushSize + 2, 2, 40)
              handledUi = true
            elif btnClear.contains(point(e.x, e.y)):
              strokes.setLen(0)
              handledUi = true
          if not handledUi and e.y > 40:
            painting = true
            if strokes.len < MaxStrokes:
              strokes.add Stroke(x: e.x, y: e.y, size: brushSize, col: brushColor)
        elif e.button == RightButton:
          strokes.setLen(0)
      of MouseUpEvent:
        if e.button == LeftButton:
          painting = false
      of MouseMoveEvent:
        if painting and e.y > 40 and strokes.len < MaxStrokes:
          strokes.add Stroke(x: e.x, y: e.y, size: brushSize, col: brushColor)
      of MouseWheelEvent:
        brushSize = clamp(brushSize + e.y, 1, 40)
      else: discard

    # --- draw ---
    let bg = color(30, 30, 46)
    let barBg = color(24, 24, 37)
    let btnBg = color(49, 50, 68)
    let fg = color(205, 214, 244)
    fillRect(rect(0, 0, width, height), bg)

    # draw all strokes
    for s in strokes:
      fillRect(rect(s.x - s.size, s.y - s.size, s.size * 2, s.size * 2), s.col)

    # Top toolbar
    fillRect(rect(0, 0, width, 40), barBg)
    drawLine(0, 39, width, 39, color(69, 71, 90))

    for i, c in palette:
      let x = 10 + i * 30
      fillRect(rect(x, 8, 24, 24), c)
      if c == brushColor:
        drawLine(x, 34, x + 24, 34, fg)

    fillRect(btnMinus, btnBg)
    drawBorder(btnMinus, color(88, 91, 112))
    discard drawText(font, btnMinus.x + 8, btnMinus.y + 5, "Brush -", fg, btnBg)

    fillRect(btnPlus, btnBg)
    drawBorder(btnPlus, color(88, 91, 112))
    discard drawText(font, btnPlus.x + 8, btnPlus.y + 5, "Brush +", fg, btnBg)

    fillRect(btnClear, color(140, 60, 75))
    drawBorder(btnClear, color(88, 91, 112))
    discard drawText(font, btnClear.x + 14, btnClear.y + 5, "Clear", fg, color(140, 60, 75))

    let sizeMsg = fitText(font,
      "Size: " & $brushSize & "px · Drag to paint (" & $width & "×" & $height & ")",
      tb.textAvail)
    if sizeMsg.len > 0:
      discard drawText(font, tb.textX, 13, sizeMsg, fg, barBg)

    # brush size preview in top-right
    let previewX = tb.previewX
    let previewY = 20
    let previewR = tb.previewR
    fillRect(rect(previewX - previewR, previewY - previewR, previewR * 2, previewR * 2), brushColor)

    refresh()
    sleep(16)

  closeFont(font)
  shutdown()

main()
