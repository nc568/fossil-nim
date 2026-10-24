## todo.nim -- Simple Todo list app using uirelays/layout.
## Add tasks, toggle completion, delete items, and navigate by keyboard.
##
## Compile from the examples/ directory:
##   nim c --path:../src -d:sdl3 -o:todo-highdpi todo.nim

import uirelays
import uirelays/layout
import std/[strutils, tables]

const
  BaseFontSize = 15

  LayoutSpec = """
(layout
  (header (lines 2))
  (composer (lines 2))
  (list)
  (status (lines 1)))
"""

  bgColor          = color(244, 243, 241)
  panelColor       = color(255, 255, 255)
  panelAltColor    = color(247, 248, 249)
  borderColor      = color(216, 219, 223)
  textColor        = color(29, 31, 34)
  mutedTextColor   = color(103, 107, 112)
  accentColor      = color(44, 120, 220)
  selectedRowColor = color(233, 240, 250)
  successColor     = color(46, 160, 67)
  dangerColor      = color(208, 56, 76)
  placeholderColor = color(126, 130, 135)
  dividerColor     = color(229, 232, 235)

type
  TodoItem = object
    text: string
    done: bool

  Focus = enum
    ComposerFocus, ListFocus

  HoverKind = enum
    HoverNone, HoverComposer, HoverRow, HoverCheckbox, HoverDelete

  HoverTarget = object
    kind: HoverKind
    index: int

proc insetRect(r: Rect; pad: int): Rect =
  rect(r.x + pad, r.y + pad, max(0, r.w - pad * 2), max(0, r.h - pad * 2))

proc drawBorder(r: Rect; c: Color) =
  if r.w <= 0 or r.h <= 0:
    return
  drawLine(r.x, r.y, r.x + r.w - 1, r.y, c)
  drawLine(r.x, r.y, r.x, r.y + r.h - 1, c)
  drawLine(r.x + r.w - 1, r.y, r.x + r.w - 1, r.y + r.h - 1, c)
  drawLine(r.x, r.y + r.h - 1, r.x + r.w - 1, r.y + r.h - 1, c)

proc countDone(items: seq[TodoItem]): int =
  result = 0
  for item in items:
    if item.done:
      inc result

proc summaryText(total, done: int): string =
  let remaining = total - done
  if total == 0:
    return "No tasks"
  if done == 0:
    return $remaining & " remaining"
  if remaining == 0:
    return "All completed"
  $remaining & " remaining, " & $done & " completed"

proc eventText(text: array[4, char]): string =
  result = ""
  for ch in text:
    if ch == '\0':
      break
    result.add ch

proc utf8StepAt(s: string; i: int): int {.inline.} =
  if i < 0 or i >= s.len: return 1
  let b = ord(s[i])
  if b < 0x80: 1
  elif (b and 0xE0) == 0xC0: 2
  elif (b and 0xF0) == 0xE0: 3
  elif (b and 0xF8) == 0xF0: 4
  else: 1

proc prevRunePos(s: string; pos: int): int =
  result = clamp(pos, 0, s.len)
  if result <= 0:
    return 0
  dec result
  while result > 0 and (ord(s[result]) and 0xC0) == 0x80:
    dec result

proc nextRunePos(s: string; pos: int): int =
  let p = clamp(pos, 0, s.len)
  if p >= s.len:
    return s.len
  result = min(s.len, p + utf8StepAt(s, p))

proc isWordByte(ch: char): bool {.inline.} =
  ch notin {' ', '\t', '\n', '\r', ',', '.', ';', ':', '!', '?', '-', '/', '(', ')', '[', ']'}

proc prevWordPos(s: string; pos: int): int =
  result = clamp(pos, 0, s.len)
  while result > 0 and not isWordByte(s[result - 1]):
    result = prevRunePos(s, result)
  while result > 0 and isWordByte(s[result - 1]):
    result = prevRunePos(s, result)

proc nextWordPos(s: string; pos: int): int =
  result = clamp(pos, 0, s.len)
  while result < s.len and isWordByte(s[result]):
    result = nextRunePos(s, result)
  while result < s.len and not isWordByte(s[result]):
    result = nextRunePos(s, result)

proc wordBoundsAt(s: string; pos: int): tuple[a, b: int] =
  if s.len == 0:
    return (0, 0)
  var p = clamp(pos, 0, s.len)
  if p == s.len and p > 0:
    p = prevRunePos(s, p)
  var a = p
  var b = p
  if isWordByte(s[p]):
    while a > 0 and isWordByte(s[a - 1]):
      a = prevRunePos(s, a)
    while b < s.len and isWordByte(s[b]):
      b = nextRunePos(s, b)
  else:
    while a > 0 and not isWordByte(s[a - 1]):
      a = prevRunePos(s, a)
    while b < s.len and not isWordByte(s[b]):
      b = nextRunePos(s, b)
  result = (a, b)

proc bytePosFromRelX(font: Font; s: string; relX: int): int =
  if relX <= 0 or s.len == 0:
    return 0
  var pos = 0
  var prevW = 0
  while pos < s.len:
    let nextP = nextRunePos(s, pos)
    let curW = measureText(font, s[0 ..< nextP]).w
    if prevW + max(1, curW - prevW) div 2 > relX:
      return pos
    prevW = curW
    pos = nextP
  result = s.len

proc hasTextSelection(caretPos, selAnchor: int): bool {.inline.} =
  selAnchor >= 0 and selAnchor != caretPos

proc selectionBounds(s: string; caretPos, selAnchor: int): tuple[a, b: int] {.inline.} =
  let a = clamp(min(caretPos, selAnchor), 0, s.len)
  let b = clamp(max(caretPos, selAnchor), 0, s.len)
  (a, b)

proc deleteTextSelection(s: var string; caretPos, selAnchor: var int): bool =
  if not hasTextSelection(caretPos, selAnchor):
    return false
  let (a, b) = selectionBounds(s, caretPos, selAnchor)
  if b > a:
    s = s[0 ..< a] & s[b .. ^1]
  caretPos = a
  selAnchor = -1
  result = true

proc insertAtCursor(s: var string; caretPos, selAnchor: var int; entered: string) =
  discard deleteTextSelection(s, caretPos, selAnchor)
  let p = clamp(caretPos, 0, s.len)
  s = s[0 ..< p] & entered & s[p .. ^1]
  caretPos = p + entered.len
  selAnchor = -1

proc truncateText(font: Font; text: string; maxWidth: int): string =
  if maxWidth <= 0:
    return ""
  if measureText(font, text).w <= maxWidth:
    return text

  let ellipsis = "..."
  let ellipsisWidth = measureText(font, ellipsis).w
  if ellipsisWidth > maxWidth:
    return ""

  var runeEnds: seq[int] = @[]
  var i = 0
  while i < text.len:
    i += utf8StepAt(text, i)
    runeEnds.add i

  var low = 0
  var high = runeEnds.len
  while low < high:
    let mid = (low + high + 1) shr 1
    let candidate =
      if mid == 0: ellipsis
      else: text[0 ..< runeEnds[mid - 1]] & ellipsis
    if measureText(font, candidate).w <= maxWidth:
      low = mid
    else:
      high = mid - 1

  if low == 0:
    return ellipsis
  result = text[0 ..< runeEnds[low - 1]]
  result.add ellipsis

proc rowHeightFor(fm: FontMetrics): int =
  fm.lineHeight + 8

proc visibleRowsFor(listInner: Rect; rowHeight: int): int =
  max(1, listInner.h div rowHeight)

proc checkboxRect(rowRect: Rect): Rect =
  let size = min(16, max(10, rowRect.h - 8))
  rect(rowRect.x + 8, rowRect.y + (rowRect.h - size) div 2, size, size)

proc deleteRect(rowRect: Rect): Rect =
  let size = min(18, max(12, rowRect.h - 8))
  rect(rowRect.x + rowRect.w - 8 - size, rowRect.y + (rowRect.h - size) div 2, size, size)

proc rowRectFor(listInner: Rect; rowHeight, visibleIndex: int): Rect =
  rect(listInner.x, listInner.y + visibleIndex * rowHeight, listInner.w, rowHeight)

proc clampSelection(items: seq[TodoItem]; selectedIndex, scrollIndex: var int;
                    visibleRows: int) =
  if items.len == 0:
    selectedIndex = -1
    scrollIndex = 0
    return

  selectedIndex = clamp(selectedIndex, 0, items.len - 1)
  let maxScroll = max(0, items.len - visibleRows)
  scrollIndex = clamp(scrollIndex, 0, maxScroll)

  if selectedIndex < scrollIndex:
    scrollIndex = selectedIndex
  elif selectedIndex >= scrollIndex + visibleRows:
    scrollIndex = selectedIndex - visibleRows + 1

  scrollIndex = clamp(scrollIndex, 0, maxScroll)

proc listInnerRect(listRect: Rect): Rect =
  insetRect(listRect, 6)

proc composerInnerRect(composerRect: Rect): Rect =
  insetRect(composerRect, 8)

proc hitList(listInner: Rect; rowHeight, scrollIndex: int; items: seq[TodoItem];
             x, y: int): HoverTarget =
  if not listInner.contains(point(x, y)):
    return HoverTarget(kind: HoverNone, index: -1)

  let visibleIndex = (y - listInner.y) div rowHeight
  let itemIndex = scrollIndex + visibleIndex
  if itemIndex < 0 or itemIndex >= items.len:
    return HoverTarget(kind: HoverNone, index: -1)

  let rowRect = rowRectFor(listInner, rowHeight, visibleIndex)
  let p = point(x, y)
  if deleteRect(rowRect).contains(p):
    return HoverTarget(kind: HoverDelete, index: itemIndex)
  if checkboxRect(rowRect).contains(p):
    return HoverTarget(kind: HoverCheckbox, index: itemIndex)
  HoverTarget(kind: HoverRow, index: itemIndex)

proc drawCheckbox(r: Rect; checked: bool) =
  fillRect(r, if checked: successColor else: panelColor)
  drawBorder(r, if checked: successColor else: borderColor)
  if checked:
    drawLine(r.x + 4, r.y + r.h div 2, r.x + r.w div 2 - 1, r.y + r.h - 5, panelColor)
    drawLine(r.x + r.w div 2 - 1, r.y + r.h - 5, r.x + r.w - 4, r.y + 4, panelColor)

proc drawDeleteButton(r: Rect; hovered: bool) =
  let fg = if hovered: panelColor else: dangerColor
  let bg = if hovered: dangerColor else: panelColor
  fillRect(r, bg)
  drawBorder(r, dangerColor)
  let pad = 4
  drawLine(r.x + pad, r.y + pad, r.x + r.w - pad - 1, r.y + r.h - pad - 1, fg)
  drawLine(r.x + r.w - pad - 1, r.y + pad, r.x + pad, r.y + r.h - pad - 1, fg)

proc main() {.uirApp.} =
  let win = createWindow(760, 560)
  # The layout below is drawn for 760x560 and does not reflow below it:
  # declaring the floor keeps the viewport from shrinking into
  # territory where the interface is clipped away and unreachable.
  setMinViewport(760, 560)
  var width = win.width
  var height = win.height

  var fm = FontMetrics()
  let font = openFont("", win.scaled(BaseFontSize), fm)
  setWindowTitle("Tasks")

  let parsedLayout = parseLayout(LayoutSpec)
  doAssert parsedLayout.error.len == 0, parsedLayout.error

  var items = @[
    TodoItem(text: "Review this week's priorities", done: true),
    TodoItem(text: "Reply to client email", done: false),
    TodoItem(text: "Prepare tomorrow's notes", done: false)
  ]
  var inputText = ""
  var caretPos = 0
  var selAnchor = -1
  var draggingInput = false
  var lastCaretTick = getTicks()
  var focus = ComposerFocus
  var selectedIndex = if items.len > 0: 0 else: -1
  var scrollIndex = 0
  var mouseX = 0
  var mouseY = 0
  var running = true

  while running:
    var cells = parsedLayout.resolve(width, height, fm.lineHeight)
    let rawComp = composerInnerRect(cells["composer"])
    let addBtnRect = rect(rawComp.x + rawComp.w - 78, rawComp.y, 78, rawComp.h)
    let composerRect = rect(rawComp.x, rawComp.y, max(120, rawComp.w - 86), rawComp.h)
    let listInner = listInnerRect(cells["list"])
    let rowHeight = rowHeightFor(fm)
    let visibleRows = visibleRowsFor(listInner, rowHeight)
    clampSelection(items, selectedIndex, scrollIndex, visibleRows)
    caretPos = clamp(caretPos, 0, inputText.len)
    if selAnchor > inputText.len:
      selAnchor = inputText.len

    let inputFlags = if focus == ComposerFocus: {WantTextInput} else: {}
    var e = default Event
    while pollEvent(e, inputFlags):
      case e.kind
      of QuitEvent, WindowCloseEvent:
        running = false
      of WindowResizeEvent, WindowMetricsEvent:
        width = max(760, e.x)
        height = max(560, e.y)
      of MouseMoveEvent:
        mouseX = e.x
        mouseY = e.y
        if draggingInput and focus == ComposerFocus:
          caretPos = bytePosFromRelX(font, inputText, e.x - (composerRect.x + 10))
          lastCaretTick = getTicks()
      of MouseUpEvent:
        mouseX = e.x
        mouseY = e.y
        if draggingInput:
          draggingInput = false
          if selAnchor == caretPos:
            selAnchor = -1
      of MouseWheelEvent:
        if listInner.contains(point(mouseX, mouseY)):
          let maxScroll = max(0, items.len - visibleRows)
          scrollIndex = clamp(scrollIndex - e.y, 0, maxScroll)
      of MouseDownEvent:
        mouseX = e.x
        mouseY = e.y
        let p = point(e.x, e.y)
        if addBtnRect.contains(p):
          draggingInput = false
          let trimmed = strutils.strip(inputText)
          let taskTitle = if trimmed.len > 0: trimmed else: "Follow up task #" & $(items.len + 1)
          items.add TodoItem(text: taskTitle, done: false)
          inputText.setLen(0)
          caretPos = 0
          selAnchor = -1
          selectedIndex = items.high
          clampSelection(items, selectedIndex, scrollIndex, visibleRows)
        elif composerRect.contains(p):
          focus = ComposerFocus
          lastCaretTick = getTicks()
          let clickedPos = bytePosFromRelX(font, inputText, e.x - (composerRect.x + 10))
          if e.clicks >= 3:
            selAnchor = 0
            caretPos = inputText.len
            draggingInput = false
          elif e.clicks == 2:
            let (wa, wb) = wordBoundsAt(inputText, clickedPos)
            selAnchor = wa
            caretPos = wb
            draggingInput = false
          elif ShiftPressed in e.mods:
            if selAnchor < 0:
              selAnchor = caretPos
            caretPos = clickedPos
            draggingInput = true
          else:
            caretPos = clickedPos
            selAnchor = clickedPos
            draggingInput = true
        else:
          draggingInput = false
          let hover = hitList(listInner, rowHeight, scrollIndex, items, e.x, e.y)
          case hover.kind
          of HoverDelete:
            focus = ListFocus
            if hover.index >= 0 and hover.index < items.len:
              items.delete(hover.index)
              clampSelection(items, selectedIndex, scrollIndex, visibleRows)
          of HoverCheckbox:
            focus = ListFocus
            if hover.index >= 0 and hover.index < items.len:
              selectedIndex = hover.index
              items[hover.index].done = not items[hover.index].done
              clampSelection(items, selectedIndex, scrollIndex, visibleRows)
          of HoverRow:
            focus = ListFocus
            selectedIndex = hover.index
            clampSelection(items, selectedIndex, scrollIndex, visibleRows)
          else:
            discard
      of TextInputEvent:
        if focus == ComposerFocus:
          let entered = eventText(e.text)
          if entered.len > 0:
            insertAtCursor(inputText, caretPos, selAnchor, entered)
            lastCaretTick = getTicks()
      of KeyDownEvent:
        let ctrl = CtrlPressed in e.mods or GuiPressed in e.mods
        let shift = ShiftPressed in e.mods
        lastCaretTick = getTicks()
        case e.key
        of KeyEsc:
          if focus == ComposerFocus and hasTextSelection(caretPos, selAnchor):
            selAnchor = -1
          else:
            running = false
        of KeyQ:
          if ctrl:
            running = false
        of KeyTab:
          if focus == ComposerFocus:
            focus = ListFocus
            if selectedIndex < 0 and items.len > 0:
              selectedIndex = 0
          else:
            focus = ComposerFocus
        of KeyEnter:
          if focus == ComposerFocus:
            let trimmed = strutils.strip(inputText)
            if trimmed.len > 0:
              items.add TodoItem(text: trimmed, done: false)
              inputText.setLen(0)
              caretPos = 0
              selAnchor = -1
              selectedIndex = items.high
              clampSelection(items, selectedIndex, scrollIndex, visibleRows)
          elif selectedIndex >= 0 and selectedIndex < items.len:
            items[selectedIndex].done = not items[selectedIndex].done
        of KeySpace:
          if focus == ListFocus and selectedIndex >= 0 and selectedIndex < items.len:
            items[selectedIndex].done = not items[selectedIndex].done
        of KeyLeft:
          if focus == ComposerFocus:
            if shift:
              if selAnchor < 0:
                selAnchor = caretPos
              caretPos = if ctrl: prevWordPos(inputText, caretPos) else: prevRunePos(inputText, caretPos)
              if selAnchor == caretPos:
                selAnchor = -1
            elif hasTextSelection(caretPos, selAnchor):
              caretPos = min(caretPos, selAnchor)
              selAnchor = -1
            else:
              caretPos = if ctrl: prevWordPos(inputText, caretPos) else: prevRunePos(inputText, caretPos)
        of KeyRight:
          if focus == ComposerFocus:
            if shift:
              if selAnchor < 0:
                selAnchor = caretPos
              caretPos = if ctrl: nextWordPos(inputText, caretPos) else: nextRunePos(inputText, caretPos)
              if selAnchor == caretPos:
                selAnchor = -1
            elif hasTextSelection(caretPos, selAnchor):
              caretPos = max(caretPos, selAnchor)
              selAnchor = -1
            else:
              caretPos = if ctrl: nextWordPos(inputText, caretPos) else: nextRunePos(inputText, caretPos)
        of KeyHome:
          if focus == ComposerFocus:
            if shift:
              if selAnchor < 0:
                selAnchor = caretPos
              caretPos = 0
              if selAnchor == caretPos:
                selAnchor = -1
            else:
              caretPos = 0
              selAnchor = -1
        of KeyEnd:
          if focus == ComposerFocus:
            if shift:
              if selAnchor < 0:
                selAnchor = caretPos
              caretPos = inputText.len
              if selAnchor == caretPos:
                selAnchor = -1
            else:
              caretPos = inputText.len
              selAnchor = -1
        of KeyBackspace:
          if focus == ComposerFocus:
            if not deleteTextSelection(inputText, caretPos, selAnchor):
              let p = if ctrl: prevWordPos(inputText, caretPos) else: prevRunePos(inputText, caretPos)
              if p < caretPos:
                inputText = inputText[0 ..< p] & inputText[caretPos .. ^1]
                caretPos = p
          elif focus == ListFocus and selectedIndex >= 0 and selectedIndex < items.len:
            items.delete(selectedIndex)
            clampSelection(items, selectedIndex, scrollIndex, visibleRows)
        of KeyDelete:
          if focus == ComposerFocus:
            if not deleteTextSelection(inputText, caretPos, selAnchor):
              let n = if ctrl: nextWordPos(inputText, caretPos) else: nextRunePos(inputText, caretPos)
              if n > caretPos:
                inputText = inputText[0 ..< caretPos] & inputText[n .. ^1]
          elif focus == ListFocus and selectedIndex >= 0 and selectedIndex < items.len:
            items.delete(selectedIndex)
            clampSelection(items, selectedIndex, scrollIndex, visibleRows)
        of KeyUp:
          if focus == ListFocus and items.len > 0:
            if selectedIndex < 0: selectedIndex = 0 else: dec selectedIndex
            clampSelection(items, selectedIndex, scrollIndex, visibleRows)
        of KeyDown:
          if focus == ListFocus and items.len > 0:
            if selectedIndex < 0: selectedIndex = 0 else: inc selectedIndex
            clampSelection(items, selectedIndex, scrollIndex, visibleRows)
        else:
          if focus == ComposerFocus and ctrl:
            case e.key
            of KeyA:
              if inputText.len > 0:
                selAnchor = 0
                caretPos = inputText.len
            of KeyC:
              if hasTextSelection(caretPos, selAnchor):
                let (a, b) = selectionBounds(inputText, caretPos, selAnchor)
                putClipboardText(inputText[a ..< b])
            of KeyX:
              if hasTextSelection(caretPos, selAnchor):
                let (a, b) = selectionBounds(inputText, caretPos, selAnchor)
                putClipboardText(inputText[a ..< b])
                discard deleteTextSelection(inputText, caretPos, selAnchor)
            of KeyV:
              let clip = getClipboardText()
              if clip.len > 0:
                insertAtCursor(inputText, caretPos, selAnchor, clip)
            else:
              discard
      else:
        discard

    cells = parsedLayout.resolve(width, height, fm.lineHeight)
    let headerRect = cells["header"]
    let composerCell = cells["composer"]
    let listRect = cells["list"]
    let statusRect = cells["status"]
    let rawCompBox = composerInnerRect(composerCell)
    let addBtnBox = rect(rawCompBox.x + rawCompBox.w - 78, rawCompBox.y, 78, rawCompBox.h)
    let composerBox = rect(rawCompBox.x, rawCompBox.y, max(120, rawCompBox.w - 86), rawCompBox.h)
    let listClip = listInnerRect(listRect)
    let listVisibleRows = visibleRowsFor(listClip, rowHeight)
    clampSelection(items, selectedIndex, scrollIndex, listVisibleRows)

    let hover = if composerBox.contains(point(mouseX, mouseY)):
                  HoverTarget(kind: HoverComposer, index: -1)
                else:
                  hitList(listClip, rowHeight, scrollIndex, items, mouseX, mouseY)

    case hover.kind
    of HoverComposer:
      setCursor(curIbeam)
    of HoverRow, HoverCheckbox, HoverDelete:
      setCursor(curHand)
    else:
      setCursor(if addBtnBox.contains(point(mouseX, mouseY)): curHand else: curArrow)

    let doneCount = countDone(items)
    let openCount = items.len - doneCount

    fillRect(rect(0, 0, width, height), bgColor)
    fillRect(headerRect, panelColor)
    discard drawText(font, headerRect.x + 14, headerRect.y + 10,
      "Tasks", textColor, panelColor)
    discard drawText(font, headerRect.x + 14, headerRect.y + 28,
      summaryText(items.len, doneCount), mutedTextColor, panelColor)
    drawLine(headerRect.x + 14, headerRect.y + headerRect.h - 1,
      headerRect.x + headerRect.w - 14, headerRect.y + headerRect.h - 1, dividerColor)

    fillRect(composerCell, panelColor)
    let composerBg = if focus == ComposerFocus: panelColor else: panelAltColor
    fillRect(composerBox, composerBg)
    drawBorder(composerBox, if focus == ComposerFocus: accentColor else: borderColor)

    fillRect(addBtnBox, accentColor)
    drawBorder(addBtnBox, accentColor)
    discard drawText(font, addBtnBox.x + 14, addBtnBox.y + (addBtnBox.h - fm.lineHeight) div 2,
      "+ Add", panelColor, accentColor)

    let composerTextX = composerBox.x + 10
    let composerTextY = composerBox.y + (composerBox.h - fm.lineHeight) div 2
    saveState()
    setClipRect(insetRect(composerBox, 2))
    if inputText.len == 0:
      discard drawText(font, composerTextX, composerTextY,
        "Add a task", placeholderColor, color(0, 0, 0, 0))
    else:
      if focus == ComposerFocus and hasTextSelection(caretPos, selAnchor):
        let (selA, selB) = selectionBounds(inputText, caretPos, selAnchor)
        let xA = composerTextX + measureText(font, inputText[0 ..< selA]).w
        let xB = composerTextX + measureText(font, inputText[0 ..< selB]).w
        if xB > xA:
          fillRect(rect(xA, composerTextY - 1, xB - xA, fm.lineHeight + 2), color(196, 221, 252))
      discard drawText(font, composerTextX, composerTextY,
        inputText, textColor, color(0, 0, 0, 0))

    if focus == ComposerFocus:
      let clampedCaret = clamp(caretPos, 0, inputText.len)
      let caretX = composerTextX + measureText(font, inputText[0 ..< clampedCaret]).w
      let elapsed = getTicks() - lastCaretTick
      if elapsed < 500 or ((elapsed div 500) mod 2 == 0):
        fillRect(rect(caretX, composerBox.y + 6, 2, composerBox.h - 12), accentColor)
    restoreState()

    fillRect(listRect, panelColor)
    drawLine(listRect.x + 14, listRect.y, listRect.x + listRect.w - 14, listRect.y, dividerColor)

    saveState()
    setClipRect(listClip)
    if items.len == 0:
      discard drawText(font, listClip.x + 10, listClip.y + 10,
        "Nothing to do.", placeholderColor, panelColor)
    else:
      for visibleIndex in 0 ..< listVisibleRows:
        let itemIndex = scrollIndex + visibleIndex
        if itemIndex >= items.len:
          break

        let rowRect = rowRectFor(listClip, rowHeight, visibleIndex)
        let rowBg =
          if itemIndex == selectedIndex: selectedRowColor
          elif hover.index == itemIndex: panelAltColor
          else: panelColor
        fillRect(rowRect, rowBg)
        if itemIndex == selectedIndex:
          fillRect(rect(rowRect.x, rowRect.y, 3, rowRect.h), accentColor)
        drawLine(rowRect.x, rowRect.y + rowRect.h - 1,
          rowRect.x + rowRect.w, rowRect.y + rowRect.h - 1, dividerColor)

        let boxRect = checkboxRect(rowRect)
        let delRect = deleteRect(rowRect)
        drawCheckbox(boxRect, items[itemIndex].done)
        drawDeleteButton(delRect, hover.kind == HoverDelete and hover.index == itemIndex)

        let textX = boxRect.x + boxRect.w + 10
        let maxTextWidth = delRect.x - textX - 10
        let shown = truncateText(font, items[itemIndex].text, maxTextWidth)
        let textY = rowRect.y + (rowRect.h - fm.lineHeight) div 2
        let fg =
          if items[itemIndex].done: mutedTextColor
          else: textColor
        discard drawText(font, textX, textY, shown, fg, rowBg)

        if items[itemIndex].done:
          let ext = measureText(font, shown)
          let strikeY = textY + fm.lineHeight div 2
          drawLine(textX, strikeY, textX + ext.w, strikeY, mutedTextColor)
    restoreState()

    fillRect(statusRect, panelColor)
    discard drawText(font, statusRect.x + 14, statusRect.y + 6,
      if openCount == 0 and items.len > 0: "All tasks completed"
      elif items.len == 0: "Ready"
      else: $openCount & " remaining",
      mutedTextColor, panelColor)

    refresh()
    sleep(16)

  closeFont(font)
  shutdown()

main()
