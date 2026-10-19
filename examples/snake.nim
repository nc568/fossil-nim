## snake.nim -- Minimalist Arcade Snake built purely in Nim (--mm:arc)
## on top of uirelays & uirelays/layout (Zero JS in application code).
##
## Features:
## - NIF declarative layout (header bar, 22x16 game arena, on-screen D-Pad sidebar, status bar)
## - Full keyboard controls (WASD / Arrow keys / Space to pause / R to restart)
## - Full mouse controls (clickable D-Pad, Step button, Wrap Walls toggle, Speed control, New Game)
##
## Compile:
##   nim c --mm:arc -d:html examples/snake.nim
##   nim c --mm:arc -d:canvas examples/snake.nim

import std/[tables]
import uirelays
import uirelays/layout

const SnakeLayoutSpec = """
(layout
  (header (px 42))
  (cols
    (arena)
    (sidebar (px 224)))
  (status (lines 1)))
"""

const
  GridCols = 22
  GridRows = 16

  bgWindow   = color(24, 24, 37)
  bgBoard    = color(17, 17, 27)
  bgSidebar  = color(30, 30, 46)
  bgBtn      = color(49, 50, 68)
  bgBtnAcc   = color(69, 71, 90)
  borderCol  = color(88, 91, 112)
  gridDotCol = color(45, 47, 66)
  snakeHead  = color(166, 227, 161)
  snakeBody1 = color(116, 199, 136)
  snakeBody2 = color(84, 168, 112)
  appleCol   = color(243, 139, 168)
  bonusCol   = color(249, 226, 175)
  fgMain     = color(205, 214, 244)
  fgSubtle   = color(147, 153, 178)

type
  GridPos = object
    x, y: int

  Direction = enum
    dirRight, dirDown, dirLeft, dirUp

  UiBtn = object
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

proc isOpposite(a, b: Direction): bool =
  (a == dirLeft and b == dirRight) or
  (a == dirRight and b == dirLeft) or
  (a == dirUp and b == dirDown) or
  (a == dirDown and b == dirUp)

proc main() {.uirApp.} =
  let win = createWindow(780, 520)
  var width = win.width
  var height = win.height

  var fmSmall, fmBold, fmTitle: FontMetrics
  let fontSmall = openFont("", win.scaled(13), fmSmall, {})
  let fontBold  = openFont("", win.scaled(14), fmBold, {FontStyle.bold})
  let fontTitle = openFont("", win.scaled(16), fmTitle, {FontStyle.bold})

  setWindowTitle("UIRelays Minimalist Snake")

  let parsed = parseLayout(SnakeLayoutSpec)
  doAssert parsed.error.len == 0, parsed.error

  var snake: seq[GridPos] = @[]
  var curDir = dirRight
  var nextDir = dirRight
  var apple = GridPos(x: 15, y: 8)
  var bonusApple = GridPos(x: 18, y: 4)
  var score = 30
  var bestScore = 30
  var stepsTaken = 0
  var paused = false
  var gameOver = false
  var wrapWalls = true
  var stepIntervalMs = 150
  var rngState = 0x13579BDF'u32

  proc nextRandInt(limit: int): int =
    rngState = rngState xor (rngState shl 13)
    rngState = rngState xor (rngState shr 17)
    rngState = rngState xor (rngState shl 5)
    result = int(rngState mod uint32(max(1, limit)))

  proc occupies(p: GridPos): bool =
    for s in snake:
      if s.x == p.x and s.y == p.y:
        return true
    false

  proc spawnApple(): GridPos =
    for attempt in 0 ..< 128:
      let candidate = GridPos(x: nextRandInt(GridCols), y: nextRandInt(GridRows))
      if not occupies(candidate):
        return candidate
    for y in 0 ..< GridRows:
      for x in 0 ..< GridCols:
        let c = GridPos(x: x, y: y)
        if not occupies(c):
          return c
    GridPos(x: 0, y: 0)

  proc resetGame() =
    snake = @[
      GridPos(x: 8, y: 8),
      GridPos(x: 7, y: 8),
      GridPos(x: 6, y: 8),
      GridPos(x: 5, y: 8),
      GridPos(x: 4, y: 8)
    ]
    curDir = dirRight
    nextDir = dirRight
    apple = GridPos(x: 14, y: 8)
    bonusApple = GridPos(x: 17, y: 4)
    score = 20
    if score > bestScore: bestScore = score
    gameOver = false
    paused = false

  resetGame()

  proc setDirection(d: Direction) =
    if not isOpposite(curDir, d):
      nextDir = d

  proc advanceSnake() =
    if gameOver or snake.len == 0:
      return
    curDir = nextDir
    var head = snake[0]
    case curDir
    of dirRight: inc head.x
    of dirLeft:  dec head.x
    of dirDown:  inc head.y
    of dirUp:    dec head.y

    if wrapWalls:
      head.x = (head.x + GridCols) mod GridCols
      head.y = (head.y + GridRows) mod GridRows
    else:
      if head.x < 0 or head.x >= GridCols or head.y < 0 or head.y >= GridRows:
        gameOver = true
        return

    # Self-collision check (excluding tail tip which moves forward)
    for i in 0 ..< snake.len - 1:
      if snake[i].x == head.x and snake[i].y == head.y:
        if wrapWalls:
          # In wrap/relaxed mode, trim tail instead of halting
          snake.setLen(max(3, i))
          break
        else:
          gameOver = true
          return

    snake.insert(head, 0)
    inc stepsTaken

    if head.x == apple.x and head.y == apple.y:
      score += 10
      if score > bestScore: bestScore = score
      apple = spawnApple()
    elif head.x == bonusApple.x and head.y == bonusApple.y:
      score += 25
      if score > bestScore: bestScore = score
      bonusApple = spawnApple()
    else:
      discard snake.pop()

  var lastTick = getTicks()
  var mouseX = 0
  var mouseY = 0
  var buttons: seq[UiBtn] = @[]
  var running = true

  proc triggerBtn(id: string) =
    case id
    of "up":    setDirection(dirUp); advanceSnake()
    of "down":  setDirection(dirDown); advanceSnake()
    of "left":  setDirection(dirLeft); advanceSnake()
    of "right": setDirection(dirRight); advanceSnake()
    of "step":  advanceSnake()
    of "pause": paused = not paused
    of "wrap":  wrapWalls = not wrapWalls
    of "faster": stepIntervalMs = max(60, stepIntervalMs - 30)
    of "slower": stepIntervalMs = min(360, stepIntervalMs + 30)
    of "reset": resetGame()
    else: discard

  while running:
    let cells = parsed.resolve(width, height, fmSmall.lineHeight, uiScale = win.uiScale)
    let headRect = cells["header"]
    let arenaRect = cells["arena"]
    let sideRect = cells["sidebar"]
    let statRect = cells["status"]

    buttons.setLen(0)
    let sx = sideRect.x + 14
    let sw = sideRect.w - 28
    let dpadW = (sw - 12) div 3

    # D-Pad layout in sidebar
    let dy = sideRect.y + 48
    buttons.add UiBtn(id: "up",    label: "▲ UP",    r: rect(sx + dpadW + 6, dy, dpadW, 34), bg: bgBtnAcc)
    buttons.add UiBtn(id: "left",  label: "◀ LEFT",  r: rect(sx, dy + 40, dpadW, 34), bg: bgBtnAcc)
    buttons.add UiBtn(id: "step",  label: "STEP",    r: rect(sx + dpadW + 6, dy + 40, dpadW, 34), bg: bgBtn)
    buttons.add UiBtn(id: "right", label: "RIGHT ▶", r: rect(sx + (dpadW + 6) * 2, dy + 40, dpadW, 34), bg: bgBtnAcc)
    buttons.add UiBtn(id: "down",  label: "▼ DOWN",  r: rect(sx + dpadW + 6, dy + 80, dpadW, 34), bg: bgBtnAcc)

    # Action controls
    let ay = dy + 132
    buttons.add UiBtn(
      id: "pause",
      label: if paused: "[>] Resume Game" else: "[||] Pause Game",
      r: rect(sx, ay, sw, 32),
      bg: if paused: color(46, 160, 67) else: bgBtn
    )
    buttons.add UiBtn(
      id: "wrap",
      label: if wrapWalls: "Walls: Wrap [ON]" else: "Walls: Solid [OFF]",
      r: rect(sx, ay + 40, sw, 32),
      bg: bgBtn
    )
    let halfW = (sw - 8) div 2
    buttons.add UiBtn(id: "slower", label: "Speed -", r: rect(sx, ay + 80, halfW, 30), bg: bgBtn)
    buttons.add UiBtn(id: "faster", label: "Speed +", r: rect(sx + halfW + 8, ay + 80, halfW, 30), bg: bgBtn)
    buttons.add UiBtn(
      id: "reset",
      label: "New Game (R)",
      r: rect(sx, ay + 120, sw, 34),
      bg: color(140, 60, 75)
    )

    var ev = default Event
    while pollEvent(ev):
      case ev.kind
      of QuitEvent, WindowCloseEvent:
        running = false
      of WindowResizeEvent, WindowMetricsEvent:
        width = max(520, ev.x)
        height = max(380, ev.y)
      of MouseMoveEvent:
        mouseX = ev.x
        mouseY = ev.y
      of MouseDownEvent:
        mouseX = ev.x
        mouseY = ev.y
        if ev.button == LeftButton:
          var hitButton = false
          for b in buttons:
            if b.r.contains(point(ev.x, ev.y)):
              triggerBtn(b.id)
              hitButton = true
              break
          # Clicking inside the board steers the snake toward the click!
          if not hitButton and arenaRect.contains(point(ev.x, ev.y)) and snake.len > 0:
            let pad = 16
            let cellW = max(12, (arenaRect.w - pad * 2) div GridCols)
            let cellH = max(12, (arenaRect.h - pad * 2) div GridRows)
            let cellSize = min(cellW, cellH)
            let boardX = arenaRect.x + (arenaRect.w - cellSize * GridCols) div 2
            let boardY = arenaRect.y + (arenaRect.h - cellSize * GridRows) div 2
            let headPxX = boardX + snake[0].x * cellSize + cellSize div 2
            let headPxY = boardY + snake[0].y * cellSize + cellSize div 2
            let dx = ev.x - headPxX
            let dyClick = ev.y - headPxY
            if abs(dx) > abs(dyClick):
              setDirection(if dx >= 0: dirRight else: dirLeft)
            else:
              setDirection(if dyClick >= 0: dirDown else: dirUp)
            advanceSnake()
      of KeyDownEvent:
        case ev.key
        of KeyUp, KeyW:    setDirection(dirUp); advanceSnake()
        of KeyDown, KeyS:  setDirection(dirDown); advanceSnake()
        of KeyLeft, KeyA:  setDirection(dirLeft); advanceSnake()
        of KeyRight, KeyD: setDirection(dirRight); advanceSnake()
        of KeySpace:       paused = not paused
        of KeyR:           resetGame()
        else: discard
      else:
        discard

    let now = getTicks()
    if not paused and not gameOver and (now - lastTick) >= stepIntervalMs:
      lastTick = now
      advanceSnake()

    # Render Frame
    fillRect(rect(0, 0, width, height), bgWindow)

    # Header
    fillRect(headRect, bgBoard)
    drawLine(headRect.x, headRect.y + headRect.h - 1, headRect.x + headRect.w, headRect.y + headRect.h - 1, borderCol)
    discard drawText(fontTitle, headRect.x + 16, headRect.y + 11, "UIRelays Minimalist Snake", snakeHead, bgBoard)
    let scoreBanner = "Score: " & $score & "   |   Best: " & $bestScore & "   |   Length: " & $snake.len
    discard drawText(fontBold, headRect.x + 280, headRect.y + 12, scoreBanner, fgMain, bgBoard)

    # Arena Board
    let pad = 16
    let cellW = max(12, (arenaRect.w - pad * 2) div GridCols)
    let cellH = max(12, (arenaRect.h - pad * 2) div GridRows)
    let cellSize = min(cellW, cellH)
    let boardW = cellSize * GridCols
    let boardH = cellSize * GridRows
    let boardX = arenaRect.x + (arenaRect.w - boardW) div 2
    let boardY = arenaRect.y + (arenaRect.h - boardH) div 2
    let boardRect = rect(boardX, boardY, boardW, boardH)

    fillRect(boardRect, bgBoard)
    drawBorder(boardRect, borderCol)

    # Subtle grid dots
    for gy in 0 ..< GridRows:
      for gx in 0 ..< GridCols:
        drawPoint(boardX + gx * cellSize + cellSize div 2,
                  boardY + gy * cellSize + cellSize div 2,
                  gridDotCol)

    # Draw Apples
    let ar = rect(boardX + apple.x * cellSize + 2, boardY + apple.y * cellSize + 2, cellSize - 4, cellSize - 4)
    fillRect(ar, appleCol)
    let br = rect(boardX + bonusApple.x * cellSize + 3, boardY + bonusApple.y * cellSize + 3, cellSize - 6, cellSize - 6)
    fillRect(br, bonusCol)

    # Draw Snake Segments
    for i, seg in snake:
      let sr = rect(boardX + seg.x * cellSize + 1, boardY + seg.y * cellSize + 1, cellSize - 2, cellSize - 2)
      let segCol = if i == 0: snakeHead
                   elif (i and 1) == 0: snakeBody1
                   else: snakeBody2
      fillRect(sr, segCol)
      if i == 0 and cellSize >= 12:
        # Eyes on snake head
        let eyeCol = bgBoard
        fillRect(rect(sr.x + 3, sr.y + 3, 3, 3), eyeCol)
        fillRect(rect(sr.x + sr.w - 6, sr.y + 3, 3, 3), eyeCol)

    if gameOver:
      let banner = rect(boardX + boardW div 2 - 130, boardY + boardH div 2 - 28, 260, 56)
      fillRect(banner, bgSidebar)
      drawBorder(banner, appleCol)
      discard drawText(fontTitle, banner.x + 24, banner.y + 10, "Game Over! Score: " & $score, appleCol, bgSidebar)
      discard drawText(fontSmall, banner.x + 36, banner.y + 32, "Press R or click New Game", fgMain, bgSidebar)

    # Sidebar
    fillRect(sideRect, bgSidebar)
    drawLine(sideRect.x, sideRect.y, sideRect.x, sideRect.y + sideRect.h, borderCol)
    discard drawText(fontBold, sideRect.x + 14, sideRect.y + 16, "Controls & Telemetry", fgMain, bgSidebar)

    for b in buttons:
      let hovered = b.r.contains(point(mouseX, mouseY))
      let fillCol = if hovered: brighten(b.bg, 22) else: b.bg
      fillRect(b.r, fillCol)
      drawBorder(b.r, borderCol)
      saveState()
      setClipRect(b.r)
      let ext = measureText(fontSmall, b.label)
      let tx = b.r.x + max(4, (b.r.w - ext.w) div 2)
      let ty = b.r.y + max(4, (b.r.h - ext.h) div 2)
      discard drawText(fontSmall, tx, ty, b.label, fgMain, fillCol)
      restoreState()

    let infoY = sideRect.y + 350
    discard drawText(fontSmall, sideRect.x + 14, infoY, "Steps: " & $stepsTaken, fgSubtle, bgSidebar)
    discard drawText(fontSmall, sideRect.x + 14, infoY + 20, "Tick: " & $stepIntervalMs & " ms", fgSubtle, bgSidebar)
    discard drawText(fontSmall, sideRect.x + 14, infoY + 40, "Tip: Click board or D-Pad", fgSubtle, bgSidebar)

    # Status Bar
    fillRect(statRect, bgBoard)
    drawLine(statRect.x, statRect.y, statRect.x + statRect.w, statRect.y, borderCol)
    let stateStr = if gameOver: "GAME OVER" elif paused: "PAUSED" else: "RUNNING"
    discard drawText(fontSmall, statRect.x + 14, statRect.y + 5,
      stateStr & " · Direction: " & $curDir & " · Red Apple = +10, Gold = +25", fgSubtle, bgBoard)

    refresh()
    sleep(16)

  closeFont(fontSmall)
  closeFont(fontBold)
  closeFont(fontTitle)
  shutdown()

main()
