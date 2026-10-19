# Pure Vanilla HTML5 + CSS3 + JS (DOM) backend driver for uirelays.
# Strictly NO <canvas> and NO WebAssembly (WASM).
# Written 100% in Nim (--mm:arc).
#
# Build:
#   nim c --mm:arc -d:html examples/hello.nim

when not defined(js):
  import std/json
import ../coords, ../input, ../screen
import ./web_common

var
  htmlFrameBuffer: string
  htmlActiveClip: WebClipState
  htmlClipOpen: bool
  htmlCurrentNodeCount: int
  lastPublishedHtml*: string

proc closeActiveClipDiv() {.inline.} =
  if htmlClipOpen:
    htmlFrameBuffer.add "</div>"
    htmlClipOpen = false

proc syncClipDiv() {.inline.} =
  if webCore.currentClip != htmlActiveClip:
    closeActiveClipDiv()
    htmlActiveClip = webCore.currentClip
    if htmlActiveClip.enabled:
      let r = htmlActiveClip.rect
      let x1 = r.x
      let y1 = r.y
      let x2 = max(r.x, r.x + r.w)
      let y2 = max(r.y, r.y + r.h)
      htmlFrameBuffer.add "<div class=\"uir-clip\" data-clip=\"" &
        $r.x & "," & $r.y & "," & $r.w & "," & $r.h &
        "\" style=\"position:absolute;left:0;top:0;width:100%;height:100%;" &
        "clip-path:polygon(" & $x1 & "px " & $y1 & "px," &
        $x2 & "px " & $y1 & "px," & $x2 & "px " & $y2 & "px," &
        $x1 & "px " & $y2 & "px);pointer-events:none;\">"
      htmlClipOpen = true

when defined(js):
  const HtmlDriverPageTemplate = ""
else:
  const HtmlDriverPageTemplate = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>UIRelays — Pure HTML/CSS/JS DOM Backend</title>
<style>
  :root {
    --bg-shell: #11111b;
    --bg-bar: #181825;
    --fg-bar: #cdd6f4;
    --accent: #89b4fa;
    --badge-bg: #1e3a2f;
    --badge-fg: #a6e3a1;
    --border: #313244;
  }
  * { box-sizing: border-box; }
  html, body {
    margin: 0;
    padding: 0;
    width: 100%;
    height: 100%;
    background: var(--bg-shell);
    color: var(--fg-bar);
    font-family: system-ui, -apple-system, sans-serif;
    overflow: hidden;
    user-select: none;
    -webkit-user-select: none;
  }
  #uir-shell {
    display: flex;
    flex-direction: column;
    width: 100%;
    height: 100%;
  }
  #uir-hud {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 10px;
    padding: 6px 12px;
    background: var(--bg-bar);
    border-bottom: 1px solid var(--border);
    font-size: 12px;
    flex-shrink: 0;
    z-index: 10;
  }
  .uir-hud-left, .uir-hud-right {
    display: flex;
    align-items: center;
    gap: 8px;
    flex-wrap: wrap;
  }
  .uir-badge {
    background: var(--badge-bg);
    color: var(--badge-fg);
    border: 1px solid #40a02b;
    padding: 2px 8px;
    border-radius: 999px;
    font-weight: 600;
    font-size: 11px;
    letter-spacing: 0.2px;
  }
  .uir-stat {
    color: #a6adc8;
    font-family: 'DejaVu Sans Mono', Consolas, monospace;
    font-size: 11px;
    background: #1e1e2e;
    padding: 2px 6px;
    border-radius: 4px;
    border: 1px solid var(--border);
  }
  .uir-btn {
    background: #313244;
    color: #cdd6f4;
    border: 1px solid #45475a;
    border-radius: 4px;
    padding: 3px 8px;
    font-size: 11px;
    cursor: pointer;
  }
  .uir-btn:hover {
    background: #45475a;
  }
  .uir-btn-danger {
    background: #452732;
    color: #f38ba8;
    border-color: #f38ba8;
  }
  .uir-btn-danger:hover {
    background: #5c2d3d;
  }
  #uir-clipboard-input {
    background: #1e1e2e;
    color: #cdd6f4;
    border: 1px solid #45475a;
    border-radius: 4px;
    padding: 2px 6px;
    font-size: 11px;
    width: 130px;
  }
  #uir-stage {
    flex: 1;
    display: flex;
    align-items: center;
    justify-content: center;
    overflow: auto;
    padding: 8px;
  }
  #uir-viewport {
    position: relative;
    width: 800px;
    height: 600px;
    background: #1e1e2e;
    overflow: hidden;
    box-shadow: 0 10px 30px rgba(0, 0, 0, 0.55);
    outline: 1px solid var(--border);
    tab-index: 0;
  }
  #uir-viewport:focus {
    outline: 1px solid var(--accent);
  }
  .uir-rect, .uir-point, .uir-line-h, .uir-line-v, .uir-svg-line, .uir-text, .uir-img-crop, .uir-blit-clip {
    position: absolute;
    pointer-events: none;
  }
  .uir-text {
    white-space: pre;
    font-variant-ligatures: none;
    margin: 0;
    padding: 0;
  }
</style>
</head>
<body>
<div id="uir-shell">
  <div id="uir-hud">
    <div class="uir-hud-left">
      <span class="uir-badge" id="uir-backend-badge">DOM BACKEND (Pure HTML/CSS/JS · No Canvas · No WASM)</span>
      <strong id="uir-win-title">UIRelays Window</strong>
      <span class="uir-stat" id="uir-stat-size">800×600</span>
      <span class="uir-stat" id="uir-stat-frame">frame: 0</span>
      <span class="uir-stat" id="uir-stat-nodes">DOM nodes: 0</span>
      <span class="uir-stat" id="uir-stat-cursor">cursor: default</span>
    </div>
    <div class="uir-hud-right">
      <input id="uir-clipboard-input" type="text" placeholder="Clipboard text..." aria-label="Clipboard text" />
      <button class="uir-btn" id="uir-btn-clip-sync" type="button">Set Clipboard</button>
      <button class="uir-btn" id="uir-btn-resize-800" type="button">800×600</button>
      <button class="uir-btn" id="uir-btn-resize-960" type="button">960×640</button>
      <button class="uir-btn uir-btn-danger" id="uir-btn-close" type="button">Close Window</button>
    </div>
  </div>
  <div id="uir-stage">
    <div id="uir-viewport" tabindex="0" role="application" aria-label="UIRelays Pure HTML DOM Viewport"></div>
  </div>
</div>
<script>
(function() {
  "use strict";
  const viewport = document.getElementById("uir-viewport");
  const titleEl = document.getElementById("uir-win-title");
  const sizeEl = document.getElementById("uir-stat-size");
  const frameEl = document.getElementById("uir-stat-frame");
  const nodesEl = document.getElementById("uir-stat-nodes");
  const cursorEl = document.getElementById("uir-stat-cursor");
  const clipInput = document.getElementById("uir-clipboard-input");

  let lastFrameId = -1;
  let pendingEvents = [];
  let flushTimer = null;
  const monkeyErrors = [];
  window.addEventListener("error", function(ev) {
    monkeyErrors.push(String(ev.message || ev));
  });
  window.addEventListener("unhandledrejection", function(ev) {
    monkeyErrors.push(String(ev.reason || ev));
  });

  function queueEvent(ev) {
    pendingEvents.push(ev);
    if (!flushTimer) {
      flushTimer = setTimeout(flushEvents, 8);
    }
  }

  function flushEvents() {
    flushTimer = null;
    if (pendingEvents.length === 0) return Promise.resolve();
    const batch = pendingEvents;
    pendingEvents = [];
    return fetch("/input", {
      method: "POST",
      keepalive: true,
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ events: batch })
    }).catch(function() {});
  }

  function applyFrame(data) {
    if (!data || typeof data.frameId !== "number") return;
    if (data.frameId === lastFrameId) return;
    lastFrameId = data.frameId;

    if (typeof data.width === "number" && typeof data.height === "number") {
      viewport.style.width = data.width + "px";
      viewport.style.height = data.height + "px";
      sizeEl.textContent = data.width + "×" + data.height;
    }
    if (typeof data.title === "string") {
      document.title = data.title + " [Pure HTML/CSS/JS DOM]";
      titleEl.textContent = data.title;
    }
    if (typeof data.cursor === "string") {
      viewport.style.cursor = data.cursor;
      cursorEl.textContent = "cursor: " + data.cursor;
    }
    if (typeof data.clipboard === "string" && document.activeElement !== clipInput) {
      clipInput.value = data.clipboard;
    }
    if (typeof data.html === "string") {
      viewport.innerHTML = data.html;
    }
    frameEl.textContent = "frame: " + data.frameId;
    nodesEl.textContent = "DOM nodes: " + (data.domNodeCount || viewport.querySelectorAll("*").length);
  }

  function relCoords(e) {
    const r = viewport.getBoundingClientRect();
    return {
      x: Math.round(e.clientX - r.left),
      y: Math.round(e.clientY - r.top)
    };
  }

  viewport.addEventListener("mousedown", function(e) {
    viewport.focus();
    const p = relCoords(e);
    queueEvent({
      type: "mousedown",
      x: p.x,
      y: p.y,
      button: e.button,
      clicks: e.detail || 1,
      shift: e.shiftKey,
      ctrl: e.ctrlKey,
      alt: e.altKey,
      meta: e.metaKey
    });
    flushEvents();
  });

  viewport.addEventListener("mouseup", function(e) {
    const p = relCoords(e);
    queueEvent({
      type: "mouseup",
      x: p.x,
      y: p.y,
      button: e.button,
      clicks: e.detail || 1,
      shift: e.shiftKey,
      ctrl: e.ctrlKey,
      alt: e.altKey,
      meta: e.metaKey
    });
    flushEvents();
  });

  viewport.addEventListener("mousemove", function(e) {
    const p = relCoords(e);
    queueEvent({
      type: "mousemove",
      x: p.x,
      y: p.y,
      shift: e.shiftKey,
      ctrl: e.ctrlKey,
      alt: e.altKey,
      meta: e.metaKey
    });
  });

  viewport.addEventListener("contextmenu", function(e) {
    e.preventDefault();
  });

  viewport.addEventListener("wheel", function(e) {
    e.preventDefault();
    const dy = e.deltaY < 0 ? 1 : (e.deltaY > 0 ? -1 : 0);
    const dx = e.deltaX < 0 ? 1 : (e.deltaX > 0 ? -1 : 0);
    queueEvent({
      type: "wheel",
      dx: dx,
      dy: dy,
      shift: e.shiftKey,
      ctrl: e.ctrlKey,
      alt: e.altKey,
      meta: e.metaKey
    });
    flushEvents();
  }, { passive: false });

  window.addEventListener("keydown", function(e) {
    if (document.activeElement === clipInput) return;
    if (["Tab", "ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight", "Space", "Backspace"].includes(e.code)) {
      e.preventDefault();
    }
    queueEvent({
      type: "keydown",
      key: e.key,
      code: e.code,
      shift: e.shiftKey,
      ctrl: e.ctrlKey,
      alt: e.altKey,
      meta: e.metaKey
    });
    flushEvents();
  });

  window.addEventListener("keyup", function(e) {
    if (document.activeElement === clipInput) return;
    queueEvent({
      type: "keyup",
      key: e.key,
      code: e.code,
      shift: e.shiftKey,
      ctrl: e.ctrlKey,
      alt: e.altKey,
      meta: e.metaKey
    });
    flushEvents();
  });

  viewport.addEventListener("focus", function() {
    queueEvent({ type: "focus" });
  });
  viewport.addEventListener("blur", function() {
    queueEvent({ type: "blur" });
  });

  document.getElementById("uir-btn-clip-sync").addEventListener("click", function() {
    queueEvent({ type: "clipboard", text: clipInput.value });
    flushEvents();
    viewport.focus();
  });

  document.getElementById("uir-btn-resize-800").addEventListener("click", function() {
    window.__uirFixedSize = true;
    queueEvent({ type: "resize", width: 800, height: 600, uiScale: 100 });
    flushEvents();
    viewport.focus();
  });

  document.getElementById("uir-btn-resize-960").addEventListener("click", function() {
    window.__uirFixedSize = true;
    queueEvent({ type: "resize", width: 960, height: 640, uiScale: 100 });
    flushEvents();
    viewport.focus();
  });

  document.getElementById("uir-btn-close").addEventListener("click", function() {
    queueEvent({ type: "close" });
    flushEvents();
  });

  // Dynamic window resize observer so UIRelays adapts to browser window dimensions
  const stageEl = document.getElementById("uir-stage");
  const isMonkeyRun = window.location.search.indexOf("monkey=1") !== -1;
  function syncStageResize() {
    if (window.__uirFixedSize || isMonkeyRun) return;
    if (!stageEl) return;
    const w = Math.max(420, Math.floor(stageEl.clientWidth - 16));
    const h = Math.max(320, Math.floor(stageEl.clientHeight - 16));
    queueEvent({ type: "resize", width: w, height: h, uiScale: 100 });
    flushEvents();
  }
  window.addEventListener("resize", syncStageResize);
  if (typeof ResizeObserver !== "undefined" && stageEl) {
    new ResizeObserver(syncStageResize).observe(stageEl);
  }
  setTimeout(syncStageResize, 20);

  // Connect SSE stream + fallback state poll
  let activeEventSource = null;
  let activePollTimer = null;
  const isScreenshotOnly = window.location.search.indexOf("screenshot=1") !== -1;

  function stopBackgroundStreams() {
    if (activeEventSource) {
      try { activeEventSource.close(); } catch (_) {}
      activeEventSource = null;
    }
    if (activePollTimer) {
      clearInterval(activePollTimer);
      activePollTimer = null;
    }
  }

  function startStream() {
    if (isScreenshotOnly) return;
    try {
      activeEventSource = new EventSource("/events");
      activeEventSource.onmessage = function(ev) {
        try {
          applyFrame(JSON.parse(ev.data));
        } catch (_) {}
      };
    } catch (_) {}
  }

  function pollState() {
    return fetch("/state")
      .then(function(r) { return r.json(); })
      .then(applyFrame)
      .catch(function() {});
  }

  startStream();
  pollState();
  if (!isScreenshotOnly) {
    activePollTimer = setInterval(pollState, 60);
  }
  viewport.focus();

  // Autonomous Browser Monkey Tester when opened with ?monkey=1
  if (window.location.search.indexOf("monkey=1") !== -1) {
    let monkeyStarted = false;
    const checkStart = setInterval(function() {
      if (lastFrameId >= 1 && !monkeyStarted) {
        monkeyStarted = true;
        clearInterval(checkStart);
        runBrowserMonkeySuite();
      }
    }, 30);

    async function sleepMs(ms) {
      return new Promise(function(resolve) { setTimeout(resolve, ms); });
    }

    function fireMouse(type, rx, ry, button, clicks) {
      const r = viewport.getBoundingClientRect();
      const ev = new MouseEvent(type, {
        bubbles: true,
        cancelable: true,
        clientX: r.left + rx,
        clientY: r.top + ry,
        button: button || 0,
        detail: clicks || 1
      });
      viewport.dispatchEvent(ev);
    }

    function fireClick(rx, ry, button, clicks) {
      fireMouse("mousemove", rx, ry, button || 0, 1);
      fireMouse("mousedown", rx, ry, button || 0, clicks || 1);
      fireMouse("mouseup", rx, ry, button || 0, clicks || 1);
    }

    function fireWheel(dy) {
      const ev = new WheelEvent("wheel", {
        bubbles: true,
        cancelable: true,
        deltaY: dy
      });
      viewport.dispatchEvent(ev);
    }

    function fireKey(key, code, ctrl) {
      const kd = new KeyboardEvent("keydown", {
        bubbles: true,
        cancelable: true,
        key: key,
        code: code,
        ctrlKey: !!ctrl
      });
      window.dispatchEvent(kd);
      const ku = new KeyboardEvent("keyup", {
        bubbles: true,
        cancelable: true,
        key: key,
        code: code,
        ctrlKey: !!ctrl
      });
      window.dispatchEvent(ku);
    }

    async function runBrowserMonkeySuite() {
      let clicksDispatched = 0;
      let keysDispatched = 0;
      let wheelDispatched = 0;
      let hudButtonsClicked = 0;
      let maxDomNodesSeen = viewport.querySelectorAll("*").length;

      // 1. Click HUD buttons
      clipInput.value = "MonkeyClip_DOM";
      document.getElementById("uir-btn-clip-sync").click();
      hudButtonsClicked++;
      document.getElementById("uir-btn-resize-960").click();
      hudButtonsClicked++;
      await sleepMs(60);
      pollState();
      document.getElementById("uir-btn-resize-800").click();
      hudButtonsClicked++;
      await sleepMs(60);
      pollState();

      // 2. Systematic clicks on sidebar, palette, composer, checkboxes, delete buttons, tabs
      const targetCoords = [
        [20, 18], [50, 18], [80, 18], [110, 18], [140, 18], [170, 18],
        [60, 60], [60, 100], [60, 140], [60, 180], [60, 245], [60, 285], [60, 325], [60, 365], [60, 405],
        [250, 75], [330, 75], [410, 75], [490, 75],
        [280, 130], [500, 130], [280, 170], [480, 170], [580, 170],
        [100, 70], [22, 145], [22, 175], [730, 145],
        [350, 250], [400, 300], [450, 350]
      ];
      for (let i = 0; i < targetCoords.length; i++) {
        fireClick(targetCoords[i][0], targetCoords[i][1], 0, 1);
        clicksDispatched++;
        if (i % 6 === 0) {
          await flushEvents();
          await sleepMs(25);
          pollState();
          maxDomNodesSeen = Math.max(maxDomNodesSeen, viewport.querySelectorAll("*").length);
        }
      }

      // 3. Systematic keyboard shortcuts & text typing
      const keys = [
        ["1", "Digit1"], ["2", "Digit2"], ["3", "Digit3"], ["4", "Digit4"],
        ["a", "KeyA"], ["b", "KeyB"], ["c", "KeyC"], ["!", "Digit1"],
        ["Backspace", "Backspace"], ["Enter", "Enter"], ["Tab", "Tab"],
        ["ArrowDown", "ArrowDown"], ["ArrowUp", "ArrowUp"], [" ", "Space"],
        ["Delete", "Delete"], ["1", "Digit1"]
      ];
      for (let i = 0; i < keys.length; i++) {
        fireKey(keys[i][0], keys[i][1], false);
        keysDispatched++;
      }
      fireKey("c", "KeyC", true);
      fireKey("v", "KeyV", true);
      keysDispatched += 2;
      await flushEvents();
      await sleepMs(50);
      pollState();

      // 4. Chaotic Monkey Fuzzing (random clicks, drags, wheel scrolls, boundary coords)
      let seed = 1337;
      function nextRand() {
        seed = (seed * 1664525 + 1013904223) >>> 0;
        return seed / 4294967296;
      }
      for (let i = 0; i < 80; i++) {
        const rx = Math.floor(nextRand() * 860) - 20;
        const ry = Math.floor(nextRand() * 640) - 20;
        const btn = i % 15 === 0 ? 2 : (i % 19 === 0 ? 1 : 0);
        const dbl = i % 11 === 0 ? 2 : 1;
        fireClick(rx, ry, btn, dbl);
        clicksDispatched++;
        if (i % 8 === 0) {
          fireWheel(i % 16 === 0 ? -120 : 120);
          wheelDispatched++;
        }
      }
      fireMouse("mousemove", 120, 120, 0, 1);
      await flushEvents();
      await sleepMs(120);
      await pollState();
      maxDomNodesSeen = Math.max(maxDomNodesSeen, viewport.querySelectorAll("*").length);

      const rectNodes = viewport.querySelectorAll(".uir-rect").length;
      const textNodes = viewport.querySelectorAll(".uir-text").length;
      const lineNodes = viewport.querySelectorAll(".uir-line-h, .uir-line-v, .uir-svg-line").length;
      const canvasNodes = document.querySelectorAll("canvas").length;
      const vpRect = viewport.getBoundingClientRect();

      const report = {
        ready: true,
        backend: "html",
        frameId: lastFrameId,
        clicksDispatched: clicksDispatched,
        keysDispatched: keysDispatched,
        wheelDispatched: wheelDispatched,
        hudButtonsClicked: hudButtonsClicked,
        domNodesNow: viewport.querySelectorAll("*").length,
        maxDomNodesSeen: maxDomNodesSeen,
        rectNodes: rectNodes,
        textNodes: textNodes,
        lineNodes: lineNodes,
        canvasElementsInDocument: canvasNodes,
        zeroCanvasVerified: canvasNodes === 0,
        viewportWidth: Math.round(vpRect.width),
        viewportHeight: Math.round(vpRect.height),
        jsErrors: monkeyErrors
      };

      await fetch("/monkey-report", {
        method: "POST",
        keepalive: true,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(report)
      });
      stopBackgroundStreams();
    }
  }
})();
</script>
</body>
</html>
"""

# ---------------------------------------------------------------------------
# Pure HTML/CSS DOM Drawing Relays (Zero <canvas>, Zero WASM)
# ---------------------------------------------------------------------------

proc resetHtmlFrameBuffer() =
  htmlFrameBuffer.setLen(0)
  htmlActiveClip = WebClipState(enabled: false)
  htmlClipOpen = false
  htmlCurrentNodeCount = 0

proc htmlCreateWindow(layout: var ScreenLayout; icon: pointer; iconLen: int) =
  webCreateWindowCommon(layout, icon, iconLen)
  resetHtmlFrameBuffer()

proc htmlSaveState() =
  webSaveState()

proc htmlRestoreState() =
  webRestoreState()

proc htmlSetClipRect(r: Rect) =
  webSetClipRect(r)

proc htmlFillRect(r: Rect; color: Color) =
  if r.w <= 0 or r.h <= 0 or color.a == 0'u8:
    return
  # "A full-window opaque fill covers everything, so drop what we have."
  # True only at the start of a frame. Halfway through, the same call is an
  # overlay (a lock screen, a scene painted over its backdrop) and silently
  # discarding the frame so far paints a blank screen.
  if htmlFrameBuffer.len == 0 and not webCore.currentClip.enabled and
     r.x <= 0 and r.y <= 0 and
     r.w >= webCore.layout.width and r.h >= webCore.layout.height and
     color.a == 255'u8:
    resetHtmlFrameBuffer()
  syncClipDiv()
  inc htmlCurrentNodeCount
  htmlFrameBuffer.add "<div class=\"uir-rect\" style=\"left:" & $r.x &
    "px;top:" & $r.y & "px;width:" & $r.w & "px;height:" & $r.h &
    "px;background:" & toCssRgba(color) & ";\"></div>"

proc htmlDrawPoint(x, y: int; color: Color) =
  if color.a == 0'u8:
    return
  syncClipDiv()
  inc htmlCurrentNodeCount
  htmlFrameBuffer.add "<div class=\"uir-point\" style=\"left:" & $x &
    "px;top:" & $y & "px;width:1px;height:1px;background:" &
    toCssRgba(color) & ";\"></div>"

proc htmlDrawLine(x1, y1, x2, y2: int; color: Color) =
  if color.a == 0'u8:
    return
  syncClipDiv()
  inc htmlCurrentNodeCount
  let cssCol = toCssRgba(color)
  if y1 == y2:
    let lx = min(x1, x2)
    let lw = max(1, abs(x2 - x1) + 1)
    htmlFrameBuffer.add "<div class=\"uir-line-h\" style=\"left:" & $lx &
      "px;top:" & $y1 & "px;width:" & $lw & "px;height:1px;background:" &
      cssCol & ";\"></div>"
  elif x1 == x2:
    let ly = min(y1, y2)
    let lh = max(1, abs(y2 - y1) + 1)
    htmlFrameBuffer.add "<div class=\"uir-line-v\" style=\"left:" & $x1 &
      "px;top:" & $ly & "px;width:1px;height:" & $lh & "px;background:" &
      cssCol & ";\"></div>"
  else:
    let minX = min(x1, x2)
    let minY = min(y1, y2)
    let w = max(2, abs(x2 - x1) + 2)
    let h = max(2, abs(y2 - y1) + 2)
    let relX1 = x1 - minX
    let relY1 = y1 - minY
    let relX2 = x2 - minX
    let relY2 = y2 - minY
    htmlFrameBuffer.add "<svg class=\"uir-svg-line\" style=\"left:" & $minX &
      "px;top:" & $minY & "px;width:" & $w & "px;height:" & $h &
      "px;overflow:visible;\" viewBox=\"0 0 " & $w & " " & $h & "\">" &
      "<line x1=\"" & $relX1 & "\" y1=\"" & $relY1 &
      "\" x2=\"" & $relX2 & "\" y2=\"" & $relY2 &
      "\" stroke=\"" & cssCol & "\" stroke-width=\"1.25\" stroke-linecap=\"round\"/></svg>"

proc buildFontCssStyle(slot: WebFontSlot; fg, bg: Color): string =
  ## `letter-spacing: calc(charWidth - 1ch)` is what makes a monospace cell
  ## land exactly on `charWidth` pixels: every glyph already advances by `1ch`,
  ## so the correction is the same for all of them and the row adds up.
  ## For a proportional font that is false -- each glyph has its own advance,
  ## so a constant correction makes the row drift off the measured width and
  ## the text slides over its neighbours. There the advance *is* the layout,
  ## so leave letter-spacing alone and use the width `measureText` returned.
  let spacing = if slot.isMonospace:
      "letter-spacing:calc(" & $slot.charWidth & "px - 1ch);"
    else:
      "letter-spacing:normal;"
  result = "font-family:" & slot.family & ";font-size:" & $slot.size &
    "px;line-height:" & $slot.metrics.lineHeight & "px;height:" &
    $slot.metrics.lineHeight & "px;font-variant-ligatures:none;" & spacing &
    "color:" & toCssRgba(fg) & ";"
  if FontStyle.bold in slot.style:
    result.add "font-weight:700;"
  if FontStyle.italics in slot.style:
    result.add "font-style:italic;"
  if bg.a > 0'u8:
    result.add "background-color:" & toCssRgba(bg) & ";"

proc htmlDrawText(f: Font; x, y: int; text: string; fg, bg: Color): TextExtent =
  result = webMeasureText(f, text)
  if text.len == 0 or result.w <= 0:
    return
  syncClipDiv()
  inc htmlCurrentNodeCount
  let slot = webGetFontSlot(f)
  htmlFrameBuffer.add "<span class=\"uir-text\" style=\"left:" & $x &
    "px;top:" & $y & "px;width:" & $result.w & "px;" & buildFontCssStyle(slot, fg, bg) & "\">" &
    htmlEscape(text) & "</span>"

proc htmlDrawMeasuredText(f: Font; x, y: int; text: string; fg, bg: Color;
                          size: TextExtent) =
  if text.len == 0 or size.w <= 0:
    return
  syncClipDiv()
  inc htmlCurrentNodeCount
  let slot = webGetFontSlot(f)
  htmlFrameBuffer.add "<span class=\"uir-text\" style=\"left:" & $x &
    "px;top:" & $y & "px;width:" & $size.w & "px;" &
    buildFontCssStyle(slot, fg, bg) & "\">" &
    htmlEscape(text) & "</span>"

proc htmlDrawImage(img: Image; src, dst: Rect) =
  let slot = webGetImageSlot(img)
  if not slot.active or slot.w <= 0 or slot.h <= 0 or dst.w <= 0 or dst.h <= 0:
    return
  let srcW = if src.w > 0: src.w else: slot.w
  let srcH = if src.h > 0: src.h else: slot.h
  let scaleX = float(dst.w) / float(max(1, srcW))
  let scaleY = float(dst.h) / float(max(1, srcH))
  let imgW = int(float(slot.w) * scaleX + 0.5)
  let imgH = int(float(slot.h) * scaleY + 0.5)
  let offsetX = -int(float(max(0, src.x)) * scaleX + 0.5)
  let offsetY = -int(float(max(0, src.y)) * scaleY + 0.5)

  syncClipDiv()
  inc htmlCurrentNodeCount
  htmlFrameBuffer.add "<div class=\"uir-img-crop\" style=\"left:" & $dst.x &
    "px;top:" & $dst.y & "px;width:" & $dst.w & "px;height:" & $dst.h &
    "px;overflow:hidden;\"><img class=\"uir-img\" src=\"" & slot.dataUri &
    "\" alt=\"\" style=\"position:absolute;left:" & $offsetX & "px;top:" &
    $offsetY & "px;width:" & $imgW & "px;height:" & $imgH & "px;\"/></div>"

proc htmlBlitRGBA(pixels: ptr UncheckedArray[uint32]; w, h: int; dst: Rect): bool =
  if pixels == nil or w <= 0 or h <= 0 or dst.w <= 0 or dst.h <= 0:
    return false
  let dataUri = encodeRgbaToPngDataUri(pixels, w, h)
  if dataUri.len == 0:
    return false
  # `dst` clips and does not scale, matching sdl3_driver/gtk4_driver semantics
  let cw = min(w, dst.w)
  let ch = min(h, dst.h)
  syncClipDiv()
  inc htmlCurrentNodeCount
  htmlFrameBuffer.add "<div class=\"uir-blit-clip\" style=\"left:" & $dst.x &
    "px;top:" & $dst.y & "px;width:" & $cw & "px;height:" & $ch &
    "px;overflow:hidden;\"><img class=\"uir-blit\" src=\"" & dataUri &
    "\" alt=\"\" style=\"position:absolute;left:0;top:0;width:" & $w &
    "px;height:" & $h & "px;image-rendering:pixelated;\"/></div>"
  result = true

proc htmlRefresh() =
  closeActiveClipDiv()
  inc webCore.totalFramesRendered
  webCore.domNodeCount = htmlCurrentNodeCount
  lastPublishedHtml = htmlFrameBuffer

  let metaAndDom = webCore.windowTitle & "|" &
                   $webCore.layout.width & "x" & $webCore.layout.height & "|" &
                   cursorToCss(webCore.currentCursor) & "|" &
                   webCore.clipboardText & "|" &
                   htmlFrameBuffer
  let h = fnv1a64(metaAndDom)
  if h != webCore.lastPayloadHash or webCore.frameId == 0:
    webCore.lastPayloadHash = h
    inc webCore.frameId
    when defined(js):
      let domCs = cstring(htmlFrameBuffer)
      let titleCs = cstring(webCore.windowTitle)
      let curCs = cstring(cursorToCss(webCore.currentCursor))
      let clipCs = cstring(webCore.clipboardText)
      let wVal = webCore.layout.width
      let hVal = webCore.layout.height
      let fId = webCore.frameId
      let nCnt = htmlCurrentNodeCount
      {.emit: """
      var vp = document.getElementById("uir-viewport");
      if (vp) {
        vp.style.width = `wVal` + "px";
        vp.style.height = `hVal` + "px";
        vp.style.cursor = `curCs`;
        vp.innerHTML = `domCs`;
      }
      var tEl = document.getElementById("uir-win-title");
      if (tEl) tEl.textContent = `titleCs`;
      var sEl = document.getElementById("uir-stat-size");
      if (sEl) sEl.textContent = `wVal` + "×" + `hVal`;
      var fEl = document.getElementById("uir-stat-frame");
      if (fEl) fEl.textContent = "frame: " + `fId`;
      var nEl = document.getElementById("uir-stat-nodes");
      if (nEl) nEl.textContent = "DOM nodes: " + `nCnt`;
      var cEl = document.getElementById("uir-stat-cursor");
      if (cEl) cEl.textContent = "cursor: " + `curCs`;
      var clEl = document.getElementById("uir-clipboard-input");
      if (clEl && document.activeElement !== clEl) clEl.value = `clipCs`;
      """.}
    else:
      let frameObj = %*{
        "frameId": webCore.frameId,
        "backend": "html",
        "title": webCore.windowTitle,
        "cursor": cursorToCss(webCore.currentCursor),
        "width": webCore.layout.width,
        "height": webCore.layout.height,
        "uiScale": webCore.layout.uiScale,
        "clipboard": webCore.clipboardText,
        "wantTextInput": webCore.wantTextInput,
        "domNodeCount": htmlCurrentNodeCount,
        "html": htmlFrameBuffer
      }
      webCore.lastFrameJson = $frameObj
      broadcastSseFrame()

  webPumpServer()
  resetHtmlFrameBuffer()

proc htmlShutdown() =
  resetHtmlFrameBuffer()
  webShutdownCommon()

proc initHtmlDriver*() =
  ## Initializes the Pure Vanilla HTML5 + CSS3 + JS (DOM) driver.
  ## Zero <canvas>, zero WASM, 100% Nim (--mm:arc).
  initWebCore(wbkHtml, HtmlDriverPageTemplate)
  resetHtmlFrameBuffer()

  windowRelays = WindowRelays(
    createWindow: htmlCreateWindow,
    getWindowLayout: webGetWindowLayout,
    refresh: htmlRefresh,
    saveState: htmlSaveState,
    restoreState: htmlRestoreState,
    setClipRect: htmlSetClipRect,
    setCursor: webSetCursor,
    setWindowTitle: webSetWindowTitle
  )
  fontRelays = FontRelays(
    openFont: webOpenFont,
    closeFont: webCloseFont,
    getFontMetrics: webGetFontMetrics,
    measureText: webMeasureText,
    drawText: htmlDrawText,
    drawMeasuredText: htmlDrawMeasuredText
  )
  drawRelays = DrawRelays(
    fillRect: htmlFillRect,
    drawLine: htmlDrawLine,
    drawPoint: htmlDrawPoint,
    loadImage: webLoadImage,
    freeImage: webFreeImage,
    drawImage: htmlDrawImage,
    imageSize: webImageSize,
    blitRGBA: htmlBlitRGBA
  )
  inputRelays = InputRelays(
    pollEvent: webPollEvent,
    waitEvent: webWaitEvent,
    getTicks: webGetTicks,
    sleep: webSleep,
    shutdown: htmlShutdown
  )
  clipboardRelays = ClipboardRelays(
    getText: webGetClipboardText,
    putText: webPutClipboardText
  )
