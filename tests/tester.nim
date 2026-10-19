import std/[os, strutils]

proc fatal(msg: string) = quit "FAILURE " & msg

proc exec(cmd: string) =
  if execShellCmd(cmd) != 0: fatal cmd

proc execIfPresent(name, cmd: string) =
  ## Run a suite only when its tool is installed. A suite that cannot run is
  ## reported, never silently dropped -- and never reported as a failure
  ## either, so a clean clone without a browser still passes.
  if findExe(name).len > 0:
    exec cmd
  else:
    echo "SKIP  ", cmd, "  (", name, " is not installed)"


template execBackend(backend: string) =
  for example in walkFiles("examples/*.nim"):
    let command: string = [
    "nim c",
    "--outdir:/tmp/uirelays_bins", # keep binaries outside repo tree
    backend,
    example
    ].join(" ")
    exec command

# The lexer needs no driver, so it is tested directly.
exec "nim c --mm:arc --outdir:/tmp/uirelays_bins -r tests/tinyniftest.nim"
# And so does the layout: dividing a rectangle, finding the borders in it, and
# moving one, are arithmetic that never touches a window.
exec "nim c --mm:arc --outdir:/tmp/uirelays_bins -r tests/layouttest.nim"
# Command chord detection needs no window either.
exec "nim c --mm:arc --outdir:/tmp/uirelays_bins -r tests/inputtest.nim"
# Pure HTML/CSS/JS DOM backend and HTML5 Canvas 2D backend unit & HTTP tests:
exec "nim c --mm:arc -d:html --outdir:/tmp/uirelays_bins -r tests/web_html_test.nim"
exec "nim c --mm:arc -d:canvas --outdir:/tmp/uirelays_bins -r tests/web_canvas_test.nim"
# One check per fixed defect, so none of them can come back unnoticed:
exec "nim c --mm:arc -d:html --outdir:/tmp/uirelays_bins -r tests/web_backend_regression_test.nim"
exec "nim c --mm:arc -d:canvas --outdir:/tmp/uirelays_bins -r tests/web_backend_regression_test.nim"
# Monkey tests that need neither a browser nor the network:
exec "nim c --mm:arc --outdir:/tmp/uirelays_bins -r tests/server_monkey_test.nim"
execIfPresent("node",
  "nim c --mm:arc --outdir:/tmp/uirelays_bins -r tests/jsdom_monkey_test.nim")
# Standalone offline HTML interactive & dynamic resize monkey test across all 9 apps:
# needs a headless browser; it says so and skips when there is none.
exec "nim c --mm:arc --outdir:/tmp/uirelays_bins -r tests/standalone_html_monkey_test.nim"
exec "nim c --mm:arc --outdir:/tmp/uirelays_bins -r tests/monkey_browser_test.nim"

# Everything else is a window, and a window is what the examples are: each
# backend gets to compile all of them.
execBackend("--mm:arc -d:html")
execBackend("--mm:arc -d:canvas")
execBackend("")
when defined(features.uirelays.figDrawWindy):
  execBackend("--define:\"features.uirelays.figDrawWindy\"")
when defined(features.uirelays.figDrawSiwin):
  execBackend("--define:\"features.uirelays.figDrawSiwin\"")
when defined(linux):
  if execShellCmd("pkg-config --exists gtk4") == 0:
    execBackend("-d:gtk4")
# execBackend("-d:sdl2")
# execBackend("-d:sdl3")
