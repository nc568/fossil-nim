## twenty48.nim -- Minimalist 2048 Puzzle built purely in Nim (--mm:arc)
## on top of uirelays & uirelays/layout (Zero JS in application code).
##
## Features:
## - NIF declarative layout (header with Score/Best/Moves, 4x4 board, controls sidebar, status bar)
## - Full slide & merge logic with single-step Undo history
## - Keyboard controls (WASD / Arrow keys / U to undo / N to reset) + clickable D-Pad & board edges
##
## Compile:
##   nim c --mm:arc -d:html examples/twenty48.nim
##   nim c --mm:arc -d:canvas examples/twenty48.nim

import std/[tables]
import uirelays
import uirelays/layout

const PuzzleLayoutSpec = """
(layout
  (header (px 44))
  (cols
    (board)
    (sidebar (px 224)))
  (status (lines 1)))
"""

const
  bgWindow  = color(24, 24, 37)
  bgBoard   = color(17, 17, 27)
  bgEmpty   = color(38, 40, 58)
  bgSidebar = color(30, 30, 46)
  bgBtn     = color(49, 50, 68)
  bgBtnAcc  = color(69, 71, 90)
  borderCol = color(88, 91, 112)
  fgLight   = color(205, 214, 244)
  fgDark    = color(17, 17, 27)
  fgSubtle  = color(147, 153, 178)

type
  Grid4x4 = array[4, array[4, int]]

  SlideDir = enum
    sdLeft, sdRight, sdUp, sdDown

  BtnItem = object
    id: string
    label: string
    r: Rect
    bg: Color

proc drawBorder(r: Rect; c: Color) =
  if r.w <= 0 or r.h <= 0: return
  drawLine(r.x, r.y, r.x + r.w - 1, r.y, c)
  drawLine(r.x, r.y, r.x, r.y + r.h - 1, c)
  drawLine(r.x + r.w - 1, r.y, r.x + r.w - 1, r.y + r.h - 1, c)
  drawLine(r.x, r.y + r.h - 1, r.x + r.w - 1, r.y + r.h - 1, c)

proc brighten(c: Color; delta: int): Color =
  color(
    uint8(clamp(int(c.r) + delta, 0, 255)),
    uint8(clamp(int(c.g) + delta, 0, 255)),
    uint8(clamp(int(c.b) + delta, 0, 255)),
    c.a
  )

proc tileColors(val: int): tuple[bg, fg: Color] =
  case val
  of 0:    (bgEmpty, fgSubtle)
  of 2:    (color(69, 71, 90), fgLight)
  of 4:    (color(88, 91, 112), fgLight)
  of 8:    (color(250, 179, 135), fgDark)
  of 16:   (color(254, 140, 89), fgDark)
  of 32:   (color(243, 139, 168), fgDark)
  of 64:   (color(235, 111, 146), fgDark)
  of 128:  (color(249, 226, 175), fgDark)
  of 256:  (color(166, 227, 161), fgDark)
  of 512:  (color(148, 226, 213), fgDark)
  of 1024: (color(137, 180, 250), fgDark)
  else:    (color(203, 166, 247), fgDark)

proc slideLine(line: array[4, int]): tuple[res: array[4, int]; gained: int; moved: bool] =
  var compact: array[4, int]
  var idx = 0
  for v in line:
    if v != 0:
      compact[idx] = v
      inc idx

  var merged: array[4, int]
  var outIdx = 0
  var i = 0
  var gained = 0
  while i < idx:
    if i + 1 < idx and compact[i] == compact[i + 1]:
      let nv = compact[i] * 2
      merged[outIdx] = nv
      gained += nv
      inc outIdx
      i += 2
    else:
      merged[outIdx] = compact[i]
      inc outIdx
      inc i

  var changed = false
  for k in 0 ..< 4:
    if merged[k] != line[k]:
      changed = true
      break
  (merged, gained, changed)

proc main() =
  let win = createWindow(720, 520)
  var width = win.width
  var height = win.height

  var fmSmall, fmBold, fmTile, fmTitle: FontMetrics
  let fontSmall = openFont("", win.scaled(13), fmSmall, {})
  let fontBold  = openFont("", win.scaled(14), fmBold, {FontStyle.bold})
  let fontTile  = openFont("", win.scaled(22), fmTile, {FontStyle.bold})
  let fontTitle = openFont("", win.scaled(16), fmTitle, {FontStyle.bold})

  setWindowTitle("UIRelays Minimalist 2048")

  let parsed = parseLayout(PuzzleLayoutSpec)
  doAssert parsed.error.len == 0, parsed.error

  var grid: Grid4x4
  var prevGrid: Grid4x4
  var score = 148
  var prevScore = 148
  var bestScore = 148
  var moves = 12
  var statusMsg = "Ready · Use Arrow keys, WASD, or click D-Pad / board edges"
  var rng = 0x2468ACE1'u32

  proc nextRand(limit: int): int =
    rng = rng xor (rng shl 13)
    rng = rng xor (rng shr 17)
    rng = rng xor (rng shl 5)
    int(rng mod uint32(max(1, limit)))

  proc spawnTile() =
    var empties: seq[tuple[r, c: int]] = @[]
    for r in 0 ..< 4:
      for c in 0 ..< 4:
        if grid[r][c] == 0:
          empties.add (r, c)
    if empties.len > 0:
      let pick = empties[nextRand(empties.len)]
      grid[pick.r][pick.c] = if nextRand(10) == 0: 4 else: 2

  proc initShowcaseBoard() =
    grid = [
      [64, 32, 16, 4],
      [8,  16, 4,  2],
      [4,  2,  2,  0],
      [2,  0,  0,  0]
    ]
    prevGrid = grid
    score = 148
    prevScore = 148
    moves = 12
    statusMsg = "New 2048 game ready"

  initShowcaseBoard()

  proc performSlide(dir: SlideDir) =
    let snapshot = grid
    let oldScore = score
    var anyMoved = false
    var totalGained = 0

    case dir
    of sdLeft:
      for r in 0 ..< 4:
        let (nl, g, m) = slideLine(grid[r])
        grid[r] = nl
        totalGained += g
        if m: anyMoved = true
    of sdRight:
      for r in 0 ..< 4:
        let rev = [grid[r][3], grid[r][2], grid[r][1], grid[r][0]]
        let (nl, g, m) = slideLine(rev)
        grid[r] = [nl[3], nl[2], nl[1], nl[0]]
        totalGained += g
        if m: anyMoved = true
    of sdUp:
      for c in 0 ..< 4:
        let col = [grid[0][c], grid[1][c], grid[2][c], grid[3][c]]
        let (nl, g, m) = slideLine(col)
        for r in 0 ..< 4: grid[r][c] = nl[r]
        totalGained += g
        if m: anyMoved = true
    of sdDown:
      for c in 0 ..< 4:
        let col = [grid[3][c], grid[2][c], grid[1][c], grid[0][c]]
        let (nl, g, m) = slideLine(col)
        for r in 0 ..< 4: grid[3 - r][c] = nl[r]
        totalGained += g
        if m: anyMoved = true

    if anyMoved:
      prevGrid = snapshot
      prevScore = oldScore
      score += totalGained
      if score > bestScore: bestScore = score
      inc moves
      spawnTile()
      statusMsg = "Moved " & $dir & " (+" & $totalGained & " pts)"
    else:
      statusMsg = "No tiles could slide " & $dir

  proc maxTile(): int =
    for r in 0 ..< 4:
      for c in 0 ..< 4:
        if grid[r][c] > result:
          result = grid[r][c]

  var mouseX = 0
  var mouseY = 0
  var buttons: seq[BtnItem] = @[]
  var running = true

  proc handleBtn(id: string) =
    case id
    of "up":    performSlide(sdUp)
    of "down":  performSlide(sdDown)
    of "left":  performSlide(sdLeft)
    of "right": performSlide(sdRight)
    of "undo":
      grid = prevGrid
      score = prevScore
      statusMsg = "Undid last move"
    of "reset":
      initShowcaseBoard()
    else: discard

  while running:
    let cells = parsed.resolve(width, height, fmSmall.lineHeight, uiScale = win.uiScale)
    let headRect  = cells["header"]
    let boardArea = cells["board"]
    let sideRect  = cells["sidebar"]
    let statRect  = cells["status"]

    buttons.setLen(0)
    let sx = sideRect.x + 14
    let sw = sideRect.w - 28
    let dpadW = (sw - 8) div 2
    let dy = sideRect.y + 52

    buttons.add BtnItem(id: "up",    label: "▲ Slide Up",   r: rect(sx, dy, sw, 34), bg: bgBtnAcc)
    buttons.add BtnItem(id: "left",  label: "◀ Left",       r: rect(sx, dy + 42, dpadW, 34), bg: bgBtnAcc)
    buttons.add BtnItem(id: "right", label: "Right ▶",      r: rect(sx + dpadW + 8, dy + 42, dpadW, 34), bg: bgBtnAcc)
    buttons.add BtnItem(id: "down",  label: "▼ Slide Down", r: rect(sx, dy + 84, sw, 34), bg: bgBtnAcc)

    buttons.add BtnItem(id: "undo",  label: "↶ Undo Move (U)", r: rect(sx, dy + 136, sw, 32), bg: bgBtn)
    buttons.add BtnItem(id: "reset", label: "New Game (N)",    r: rect(sx, dy + 176, sw, 34), bg: color(140, 60, 75))

    var ev = default Event
    while pollEvent(ev):
      case ev.kind
      of QuitEvent, WindowCloseEvent:
        running = false
      of WindowResizeEvent, WindowMetricsEvent:
        width = max(480, ev.x)
        height = max(380, ev.y)
      of MouseMoveEvent:
        mouseX = ev.x
        mouseY = ev.y
      of MouseDownEvent:
        mouseX = ev.x
        mouseY = ev.y
        if ev.button == LeftButton:
          var hit = false
          for b in buttons:
            if b.r.contains(point(ev.x, ev.y)):
              handleBtn(b.id)
              hit = true
              break
          if not hit and boardArea.contains(point(ev.x, ev.y)):
            let cx = boardArea.x + boardArea.w div 2
            let cy = boardArea.y + boardArea.h div 2
            let dx = ev.x - cx
            let dyClick = ev.y - cy
            if abs(dx) > abs(dyClick):
              performSlide(if dx >= 0: sdRight else: sdLeft)
            else:
              performSlide(if dyClick >= 0: sdDown else: sdUp)
      of KeyDownEvent:
        case ev.key
        of KeyUp, KeyW:    performSlide(sdUp)
        of KeyDown, KeyS:  performSlide(sdDown)
        of KeyLeft, KeyA:  performSlide(sdLeft)
        of KeyRight, KeyD: performSlide(sdRight)
        of KeyU:           handleBtn("undo")
        of KeyN, KeyR:     handleBtn("reset")
        else: discard
      else:
        discard

    # Render Frame
    fillRect(rect(0, 0, width, height), bgWindow)

    # Header
    fillRect(headRect, bgBoard)
    drawLine(headRect.x, headRect.y + headRect.h - 1, headRect.x + headRect.w, headRect.y + headRect.h - 1, borderCol)
    discard drawText(fontTitle, headRect.x + 16, headRect.y + 12, "UIRelays 2048", color(249, 226, 175), bgBoard)
    let hdrStats = "Score: " & $score & "   |   Best: " & $bestScore & "   |   Max Tile: " & $maxTile()
    discard drawText(fontBold, headRect.x + 250, headRect.y + 13, hdrStats, fgLight, bgBoard)

    # 4x4 Board
    let boardSize = min(boardArea.w - 36, boardArea.h - 36)
    let gap = 10
    let tileSize = max(44, (boardSize - gap * 5) div 4)
    let actualBoard = tileSize * 4 + gap * 5
    let bx = boardArea.x + (boardArea.w - actualBoard) div 2
    let by = boardArea.y + (boardArea.h - actualBoard) div 2
    let outerRect = rect(bx, by, actualBoard, actualBoard)

    fillRect(outerRect, bgBoard)
    drawBorder(outerRect, borderCol)

    for r in 0 ..< 4:
      for c in 0 ..< 4:
        let val = grid[r][c]
        let tr = rect(bx + gap + c * (tileSize + gap), by + gap + r * (tileSize + gap), tileSize, tileSize)
        let (tBg, tFg) = tileColors(val)
        fillRect(tr, tBg)
        drawBorder(tr, borderCol)
        if val > 0:
          let lbl = $val
          let ext = measureText(fontTile, lbl)
          let tx = tr.x + max(4, (tr.w - ext.w) div 2)
          let ty = tr.y + max(4, (tr.h - ext.h) div 2)
          discard drawText(fontTile, tx, ty, lbl, tFg, tBg)

    # Sidebar
    fillRect(sideRect, bgSidebar)
    drawLine(sideRect.x, sideRect.y, sideRect.x, sideRect.y + sideRect.h, borderCol)
    discard drawText(fontBold, sideRect.x + 14, sideRect.y + 16, "Slide Controls", fgLight, bgSidebar)

    for b in buttons:
      let hovered = b.r.contains(point(mouseX, mouseY))
      let fillCol = if hovered: brighten(b.bg, 22) else: b.bg
      fillRect(b.r, fillCol)
      drawBorder(b.r, borderCol)
      saveState()
      setClipRect(b.r)
      let ext = measureText(fontSmall, b.label)
      let tx = b.r.x + max(6, (b.r.w - ext.w) div 2)
      let ty = b.r.y + max(4, (b.r.h - ext.h) div 2)
      discard drawText(fontSmall, tx, ty, b.label, fgLight, fillCol)
      restoreState()

    let infoY = sideRect.y + 286
    discard drawText(fontSmall, sideRect.x + 14, infoY, "Moves: " & $moves, fgSubtle, bgSidebar)
    discard drawText(fontSmall, sideRect.x + 14, infoY + 22, "Max Tile: " & $maxTile(), fgSubtle, bgSidebar)
    discard drawText(fontSmall, sideRect.x + 14, infoY + 44, "Goal: 2048 Tile", fgSubtle, bgSidebar)

    # Status bar
    fillRect(statRect, bgBoard)
    drawLine(statRect.x, statRect.y, statRect.x + statRect.w, statRect.y, borderCol)
    discard drawText(fontSmall, statRect.x + 14, statRect.y + 5, statusMsg, fgSubtle, bgBoard)

    refresh()
    sleep(16)

  closeFont(fontSmall)
  closeFont(fontBold)
  closeFont(fontTile)
  closeFont(fontTitle)
  shutdown()

main()
