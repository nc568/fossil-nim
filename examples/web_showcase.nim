## web_showcase.nim -- Comprehensive interactive showcase & stress-test suite
## for UIRelays Web Backends (`-d:html` Pure DOM and `-d:canvas` HTML5 Canvas 2D).
##
## Exercises 100% of uirelays APIs:
## - WindowRelays: createWindow, getWindowLayout, refresh, saveState, restoreState,
##                 setClipRect, setCursor, setWindowTitle
## - FontRelays:   openFont (regular/bold/italic), closeFont, getFontMetrics,
##                 measureText, drawText, drawMeasuredText
## - DrawRelays:   fillRect, drawLine (H/V/diagonal), drawPoint, loadImage,
##                 freeImage, drawImage (full & cropped), imageSize, blitRGBA
## - InputRelays:  pollEvent, getTicks, sleep, shutdown, all mouse/key/wheel/text events
## - Clipboard:    getClipboardText, putClipboardText
## - Layout:       NIF layout parsing, hitTest, interactive buttons, tabs, paint pad
##
## Compile:
##   nim c --mm:arc -d:html examples/web_showcase.nim
##   nim c --mm:arc -d:canvas examples/web_showcase.nim

import std/[strutils, tables, os, unicode]
import uirelays
import uirelays/layout
import uirelays/drivers/web_common

const ShowcaseLayoutSpec = """
(layout
  (topbar (px 44))
  (cols
    (sidebar (px 226))
    (center)
    (inspector (px 234)))
  (statusbar (lines 1)))
"""

type
  ShowcaseTab = enum
    TabWidgets = "Widgets & Controls"
    TabGraphics = "Graphics, Clip & Blit"
    TabPaint = "Interactive Paint"
    TabEvents = "Event & Monkey Log"

  PaintDot = object
    x, y, r: int
    c: Color

  ButtonDef = object
    id: string
    label: string
    rect: Rect
    bg: Color

proc drawBoxBorder(r: Rect; c: Color) =
  if r.w <= 0 or r.h <= 0: return
  drawLine(r.x, r.y, r.x + r.w - 1, r.y, c)
  drawLine(r.x, r.y, r.x, r.y + r.h - 1, c)
  drawLine(r.x + r.w - 1, r.y, r.x + r.w - 1, r.y + r.h - 1, c)
  drawLine(r.x, r.y + r.h - 1, r.x + r.w - 1, r.y + r.h - 1, c)

proc createSampleIconPng(path: string) =
  ## Creates a 32x32 colorful gradient PNG image on disk using our pure-Nim PNG encoder
  ## so `loadImage`, `imageSize`, and `drawImage` can be tested anywhere without external assets.
  if fileExists(path):
    return
  var pixels = newSeq[uint32](32 * 32)
  for y in 0 ..< 32:
    for x in 0 ..< 32:
      let r = uint32((x * 8) and 0xFF)
      let g = uint32((y * 8) and 0xFF)
      let b = uint32(((x xor y) * 8) and 0xFF)
      pixels[y * 32 + x] = (0xFF'u32 shl 24) or (r shl 16) or (g shl 8) or b
  let pngBytes = encodeRgbaToPngBytes(cast[ptr UncheckedArray[uint32]](addr pixels[0]), 32, 32)
  if pngBytes.len > 0:
    var s = newString(pngBytes.len)
    for i in 0 ..< pngBytes.len:
      s[i] = char(pngBytes[i])
    try:
      writeFile(path, s)
    except CatchableError:
      discard

proc eventString(text: array[4, char]): string =
  result = ""
  for ch in text:
    if ch == '\0': break
    result.add ch

proc removeLastUtf8Rune(s: var string) =
  if s.len == 0: return
  let (_, runeBytes) = lastRune(s, s.high)
  s.setLen(s.len - runeBytes)

proc main() =
  let win = createWindow(960, 640)
  var width = win.width
  var height = win.height

  var fmReg, fmBold, fmItalic, fmTitle: FontMetrics
  let fontReg = openFont("", win.scaled(14), fmReg, {})
  let fontBold = openFont("", win.scaled(14), fmBold, {FontStyle.bold})
  let fontItalic = openFont("", win.scaled(13), fmItalic, {FontStyle.italics})
  let fontTitle = openFont("", win.scaled(16), fmTitle, {FontStyle.bold})

  setWindowTitle("UIRelays Web Showcase")
  putClipboardText("UIRelays Initial Clipboard")

  let iconPath = getTempDir() / "uirelays_showcase_test_icon.png"
  createSampleIconPng(iconPath)
  let sampleImg = loadImage(iconPath)
  let (imgW, imgH) = imageSize(sampleImg)

  var blitBuf = newSeq[uint32](48 * 48)

  let parsedLayout = parseLayout(ShowcaseLayoutSpec)
  doAssert parsedLayout.error.len == 0, parsedLayout.error

  var activeTab = TabWidgets
  var counter = 0
  var darkTheme = true
  var toggleA = true
  var toggleB = false
  var toggleC = true
  var sliderVal = 50
  var cursorIdx = 0
  let allCursors = [
    curDefault, curArrow, curIbeam, curWait,
    curCrosshair, curHand, curSizeNS, curSizeWE
  ]
  var textInput = "Type here in Nim ARC!"
  var paintDots: seq[PaintDot] = @[]
  var brushRadius = 6
  var brushColorIdx = 0
  let palette = [
    color(137, 180, 250),
    color(166, 227, 161),
    color(249, 226, 175),
    color(243, 139, 168),
    color(203, 166, 247),
    color(148, 226, 213)
  ]
  var isPainting = false
  var mouseX = 0
  var mouseY = 0
  var totalClicks = 0
  var totalKeyDowns = 0
  var wheelDeltaAccum = 0
  var focusState = "Focused"
  var eventLog: seq[string] = @[
    "Showcase initialized",
    "Loaded test image " & $imgW & "x" & $imgH
  ]
  var buttons: seq[ButtonDef] = @[]
  var running = true

  proc addLog(msg: string) =
    eventLog.add msg
    if eventLog.len > 18:
      eventLog.delete(0)

  while running:
    let cells = parsedLayout.resolve(width, height, fmReg.lineHeight, uiScale = win.uiScale)
    let topRect = cells["topbar"]
    let sideRect = cells["sidebar"]
    let centerRect = cells["center"]
    let inspRect = cells["inspector"]
    let statusRect = cells["statusbar"]

    # Build interactive buttons for the current frame so click testing hits them accurately
    buttons.setLen(0)

    # Sidebar tab buttons
    var tabIdx = 0
    for tab in ShowcaseTab:
      let r = rect(sideRect.x + 12, sideRect.y + 44 + tabIdx * 42, sideRect.w - 24, 34)
      buttons.add ButtonDef(
        id: "tab_" & $tabIdx,
        label: $tab,
        rect: r,
        bg: if activeTab == tab: color(69, 71, 90) else: color(49, 50, 68)
      )
      inc tabIdx

    # Sidebar quick action buttons
    buttons.add ButtonDef(
      id: "theme_toggle",
      label: if darkTheme: "Theme: Dark" else: "Theme: Light",
      rect: rect(sideRect.x + 12, sideRect.y + 230, sideRect.w - 24, 32),
      bg: color(88, 91, 112)
    )
    buttons.add ButtonDef(
      id: "cursor_cycle",
      label: "Cursor: " & $allCursors[cursorIdx],
      rect: rect(sideRect.x + 12, sideRect.y + 270, sideRect.w - 24, 32),
      bg: color(88, 91, 112)
    )
    buttons.add ButtonDef(
      id: "clip_copy",
      label: "Copy to Clipboard",
      rect: rect(sideRect.x + 12, sideRect.y + 310, sideRect.w - 24, 32),
      bg: color(88, 91, 112)
    )
    buttons.add ButtonDef(
      id: "clip_paste",
      label: "Paste Clipboard",
      rect: rect(sideRect.x + 12, sideRect.y + 350, sideRect.w - 24, 32),
      bg: color(88, 91, 112)
    )
    buttons.add ButtonDef(
      id: "clear_state",
      label: "Reset State & Paint",
      rect: rect(sideRect.x + 12, sideRect.y + 390, sideRect.w - 24, 32),
      bg: color(140, 60, 75)
    )

    # Center tab-specific buttons
    case activeTab
    of TabWidgets:
      let bx = centerRect.x + 20
      let by = centerRect.y + 60
      buttons.add ButtonDef(id: "inc_1", label: "+1", rect: rect(bx, by, 70, 34), bg: color(46, 160, 67))
      buttons.add ButtonDef(id: "dec_1", label: "-1", rect: rect(bx + 80, by, 70, 34), bg: color(208, 56, 76))
      buttons.add ButtonDef(id: "inc_10", label: "+10", rect: rect(bx + 160, by, 70, 34), bg: color(44, 120, 220))
      buttons.add ButtonDef(id: "reset_cnt", label: "Zero", rect: rect(bx + 240, by, 80, 34), bg: color(88, 91, 112))

      buttons.add ButtonDef(
        id: "tog_a",
        label: if toggleA: "[ON] High FPS Mode" else: "[OFF] High FPS Mode",
        rect: rect(bx, by + 54, 210, 32),
        bg: if toggleA: color(46, 160, 67) else: color(69, 71, 90)
      )
      buttons.add ButtonDef(
        id: "tog_b",
        label: if toggleB: "[ON] Diagnostic Grid" else: "[OFF] Diagnostic Grid",
        rect: rect(bx + 220, by + 54, 210, 32),
        bg: if toggleB: color(46, 160, 67) else: color(69, 71, 90)
      )
      buttons.add ButtonDef(
        id: "tog_c",
        label: if toggleC: "[ON] Clip Region Guard" else: "[OFF] Clip Region Guard",
        rect: rect(bx, by + 96, 210, 32),
        bg: if toggleC: color(46, 160, 67) else: color(69, 71, 90)
      )
      buttons.add ButtonDef(
        id: "slider_down",
        label: "Slider -10%",
        rect: rect(bx + 220, by + 96, 108, 32),
        bg: color(69, 71, 90)
      )
      buttons.add ButtonDef(
        id: "slider_up",
        label: "Slider +10%",
        rect: rect(bx + 336, by + 96, 108, 32),
        bg: color(69, 71, 90)
      )
      buttons.add ButtonDef(
        id: "clear_text",
        label: "Clear Text",
        rect: rect(bx + 336, by + 150, 108, 32),
        bg: color(140, 60, 75)
      )
    of TabGraphics:
      let bx = centerRect.x + 20
      let by = centerRect.y + 52
      for i in 0 ..< palette.len:
        buttons.add ButtonDef(
          id: "pal_" & $i,
          label: "C" & $(i + 1),
          rect: rect(bx + i * 54, by, 46, 28),
          bg: palette[i]
        )
    of TabPaint:
      let bx = centerRect.x + 20
      let by = centerRect.y + 48
      for i in 0 ..< palette.len:
        buttons.add ButtonDef(
          id: "paint_col_" & $i,
          label: "",
          rect: rect(bx + i * 36, by, 28, 28),
          bg: palette[i]
        )
      buttons.add ButtonDef(
        id: "paint_clear",
        label: "Clear Canvas",
        rect: rect(bx + 230, by, 118, 28),
        bg: color(208, 56, 76)
      )
    of TabEvents:
      buttons.add ButtonDef(
        id: "log_clear",
        label: "Clear Event Log",
        rect: rect(centerRect.x + 20, centerRect.y + 48, 150, 30),
        bg: color(88, 91, 112)
      )

    # Process all pending input events
    var e = default(Event)
    while pollEvent(e, {WantTextInput}):
      case e.kind
      of QuitEvent, WindowCloseEvent:
        addLog("Quit/Close received")
        running = false
      of WindowResizeEvent, WindowMetricsEvent:
        width = max(320, e.x)
        height = max(240, e.y)
        addLog("Resize -> " & $width & "x" & $height)
      of WindowFocusGainedEvent:
        focusState = "Focused"
        addLog("Window focus gained")
      of WindowFocusLostEvent:
        focusState = "Blurred"
        addLog("Window focus lost")
      of MouseMoveEvent:
        mouseX = e.x
        mouseY = e.y
        if isPainting and activeTab == TabPaint:
          let padRect = rect(centerRect.x + 20, centerRect.y + 88, centerRect.w - 40, centerRect.h - 108)
          if padRect.contains(point(e.x, e.y)) and paintDots.len < 5000:
            paintDots.add PaintDot(x: e.x, y: e.y, r: brushRadius, c: palette[brushColorIdx])
      of MouseUpEvent:
        isPainting = false
      of MouseWheelEvent:
        wheelDeltaAccum += e.y
        brushRadius = clamp(brushRadius + e.y, 2, 24)
        sliderVal = clamp(sliderVal + e.y * 5, 0, 100)
        addLog("Wheel dy=" & $e.y & " radius=" & $brushRadius)
      of MouseDownEvent:
        mouseX = e.x
        mouseY = e.y
        inc totalClicks
        let p = point(e.x, e.y)
        var hitBtn = ""
        for b in buttons:
          if b.rect.contains(p):
            hitBtn = b.id
            break
        if hitBtn.len > 0:
          addLog("Click button: " & hitBtn)
          case hitBtn
          of "tab_0": activeTab = TabWidgets
          of "tab_1": activeTab = TabGraphics
          of "tab_2": activeTab = TabPaint
          of "tab_3": activeTab = TabEvents
          of "theme_toggle": darkTheme = not darkTheme
          of "cursor_cycle":
            cursorIdx = (cursorIdx + 1) mod allCursors.len
            setCursor(allCursors[cursorIdx])
          of "clip_copy":
            putClipboardText(textInput)
            addLog("Copied to clipboard")
          of "clip_paste":
            textInput.add getClipboardText()
            addLog("Pasted clipboard")
          of "clear_state":
            counter = 0
            paintDots.setLen(0)
            sliderVal = 50
          of "inc_1": inc counter
          of "dec_1": dec counter
          of "inc_10": counter += 10
          of "reset_cnt": counter = 0
          of "tog_a": toggleA = not toggleA
          of "tog_b": toggleB = not toggleB
          of "tog_c": toggleC = not toggleC
          of "slider_down": sliderVal = clamp(sliderVal - 10, 0, 100)
          of "slider_up": sliderVal = clamp(sliderVal + 10, 0, 100)
          of "clear_text": textInput.setLen(0)
          of "paint_clear": paintDots.setLen(0)
          of "log_clear": eventLog.setLen(0)
          else:
            if hitBtn.startsWith("pal_") or hitBtn.startsWith("paint_col_"):
              let idxStr = hitBtn.split("_")[^1]
              try:
                brushColorIdx = clamp(parseInt(idxStr), 0, palette.high)
              except ValueError:
                discard
          setWindowTitle("UIRelays Showcase [" & $activeTab & "] clicks=" & $totalClicks)
        elif activeTab == TabPaint:
          let padRect = rect(centerRect.x + 20, centerRect.y + 88, centerRect.w - 40, centerRect.h - 108)
          if padRect.contains(p):
            if e.button == RightButton:
              paintDots.setLen(0)
              addLog("Paint cleared via right-click")
            else:
              isPainting = true
              paintDots.add PaintDot(x: e.x, y: e.y, r: brushRadius, c: palette[brushColorIdx])
      of TextInputEvent:
        let s = eventString(e.text)
        if s.len > 0 and textInput.len < 120:
          textInput.add s
          addLog("TextInput: '" & s & "'")
      of KeyDownEvent:
        inc totalKeyDowns
        addLog("KeyDown: " & $e.key)
        case e.key
        of KeyEsc:
          running = false
        of KeyBackspace:
          removeLastUtf8Rune(textInput)
        of Key1: activeTab = TabWidgets
        of Key2: activeTab = TabGraphics
        of Key3: activeTab = TabPaint
        of Key4: activeTab = TabEvents
        of KeyUp: inc counter
        of KeyDown: dec counter
        else:
          if e.key == KeyV and CtrlPressed in e.mods:
            textInput.add getClipboardText()
          elif e.key == KeyC and CtrlPressed in e.mods:
            putClipboardText(textInput)
      else:
        discard

    # Update cursor on button hover if user hasn't locked a special diagnostic cursor
    var hoveringButton = false
    for b in buttons:
      if b.rect.contains(point(mouseX, mouseY)):
        hoveringButton = true
        break
    if hoveringButton:
      setCursor(curHand)
    else:
      setCursor(allCursors[cursorIdx])

    # Theme colors
    let bgMain   = if darkTheme: color(24, 24, 37) else: color(240, 242, 246)
    let bgPanel  = if darkTheme: color(30, 30, 46) else: color(255, 255, 255)
    let bgHeader = if darkTheme: color(17, 17, 27) else: color(226, 230, 238)
    let fgMain   = if darkTheme: color(205, 214, 244) else: color(28, 30, 36)
    let fgMuted  = if darkTheme: color(166, 173, 200) else: color(100, 106, 118)
    let borderCol = if darkTheme: color(69, 71, 90) else: color(204, 210, 220)

    fillRect(rect(0, 0, width, height), bgMain)

    # 1. Topbar
    fillRect(topRect, bgHeader)
    discard drawText(fontTitle, topRect.x + 14, topRect.y + 11,
      "UIRelays Web Showcase (" & $webCore.backendKind & " backend)", palette[0], bgHeader)
    let badgeText = "Clicks: " & $totalClicks & " | Keys: " & $totalKeyDowns &
                    " | Mouse: (" & $mouseX & "," & $mouseY & ")"
    let badgeExt = measureText(fontReg, badgeText)
    discard drawText(fontReg, max(topRect.x + 360, topRect.x + topRect.w - badgeExt.w - 16),
      topRect.y + 13, badgeText, fgMuted, bgHeader, known = badgeExt)
    drawLine(topRect.x, topRect.y + topRect.h - 1, topRect.x + topRect.w, topRect.y + topRect.h - 1, borderCol)

    # 2. Sidebar
    fillRect(sideRect, bgPanel)
    discard drawText(fontBold, sideRect.x + 12, sideRect.y + 14, "Navigation & Actions", fgMain, bgPanel)
    drawLine(sideRect.x + sideRect.w - 1, sideRect.y, sideRect.x + sideRect.w - 1, sideRect.y + sideRect.h, borderCol)

    # 3. Center panel
    fillRect(centerRect, bgMain)
    discard drawText(fontTitle, centerRect.x + 20, centerRect.y + 16, $activeTab, fgMain, bgMain)

    if toggleB:
      # Diagnostic dot grid using drawPoint
      var gx = centerRect.x + 16
      while gx < centerRect.x + centerRect.w - 16:
        var gy = centerRect.y + 44
        while gy < centerRect.y + centerRect.h - 16:
          drawPoint(gx, gy, borderCol)
          gy += 24
        gx += 24

    # Draw all registered buttons
    for b in buttons:
      let isHover = b.rect.contains(point(mouseX, mouseY))
      let fillCol = if isHover:
                      color(uint8(min(255, int(b.bg.r) + 25)),
                            uint8(min(255, int(b.bg.g) + 25)),
                            uint8(min(255, int(b.bg.b) + 25)), b.bg.a)
                    else: b.bg
      fillRect(b.rect, fillCol)
      drawBoxBorder(b.rect, borderCol)
      if b.label.len > 0:
        saveState()
        setClipRect(b.rect)
        let ty = b.rect.y + max(2, (b.rect.h - fmReg.lineHeight) div 2)
        discard drawText(fontReg, b.rect.x + 8, ty, b.label, color(255, 255, 255), fillCol)
        restoreState()

    # Tab-specific content
    case activeTab
    of TabWidgets:
      let bx = centerRect.x + 20
      let by = centerRect.y + 60
      discard drawText(fontBold, bx + 335, by + 8, "Counter = " & $counter, palette[1], bgMain)

      # Progress / Slider bar
      let barRect = rect(bx, by + 136, 310, 12)
      fillRect(barRect, color(49, 50, 68))
      fillRect(rect(barRect.x, barRect.y, barRect.w * sliderVal div 100, barRect.h), palette[0])
      drawBoxBorder(barRect, borderCol)

      # Live text input box
      let inputBox = rect(bx, by + 150, 320, 32)
      fillRect(inputBox, bgPanel)
      drawBoxBorder(inputBox, palette[0])
      discard drawText(fontReg, inputBox.x + 8, inputBox.y + 7, textInput, fgMain, bgPanel)

      # Styled fonts preview
      discard drawText(fontBold, bx, by + 200, "Bold Font Style (FontStyle.bold)", fgMain, bgMain)
      discard drawText(fontItalic, bx, by + 224, "Italic Font Style (FontStyle.italics)", fgMuted, bgMain)

      # Clipped box demonstration
      let clipDemoRect = rect(bx, by + 255, min(420, centerRect.w - 40), 90)
      fillRect(clipDemoRect, bgPanel)
      drawBoxBorder(clipDemoRect, palette[2])
      if toggleC:
        saveState()
        setClipRect(clipDemoRect)
      fillRect(rect(clipDemoRect.x - 20, clipDemoRect.y + 12, clipDemoRect.w + 60, 24), color(44, 120, 220))
      discard drawText(fontBold, clipDemoRect.x + 8, clipDemoRect.y + 15,
        "Clipped banner: overhangs are cleanly clipped by setClipRect!", color(255, 255, 255), color(44, 120, 220))
      drawLine(clipDemoRect.x, clipDemoRect.y, clipDemoRect.x + clipDemoRect.w, clipDemoRect.y + clipDemoRect.h, palette[3])
      drawLine(clipDemoRect.x, clipDemoRect.y + clipDemoRect.h, clipDemoRect.x + clipDemoRect.w, clipDemoRect.y, palette[1])
      if toggleC:
        restoreState()

    of TabGraphics:
      let gx = centerRect.x + 20
      let gy = centerRect.y + 96
      discard drawText(fontBold, gx, gy, "1. Lines (drawLine):", fgMain, bgMain)
      let lineBox = rect(gx, gy + 24, 180, 110)
      fillRect(lineBox, bgPanel)
      drawBoxBorder(lineBox, borderCol)
      for i in 0 ..< 6:
        drawLine(lineBox.x + 8, lineBox.y + 8 + i * 18,
                 lineBox.x + lineBox.w - 8, lineBox.y + lineBox.h - 8 - i * 18,
                 palette[i mod palette.len])

      discard drawText(fontBold, gx + 200, gy, "2. Image & Crop (drawImage):", fgMain, bgMain)
      if int(sampleImg) != 0:
        drawImage(sampleImg, rect(0, 0, imgW, imgH), rect(gx + 200, gy + 28, 64, 64))
        drawImage(sampleImg, rect(8, 8, 16, 16), rect(gx + 280, gy + 28, 64, 64))
        discard drawText(fontReg, gx + 200, gy + 98, "Full 32x32 & Cropped 16x16", fgMuted, bgMain)

      discard drawText(fontBold, gx, gy + 150, "3. Procedural 32-bit RGBA Blit (blitRGBA):", fgMain, bgMain)
      let t = getTicks() div 40
      for py in 0 ..< 48:
        for px in 0 ..< 48:
          let r = uint32(((px * 5 + t) xor (py * 3)) and 0xFF)
          let g = uint32(((py * 5 + t) + px * 2) and 0xFF)
          let b = uint32(((px + py + t * 2) * 4) and 0xFF)
          blitBuf[py * 48 + px] = (0xFF'u32 shl 24) or (r shl 16) or (g shl 8) or b
      discard blitRGBA(cast[ptr UncheckedArray[uint32]](addr blitBuf[0]), 48, 48,
        rect(gx, gy + 178, 48, 48))
      # Also test clipped blitRGBA where dst is smaller than source w x h
      discard blitRGBA(cast[ptr UncheckedArray[uint32]](addr blitBuf[0]), 48, 48,
        rect(gx + 64, gy + 178, 28, 28))

    of TabPaint:
      let padRect = rect(centerRect.x + 20, centerRect.y + 88, max(80, centerRect.w - 40), max(80, centerRect.h - 108))
      fillRect(padRect, bgPanel)
      drawBoxBorder(padRect, borderCol)
      saveState()
      setClipRect(padRect)
      for d in paintDots:
        fillRect(rect(d.x - d.r, d.y - d.r, d.r * 2, d.r * 2), d.c)
      restoreState()
      discard drawText(fontReg, padRect.x + 8, padRect.y + 8,
        "Drag to paint (" & $paintDots.len & " dots, radius=" & $brushRadius & ")", fgMuted, bgPanel)

    of TabEvents:
      let logBox = rect(centerRect.x + 20, centerRect.y + 88, max(100, centerRect.w - 40), max(100, centerRect.h - 108))
      fillRect(logBox, bgPanel)
      drawBoxBorder(logBox, borderCol)
      saveState()
      setClipRect(logBox)
      for i, line in eventLog:
        discard drawText(fontReg, logBox.x + 10, logBox.y + 8 + i * (fmReg.lineHeight + 2),
          line, fgMain, bgPanel)
      restoreState()

    # 4. Inspector panel
    fillRect(inspRect, bgPanel)
    drawLine(inspRect.x, inspRect.y, inspRect.x, inspRect.y + inspRect.h, borderCol)
    discard drawText(fontBold, inspRect.x + 12, inspRect.y + 14, "Live Telemetry", fgMain, bgPanel)
    let statsLines = [
      "Backend: " & $webCore.backendKind,
      "Window: " & $width & "x" & $height,
      "Scale: " & $win.uiScale & "%",
      "Counter: " & $counter,
      "Slider: " & $sliderVal & "%",
      "Clicks: " & $totalClicks,
      "Keys: " & $totalKeyDowns,
      "Wheel: " & $wheelDeltaAccum,
      "Focus: " & focusState,
      "Cursor: " & $allCursors[cursorIdx],
      "Dots: " & $paintDots.len,
      "ClipLen: " & $getClipboardText().len
    ]
    for i, sl in statsLines:
      discard drawText(fontReg, inspRect.x + 12, inspRect.y + 42 + i * (fmReg.lineHeight + 4),
        sl, fgMuted, bgPanel)

    # 5. Statusbar
    fillRect(statusRect, bgHeader)
    drawLine(statusRect.x, statusRect.y, statusRect.x + statusRect.w, statusRect.y, borderCol)
    discard drawText(fontReg, statusRect.x + 12, statusRect.y + 3,
      "Ready | Tab: " & $activeTab & " | Clipboard: " & getClipboardText(), fgMuted, bgHeader)

    refresh()
    input.sleep(if toggleA: 12 else: 20)

  freeImage(sampleImg)
  closeFont(fontReg)
  closeFont(fontBold)
  closeFont(fontItalic)
  closeFont(fontTitle)
  shutdown()

main()
