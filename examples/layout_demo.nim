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

    let btns = [
      ToolBtn(id: "split_v", label: "[+ Split Right]", r: rect(tbRect.x + 190, tbRect.y + 6, 134, 28)),
      ToolBtn(id: "split_h", label: "[+ Split Down]",  r: rect(tbRect.x + 332, tbRect.y + 6, 130, 28)),
      ToolBtn(id: "remove",  label: "[- Remove Pane]", r: rect(tbRect.x + 470, tbRect.y + 6, 136, 28)),
      ToolBtn(id: "reset",   label: "[Reset Layout]",  r: rect(tbRect.x + 614, tbRect.y + 6, 126, 28))
    ]

    var e = default Event
    while pollEvent(e):
      case e.kind
      of QuitEvent, WindowCloseEvent:
        running = false
      of WindowResizeEvent, WindowMetricsEvent:
        width = max(420, e.x)
        height = max(300, e.y)
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
          discard drawText(fontSmall, b.r.x + 8, b.r.y + 6, b.label, fg, bCol)
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
