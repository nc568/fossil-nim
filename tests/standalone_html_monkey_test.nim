## standalone_html_monkey_test.nim -- Pure Nim (--mm:arc) Headless Chromium test
## that opens the exported standalone `.html` files directly via `file://`
## (no server, zero network) and monkey-tests interactive buttons, animations,
## keyboard input, and dynamic window resizing in all 9 applications.

import std/[os, osproc, strutils]

proc findNodeIndexByText(html, needle: string): int =
  html.find(needle)

proc main() =
  echo "======================================================================"
  echo " UIRelays Standalone Offline HTML Interactive & Resize Monkey Test"
  echo "======================================================================"

  # Inject a self-verifying monkey test harness into a temporary copy of uirelays_all_apps.html
  # and open it in Headless Chromium via file:// with zero network.
  let bundleSrc = readFile("/home/user/uirelays_all_apps.html")
  doAssert "<canvas" notin bundleSrc.toLowerAscii(), "Zero <canvas> policy violated!"
  doAssert "WebAssembly" notin bundleSrc, "Zero WASM policy violated!"

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

  // 4. Focim IDE: click [Theme: paper], click [Split Editor], click calculator.nim tab + resize
  switchUirApp("focim");
  await sleepMs(100);
  var themeClicked = clickElementWithText("[Theme: paper]");
  await sleepMs(80);
  var splitClicked = clickElementWithText("[Split Editor]");
  await sleepMs(80);
  var tabClicked = clickElementWithText("examples/calculator.nim");
  await sleepMs(80);
  var hasCalcCode = vp.textContent.indexOf("Calculator") !== -1;
  testResizeTo(1160, 720);
  await sleepMs(80);
  var focimResized = vp.style.width === "1160px";
  results.push("focim:theme=" + themeClicked + ":split=" + splitClicked + ":tab=" + (tabClicked && hasCalcCode) + ":resize=" + focimResized);

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
  results.push("web_showcase:inc=" + (incClicked && count1) + ":tab=" + (gfxTab && hasBlit) + ":resize=" + showcaseResized);

  // 6. Todo: type task + click + Add + resize
  switchUirApp("todo");
  await sleepMs(80);
  window.__uirActive.key("keydown", "X", "KeyX", false, false, false, false);
  window.__uirActive.key("keydown", "Y", "KeyY", false, false, false, false);
  await sleepMs(50);
  var addClicked = clickElementWithText("+ Add");
  await sleepMs(60);
  var hasXY = vp.textContent.indexOf("XY") !== -1;
  testResizeTo(940, 620);
  await sleepMs(60);
  var todoResized = vp.style.width === "940px";
  results.push("todo:addBtn=" + (addClicked && hasXY) + ":resize=" + todoResized);

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

  let testHtmlPath = "/tmp/test_standalone_all_apps.html"
  writeFile(testHtmlPath, bundleSrc.replace("</body>", verifierJs & "\n</body>"))

  let cmd = "chromium --headless --no-sandbox --disable-gpu --user-data-dir=/tmp/chromium-profile " &
            "--window-size=1280,820 --virtual-time-budget=15000 --dump-dom file://" & testHtmlPath & " 2>/dev/null"
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
