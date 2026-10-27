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
# Standalone offline HTML interactive & dynamic resize monkey test across all 10 apps:
# needs a headless browser; it says so and skips when there is none.
exec "nim c --mm:arc --outdir:/tmp/uirelays_bins -r tests/standalone_html_monkey_test.nim"
exec "nim c --mm:arc --outdir:/tmp/uirelays_bins -r tests/monkey_browser_test.nim"

# The arithmetic every cross-backend comparison rests on: a 32-bit multiply
# that is bit-identical on the C and the JS backend, and libm agreeing with V8.
# The JavaScript half of this file runs in the `sharks` CI job on all three
# operating systems; here it is the C half, on this machine's libm.
exec "nim c --mm:arc --outdir:/tmp/uirelays_bins -r tests/portability_math_test.nim"

# examples/sharks.nim renders a fixed 120-frame scene and prints a digest of
# every primitive argument, of every baked seabed pixel and of every joint
# position. tools/sharks_run.sh runs one backend, tools/sharks_crosscheck.nim
# judges them all against tests/sharks_digest_golden.txt. The web backends and
# the standalone `nim js` page must land on exactly the same numbers: that is
# the "it looks the same everywhere" claim, measured rather than asserted.
const SharksDigests = "/tmp/uirelays_sharks_digests"
removeDir(SharksDigests)
createDir(SharksDigests)
exec "sh tools/sharks_run.sh html " & SharksDigests & " 120"
exec "sh tools/sharks_run.sh canvas " & SharksDigests & " 120"
var sharksRequire = "html,canvas"
if findExe("node").len > 0:
  exec "sh tools/sharks_run.sh jsdom " & SharksDigests & " 120"
  sharksRequire.add ",jsdom"
else:
  echo "SKIP  sh tools/sharks_run.sh jsdom  (node is not installed)"
exec "nim c --mm:arc --outdir:/tmp/uirelays_bins -r tools/sharks_crosscheck.nim " &
     "--dir=" & SharksDigests & " --golden=tests/sharks_digest_golden.txt " &
     "--require=" & sharksRequire

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
