## hello.nim -- Minimal interactive uirelays example.
## Opens a window, draws interactive color buttons, animated diagonal rays,
## click crosshair marker, and adapts dynamically to window resizing.
##
## Compile:
##   nim c --mm:arc -d:html examples/hello.nim
##   nim c --mm:arc -d:canvas examples/hello.nim

import uirelays

proc drawBorder(r: Rect; c: Color) =
  if r.w <= 0 or r.h <= 0: return
  drawLine(r.x, r.y, r.x + r.w - 1, r.y, c)
  drawLine(r.x, r.y, r.x, r.y + r.h - 1, c)
  drawLine(r.x + r.w - 1, r.y, r.x + r.w - 1, r.y + r.h - 1, c)
  drawLine(r.x, r.y + r.h - 1, r.x + r.w - 1, r.y + r.h - 1, c)

proc main() {.uirApp.} =
  let layout = createWindow(640, 480)
  var width = layout.width
  var height = layout.height

  var fm = FontMetrics()
  let font = openFont("", layout.scaled(16), fm)
  setWindowTitle("Hello uirelays")

  let bg = color(30, 30, 46)
  let fg = color(205, 214, 244)
  let accent = color(137, 180, 250)
  let pink = color(245, 194, 231)
  let green = color(166, 227, 161)
  let yellow = color(249, 226, 175)

  var running = true
  var mouseX = 220
  var mouseY = 240
  var hoverX = 0
  var hoverY = 0
  var selectedIdx = 0
  var activeColor = accent
  var animateRays = true
  var clickCount = 0
  var clickMsg = "Click buttons above or click anywhere to place marker"

  while running:
    let padX = max(24, width div 18)
    let gap = max(12, width div 40)
    let boxW = clamp((width - padX * 2 - gap * 3) div 4, 96, 180)
    let boxH = clamp(height div 6, 56, 92)
    let boxY = 58

    let btnRects = [
      rect(padX, boxY, boxW, boxH),
      rect(padX + (boxW + gap), boxY, boxW, boxH),
      rect(padX + (boxW + gap) * 2, boxY, boxW, boxH),
      rect(padX + (boxW + gap) * 3, boxY, boxW, boxH)
    ]
    let btnColors = [accent, pink, green, yellow]
    let btnNames = ["Accent", "Pink", "Green", "Animate"]

    var e = Event()
    while pollEvent(e):
      case e.kind
      of QuitEvent, WindowCloseEvent:
        running = false
      of WindowResizeEvent, WindowMetricsEvent:
        width = max(360, e.x)
        height = max(280, e.y)
      of MouseMoveEvent:
        hoverX = e.x
        hoverY = e.y
      of MouseDownEvent:
        hoverX = e.x
        hoverY = e.y
        mouseX = e.x
        mouseY = e.y
        inc clickCount
        var hitBtn = -1
        for i in 0 ..< 4:
          if btnRects[i].contains(point(e.x, e.y)):
            hitBtn = i
            break
        if hitBtn in 0 .. 2:
          selectedIdx = hitBtn
          activeColor = btnColors[hitBtn]
          clickMsg = "Selected [" & btnNames[hitBtn] & "] theme (click #" & $clickCount & ")"
        elif hitBtn == 3:
          animateRays = not animateRays
          clickMsg = "Animation " & (if animateRays: "ENABLED" else: "PAUSED") & " (click #" & $clickCount & ")"
        else:
          clickMsg = "Clicked at (" & $e.x & ", " & $e.y & ") · Window " & $width & "×" & $height
          if e.button == RightButton:
            clickMsg &= " [Right]"
      of KeyDownEvent:
        if e.key == KeyEsc:
          running = false
        elif e.key == KeyQ and CtrlPressed in e.mods:
          running = false
        elif e.key == Key1:
          selectedIdx = 0; activeColor = accent; clickMsg = "Key 1: Accent"
        elif e.key == Key2:
          selectedIdx = 1; activeColor = pink; clickMsg = "Key 2: Pink"
        elif e.key == Key3:
          selectedIdx = 2; activeColor = green; clickMsg = "Key 3: Green"
        elif e.key == KeySpace:
          animateRays = not animateRays
      else: discard

    # background
    fillRect(rect(0, 0, width, height), bg)

    # title bar (stretches with window width)
    fillRect(rect(0, 0, width, 42), color(49, 50, 68))
    discard drawText(font, 16, 11, "Hello, uirelays!  [" & $width & "×" & $height & "]", fg, color(49, 50, 68))

    # interactive colored buttons
    for i in 0 ..< 4:
      let r = btnRects[i]
      let c = btnColors[i]
      fillRect(r, c)
      let isHovered = r.contains(point(hoverX, hoverY))
      let isSelected = (i == selectedIdx) or (i == 3 and animateRays)
      if isSelected or isHovered:
        drawBorder(rect(r.x - 2, r.y - 2, r.w + 4, r.h + 4), fg)
      let lbl = if i == 3: (if animateRays: "Anim: ON" else: "Anim: OFF") else: btnNames[i]
      let ext = measureText(font, lbl)
      let tx = r.x + max(6, (r.w - ext.w) div 2)
      let ty = r.y + max(6, (r.h - ext.h) div 2)
      discard drawText(font, tx, ty, lbl, bg, c)

    # animated diagonal lines that adapt to window width
    let rayTop = boxY + boxH + 28
    let rayBottom = min(height - 96, rayTop + max(70, height div 4))
    let phase = if animateRays: (getTicks() div 35) mod 24 else: 0
    let rayCount = max(8, (width - padX * 2 - 100) div 24)
    for i in 0 ..< rayCount:
      let x = padX + i * 24 + phase
      if x + 90 < width - padX:
        drawLine(x, rayTop, x + 90, rayBottom, activeColor)

    # interactive click marker crosshair
    if mouseY > 44:
      let mx = clamp(mouseX, 12, width - 12)
      let my = clamp(mouseY, 48, height - 48)
      fillRect(rect(mx - 5, my - 5, 11, 11), activeColor)
      drawLine(mx - 12, my, mx + 12, my, fg)
      drawLine(mx, my - 12, mx, my + 12, fg)

    # click feedback
    discard drawText(font, padX, height - 74, clickMsg, fg, bg)

    # instructions
    discard drawText(font, padX, height - 38,
      "Click buttons (1-3, Space) or resize window · Press ESC or Ctrl+Q to quit",
      color(147, 153, 178), bg)

    refresh()
    sleep(16)

  closeFont(font)
  shutdown()

main()
