## jsdom_monkey_test.nim -- runs the exported standalone HTML bundle inside
## jsdom (via node) and monkey-tests it: random clicks, keys, wheels, pastes
## and resizes, checking after every step that no script threw, that no
## primitive was emitted with a NaN in its style, and that nothing ran away.
##
## This is the browser-side monkey test for machines with no browser binary
## installed. `monkey_browser_test.nim` and `standalone_html_monkey_test.nim`
## drive real Chromium when it is available; this one needs nothing but node.
##
## Compile & run:
##   nim c --mm:arc --outdir:/tmp/uirelays_bins -r tests/jsdom_monkey_test.nim
##
## Environment:
##   NODE / NIM       override the binaries
##   UIRELAYS_STEPS   monkey steps per app (default 120)
##   UIRELAYS_APPS    comma-separated app ids to test (default: all)

import std/[os, osproc, strutils, json]

var passes = 0
var failures = 0
var skips = 0

proc check(name: string; cond: bool; detail = "") =
  if cond:
    inc passes
    echo "  PASS  ", name
  else:
    inc failures
    echo "  FAIL  ", name, (if detail.len > 0: "  -- " & detail else: "")

proc skip(name: string; why: string) =
  inc skips
  echo "  SKIP  ", name, "  -- ", why

proc repoRoot(): string =
  let envRoot = getEnv("UIRELAYS_ROOT", "")
  if envRoot.len > 0 and dirExists(envRoot / "src" / "uirelays"):
    return envRoot
  for start in [getCurrentDir(), getAppDir()]:
    var dir = start
    for _ in 0 ..< 8:
      if dirExists(dir / "src" / "uirelays"):
        return dir
      let parent = parentDir(dir)
      if parent == dir:
        break
      dir = parent
  getCurrentDir()

proc findTool(envName, defaultName: string): string =
  let fromEnv = getEnv(envName, "")
  if fromEnv.len > 0:
    return fromEnv
  let found = findExe(defaultName)
  if found.len > 0: found else: ""

proc violatesZeroCanvasPolicy(code: string): string =
  ## The policy forbids *using* a canvas or WebAssembly, not writing about
  ## them: the Focim demo embeds this repository's README, which is full of
  ## both words. So look for API calls.
  const forbidden = [
    "getContext(\"2d\")", "getContext('2d')", "getContext(`2d`)",
    "createElement(\"canvas\")", "createElement('canvas')",
    "WebAssembly.", "WebAssembly(", "new WebAssembly"
  ]
  for needle in forbidden:
    if needle in code:
      return needle
  ""

proc main() =
  echo "======================================================================"
  echo " UIRelays Standalone HTML Monkey Test (jsdom, offline)"
  echo "======================================================================"

  let node = findTool("NODE", "node")
  if node.len == 0:
    skip("jsdom monkey", "node is not installed (set NODE=... to point at it)")
    echo "-------------------------------------------------------------------"
    echo "Passed: ", passes, " | Failed: ", failures, " | Skipped: ", skips
    return

  let root = repoRoot()
  let harness = root / "tests" / "jsdom" / "monkey_harness.js"
  if not fileExists(harness):
    check("monkey harness is present", false, harness)
    quit 1

  # jsdom is a dev dependency of the harness; fetch it on first run.
  let jsdomDir = root / "tests" / "jsdom" / "node_modules" / "jsdom"
  if not dirExists(jsdomDir):
    echo "  installing jsdom into tests/jsdom ..."
    let npm = findTool("NPM", "npm")
    if npm.len == 0:
      skip("jsdom monkey", "jsdom is missing and npm is not installed, so it cannot be fetched")
      echo "-------------------------------------------------------------------"
      echo "Passed: ", passes, " | Failed: ", failures, " | Skipped: ", skips
      return
    let (outp, code) = execCmdEx(quoteShell(npm) & " install --silent",
                                 workingDir = root / "tests" / "jsdom")
    if code != 0:
      skip("jsdom monkey", "npm install failed: " & outp.strip().splitLines()[^1 .. ^1][0])
      echo "-------------------------------------------------------------------"
      echo "Passed: ", passes, " | Failed: ", failures, " | Skipped: ", skips
      return

  # 1. Build the bundle (this also proves every app still compiles to js).
  let bundle = getTempDir() / "uirelays_jsdom_bundle.html"
  let nimBin = block:
    let e = getEnv("NIM", "")
    if e.len > 0: e else: "nim"
  let exporter = root / "tools" / "export_interactive_html.nim"
  let buildCmd = nimBin & " c --mm:arc --outdir:" &
    quoteShell(getTempDir() / "uirelays_bins") & " -r " & quoteShell(exporter)
  echo "  building the bundle: ", buildCmd
  putEnv("UIRELAYS_EXPORT_DIR", getTempDir() / "uirelays_jsdom_export")
  putEnv("UIRELAYS_BUNDLE_OUT", bundle)
  putEnv("UIRELAYS_TMPDIR", getTempDir() / "uirelays_jsdom_js")
  let (buildOut, buildCode) = execCmdEx(buildCmd)
  check("all 9 apps compile to standalone HTML", buildCode == 0 and fileExists(bundle),
        (if buildCode != 0: buildOut.strip().splitLines()[^1 .. ^1][0] else: bundle & " missing"))
  if buildCode != 0 or not fileExists(bundle):
    echo "-------------------------------------------------------------------"
    echo "Passed: ", passes, " | Failed: ", failures, " | Skipped: ", skips
    quit 1

  let bundleSrc = readFile(bundle)
  let violation = violatesZeroCanvasPolicy(bundleSrc)
  check("bundle uses neither <canvas> nor WebAssembly", violation.len == 0, violation)

  # 2. Monkey it.
  let steps = getEnv("UIRELAYS_STEPS", "120")
  var args = @[quoteShell(harness), quoteShell(bundle), "--steps=" & steps,
               "--seed=20261019", "--json"]
  let onlyApps = getEnv("UIRELAYS_APPS", "")
  if onlyApps.len > 0:
    args.add "--apps=" & onlyApps
  let cmd = quoteShell(node) & " " & args.join(" ")
  echo "  running: ", cmd
  let (outp, code) = execCmdEx(cmd, workingDir = root)

  var report: JsonNode
  var parsed = false
  try:
    # The harness prints per-app progress lines and then the JSON report.
    let start = outp.rfind("{\n  \"file\"")
    let jsonText = if start >= 0: outp[start .. ^1] else: outp
    report = parseJson(jsonText)
    parsed = true
  except CatchableError:
    parsed = false

  if not parsed:
    check("jsdom monkey run produced a report", false,
          "exit=" & $code & "\n" & outp.strip().splitLines()[max(0, outp.strip().splitLines().len - 8) .. ^1].join("\n      "))
    echo "-------------------------------------------------------------------"
    echo "Passed: ", passes, " | Failed: ", failures, " | Skipped: ", skips
    quit 1

  for line in outp.splitLines():
    if line.startsWith("  PASS  ") or line.startsWith("  FAIL  "):
      echo "  ", line

  let errors = if report.hasKey("errors"): report["errors"].len else: 0
  let badStyles = if report.hasKey("badStyles"): report["badStyles"].getInt() else: 0
  let huge = if report.hasKey("hugeNodes"): report["hugeNodes"].getInt() else: 0
  let apps = if report.hasKey("apps"): report["apps"].len else: 0

  check("every app rendered a frame", apps > 0, "apps=" & $apps)
  check("no script threw during the monkey run", errors == 0,
        (if errors > 0: $report["errors"][0].getStr() else: ""))
  check("no primitive was emitted with a broken style", badStyles == 0, $badStyles)
  check("no primitive ran away in size", huge == 0, $huge)

  if report.hasKey("clipboardWrites") and report["clipboardWrites"].getInt() > 0:
    check("putClipboardText reaches the system clipboard", true)
  if report.hasKey("maxTextOverflowPx"):
    echo "  INFO  worst text overflow past the window edge: ",
      $report["maxTextOverflowPx"].getInt(), " px"
  if report.hasKey("maxNodes"):
    echo "  INFO  largest frame: ", $report["maxNodes"].getInt(), " DOM nodes"

  # D3: the DOM must be reconciled, not rewritten. The harness instruments the
  # live viewport and reports what the driver actually did to it.
  if report.hasKey("reconcileTotals"):
    let rec = report["reconcileTotals"]
    let probed = rec["appsProbed"].getInt()
    let steady = rec["steadySamples"].getInt()
    let breaks = rec["identityBreaks"].getInt()
    let rewrites = rec["innerHtmlWrites"].getInt()
    let worst = rec["worstChurnVsRewrite"].getFloat()
    check("the reconcile probe ran on every app", probed == apps,
          $probed & " of " & $apps)
    check("some frames were unchanged, so the identity check was not vacuous",
          steady > 0, "steadySamples=" & $steady)
    check("D3 an unchanged frame keeps its DOM nodes", breaks == 0,
          "identityBreaks=" & $breaks)
    check("D3 the viewport is never rewritten wholesale", rewrites == 0,
          "innerHtmlWrites=" & $rewrites)
    check("D3 structural work tracks what changed, not the frame size",
          worst < 0.75, "worst churn/rewrite=" & $worst)
    let countSamples = rec["nodeCountSamples"].getInt()
    let countBad = rec["nodeCountMismatches"].getInt()
    check("D3 the DOM holds exactly as many elements as the frame declares",
          countSamples > 0 and countBad == 0,
          $countBad & " of " & $countSamples & " samples disagreed")
    echo "  INFO  D3 reconcile: ", $probed, " apps, ", $steady,
      " unchanged frames, ", $countSamples, " node-count samples, worst churn ",
      $worst, " of a full rewrite"

  # The window is the relays' to own, but the app's canvas has to follow it:
  # cover the window it was handed, and shrink when the window shrinks.
  if report.hasKey("settle") and report["settle"].len > 0:
    var settled = 0
    for e in report["settle"]:
      inc settled
    check("every app was grown, shrunk and grown back", settled == apps,
          $settled & " of " & $apps)

  echo "-------------------------------------------------------------------"
  echo "Passed: ", passes, " | Failed: ", failures, " | Skipped: ", skips
  if failures > 0:
    quit 1

main()
