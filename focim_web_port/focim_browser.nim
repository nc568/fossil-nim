## focim_browser.nim -- Full interactive Focim IDE built on uirelays + focim core
## Runs identically in native HTTP/SSE (-d:html / -d:canvas) and in-browser JS
## (nim js --mm:arc -d:danger -d:html) with zero <canvas> and zero WASM.

import std/[strutils, tables]
import uirelays
import uirelays/layout
import uirelays/drivers/web_common
import focim/[synedit, config, panels, search, theme, images]

const
  DefaultLayoutText = """# Where the widgets go, and the file the mouse writes: dragging a border
# between two panels rewrites the sizes below.
(layout
  (cols
    (rows (px 210)
      (tabs (lines 7))
      (explorer))
    (editor (stretch 4))
    (rows (stretch 2)
      (clipboard (lines 7))
      (history (lines 5))
      (terminal)))
  (status (lines 1)))
"""

  ConfigHeadText = """(config
  # Edit any "#RRGGBB" color literal below to recolor the entire IDE live!
"""
  ConfigTailText = """
  (track
    (compiler "nim")))
"""

  ReadmeContent = staticRead("/home/user/focim/README.md")
  CalcContent   = staticRead("/home/user/uirelays/examples/calculator.nim")
  SnakeContent  = staticRead("/home/user/uirelays/examples/snake.nim")
  T2048Content  = staticRead("/home/user/uirelays/examples/twenty48.nim")

  FocimBannerSvgRaw =
    "<svg xmlns='http://www.w3.org/2000/svg' width='460' height='120' viewBox='0 0 460 120'>" &
    "<rect width='460' height='120' rx='8' fill='#181825' stroke='#45475a' stroke-width='2'/>" &
    "<rect x='12' y='12' width='110' height='96' rx='4' fill='#1e1e2e' stroke='#313244'/>" &
    "<text x='20' y='30' fill='#89b4fa' font-family='monospace' font-size='11'>[config]</text>" &
    "<text x='20' y='46' fill='#a6e3a1' font-family='monospace' font-size='11'>[layout]</text>" &
    "<text x='20' y='62' fill='#f9e2af' font-family='monospace' font-size='11'>README.md</text>" &
    "<text x='20' y='78' fill='#cdd6f4' font-family='monospace' font-size='11'>calc.nim</text>" &
    "<rect x='130' y='12' width='200' height='96' rx='4' fill='#1e1e2e' stroke='#89b4fa'/>" &
    "<text x='142' y='32' fill='#cba6f7' font-family='monospace' font-size='12' font-weight='bold'># focim IDE</text>" &
    "<text x='142' y='52' fill='#cdd6f4' font-family='monospace' font-size='11'>Everything is text.</text>" &
    "<text x='142' y='70' fill='#a6adc8' font-family='monospace' font-size='11'>Pure Nim + UIRelays</text>" &
    "<text x='142' y='88' fill='#89dceb' font-family='monospace' font-size='11'>Zero Canvas / WASM</text>" &
    "<rect x='338' y='12' width='110' height='96' rx='4' fill='#1e1e2e' stroke='#313244'/>" &
    "<text x='348' y='32' fill='#f38ba8' font-family='monospace' font-size='11'>clipboard</text>" &
    "<text x='348' y='54' fill='#a6e3a1' font-family='monospace' font-size='11'>$ nim c focim</text>" &
    "<text x='348' y='72' fill='#cdd6f4' font-family='monospace' font-size='11'>[SuccessX]</text>" &
    "</svg>"

proc makeFocimBannerUri(): string =
  "data:image/svg+xml;utf8," & FocimBannerSvgRaw.multiReplace(
    ("<", "%3C"), (">", "%3E"), ("#", "%23"), (" ", "%20"))

proc makeConfigText(t: Theme): string =
  ConfigHeadText & themeText(t) & "\n" & ConfigTailText

type
  TabItem = object
    name: string
    ed: SynEdit

proc rebuildTabsView(tabsEd: var SynEdit; openTabs: seq[TabItem]; activeIdx: int; th: Theme) =
  var lines: seq[string] = @[]
  for t in openTabs:
    lines.add t.name
  let oldLine = tabsEd.firstLine.int
  tabsEd.setLabel(lines.join("\n"))
  tabsEd.setActionLines(0)
  tabsEd.setCloseButtons(2) # tabs >= 2 can be closed
  tabsEd.setRowHighlight(activeIdx, th.activeLineBg)
  tabsEd.scrollTo(oldLine)

proc rebuildClipView(clipEd: var SynEdit; clips: seq[string]) =
  var lines: seq[string] = @[]
  for i, c in clips:
    let oneLine = c.replace("\n", " ↵ ").strip()
    let snippet = if oneLine.len > 36: oneLine[0 ..< 36] & "…" else: oneLine
    lines.add $(i + 1) & "  " & snippet
  clipEd.setLabel(lines.join("\n"))
  clipEd.setActionLines(0)

proc rebuildHistoryView(histEd: var SynEdit; cmds: seq[string]) =
  histEd.setLabel(cmds.join("\n"))
  histEd.setActionLines(0)

proc main() {.uirApp.} =
  let win = createWindow(1080, 680)
  var width = win.width
  var height = win.height

  var fm: FontMetrics
  let font = openFont("", win.scaled(14), fm, {})
  setWindowTitle("focim — The Focussed Nim Editor (UIRelays Pure HTML/CSS DOM)")

  discard webRegisterMemoryImage("screenshots/focim.png", 460, 120, "image/svg+xml", makeFocimBannerUri())

  var curTheme = defaultTheme()
  var parsedLayout = parseLayout(DefaultLayoutText)

  var openTabs: seq[TabItem] = @[]

  proc addBuffer(name, content: string; lang: SourceLanguage; flags: set[RenderFlag] = {}; lineNums = true) =
    var s = createSynEdit(font, curTheme)
    s.lang = lang
    s.flags = flags
    s.showLineNumbers = lineNums
    s.setText(content)
    openTabs.add TabItem(name: name, ed: s)

  addBuffer("[config]", makeConfigText(curTheme), langNone, {rfColorLiterals}, lineNums = true)
  addBuffer("[layout]", DefaultLayoutText, langNone, {}, lineNums = true)
  addBuffer("README.md", ReadmeContent, langMarkdown, {rfMarkdownImages, rfColorLiterals}, lineNums = true)
  addBuffer("examples/calculator.nim", CalcContent, langNim, {rfColorLiterals}, lineNums = true)
  addBuffer("examples/snake.nim", SnakeContent, langNim, {rfColorLiterals}, lineNums = true)
  addBuffer("examples/twenty48.nim", T2048Content, langNim, {rfColorLiterals}, lineNums = true)

  var activeTabIdx = 2 # Start on README.md so markdown + syntax + image are immediately visible!

  var tabsEd = createSynEdit(font, curTheme)
  tabsEd.lang = langNone
  tabsEd.theme.bg = curTheme.panelBg
  rebuildTabsView(tabsEd, openTabs, activeTabIdx, curTheme)

  let explorerItems = @[
    "/home/user/focim",
    "[Theme: dark]",
    "[Theme: paper]",
    "[Theme: amber]",
    "[Split Editor]",
    "[Reset Layout]",
    "README.md",
    "examples/calculator.nim",
    "examples/snake.nim",
    "examples/twenty48.nim",
    "[config]",
    "[layout]"
  ]
  var explorerEd = createSynEdit(font, curTheme)
  explorerEd.lang = langNone
  explorerEd.theme.bg = curTheme.panelBg
  explorerEd.setLabel(explorerItems.join("\n"))
  explorerEd.setActionLines(1)

  var clips = @[
    "nim c --mm:arc -d:html examples/calculator.nim",
    "setClipRect(rect(x, y, w, h))",
    "(layout (cols (tabs (px 180)) (editor)))",
    "#89b4fa"
  ]
  putClipboardText(clips[0])
  var clipEd = createSynEdit(font, curTheme)
  clipEd.lang = langNone
  clipEd.theme.bg = curTheme.panelBg
  rebuildClipView(clipEd, clips)

  var cmdHistory = @[
    "help",
    "theme paper",
    "theme amber",
    "theme dark",
    "open examples/calculator.nim"
  ]
  var histEd = createSynEdit(font, curTheme)
  histEd.lang = langNone
  histEd.theme.bg = curTheme.panelBg
  rebuildHistoryView(histEd, cmdHistory)

  var termEd = createSynEdit(font, curTheme)
  termEd.lang = langConsole
  termEd.theme.bg = curTheme.panelBg
  termEd.appendOutput(
    "focim interactive terminal (Pure Nim --mm:arc on UIRelays)\n" &
    "Hint: Click any tab, file, theme button, or drag panel borders! [Ready]\n" &
    "$ ")

  var statusEd = createSynEdit(font, curTheme)
  statusEd.lang = langNone
  statusEd.theme.bg = curTheme.panelBg

  var focusedCell = "editor"
  var statusMsg = "Ready — click tabs/explorer items, edit code or [config]/[layout], or drag borders!"
  var lastConfigVer = openTabs[0].ed.textVersion
  var lastLayoutVer = openTabs[1].ed.textVersion

  var activeSplitter = Splitter()
  var isDraggingSplitter = false

  proc applyThemeToAll(th: Theme) =
    curTheme = th
    for i in 0 ..< openTabs.len:
      openTabs[i].ed.theme = th
    var pTh = th
    pTh.bg = th.panelBg
    tabsEd.theme = pTh
    explorerEd.theme = pTh
    clipEd.theme = pTh
    histEd.theme = pTh
    termEd.theme = pTh
    statusEd.theme = pTh
    rebuildTabsView(tabsEd, openTabs, activeTabIdx, curTheme)

  proc switchOrOpenTab(targetName: string) =
    for i in 0 ..< openTabs.len:
      if openTabs[i].name == targetName:
        activeTabIdx = i
        focusedCell = "editor"
        rebuildTabsView(tabsEd, openTabs, activeTabIdx, curTheme)
        statusMsg = "Switched to tab '" & targetName & "'"
        return

  proc executeCommand(rawCmd: string) =
    let cmd = rawCmd.strip()
    if cmd.len == 0:
      termEd.appendOutput("\n$ ")
      return
    cmdHistory.insert(cmd, 0)
    if cmdHistory.len > 12: cmdHistory.setLen(12)
    rebuildHistoryView(histEd, cmdHistory)

    if cmd == "help":
      termEd.appendOutput("\nCommands: help | ls | theme <dark|paper|amber> | open <file> | clear\n$ ")
      statusMsg = "Executed 'help' in terminal"
    elif cmd == "ls":
      termEd.appendOutput("\nREADME.md  examples/calculator.nim  examples/snake.nim  examples/twenty48.nim  [config]  [layout]\n$ ")
      statusMsg = "Listed workspace buffers"
    elif cmd == "clear":
      termEd.setText("")
      termEd.appendOutput("Terminal cleared.\n$ ")
      statusMsg = "Cleared terminal output"
    elif cmd.startsWith("theme"):
      let arg = cmd[5 .. ^1].strip()
      var th = default(Theme)
      if findTheme(arg, th):
        openTabs[0].ed.setText(makeConfigText(th))
        lastConfigVer = openTabs[0].ed.textVersion
        applyThemeToAll(th)
        termEd.appendOutput("\nHint: Switched active theme to '" & arg & "' [ThemeOK]\n$ ")
        statusMsg = "Theme changed to '" & arg & "'"
      else:
        termEd.appendOutput("\nAvailable themes: dark, paper, amber\n$ ")
    elif cmd.startsWith("open ") or cmd.startsWith("o "):
      let target = cmd.splitWhitespace()[1]
      for it in openTabs:
        if it.name == target or it.name.endsWith(target):
          switchOrOpenTab(it.name)
          termEd.appendOutput("\nOpened " & it.name & "\n$ ")
          return
      termEd.appendOutput("\nWarning: Unknown buffer '" & target & "'\n$ ")
    else:
      termEd.appendOutput("\nHint: Evaluated '" & cmd & "' [OK]\n$ ")
      statusMsg = "Ran command: " & cmd

  var running = true
  while running:
    let metrics = LayoutMetrics(
      screenW: width,
      screenH: height,
      lineHeight: fontLineSkip(font),
      padding: 2,
      gap: 4,
      uiScale: win.uiScale
    )
    var cells = parsedLayout.resolve(metrics)

    var e = default Event
    while pollEvent(e):
      case e.kind
      of QuitEvent, WindowCloseEvent:
        running = false
      of WindowResizeEvent, WindowMetricsEvent:
        width = max(480, e.x)
        height = max(320, e.y)
        statusMsg = "Resized focim viewport to " & $width & "×" & $height
      of MouseMoveEvent:
        if isDraggingSplitter and activeSplitter.found:
          if parsedLayout.dragTo(metrics, activeSplitter, e.x, e.y):
            cells = parsedLayout.resolve(metrics)
            openTabs[1].ed.setText($parsedLayout)
            lastLayoutVer = openTabs[1].ed.textVersion
            statusMsg = "Resized panel border -> updated [layout] live"
        else:
          let sp = parsedLayout.splitterAt(metrics, e.x, e.y, slack = 4)
          if sp.found:
            setCursor(if sp.vertical: curSizeNS else: curSizeWE)
          else:
            setCursor(curDefault)
          # Forward hover to active cells
          for cellName, r in cells:
            if cellName == "tabs":
              discard tabsEd.draw(e, r, focusedCell == "tabs")
            elif cellName.isEditor:
              discard openTabs[activeTabIdx].ed.draw(e, r, focusedCell == cellName)
      of MouseDownEvent:
        if e.button == LeftButton:
          let sp = parsedLayout.splitterAt(metrics, e.x, e.y, slack = 4)
          if sp.found:
            activeSplitter = sp
            isDraggingSplitter = true
          else:
            let hit = cells.hitTest(e.x, e.y)
            if hit.name.len > 0:
              focusedCell = hit.name
              let cellRect = cells[hit.name]
              if hit.name == "tabs":
                let act = tabsEd.draw(e, cellRect, true)
                if act.kind == closeLine and act.line >= 2 and act.line < openTabs.len:
                  let closedName = openTabs[act.line].name
                  openTabs.delete(act.line)
                  if activeTabIdx >= openTabs.len: activeTabIdx = openTabs.high
                  rebuildTabsView(tabsEd, openTabs, activeTabIdx, curTheme)
                  statusMsg = "Closed tab '" & closedName & "'"
                else:
                  let clickedLine = clamp(tabsEd.currentLine, 0, openTabs.high)
                  activeTabIdx = clickedLine
                  focusedCell = "editor"
                  rebuildTabsView(tabsEd, openTabs, activeTabIdx, curTheme)
                  statusMsg = "Active tab: " & openTabs[activeTabIdx].name
              elif hit.name == "explorer":
                discard explorerEd.draw(e, cellRect, true)
                let lineIdx = explorerEd.currentLine
                if lineIdx >= 1 and lineIdx < explorerItems.len:
                  let item = explorerItems[lineIdx]
                  if item.startsWith("[Theme: "):
                    let tName = item[8 .. ^2]
                    var th = default(Theme)
                    if findTheme(tName, th):
                      openTabs[0].ed.setText(makeConfigText(th))
                      lastConfigVer = openTabs[0].ed.textVersion
                      applyThemeToAll(th)
                      statusMsg = "Applied '" & tName & "' theme across all panels!"
                  elif item == "[Split Editor]":
                    let newCell = freeName(parsedLayout.cellNames(), EditorStem)
                    if parsedLayout.splitCell("editor", newCell, asColumn = true):
                      openTabs[1].ed.setText($parsedLayout)
                      lastLayoutVer = openTabs[1].ed.textVersion
                      cells = parsedLayout.resolve(metrics)
                      statusMsg = "Split editor -> created panel '" & newCell & "'"
                  elif item == "[Reset Layout]":
                    parsedLayout = parseLayout(DefaultLayoutText)
                    openTabs[1].ed.setText(DefaultLayoutText)
                    lastLayoutVer = openTabs[1].ed.textVersion
                    cells = parsedLayout.resolve(metrics)
                    statusMsg = "Reset layout to default"
                  else:
                    switchOrOpenTab(item)
              elif hit.name == "clipboard":
                discard clipEd.draw(e, cellRect, true)
                let lineIdx = clipEd.currentLine
                if lineIdx >= 0 and lineIdx < clips.len:
                  let chosen = clips[lineIdx]
                  putClipboardText(chosen)
                  openTabs[activeTabIdx].ed.insertText(chosen)
                  focusedCell = "editor"
                  statusMsg = "Pasted clipboard entry #" & $(lineIdx + 1) & " into " & openTabs[activeTabIdx].name
              elif hit.name == "history":
                discard histEd.draw(e, cellRect, true)
                let lineIdx = histEd.currentLine
                if lineIdx >= 0 and lineIdx < cmdHistory.len:
                  let cmd = cmdHistory[lineIdx]
                  termEd.appendOutput(cmd)
                  executeCommand(cmd)
                  focusedCell = "terminal"
              elif hit.name == "terminal":
                discard termEd.draw(e, cellRect, true)
              elif hit.name.isEditor:
                let act = openTabs[activeTabIdx].ed.draw(e, cellRect, true)
                if act.kind == ctrlClick and openTabs[activeTabIdx].ed.lang == langMarkdown:
                  let (url, _, _) = openTabs[activeTabIdx].ed.extractMarkdownLink(act.pos)
                  if url.startsWith("#"):
                    discard openTabs[activeTabIdx].ed.gotoMarkdownHeading(url[1 .. ^1])
                    statusMsg = "Jumped to heading " & url
      of MouseUpEvent:
        isDraggingSplitter = false
        activeSplitter = Splitter()
        for cellName, r in cells:
          if cellName.isEditor:
            discard openTabs[activeTabIdx].ed.draw(e, r, focusedCell == cellName)
      of MouseWheelEvent:
        if focusedCell == "tabs":
          tabsEd.wheelScroll(e.y)
        elif focusedCell == "explorer":
          explorerEd.wheelScroll(e.y)
        elif focusedCell == "terminal":
          termEd.wheelScroll(e.y)
        else:
          openTabs[activeTabIdx].ed.wheelScroll(e.y)
      of KeyDownEvent, TextInputEvent:
        if focusedCell == "terminal":
          if e.kind == KeyDownEvent and e.key == KeyEnter:
            let lastLine = termEd.getLineText(termEd.getLineCount() - 1)
            let cmd = if lastLine.startsWith("$ "): lastLine[2 .. ^1] else: lastLine
            executeCommand(cmd)
          else:
            discard termEd.draw(e, cells.getOrDefault("terminal", rect(0, 0, 100, 100)), true)
        else:
          let edRect = cells.getOrDefault(focusedCell, cells.getOrDefault("editor", rect(0, 0, width, height)))
          discard openTabs[activeTabIdx].ed.draw(e, edRect, true)
          if e.kind == KeyDownEvent and e.key == KeyC and (CtrlPressed in e.mods or GuiPressed in e.mods):
            let cb = getClipboardText()
            if cb.len > 0 and (clips.len == 0 or clips[0] != cb):
              clips.insert(cb, 0)
              rebuildClipView(clipEd, clips)
              statusMsg = "Copied selection to clipboard history"
      else:
        discard

    # Live reactive [config] & [layout] lanes!
    if openTabs[0].ed.textVersion != lastConfigVer:
      lastConfigVer = openTabs[0].ed.textVersion
      let cfg = parseConfig(openTabs[0].ed.fullText())
      if cfg.error.len == 0 and cfg.note.len == 0:
        applyThemeToAll(cfg.theme)
        statusMsg = "Applied live [config] theme update!"
      elif cfg.error.len > 0:
        statusMsg = "[config] " & cfg.error
      else:
        statusMsg = "[config] " & cfg.note

    if openTabs[1].ed.textVersion != lastLayoutVer:
      lastLayoutVer = openTabs[1].ed.textVersion
      let candidate = parseLayout(openTabs[1].ed.fullText())
      if candidate.error.len == 0 and panelsOf(candidate.cellNames(), EditorStem).len > 0:
        parsedLayout = candidate
        cells = parsedLayout.resolve(metrics)
        statusMsg = "Applied live [layout] update!"
      elif candidate.error.len > 0:
        statusMsg = "[layout] " & candidate.error

    # Render frame
    fillRect(rect(0, 0, width, height), curTheme.panelBg)

    let noEv = Event(kind: NoEvent)
    var editorSeat = 0
    for cellName, r in cells:
      if cellName == "tabs":
        discard tabsEd.draw(noEv, r, focusedCell == "tabs")
      elif cellName == "explorer":
        discard explorerEd.draw(noEv, r, focusedCell == "explorer")
      elif cellName == "clipboard":
        discard clipEd.draw(noEv, r, focusedCell == "clipboard")
      elif cellName == "history":
        discard histEd.draw(noEv, r, focusedCell == "history")
      elif cellName == "terminal":
        discard termEd.draw(noEv, r, focusedCell == "terminal")
      elif cellName == "status":
        let curEd = openTabs[activeTabIdx].ed
        let label = " " & openTabs[activeTabIdx].name &
          "  Ln " & $(curEd.currentLine + 1) & ", Col " & $(curEd.currentCol + 1) &
          "  |  " & statusMsg & "  (" & $width & "×" & $height & ")"
        statusEd.setLabel(label)
        discard statusEd.draw(noEv, r, false)
      elif cellName.isEditor:
        openTabs[activeTabIdx].ed.enter(editorSeat)
        discard openTabs[activeTabIdx].ed.draw(noEv, r, focusedCell == cellName)
        inc editorSeat

    refresh()
    sleep(16)

  closeFont(font)
  shutdown()

main()
