## Automatic platform driver selection.
## Uses the native backend for each OS, with `-d:` overrides for
## cross-platform toolkits.
##
## Override flags (checked first):
##   -d:html / -d:uirelaysHtml / --define:"features.uirelays.html"
##              Force Pure Vanilla HTML5/CSS3/JS DOM backend (NO Canvas, NO WASM)
##   -d:canvas / -d:uirelaysCanvas / --define:"features.uirelays.canvas"
##              Force Separate HTML5 <canvas> 2D backend (NO WASM)
##   --define:"features.uirelays.figDrawWindy" Force FigDraw + Windy backend
##   --define:"features.uirelays.figDrawSiwin" Force FigDraw + siwin backend
##   -d:sdl3    Force SDL3 backend
##   -d:sdl2    Force SDL2 backend
##   -d:gtk4    Force GTK4 backend

import std/macros

when defined(js):
  proc uirRequestAnimationFrame*(cb: proc(t: float)) {.importjs: "window.__uirScheduleFrame(#)".}
  proc uirGetRunId*(): int {.importjs: "(window.__uirRunId || 0)".}

macro uirApp*(p: untyped): untyped =
  ## Transforms a UIRelays `while running:` main loop into a non-blocking
  ## `requestAnimationFrame` callback when compiled with `nim js` (`--mm:arc`),
  ## while preserving the native loop unchanged when compiled with `nim c`.
  if not defined(js):
    return p
  expectKind(p, {nnkProcDef, nnkFuncDef})
  result = copyNimTree(p)
  let body = result.body
  var whileIdx = -1
  for i in 0 ..< body.len:
    if body[i].kind == nnkWhileStmt:
      whileIdx = i
      break
  if whileIdx < 0:
    return result
  let whileNode = body[whileIdx]
  let cond = whileNode[0]
  let loopBody = whileNode[1]
  var afterStmts = newStmtList()
  for i in (whileIdx + 1) ..< body.len:
    afterStmts.add(body[i])
  while body.len > whileIdx:
    body.del(whileIdx)
  let stepIdent = genSym(nskProc, "uirStepFrame")
  let tIdent = genSym(nskParam, "t")
  let runIdIdent = genSym(nskLet, "uirRunId")
  let stepProc = quote do:
    let `runIdIdent` = uirGetRunId()
    proc `stepIdent`(`tIdent`: float) =
      if uirGetRunId() != `runIdIdent`:
        return
      if `cond`:
        `loopBody`
      if `cond` and uirGetRunId() == `runIdIdent`:
        uirRequestAnimationFrame(`stepIdent`)
      else:
        `afterStmts`
    `stepIdent`(0.0)
  body.add(stepProc)

when (defined(features.uirelays.html) or defined(uirelaysHtml) or defined(html)) and
    (defined(features.uirelays.canvas) or defined(uirelaysCanvas) or defined(canvas)):
  {.error: "html and canvas backends are mutually exclusive".}

elif defined(features.uirelays.html) or defined(uirelaysHtml) or defined(html):
  import drivers/html_driver
  proc initBackend*() = initHtmlDriver()

elif defined(features.uirelays.canvas) or defined(uirelaysCanvas) or defined(canvas):
  import drivers/canvas_driver
  proc initBackend*() = initCanvasDriver()

elif (defined(features.uirelays.figDrawWindy) or defined(figDrawWindy)) and
    (defined(features.uirelays.figDrawSiwin) or defined(figDrawSiwin)):
  {.error: "figDrawWindy and figDrawSiwin are mutually exclusive".}

elif defined(features.uirelays.figDrawWindy) or defined(figDrawWindy):
  import drivers/figdraw_windy_driver
  proc initBackend*() = initFigDrawWindyDriver()

elif defined(features.uirelays.figDrawSiwin) or defined(figDrawSiwin):
  import drivers/figdraw_siwin_driver
  proc initBackend*() = initFigDrawSiwinDriver()

elif defined(sdl3):
  import drivers/sdl3_driver
  proc initBackend*() = initSdl3Driver()

elif defined(sdl2):
  import drivers/sdl2_driver
  proc initBackend*() = initSdl2Driver()

elif defined(gtk4):
  import drivers/gtk4_driver
  proc initBackend*() = initGtk4Driver()

elif defined(macosx):
  import drivers/cocoa_driver
  proc initBackend*() = initCocoaDriver()

elif defined(windows):
  import drivers/winapi_driver
  proc initBackend*() = initWinapiDriver()

elif defined(linux) or defined(freebsd) or defined(openbsd) or defined(netbsd):
  import drivers/x11_driver
  proc initBackend*() = initX11Driver()

else:
  import drivers/sdl3_driver
  proc initBackend*() = initSdl3Driver()
