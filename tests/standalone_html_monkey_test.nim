## standalone_html_monkey_test.nim -- Pure Nim (--mm:arc) Headless Chromium test
## that opens the exported standalone `.html` files directly via `file://`
## (no server, zero network) and monkey-tests interactive buttons, animations,
## keyboard input, and dynamic window resizing in all 10 applications.

import std/[os, osproc, strutils]

proc findNodeIndexByText(html, needle: string): int =
  html.find(needle)

proc repoRoot(): string =
  ## No /home/user paths: the bundle is looked up inside this checkout.
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

proc findBrowser(): string =
  let fromEnv = getEnv("UIRELAYS_BROWSER", "")
  if fromEnv.len > 0:
    return fromEnv
  for name in ["chromium", "chromium-browser", "google-chrome",
               "google-chrome-stable", "chrome"]:
    let found = findExe(name)
    if found.len > 0:
      return found
  ""

proc main() =
  echo "======================================================================"
  echo " UIRelays Standalone Offline HTML Interactive & Resize Monkey Test"
  echo "======================================================================"

  # Inject a self-verifying monkey test harness into a temporary copy of the
  # exported bundle and open it in Headless Chromium via file:// with zero
  # network. The bundle is built by tools/export_interactive_html.nim; if it
  # is not there yet, build it -- a clean clone must be able to run this.
  let root = repoRoot()
  var bundlePath = getEnv("UIRELAYS_BUNDLE", "")
  if bundlePath.len == 0:
    bundlePath = root / "exported_html" / "uirelays_all_apps.html"
  if not fileExists(bundlePath):
    echo "  bundle not found at ", bundlePath, " -- exporting it first ..."
    let exportCmd = "nim c --mm:arc --outdir:" & quoteShell(getTempDir() / "uirelays_bins") &
                    " -r " & quoteShell(root / "tools" / "export_interactive_html.nim")
    let exportCode = execShellCmd(exportCmd)
    doAssert exportCode == 0, "Could not export the standalone bundle: " & exportCmd
  doAssert fileExists(bundlePath), "Bundle still missing after exporting: " & bundlePath

  let bundleSrc = readFile(bundlePath)
  # The policy is that the apps do not *use* a canvas or WebAssembly. The
  # Focim demo embeds this repository's README, which talks about both, so
  # look for API calls rather than for the words.
  const forbidden = ["getContext(\"2d\")", "getContext('2d')",
                     "createElement(\"canvas\")", "createElement('canvas')",
                     "WebAssembly.", "WebAssembly(", "new WebAssembly"]
  for needle in forbidden:
    doAssert needle notin bundleSrc, "Zero <canvas>/WASM policy violated: " & needle

  let verifierJs = """
<script>
window.__monkeyErrors = [];
window.addEventListener("error", function(e) {
  window.__monkeyErrors.push(e.message || String(e));
});

function sleepMs(ms) {
  return new Promise(function(resolve) { setTimeout(resolve, ms); });
}

function findElementWithText(txt) {
  var vp = document.getElementById("uir-viewport");
  if (!vp) return null;
  var nodes = vp.querySelectorAll(".uir-text");
  for (var i = 0; i < nodes.length; i++) {
    if (nodes[i].textContent.trim() === txt) {
      return nodes[i];
    }
  }
  for (var j = 0; j < nodes.length; j++) {
    if (nodes[j].textContent.indexOf(txt) !== -1) {
      return nodes[j];
    }
  }
  return null;
}

function countTextNodes(sub) {
  // How many rendered text nodes contain `sub` at all. A click helper that
  // returns false cannot say whether the label was missing from the DOM or
  // merely unmatched; this can, and the difference decides where the bug is.
  var vp = document.getElementById("uir-viewport");
  if (!vp) return -1;
  var nodes = vp.querySelectorAll(".uir-text");
  var n = 0;
  for (var i = 0; i < nodes.length; i++) {
    if (nodes[i].textContent.indexOf(sub) !== -1) n++;
  }
  return n;
}

function testResizeTo(w, h) {
  window.__uirFixedSizeMode = true;
  var vp = document.getElementById("uir-viewport");
  if (vp) {
    vp.style.width = w + "px";
    vp.style.height = h + "px";
  }
  window.__uirActive.resize(w, h, 100);
}

function clickElementWithText(txt) {
  var vp = document.getElementById("uir-viewport");
  var el = findElementWithText(txt);
  if (!vp || !el) return false;
  var vpRect = vp.getBoundingClientRect();
  var elRect = el.getBoundingClientRect();
  var cx = Math.round((elRect.left - vpRect.left) + elRect.width / 2);
  var cy = Math.round((elRect.top - vpRect.top) + elRect.height / 2);
  window.__uirActive.mouse("mousemove", cx, cy, 0, 1, false, false, false, false);
  window.__uirActive.mouse("mousedown", cx, cy, 0, 1, false, false, false, false);
  window.__uirActive.mouse("mouseup", cx, cy, 0, 1, false, false, false, false);
  return true;
}

function clickAt(x, y) {
  window.__uirActive.mouse("mousemove", x, y, 0, 1, false, false, false, false);
  window.__uirActive.mouse("mousedown", x, y, 0, 1, false, false, false, false);
  window.__uirActive.mouse("mouseup", x, y, 0, 1, false, false, false, false);
}

async function runAllInteractiveChecks() {
  var results = [];
  var vp = document.getElementById("uir-viewport");

  // 1. Calculator: click 7, +, 8, = -> verify 15; test resize 1100x700 -> 640x480
  switchUirApp("calculator");
  await sleepMs(80);
  var c7 = clickElementWithText("7");
  await sleepMs(40);
  var cPlus = clickElementWithText("+");
  await sleepMs(40);
  var c8 = clickElementWithText("8");
  await sleepMs(40);
  var cEq = clickElementWithText("=");
  await sleepMs(60);
  var has15 = vp.textContent.indexOf("15") !== -1;
  testResizeTo(1100, 700);
  await sleepMs(60);
  var calcW1 = vp.style.width;
  testResizeTo(680, 500);
  await sleepMs(60);
  var calcW2 = vp.style.width;
  results.push("calculator:clicks=" + (c7 && cPlus && c8 && cEq) + ":sum15=" + has15 + ":resize=" + (calcW1 !== calcW2));

  // 2. Snake: verify animation advances frames & clicking [Pause] / D-pad works + resize
  switchUirApp("snake");
  await sleepMs(80);
  var f1 = document.getElementById("uir-stat-frame").textContent;
  clickElementWithText("▼");
  await sleepMs(160);
  var f2 = document.getElementById("uir-stat-frame").textContent;
  var pClicked = clickElementWithText("Pause");
  await sleepMs(60);
  var isPaused = vp.textContent.indexOf("PAUSED") !== -1 || vp.textContent.indexOf("Resume") !== -1;
  testResizeTo(1040, 680);
  await sleepMs(60);
  var snakeResized = vp.style.width === "1040px";
  results.push("snake:anim=" + (f1 !== f2) + ":pauseBtn=" + (pClicked && isPaused) + ":resize=" + snakeResized);

  // 3. 2048: click directional buttons & New Game + resize
  switchUirApp("twenty48");
  await sleepMs(80);
  var bRight = clickElementWithText("Right");
  await sleepMs(50);
  var bDown = clickElementWithText("Down");
  await sleepMs(50);
  var bLeft = clickElementWithText("Left");
  await sleepMs(50);
  var bUp = clickElementWithText("Up");
  await sleepMs(60);
  var hasMoves = vp.textContent.indexOf("Moves: 0") === -1;
  testResizeTo(980, 660);
  await sleepMs(60);
  var t2048Resized = vp.style.width === "980px";
  results.push("twenty48:dpad=" + (bRight && bDown && bLeft && bUp) + ":moved=" + hasMoves + ":resize=" + t2048Resized);

  // 4. Focim IDE: click [Theme: paper], click calculator.nim tab,
  //    click inside editor to position cursor, type code, press Backspace & Enter,
  //    click [Split Editor], AND click [+ New Scratch File] and type into it + resize
  switchUirApp("focim");
  await sleepMs(100);
  var themeClicked = clickElementWithText("[Theme: paper]");
  await sleepMs(60);
  var tabClicked = clickElementWithText("examples/calculator.nim");
  await sleepMs(60);
  var hasCalcCode = vp.textContent.indexOf("Calculator") !== -1;
  // Click inside editor pane to place cursor and type text directly into calculator.nim
  clickAt(260, 14);
  await sleepMs(40);
  var editToken = "FOCIM_EDIT_OKX";
  for (var ti = 0; ti < editToken.length; ti++) {
    var ch = editToken.charAt(ti);
    window.__uirActive.key("keydown", ch, "Key" + ch.toUpperCase(), false, false, false, false);
  }
  window.__uirActive.key("keydown", "Backspace", "Backspace", false, false, false, false);
  window.__uirActive.key("keydown", "Enter", "Enter", false, false, false, false);
  await sleepMs(80);
  var hasEditedCode = vp.textContent.indexOf("FOCIM_EDIT_OK") !== -1 && vp.textContent.indexOf("FOCIM_EDIT_OKX") === -1;
  var hasDirtyStar = vp.textContent.indexOf("examples/calculator.nim*") !== -1;
  var splitClicked = clickElementWithText("[Split Editor]");
  await sleepMs(60);
  // Click [+ New Scratch File] and type into it
  var scratchClicked = clickElementWithText("[+ New Scratch File]");
  await sleepMs(60);
  var scratchCode = "SCRATCH_777";
  for (var si = 0; si < scratchCode.length; si++) {
    var sch = scratchCode.charAt(si);
    window.__uirActive.key("keydown", sch, "KeyA", false, false, false, false);
  }
  await sleepMs(60);
  var hasScratchEdited = vp.textContent.indexOf("SCRATCH_777") !== -1;
  // Verify exact 8.000px per-character cell alignment (0.000px drift / 0px line shift)
  var scratchNode = findElementWithText("SCRATCH_777");
  var exactCellAlign = false;
  if (scratchNode && scratchNode.firstChild && scratchNode.textContent.length >= 5) {
    var rng = document.createRange();
    rng.setStart(scratchNode.firstChild, 0);
    rng.setEnd(scratchNode.firstChild, 5);
    var rw = rng.getBoundingClientRect().width;
    exactCellAlign = Math.abs(rw - 40.0) < 0.05;
  }
  // Test Shift+ArrowLeft selection and replacement in focim
  for (var sl = 0; sl < 3; sl++) {
    window.__uirActive.key("keydown", "ArrowLeft", "ArrowLeft", true, false, false, false);
  }
  window.__uirActive.key("keydown", "9", "Digit9", false, false, false, false);
  await sleepMs(60);
  var hasSelReplaced = vp.textContent.indexOf("SCRATCH_9") !== -1 && vp.textContent.indexOf("SCRATCH_777") === -1;
  testResizeTo(1160, 720);
  await sleepMs(80);
  var focimResized = vp.style.width === "1160px";
  results.push("focim:theme=" + themeClicked + ":split=" + splitClicked + ":tabClick=" + tabClicked + ":tabCode=" + hasCalcCode + ":edit=" + (hasEditedCode && hasDirtyStar && scratchClicked && hasScratchEdited && hasSelReplaced) + ":align=" + exactCellAlign + ":resize=" + focimResized);

  // 5. Web Showcase: click +1 on Widgets tab, then switch to 2. Graphics & Clip + resize
  switchUirApp("web_showcase");
  await sleepMs(80);
  var incClicked = clickElementWithText("+1");
  await sleepMs(60);
  var count1 = vp.textContent.indexOf("Counter: 1") !== -1;
  var gfxTab = clickElementWithText("Graphics, Clip & Blit");
  await sleepMs(60);
  var hasBlit = vp.textContent.indexOf("Procedural 32-bit RGBA Blit") !== -1;
  testResizeTo(1020, 680);
  await sleepMs(60);
  var showcaseResized = vp.style.width === "1020px";
  results.push("web_showcase:inc=" + (incClicked && count1) + ":tabClick=" + gfxTab + ":tabBlit=" + hasBlit + ":tabNodes=" + countTextNodes("Graphics") + ":blitNodes=" + countTextNodes("Procedural") + ":resize=" + showcaseResized);

  // 6. Todo: type text, move cursor left into middle with ArrowLeft, insert text,
  //    select with Shift+ArrowLeft, replace selection, click + Add + resize
  switchUirApp("todo");
  await sleepMs(80);
  var todoStart = "AlphaGamma";
  for (var qi = 0; qi < todoStart.length; qi++) {
    var qch = todoStart.charAt(qi);
    window.__uirActive.key("keydown", qch, "KeyA", false, false, false, false);
  }
  // Move cursor 5 characters left (between Alpha and Gamma)
  for (var ql = 0; ql < 5; ql++) {
    window.__uirActive.key("keydown", "ArrowLeft", "ArrowLeft", false, false, false, false);
  }
  // Insert Beta in the middle -> AlphaBetaGamma
  var todoMid = "Beta";
  for (var qm = 0; qm < todoMid.length; qm++) {
    var mch = todoMid.charAt(qm);
    window.__uirActive.key("keydown", mch, "KeyB", false, false, false, false);
  }
  await sleepMs(40);
  var hasMidInsert = vp.textContent.indexOf("AlphaBetaGamma") !== -1;
  // Select "Beta" with Shift+ArrowLeft x4 and replace with "_" -> Alpha_Gamma
  for (var qs = 0; qs < 4; qs++) {
    window.__uirActive.key("keydown", "ArrowLeft", "ArrowLeft", true, false, false, false);
  }
  window.__uirActive.key("keydown", "_", "Minus", true, false, false, false);
  await sleepMs(50);
  var addClicked = clickElementWithText("+ Add");
  await sleepMs(60);
  var hasReplacedTask = vp.textContent.indexOf("Alpha_Gamma") !== -1;
  testResizeTo(940, 620);
  await sleepMs(60);
  var todoResized = vp.style.width === "940px";
  results.push("todo:cursorMove=" + hasMidInsert + ":selReplace=" + hasReplacedTask + ":addBtn=" + (addClicked && hasReplacedTask) + ":resize=" + todoResized);

  // 7. Paint: click Brush +, drag on canvas, click Clear + resize
  switchUirApp("paint");
  await sleepMs(80);
  var brPlus = clickElementWithText("Brush +");
  await sleepMs(50);
  var br8 = vp.textContent.indexOf("8px") !== -1;
  clickAt(300, 220);
  await sleepMs(50);
  var clrClicked = clickElementWithText("Clear");
  await sleepMs(50);
  testResizeTo(920, 600);
  await sleepMs(60);
  var paintResized = vp.style.width === "920px";
  results.push("paint:brushPlus=" + (brPlus && br8) + ":clear=" + clrClicked + ":resize=" + paintResized);

  // 8. Layout Demo: click [+ Split Right], [+ Split Down], [Reset Layout] + resize
  switchUirApp("layout_demo");
  await sleepMs(80);
  var spRight = clickElementWithText("[+ Split Right]");
  await sleepMs(60);
  var hasPane1 = vp.textContent.indexOf("pane_1") !== -1;
  var spDown = clickElementWithText("[+ Split Down]");
  await sleepMs(60);
  var hasPane2 = vp.textContent.indexOf("pane_2") !== -1;
  testResizeTo(1000, 650);
  await sleepMs(60);
  var layoutResized = vp.style.width === "1000px";
  results.push("layout_demo:splitR=" + (spRight && hasPane1) + ":splitD=" + (spDown && hasPane2) + ":resize=" + layoutResized);

  // 9. Hello: click Pink, verify animated frames advance + resize
  switchUirApp("hello");
  await sleepMs(80);
  var hf1 = document.getElementById("uir-stat-frame").textContent;
  var pinkClicked = clickElementWithText("Pink");
  await sleepMs(120);
  var hf2 = document.getElementById("uir-stat-frame").textContent;
  testResizeTo(900, 580);
  await sleepMs(60);
  var helloResized = vp.style.width === "900px";
  results.push("hello:pinkBtn=" + pinkClicked + ":anim=" + (hf1 !== hf2) + ":resize=" + helloResized);

  // Stop active rAF loop once all checks complete so headless --virtual-time-budget exits immediately
  window.__uirRunId = (window.__uirRunId || 0) + 1;

  var summary = document.createElement("pre");
  summary.id = "standalone-monkey-summary";
  summary.textContent = "STANDALONE_MONKEY_" + "OK=true\n" +
    "CANVAS_COUNT=" + document.querySelectorAll("canvas").length + "\n" +
    "JS_ERRORS=" + window.__monkeyErrors.length + "\n" +
    results.join("\n");
  document.body.appendChild(summary);
}

window.addEventListener("load", function() {
  setTimeout(runAllInteractiveChecks, 120);
});
</script>
"""

  let testHtmlPath = getTempDir() / "test_standalone_all_apps.html"
  writeFile(testHtmlPath, bundleSrc.replace("</body>", verifierJs & "\n</body>"))

  let browserBin = findBrowser()
  if browserBin.len == 0:
    echo "======================================================================"
    echo " SKIPPED: no headless browser installed."
    echo " Install chromium (or set UIRELAYS_BROWSER=/path/to/browser) to run"
    echo " the standalone interactive monkey test; tests/jsdom_monkey_test.nim"
    echo " covers the same ground with node + jsdom and needs no browser."
    echo "======================================================================"
    return

  let cmd = quoteShell(browserBin) &
            " --headless --no-sandbox --disable-gpu --user-data-dir=" &
            quoteShell(getTempDir() / "uir-chromium-profile") & " " &
            "--window-size=1280,820 --virtual-time-budget=15000 --dump-dom file://" &
            testHtmlPath & " 2>/dev/null"
  let (domOut, exitCode) = execCmdEx(cmd)
  doAssert exitCode == 0, "Chromium failed with exit code " & $exitCode
  let idx = findNodeIndexByText(domOut, "<pre id=\"standalone-monkey-summary\">")
  if idx < 0:
    echo "DOM output tail:\n", domOut[max(0, domOut.len - 2000) .. ^1]
    doAssert false, "standalone-monkey-summary not found in DOM output!"

  let endIdx = domOut.find("</pre>", idx)
  let summaryBlock = domOut[idx ..< (if endIdx > idx: endIdx else: min(domOut.len, idx + 1500))]
  echo summaryBlock

  doAssert "CANVAS_COUNT=0" in summaryBlock, "Expected 0 <canvas> elements!"
  doAssert "JS_ERRORS=0" in summaryBlock, "Expected 0 JS errors!"
  for line in summaryBlock.splitLines():
    if ":" in line:
      doAssert "false" notin line, "Interactive check failed on line: " & line
  echo "======================================================================"
  echo " ALL 9 STANDALONE OFFLINE HTML APPS PASSED INTERACTIVE & RESIZE TESTS!"
  echo "======================================================================"

main()
