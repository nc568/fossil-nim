## layout_demo.nim -- Interactive demonstration of uirelays/layout.
## Parses a NIF layout into named screen regions, lets you drag splitters
## to resize panels, click toolbar buttons to split/remove cells dynamically,
## and reflows automatically when the window resizes.
##
## Compile:
##   nim c --mm:arc -d:html examples/layout_demo.nim
##   nim c --mm:arc -d:canvas examples/layout_demo.nim

import uirelays
import uirelays/layout
import std/tables

const DefaultLayoutSpec = """
(layout
  (toolbar (px 40))
  (cols
    (sidebar (px 220))
    (editor))
  (status (lines 1)))
"""

const
  bg       = color(30, 30, 46)
  panelBg  = color(49, 50, 68)
  hoverBg  = color(62, 64, 86)
  btnBg    = color(69, 71, 90)
  btnHover = color(88, 91, 112)
  divColor = color(108, 112, 134)
  fg       = color(205, 214, 244)
  subtleFg = color(166, 173, 200)
  accent   = color(137, 180, 250)
  green    = color(166, 227, 161)

type
  ToolBtn = object
    id: string
    label: string
    r: Rect

proc drawBorder(r: Rect; c: Color) =
  if r.w <= 0 or r.h <= 0: return
  drawLine(r.x, r.y, r.x + r.w - 1, r.y, c)
  drawLine(r.x, r.y, r.x, r.y + r.h - 1, c)
  drawLine(r.x + r.w - 1, r.y, r.x + r.w - 1, r.y + r.h - 1, c)
  drawLine(r.x, r.y + r.h - 1, r.x + r.w - 1, r.y + r.h - 1, c)

proc main() {.uirApp.} =
  let win = createWindow(900, 600)
  # The layout below is drawn for 900x600 and does not reflow below it:
  # declaring the floor keeps the viewport from shrinking into
  # territory where the interface is clipped away and unreachable.
  setMinViewport(900, 600)
  var width = win.width
  var height = win.height

  var fm, fmSmall: FontMetrics
  let font = openFont("", win.scaled(15), fm, {FontStyle.bold})
  let fontSmall = openFont("", win.scaled(13), fmSmall, {})
  setWindowTitle("Layout Demo")

  var parsed = parseLayout(DefaultLayoutSpec)
  doAssert parsed.error.len == 0, parsed.error

  var running = true
  var mouseX, mouseY = 0
  var hovered = ""
  var selectedCell = "editor"
  var splitCounter = 1
  var statusNote = "Drag any border to resize panes, or click toolbar buttons to split/remove cells"
  var activeSplitter = Splitter()
  var isDragging = false

  while running:
    let metrics = LayoutMetrics(
      screenW: width,
      screenH: height,
      lineHeight: fm.lineHeight,
      padding: 4,
      gap: 4,
      uiScale: win.uiScale
    )
    var cells = parsed.resolve(metrics)
    let tbRect = cells.getOrDefault("toolbar", rect(0, 0, width, 40))

    # Laid out from the toolbar's own width. These used to sit at hardcoded
    # x=190/332/470/614, which needs 740px of toolbar -- while the window's
    # own minimum is 420px, so "[- Remove Pane]" and "[Reset Layout]" were
    # entirely past the right edge there. `overflow:hidden` does not make them
    # reachable, it just hides them.
    let tbGap = 8
    let tbLabelW = min(190, max(0, tbRect.w div 4))
    let tbAvail = max(0, tbRect.w - tbLabelW - tbGap * 5)
    let tbBtnW = clamp(tbAvail div 4, 40, 136)
    let tbBtns: array[4, Rect] = [
      rect(tbRect.x + tbLabelW + tbGap, tbRect.y + 6, tbBtnW, 28),
      rect(tbRect.x + tbLabelW + tbGap * 2 + tbBtnW, tbRect.y + 6, tbBtnW, 28),
      rect(tbRect.x + tbLabelW + tbGap * 3 + tbBtnW * 2, tbRect.y + 6, tbBtnW, 28),
      rect(tbRect.x + tbLabelW + tbGap * 4 + tbBtnW * 3, tbRect.y + 6, tbBtnW, 28)
    ]
    let btns = [
      ToolBtn(id: "split_v", label: "[+ Split Right]", r: tbBtns[0]),
      ToolBtn(id: "split_h", label: "[+ Split Down]",  r: tbBtns[1]),
      ToolBtn(id: "remove",  label: "[- Remove Pane]", r: tbBtns[2]),
      ToolBtn(id: "reset",   label: "[Reset Layout]",  r: tbBtns[3])
    ]

    var e = default Event
    while pollEvent(e):
      case e.kind
      of QuitEvent, WindowCloseEvent:
        running = false
      of WindowResizeEvent, WindowMetricsEvent:
        width = max(900, e.x)
        height = max(600, e.y)
        statusNote = "Window resized to " & $width & "×" & $height
      of MouseMoveEvent:
        mouseX = e.x
        mouseY = e.y
        if isDragging and activeSplitter.found:
          if parsed.dragTo(metrics, activeSplitter, e.x, e.y):
            cells = parsed.resolve(metrics)
            statusNote = "Dragging splitter to (" & $e.x & ", " & $e.y & ")"
        else:
          let sp = parsed.splitterAt(metrics, e.x, e.y, slack = 4)
          if sp.found:
            setCursor(if sp.vertical: curSizeNS else: curSizeWE)
          else:
            setCursor(curDefault)
      of MouseDownEvent:
        mouseX = e.x
        mouseY = e.y
        if e.button == LeftButton:
          var clickedBtn = ""
          for b in btns:
            if b.r.contains(point(e.x, e.y)):
              clickedBtn = b.id
              break
          if clickedBtn.len > 0:
            case clickedBtn
            of "split_v":
              let newName = "pane_" & $splitCounter
              if parsed.splitCell(selectedCell, newName, asColumn = true):
                inc splitCounter
                selectedCell = newName
                statusNote = "Split right -> created '" & newName & "'"
            of "split_h":
              let newName = "pane_" & $splitCounter
              if parsed.splitCell(selectedCell, newName, asColumn = false):
                inc splitCounter
                selectedCell = newName
                statusNote = "Split down -> created '" & newName & "'"
            of "remove":
              if selectedCell notin ["toolbar", "status", "sidebar"]:
                let old = selectedCell
                if parsed.removeCell(old):
                  let remaining = parsed.cellNames()
                  selectedCell = if "editor" in remaining: "editor" elif remaining.len > 0: remaining[^1] else: "sidebar"
                  statusNote = "Removed pane '" & old & "'"
              else:
                statusNote = "Select an editor/split pane to remove"
            of "reset":
              parsed = parseLayout(DefaultLayoutSpec)
              selectedCell = "editor"
              splitCounter = 1
              statusNote = "Reset layout to default"
            cells = parsed.resolve(metrics)
          else:
            let sp = parsed.splitterAt(metrics, e.x, e.y, slack = 4)
            if sp.found:
              activeSplitter = sp
              isDragging = true
            else:
              let hCell = cells.hitTest(e.x, e.y)
              if hCell.name.len > 0 and hCell.name notin ["toolbar", "status"]:
                selectedCell = hCell.name
                statusNote = "Selected cell '" & selectedCell & "' (" & $cells[selectedCell].w & "×" & $cells[selectedCell].h & ")"
      of MouseUpEvent:
        isDragging = false
        activeSplitter = Splitter()
      of KeyDownEvent:
        if e.key == KeyEsc or (e.key == KeyQ and CtrlPressed in e.mods):
          running = false
      else: discard

    let hit = cells.hitTest(mouseX, mouseY)
    hovered = hit.name

    # background
    fillRect(rect(0, 0, width, height), bg)

    # draw each cell
    for name, r in cells:
      let isHover = name == hovered
      let isSel = name == selectedCell
      let cellBg = if isHover and name notin ["toolbar", "status"]: hoverBg else: panelBg
      fillRect(r, cellBg)
      if isSel and name notin ["toolbar", "status"]:
        drawBorder(r, accent)
      else:
        drawBorder(r, divColor)

      if name == "toolbar":
        discard drawText(font, r.x + 10, r.y + 10, "toolbar (" & $r.w & "x" & $r.h & ")", accent, cellBg)
        for b in btns:
          let bHov = b.r.contains(point(mouseX, mouseY))
          let bCol = if bHov: btnHover else: btnBg
          fillRect(b.r, bCol)
          drawBorder(b.r, divColor)
          # Clip the caption to the button: a label wider than the button it
          # sits on runs into its neighbour, and past the last one it runs out
          # of the window.
          var caption = b.label
          let captionAvail = b.r.w - 12
          while caption.len > 1 and measureText(fontSmall, caption).w > captionAvail:
            caption.setLen(caption.len - 1)
          if caption.len < b.label.len and caption.len > 1:
            caption = caption[0 ..< caption.len - 1] & "\u2026"
          discard drawText(fontSmall, b.r.x + 8, b.r.y + 6, caption, fg, bCol)
      elif name == "status":
        discard drawText(fontSmall, r.x + 10, r.y + 3,
          "status (" & $r.w & "x" & $r.h & ") · " & statusNote, subtleFg, cellBg)
      else:
        let label = name & " (" & $r.w & "x" & $r.h & ")"
        let labelFg = if isSel: green elif isHover: accent else: fg
        discard drawText(font, r.x + 12, r.y + 12, label, labelFg, cellBg)
        if r.h > 60 and r.w > 140:
          discard drawText(fontSmall, r.x + 12, r.y + 38,
            if isSel: "[Active pane — click Split/Remove or drag border]" else: "Click to select pane",
            subtleFg, cellBg)

    refresh()
    sleep(16)

  closeFont(fontSmall)
  closeFont(font)
  shutdown()

main()
