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

const UirFrameLoopMarkers = ["refresh", "pollEvent", "waitEvent", "sleep"]
  ## Calls that only ever appear in a UIRelays main loop. Used to tell the
  ## `while running:` loop apart from an unrelated `while` that happens to
  ## sit earlier in the same procedure (initialisation, parsing, retry...).

proc hasFrameLoopMarker(n: NimNode): bool =
  ## True when `n` (or anything nested in it, but not a nested routine) calls
  ## one of `UirFrameLoopMarkers`. `n.strVal` is only read for identifiers and
  ## symbols, so the walk cannot crash on literals or on empty nodes.
  if n.kind in {nnkProcDef, nnkFuncDef, nnkMethodDef, nnkConverterDef,
                nnkLambda, nnkDo, nnkTemplateDef, nnkMacroDef}:
    return false
  if n.kind in {nnkIdent, nnkSym}:
    if n.strVal in UirFrameLoopMarkers:
      return true
  elif n.kind in {nnkOpenSymChoice, nnkClosedSymChoice}:
    for i in 0 ..< n.len:
      if hasFrameLoopMarker(n[i]):
        return true
    return false
  for i in 0 ..< n.len:
    if hasFrameLoopMarker(n[i]):
      return true
  return false

proc collectWhileLoops(body: NimNode; loops: var seq[int]) =
  ## Collects the indices of every `while` statement that is a direct
  ## statement of the procedure body. Only direct statements can be turned
  ## into a frame callback: hoisting a loop out of an `if` or a `block` would
  ## change when (and whether) it runs.
  for i in 0 ..< body.len:
    if body[i].kind == nnkWhileStmt:
      loops.add i

proc countNestedWhileLoops(n: NimNode): int =
  ## How many `while` statements sit somewhere below `n`. Used only to tell
  ## the user *why* no main loop was found.
  if n.kind in {nnkProcDef, nnkFuncDef, nnkMethodDef, nnkConverterDef,
                nnkLambda, nnkDo, nnkTemplateDef, nnkMacroDef}:
    return 0
  for i in 0 ..< n.len:
    if n[i].kind == nnkWhileStmt:
      inc result
    result += countNestedWhileLoops(n[i])

macro uirApp*(p: untyped): untyped =
  ## Transforms a UIRelays `while running:` main loop into a non-blocking
  ## frame callback when compiled with `nim js` (`--mm:arc`), while preserving
  ## earlier initialization `while` loops and native compilation (`nim c`).
  if not defined(js):
    return p
  expectKind(p, {nnkProcDef, nnkFuncDef})
  result = copyNimTree(p)
  let body = result.body

  # Which `while` is the main loop? Taking the first one silently breaks any
  # procedure that has an initialisation loop before the real one (a `while`
  # that drains stdin, waits for a file, walks a list...): the wrong loop
  # becomes the frame callback and the tab hangs. Prefer the last loop that
  # actually drives the relays, fall back to the last loop at all, and fail
  # loudly instead of no-op'ing when there is nothing to transform.
  var loops: seq[int] = @[]
  collectWhileLoops(body, loops)

  var whileIdx = -1
  for i in countdown(loops.len - 1, 0):
    if hasFrameLoopMarker(body[loops[i]][1]):
      whileIdx = loops[i]
      break
  if whileIdx < 0 and loops.len > 0:
    whileIdx = loops[^1]
  if whileIdx < 0:
    var msg = "uirApp: procedure '" & $p.name & "' has no top-level `while` loop, " &
      "so there is nothing to turn into a browser frame callback. " &
      "In `nim js` the loop must be written directly in the procedure body"
    let nested = countNestedWhileLoops(body)
    if nested > 0:
      msg.add " (found " & $nested & " nested/conditional `while` loop(s): hoist the main loop to the top level)"
    error(msg, p)

  let cond = body[whileIdx][0]
  let loopBody = body[whileIdx][1]
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
