## calculator.nim -- Minimalist Desktop/Web Calculator built purely in Nim (--mm:arc)
## on top of uirelays & uirelays/layout (Zero JS in application code).
##
## Features:
## - NIF declarative layout (header, calculator pad, live history tape, status bar)
## - Full arithmetic (+, -, ×, ÷, %, ±, x², √x), memory registers (MC, MR, M+, M-)
## - Interactive mouse buttons with hover states + full keyboard numpad/shortcuts
## - Clickable history tape entries & clipboard integration (Copy Result)
##
## Compile:
##   nim c --mm:arc -d:html examples/calculator.nim
##   nim c --mm:arc -d:canvas examples/calculator.nim

import std/[strutils, math, tables]
import uirelays
import uirelays/layout

const CalcLayoutSpec = """
(layout
  (header (px 40))
  (cols
    (pad (stretch 3))
    (tape (stretch 2)))
  (status (lines 1)))
"""

const
  bgWindow   = color(24, 24, 37)
  bgSurface  = color(30, 30, 46)
  bgDisplay  = color(17, 17, 27)
  bgBtnNum   = color(49, 50, 68)
  bgBtnOp    = color(69, 71, 90)
  bgBtnEq    = color(137, 180, 250)
  bgBtnClear = color(243, 139, 168)
  bgBtnMem   = color(38, 40, 56)
  borderCol  = color(88, 91, 112)
  fgPrimary  = color(205, 214, 244)
  fgSubtle   = color(147, 153, 178)
  fgDark     = color(17, 17, 27)
  fgAccent   = color(166, 227, 161)

type
  CalcButton = object
    id: string
    label: string
    r: Rect
    bg: Color
    fg: Color

  HistoryItem = object
    exprText: string
    resultText: string
    val: float64

proc drawBorder(r: Rect; c: Color) =
  if r.w <= 0 or r.h <= 0: return
  drawLine(r.x, r.y, r.x + r.w - 1, r.y, c)
  drawLine(r.x, r.y, r.x, r.y + r.h - 1, c)
  drawLine(r.x + r.w - 1, r.y, r.x + r.w - 1, r.y + r.h - 1, c)
  drawLine(r.x, r.y + r.h - 1, r.x + r.w - 1, r.y + r.h - 1, c)

proc formatNumber(v: float64): string =
  if classify(v) in {fcNan, fcInf, fcNegInf}:
    return "Error"
  let rounded = round(v, 8)
  if abs(rounded - float64(int64(rounded))) < 1e-9 and abs(rounded) < 1e15:
    result = $int64(rounded)
  else:
    result = formatFloat(rounded, ffDecimal, 6)
    while result.len > 1 and result[^1] == '0':
      result.setLen(result.len - 1)
    if result.len > 1 and result[^1] == '.':
      result.setLen(result.len - 1)

proc brighten(c: Color; delta: int): Color =
  color(
    uint8(clamp(int(c.r) + delta, 0, 255)),
    uint8(clamp(int(c.g) + delta, 0, 255)),
    uint8(clamp(int(c.b) + delta, 0, 255)),
    c.a
  )

proc main() {.uirApp.} =
  let win = createWindow(680, 520)
  var width = win.width
  var height = win.height

  var fmSmall, fmBtn, fmDisplay, fmTitle: FontMetrics
  let fontSmall   = openFont("", win.scaled(13), fmSmall, {})
  let fontBtn     = openFont("", win.scaled(15), fmBtn, {FontStyle.bold})
  let fontDisplay = openFont("", win.scaled(24), fmDisplay, {FontStyle.bold})
  let fontTitle   = openFont("", win.scaled(15), fmTitle, {FontStyle.bold})

  setWindowTitle("UIRelays Minimalist Calculator")

  let parsed = parseLayout(CalcLayoutSpec)
  doAssert parsed.error.len == 0, parsed.error

  var displayStr = "42"
  var exprLine = "6 × 7 ="
  var storedVal = 0.0
  var pendingOp = ""
  var resetOnNextDigit = true
  var memoryVal = 100.0
  var statusNote = "Ready · Click buttons or use keyboard (0-9, +, -, *, /, Enter)"
  var history: seq[HistoryItem] = @[
    HistoryItem(exprText: "128 + 256", resultText: "384", val: 384.0),
    HistoryItem(exprText: "1024 / 16", resultText: "64", val: 64.0),
    HistoryItem(exprText: "6 × 7", resultText: "42", val: 42.0)
  ]

  var mouseX = 0
  var mouseY = 0
  var buttons: seq[CalcButton] = @[]
  var running = true

  proc currentVal(): float64 =
    try:
      parseFloat(displayStr)
    except CatchableError:
      0.0

  proc pushHistory(eTxt, rTxt: string; v: float64) =
    history.add HistoryItem(exprText: eTxt, resultText: rTxt, val: v)
    if history.len > 10:
      history.delete(0)

  proc pressDigit(d: string) =
    if displayStr == "Error" or resetOnNextDigit:
      displayStr = if d == ".": "0." else: d
      resetOnNextDigit = false
    else:
      if d == "." and "." in displayStr:
        return
      if displayStr == "0" and d != ".":
        displayStr = d
      elif displayStr.len < 16:
        displayStr.add d
    statusNote = "Input: " & displayStr

  proc evaluatePending() =
    if pendingOp.len == 0:
      return
    let rhs = currentVal()
    var res = storedVal
    var ok = true
    case pendingOp
    of "+": res = storedVal + rhs
    of "-": res = storedVal - rhs
    of "×", "*": res = storedVal * rhs
    of "÷", "/":
      if abs(rhs) < 1e-12:
        ok = false
      else:
        res = storedVal / rhs
    else: discard

    let lhsStr = formatNumber(storedVal)
    let rhsStr = formatNumber(rhs)
    if not ok:
      exprLine = lhsStr & " " & pendingOp & " " & rhsStr & " ="
      displayStr = "Error"
      statusNote = "Division by zero"
    else:
      let resStr = formatNumber(res)
      exprLine = lhsStr & " " & pendingOp & " " & rhsStr & " ="
      displayStr = resStr
      pushHistory(lhsStr & " " & pendingOp & " " & rhsStr, resStr, res)
      statusNote = "Result: " & resStr
    pendingOp = ""
    resetOnNextDigit = true

  proc pressOperator(op: string) =
    if displayStr == "Error":
      displayStr = "0"
    if pendingOp.len > 0 and not resetOnNextDigit:
      evaluatePending()
    storedVal = currentVal()
    pendingOp = op
    exprLine = formatNumber(storedVal) & " " & op
    resetOnNextDigit = true
    statusNote = "Operator: " & op

  proc handleAction(id: string) =
    case id
    of "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", ".":
      pressDigit(id)
    of "+", "-", "×", "÷":
      pressOperator(id)
    of "=":
      evaluatePending()
    of "C":
      displayStr = "0"
      exprLine = "Cleared"
      storedVal = 0.0
      pendingOp = ""
      resetOnNextDigit = true
      statusNote = "Cleared calculator state"
    of "sign":
      if displayStr != "0" and displayStr != "Error":
        if displayStr.startsWith("-"):
          displayStr = displayStr[1 .. ^1]
        else:
          displayStr = "-" & displayStr
    of "pct":
      let v = currentVal() / 100.0
      displayStr = formatNumber(v)
      resetOnNextDigit = true
    of "back":
      if not resetOnNextDigit and displayStr != "Error":
        if displayStr.len > 1:
          displayStr.setLen(displayStr.len - 1)
          if displayStr == "-": displayStr = "0"
        else:
          displayStr = "0"
    of "sq":
      let v = currentVal()
      let r = v * v
      let rStr = formatNumber(r)
      exprLine = "sqr(" & formatNumber(v) & ") ="
      displayStr = rStr
      pushHistory("sqr(" & formatNumber(v) & ")", rStr, r)
      resetOnNextDigit = true
    of "sqrt":
      let v = currentVal()
      if v < 0:
        displayStr = "Error"
        statusNote = "Invalid input for square root"
      else:
        let r = sqrt(v)
        let rStr = formatNumber(r)
        exprLine = "sqrt(" & formatNumber(v) & ") ="
        displayStr = rStr
        pushHistory("sqrt(" & formatNumber(v) & ")", rStr, r)
      resetOnNextDigit = true
    of "mc":
      memoryVal = 0.0
      statusNote = "Memory cleared (M = 0)"
    of "mr":
      displayStr = formatNumber(memoryVal)
      resetOnNextDigit = true
      statusNote = "Recalled M = " & displayStr
    of "mplus":
      memoryVal += currentVal()
      statusNote = "Added to memory (M = " & formatNumber(memoryVal) & ")"
    of "mminus":
      memoryVal -= currentVal()
      statusNote = "Subtracted from memory (M = " & formatNumber(memoryVal) & ")"
    of "copy_res":
      putClipboardText(displayStr)
      statusNote = "Copied '" & displayStr & "' to clipboard"
    of "clear_tape":
      history.setLen(0)
      statusNote = "History tape cleared"
    else:
      if id.startsWith("hist_"):
        let idx = parseInt(id[5 .. ^1])
        if idx >= 0 and idx < history.len:
          displayStr = history[idx].resultText
          exprLine = history[idx].exprText & " ="
          resetOnNextDigit = true
          statusNote = "Loaded from tape: " & displayStr

  while running:
    let cells = parsed.resolve(width, height, fmSmall.lineHeight, uiScale = win.uiScale)
    let headRect = cells["header"]
    let padRect  = cells["pad"]
    let tapeRect = cells["tape"]
    let statRect = cells["status"]

    buttons.setLen(0)

    # Memory & scientific row
    let mx = padRect.x + 16
    let my = padRect.y + 114
    let mw = (padRect.w - 32 - 5 * 6) div 6
    let memIds = ["mc", "mr", "mplus", "mminus", "sq", "sqrt"]
    let memLabels = ["MC", "MR", "M+", "M-", "x²", "√x"]
    for i in 0 ..< 6:
      buttons.add CalcButton(
        id: memIds[i],
        label: memLabels[i],
        r: rect(mx + i * (mw + 6), my, mw, 28),
        bg: bgBtnMem,
        fg: fgSubtle
      )

    # 4x5 Main Keypad
    let gridTop = my + 38
    let gridH = max(180, padRect.h - (gridTop - padRect.y) - 16)
    let gap = 8
    let bw = (padRect.w - 32 - 3 * gap) div 4
    let bh = (gridH - 4 * gap) div 5

    const gridDefs: array[5, array[4, tuple[id, lbl: string; kind: int]]] = [
      [("C", "C", 3), ("sign", "+/-", 1), ("pct", "%", 1), ("÷", "÷", 1)],
      [("7", "7", 0), ("8", "8", 0), ("9", "9", 0), ("×", "×", 1)],
      [("4", "4", 0), ("5", "5", 0), ("6", "6", 0), ("-", "−", 1)],
      [("1", "1", 0), ("2", "2", 0), ("3", "3", 0), ("+", "+", 1)],
      [("0", "0", 0), (".", ".", 0), ("back", "⌫", 1), ("=", "=", 2)]
    ]

    for row in 0 ..< 5:
      for col in 0 ..< 4:
        let item = gridDefs[row][col]
        let btnBg = case item.kind
          of 1: bgBtnOp
          of 2: bgBtnEq
          of 3: bgBtnClear
          else: bgBtnNum
        let btnFg = if item.kind in {2, 3}: fgDark else: fgPrimary
        buttons.add CalcButton(
          id: item.id,
          label: item.lbl,
          r: rect(mx + col * (bw + gap), gridTop + row * (bh + gap), bw, bh),
          bg: btnBg,
          fg: btnFg
        )

    # Tape panel buttons
    let tx = tapeRect.x + 14
    let ty = tapeRect.y + 44
    let tw = max(100, tapeRect.w - 28)
    for i in 0 ..< history.len:
      let hr = rect(tx, ty + i * 38, tw, 32)
      if hr.y + hr.h < tapeRect.y + tapeRect.h - 46:
        buttons.add CalcButton(
          id: "hist_" & $i,
          label: history[i].exprText & " = " & history[i].resultText,
          r: hr,
          bg: bgSurface,
          fg: fgPrimary
        )

    let bottomBtnY = tapeRect.y + tapeRect.h - 42
    let halfW = (tw - 8) div 2
    buttons.add CalcButton(
      id: "copy_res",
      label: "Copy Result",
      r: rect(tx, bottomBtnY, halfW, 30),
      bg: bgBtnOp,
      fg: fgPrimary
    )
    buttons.add CalcButton(
      id: "clear_tape",
      label: "Clear Tape",
      r: rect(tx + halfW + 8, bottomBtnY, halfW, 30),
      bg: bgBtnMem,
      fg: fgSubtle
    )

    # Poll events
    var ev = default Event
    while pollEvent(ev, {WantTextInput}):
      case ev.kind
      of QuitEvent, WindowCloseEvent:
        running = false
      of WindowResizeEvent, WindowMetricsEvent:
        width = max(420, ev.x)
        height = max(360, ev.y)
      of MouseMoveEvent:
        mouseX = ev.x
        mouseY = ev.y
      of MouseDownEvent:
        mouseX = ev.x
        mouseY = ev.y
        if ev.button == LeftButton:
          for b in buttons:
            if b.r.contains(point(ev.x, ev.y)):
              handleAction(b.id)
              break
      of KeyDownEvent:
        if ev.key == KeyEsc:
          handleAction("C")
        elif ev.key == KeyBackspace:
          handleAction("back")
        elif ev.key == KeyEnter:
          handleAction("=")
        elif ev.key == KeyDelete:
          handleAction("C")
        elif CtrlPressed in ev.mods and ev.key == KeyC:
          handleAction("copy_res")
      of TextInputEvent:
        var ch = ""
        for c in ev.text:
          if c == '\0': break
          ch.add c
        case ch
        of "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", ".":
          pressDigit(ch)
        of "+": pressOperator("+")
        of "-": pressOperator("-")
        of "*": pressOperator("×")
        of "/": pressOperator("÷")
        of "=": evaluatePending()
        of "%": handleAction("pct")
        of "c", "C": handleAction("C")
        else: discard
      else:
        discard

    # Render Frame
    fillRect(rect(0, 0, width, height), bgWindow)

    # Header
    fillRect(headRect, bgDisplay)
    drawLine(headRect.x, headRect.y + headRect.h - 1, headRect.x + headRect.w, headRect.y + headRect.h - 1, borderCol)
    discard drawText(fontTitle, headRect.x + 16, headRect.y + 10, "UIRelays Calculator", fgPrimary, bgDisplay)
    let memBadge = "M: " & formatNumber(memoryVal)
    discard drawText(fontSmall, headRect.x + headRect.w - 110, headRect.y + 12, memBadge, fgAccent, bgDisplay)

    # Calculator Display Box
    let dispRect = rect(padRect.x + 16, padRect.y + 14, padRect.w - 32, 90)
    fillRect(dispRect, bgDisplay)
    drawBorder(dispRect, borderCol)
    saveState()
    setClipRect(dispRect)
    discard drawText(fontSmall, dispRect.x + 14, dispRect.y + 12, exprLine, fgSubtle, bgDisplay)
    let valExt = measureText(fontDisplay, displayStr)
    let valX = max(dispRect.x + 14, dispRect.x + dispRect.w - valExt.w - 16)
    discard drawText(fontDisplay, valX, dispRect.y + 42, displayStr, fgPrimary, bgDisplay)
    restoreState()

    # Tape Panel Divider & Header
    drawLine(tapeRect.x, tapeRect.y, tapeRect.x, tapeRect.y + tapeRect.h, borderCol)
    discard drawText(fontTitle, tapeRect.x + 14, tapeRect.y + 14, "History Tape (" & $history.len & ")", fgPrimary, bgWindow)
    if history.len == 0:
      discard drawText(fontSmall, tapeRect.x + 14, tapeRect.y + 52, "No calculations yet.", fgSubtle, bgWindow)

    # Render all buttons
    for b in buttons:
      let hovered = b.r.contains(point(mouseX, mouseY))
      let fillCol = if hovered: brighten(b.bg, 22) else: b.bg
      fillRect(b.r, fillCol)
      drawBorder(b.r, borderCol)
      saveState()
      setClipRect(b.r)
      let fnt = if b.id.startsWith("hist_") or b.id in ["mc", "mr", "mplus", "mminus", "sq", "sqrt", "copy_res", "clear_tape"]:
                  fontSmall
                else:
                  fontBtn
      let ext = measureText(fnt, b.label)
      let txPos = if b.id.startsWith("hist_"):
                    b.r.x + 10
                  else:
                    b.r.x + max(6, (b.r.w - ext.w) div 2)
      let tyPos = b.r.y + max(4, (b.r.h - ext.h) div 2)
      discard drawText(fnt, txPos, tyPos, b.label, b.fg, fillCol)
      restoreState()

    # Status bar
    fillRect(statRect, bgDisplay)
    drawLine(statRect.x, statRect.y, statRect.x + statRect.w, statRect.y, borderCol)
    discard drawText(fontSmall, statRect.x + 14, statRect.y + 5, statusNote, fgSubtle, bgDisplay)

    refresh()
    sleep(16)

  closeFont(fontSmall)
  closeFont(fontBtn)
  closeFont(fontDisplay)
  closeFont(fontTitle)
  shutdown()

main()
