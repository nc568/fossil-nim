# Separate HTML5 <canvas> 2D backend driver for uirelays.
# Uses HTML5 Canvas 2D Context API (`getContext("2d")`), strictly NO WebAssembly (WASM).
# Written 100% in Nim (--mm:arc).
#
# Build:
#   nim c --mm:arc -d:canvas examples/hello.nim

import std/json
import ../coords, ../input, ../screen
import ./web_common

var
  canvasCmdList: seq[JsonNode]
  canvasCurrentCmdCount: int
  lastPublishedCanvasJson*: string

const CanvasDriverPageTemplate = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>UIRelays — HTML5 Canvas 2D Backend</title>
<style>
  :root {
    --bg-shell: #11111b;
    --bg-bar: #181825;
    --fg-bar: #cdd6f4;
    --accent: #cba6f7;
    --badge-bg: #2a2139;
    --badge-fg: #cba6f7;
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
    border: 1px solid #9368d9;
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
  #uir-canvas {
    display: block;
    background: #1e1e2e;
    box-shadow: 0 10px 30px rgba(0, 0, 0, 0.55);
    outline: 1px solid var(--border);
  }
  #uir-canvas:focus {
    outline: 1px solid var(--accent);
  }
</style>
</head>
<body>
<div id="uir-shell">
  <div id="uir-hud">
    <div class="uir-hud-left">
      <span class="uir-badge" id="uir-backend-badge">CANVAS 2D BACKEND (HTML5 &lt;canvas&gt; · No WASM)</span>
      <strong id="uir-win-title">UIRelays Window</strong>
      <span class="uir-stat" id="uir-stat-size">800×600</span>
      <span class="uir-stat" id="uir-stat-frame">frame: 0</span>
      <span class="uir-stat" id="uir-stat-cmds">2D cmds: 0</span>
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
    <canvas id="uir-canvas" width="800" height="600" tabindex="0" role="application" aria-label="UIRelays HTML5 Canvas 2D Viewport"></canvas>
  </div>
</div>
<script>
(function() {
  "use strict";
  const canvas = document.getElementById("uir-canvas");
  const ctx = canvas.getContext("2d");
  const titleEl = document.getElementById("uir-win-title");
  const sizeEl = document.getElementById("uir-stat-size");
  const frameEl = document.getElementById("uir-stat-frame");
  const cmdsEl = document.getElementById("uir-stat-cmds");
  const cursorEl = document.getElementById("uir-stat-cursor");
  const clipInput = document.getElementById("uir-clipboard-input");

  let lastFrameId = -1;
  let lastCommands = [];
  let pendingEvents = [];
  let flushTimer = null;
  const imgCache = new Map();
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

  function getCachedImage(src) {
    if (imgCache.has(src)) {
      return imgCache.get(src);
    }
    const img = new Image();
    imgCache.set(src, img);
    img.onload = function() {
      renderCommands(lastCommands);
    };
    img.src = src;
    return img;
  }

  function renderCommands(cmds) {
    if (!Array.isArray(cmds)) return;
    // A frame starts empty: an app that does not paint a background must not
    // see the previous frame still lying around.
    ctx.save();
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    ctx.restore();
    ctx.save();
    let clipActive = false;
    const stateStack = [];

    for (let i = 0; i < cmds.length; i++) {
      const cmd = cmds[i];
      switch (cmd.op) {
        case "rect":
          ctx.fillStyle = cmd.c;
          ctx.fillRect(cmd.x, cmd.y, cmd.w, cmd.h);
          break;
        case "point":
          ctx.fillStyle = cmd.c;
          ctx.fillRect(cmd.x, cmd.y, 1, 1);
          break;
        case "line":
          if (cmd.y1 === cmd.y2) {
            const lx = Math.min(cmd.x1, cmd.x2);
            const lw = Math.max(1, Math.abs(cmd.x2 - cmd.x1) + 1);
            ctx.fillStyle = cmd.c;
            ctx.fillRect(lx, cmd.y1, lw, 1);
          } else if (cmd.x1 === cmd.x2) {
            const ly = Math.min(cmd.y1, cmd.y2);
            const lh = Math.max(1, Math.abs(cmd.y2 - cmd.y1) + 1);
            ctx.fillStyle = cmd.c;
            ctx.fillRect(cmd.x1, ly, 1, lh);
          } else {
            ctx.strokeStyle = cmd.c;
            ctx.lineWidth = 1.25;
            ctx.beginPath();
            ctx.moveTo(cmd.x1 + 0.5, cmd.y1 + 0.5);
            ctx.lineTo(cmd.x2 + 0.5, cmd.y2 + 0.5);
            ctx.stroke();
          }
          break;
        case "text":
          if (cmd.bg) {
            ctx.fillStyle = cmd.bg;
            ctx.fillRect(cmd.x, cmd.y, cmd.w, cmd.h);
          }
          ctx.font = cmd.font;
          if ("letterSpacing" in ctx) {
            ctx.letterSpacing = "0px";
            if (cmd.cw > 0) {
              const mAdv = ctx.measureText("M").width;
              ctx.letterSpacing = (cmd.cw - mAdv) + "px";
            }
          }
          ctx.fillStyle = cmd.fg;
          ctx.textBaseline = "alphabetic";
          ctx.fillText(cmd.t, cmd.x, cmd.y + (cmd.ascent || 12));
          if (cmd.underline) {
            ctx.fillRect(cmd.x, cmd.y + (cmd.ascent || 12) + 2, cmd.w, 1);
          }
          if (cmd.strike) {
            ctx.fillRect(cmd.x, cmd.y + Math.floor(cmd.h / 2), cmd.w, 1);
          }
          break;
        case "save":
          stateStack.push(clipActive ? { x: clipActive.x, y: clipActive.y, w: clipActive.w, h: clipActive.h } : null);
          break;
        case "restore":
          clipActive = stateStack.length > 0 ? stateStack.pop() : null;
          ctx.restore();
          ctx.save();
          if (clipActive) {
            ctx.beginPath();
            ctx.rect(clipActive.x, clipActive.y, clipActive.w, clipActive.h);
            ctx.clip();
          }
          break;
        case "clip":
          clipActive = { x: cmd.x, y: cmd.y, w: cmd.w, h: cmd.h };
          ctx.restore();
          ctx.save();
          ctx.beginPath();
          ctx.rect(cmd.x, cmd.y, cmd.w, cmd.h);
          ctx.clip();
          break;
        case "img": {
          const im = getCachedImage(cmd.src);
          if (im && im.complete && im.naturalWidth > 0) {
            ctx.drawImage(im, cmd.sx, cmd.sy, cmd.sw, cmd.sh, cmd.dx, cmd.dy, cmd.dw, cmd.dh);
          }
          break;
        }
        case "blit": {
          const im = getCachedImage(cmd.src);
          if (im && im.complete && im.naturalWidth > 0) {
            ctx.drawImage(im, 0, 0, cmd.dw, cmd.dh, cmd.dx, cmd.dy, cmd.dw, cmd.dh);
          }
          break;
        }
      }
    }
    ctx.restore();
  }

  function applyFrame(data) {
    if (!data || typeof data.frameId !== "number") return;
    if (data.frameId === lastFrameId) return;
    lastFrameId = data.frameId;

    if (typeof data.width === "number" && typeof data.height === "number") {
      // CSS pixels for layout, device pixels for the backing store: on a
      // retina display a 1:1 backing store is stretched by the browser and
      // every glyph and line comes out blurred.
      var dpr = (window.devicePixelRatio || 1);
      if (!(dpr > 0)) dpr = 1;
      var bw = Math.max(1, Math.round(data.width * dpr));
      var bh = Math.max(1, Math.round(data.height * dpr));
      if (canvas.width !== bw || canvas.height !== bh) {
        canvas.width = bw;
        canvas.height = bh; // resets the context, so set the transform below
      }
      canvas.style.width = data.width + "px";
      canvas.style.height = data.height + "px";
      if (ctx.setTransform) ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      sizeEl.textContent = data.width + "×" + data.height;
    }
    if (typeof data.title === "string") {
      document.title = data.title + " [HTML5 Canvas 2D]";
      titleEl.textContent = data.title;
    }
    if (typeof data.cursor === "string") {
      canvas.style.cursor = data.cursor;
      cursorEl.textContent = "cursor: " + data.cursor;
    }
    if (typeof data.clipboard === "string" && document.activeElement !== clipInput) {
      clipInput.value = data.clipboard;
    }
    if (Array.isArray(data.commands)) {
      lastCommands = data.commands;
      renderCommands(lastCommands);
    }
    frameEl.textContent = "frame: " + data.frameId;
    cmdsEl.textContent = "2D cmds: " + (data.canvasCommandCount || lastCommands.length);
  }

  function relCoords(e) {
    const r = canvas.getBoundingClientRect();
    return {
      x: Math.round(e.clientX - r.left),
      y: Math.round(e.clientY - r.top)
    };
  }

  canvas.addEventListener("mousedown", function(e) {
    canvas.focus();
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

  canvas.addEventListener("mouseup", function(e) {
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

  canvas.addEventListener("mousemove", function(e) {
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

  canvas.addEventListener("contextmenu", function(e) {
    e.preventDefault();
  });

  canvas.addEventListener("wheel", function(e) {
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

  canvas.addEventListener("focus", function() {
    queueEvent({ type: "focus" });
  });
  canvas.addEventListener("blur", function() {
    queueEvent({ type: "blur" });
  });

  document.getElementById("uir-btn-clip-sync").addEventListener("click", function() {
    queueEvent({ type: "clipboard", text: clipInput.value });
    flushEvents();
    canvas.focus();
  });

  document.getElementById("uir-btn-resize-800").addEventListener("click", function() {
    window.__uirFixedSize = true;
    queueEvent({ type: "resize", width: 800, height: 600, uiScale: 100 });
    flushEvents();
    canvas.focus();
  });

  document.getElementById("uir-btn-resize-960").addEventListener("click", function() {
    window.__uirFixedSize = true;
    queueEvent({ type: "resize", width: 960, height: 640, uiScale: 100 });
    flushEvents();
    canvas.focus();
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
  canvas.focus();

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
      const r = canvas.getBoundingClientRect();
      const ev = new MouseEvent(type, {
        bubbles: true,
        cancelable: true,
        clientX: r.left + rx,
        clientY: r.top + ry,
        button: button || 0,
        detail: clicks || 1
      });
      canvas.dispatchEvent(ev);
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
      canvas.dispatchEvent(ev);
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
      let maxCmdsSeen = lastCommands.length;

      // 1. Click HUD buttons
      clipInput.value = "MonkeyClip_Canvas";
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
          maxCmdsSeen = Math.max(maxCmdsSeen, lastCommands.length);
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
      let seed = 4242;
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
      maxCmdsSeen = Math.max(maxCmdsSeen, lastCommands.length);

      // Sample real rendered pixels from HTML5 <canvas> 2D context
      const colorSet = new Set();
      let nonTransparentSamples = 0;
      try {
        const imgData = ctx.getImageData(0, 0, canvas.width, canvas.height).data;
        const stepX = 11;
        const stepY = 11;
        for (let y = 2; y < canvas.height; y += stepY) {
          for (let x = 2; x < canvas.width; x += stepX) {
            const idx = (y * canvas.width + x) * 4;
            const r = imgData[idx];
            const g = imgData[idx + 1];
            const b = imgData[idx + 2];
            const a = imgData[idx + 3];
            if (a > 0) {
              nonTransparentSamples++;
              colorSet.add(r + "," + g + "," + b);
            }
          }
        }
      } catch (err) {
        monkeyErrors.push("getImageData failed: " + String(err));
      }

      const report = {
        ready: true,
        backend: "canvas",
        frameId: lastFrameId,
        clicksDispatched: clicksDispatched,
        keysDispatched: keysDispatched,
        wheelDispatched: wheelDispatched,
        hudButtonsClicked: hudButtonsClicked,
        commandsNow: lastCommands.length,
        maxCommandsSeen: maxCmdsSeen,
        canvasWidth: canvas.width,
        canvasHeight: canvas.height,
        nonTransparentSamples: nonTransparentSamples,
        distinctCanvasColors: colorSet.size,
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
# HTML5 Canvas 2D Drawing Relays (Zero WASM)
# ---------------------------------------------------------------------------

proc resetCanvasCommands() =
  canvasCmdList.setLen(0)
  canvasCurrentCmdCount = 0

proc canvasCreateWindow(layout: var ScreenLayout; icon: pointer; iconLen: int) =
  webCreateWindowCommon(layout, icon, iconLen)
  resetCanvasCommands()

proc canvasSaveState() =
  webSaveState()
  inc canvasCurrentCmdCount
  canvasCmdList.add(%*{"op": "save"})

proc canvasRestoreState() =
  webRestoreState()
  inc canvasCurrentCmdCount
  canvasCmdList.add(%*{"op": "restore"})

proc canvasSetClipRect(r: Rect) =
  webSetClipRect(r)
  inc canvasCurrentCmdCount
  canvasCmdList.add(%*{
    "op": "clip",
    "x": r.x,
    "y": r.y,
    "w": r.w,
    "h": r.h
  })

proc canvasFillRect(r: Rect; color: Color) =
  if r.w <= 0 or r.h <= 0 or color.a == 0'u8:
    return
  inc canvasCurrentCmdCount
  canvasCmdList.add(%*{
    "op": "rect",
    "x": r.x,
    "y": r.y,
    "w": r.w,
    "h": r.h,
    "c": toCssRgba(color)
  })

proc canvasDrawPoint(x, y: int; color: Color) =
  if color.a == 0'u8:
    return
  inc canvasCurrentCmdCount
  canvasCmdList.add(%*{
    "op": "point",
    "x": x,
    "y": y,
    "c": toCssRgba(color)
  })

proc canvasDrawLine(x1, y1, x2, y2: int; color: Color) =
  if color.a == 0'u8:
    return
  inc canvasCurrentCmdCount
  canvasCmdList.add(%*{
    "op": "line",
    "x1": x1,
    "y1": y1,
    "x2": x2,
    "y2": y2,
    "c": toCssRgba(color)
  })

proc buildCanvasFontShorthand(slot: WebFontSlot): string =
  result = ""
  if FontStyle.italics in slot.style:
    result.add "italic "
  if FontStyle.bold in slot.style:
    result.add "bold "
  result.add $slot.size & "px " & slot.family

proc canvasDrawText(f: Font; x, y: int; text: string; fg, bg: Color): TextExtent =
  result = webMeasureText(f, text)
  if text.len == 0 or result.w <= 0:
    return
  inc canvasCurrentCmdCount
  let slot = webGetFontSlot(f)
  canvasCmdList.add(%*{
    "op": "text",
    "x": x,
    "y": y,
    "w": result.w,
    "h": result.h,
    "cw": (if slot.isMonospace: slot.charWidth else: 0),
    "t": text,
    "font": buildCanvasFontShorthand(slot),
    "ascent": slot.metrics.ascent,
    "fg": toCssRgba(fg),
    "bg": (if bg.a > 0'u8: toCssRgba(bg) else: "")
  })

proc canvasDrawMeasuredText(f: Font; x, y: int; text: string; fg, bg: Color;
                            size: TextExtent) =
  if text.len == 0 or size.w <= 0:
    return
  inc canvasCurrentCmdCount
  let slot = webGetFontSlot(f)
  canvasCmdList.add(%*{
    "op": "text",
    "x": x,
    "y": y,
    "w": size.w,
    "h": size.h,
    "cw": (if slot.isMonospace: slot.charWidth else: 0),
    "t": text,
    "font": buildCanvasFontShorthand(slot),
    "ascent": slot.metrics.ascent,
    "fg": toCssRgba(fg),
    "bg": (if bg.a > 0'u8: toCssRgba(bg) else: "")
  })

proc canvasDrawImage(img: Image; src, dst: Rect) =
  let slot = webGetImageSlot(img)
  if not slot.active or slot.w <= 0 or slot.h <= 0 or dst.w <= 0 or dst.h <= 0:
    return
  let sx = max(0, src.x)
  let sy = max(0, src.y)
  let sw = if src.w > 0: src.w else: slot.w
  let sh = if src.h > 0: src.h else: slot.h
  inc canvasCurrentCmdCount
  canvasCmdList.add(%*{
    "op": "img",
    "src": slot.dataUri,
    "sx": sx,
    "sy": sy,
    "sw": sw,
    "sh": sh,
    "dx": dst.x,
    "dy": dst.y,
    "dw": dst.w,
    "dh": dst.h
  })

proc canvasBlitRGBA(pixels: ptr UncheckedArray[uint32]; w, h: int; dst: Rect): bool =
  if pixels == nil or w <= 0 or h <= 0 or dst.w <= 0 or dst.h <= 0:
    return false
  let dataUri = encodeRgbaToPngDataUri(pixels, w, h)
  if dataUri.len == 0:
    return false
  let cw = min(w, dst.w)
  let ch = min(h, dst.h)
  inc canvasCurrentCmdCount
  canvasCmdList.add(%*{
    "op": "blit",
    "src": dataUri,
    "w": w,
    "h": h,
    "dx": dst.x,
    "dy": dst.y,
    "dw": cw,
    "dh": ch
  })
  result = true

# ---------------------------------------------------------------------------
# Standalone (`nim js`) rendering
# ---------------------------------------------------------------------------
#
# `nim js -d:canvas` has no server behind it, so `broadcastSseFrame` sends the
# commands nowhere and the page stays blank while the app looks perfectly
# alive. The commands are executed right here instead: the same JSON stream
# the server would have sent is played onto the page's <canvas>, in Nim, with
# no eval and no CSP exception.

when defined(js):
  type
    JsElement {.importc.} = ref object ## a DOM element, reached only through `importjs`
    JsCtx {.importc.} = ref object     ## CanvasRenderingContext2D
    JsImage {.importc.} = ref object   ## HTMLImageElement

  proc jsGetElementById(id: cstring): JsElement {.importjs: "document.getElementById(#)".}
  proc jsGetContext(el: JsElement; kind: cstring): JsCtx {.importjs: "#.getContext(#)".}
  proc jsElementWidth(el: JsElement): int {.importjs: "#.width".}
  proc jsSetElementWidth(el: JsElement; v: int) {.importjs: "#.width = #".}
  proc jsElementHeight(el: JsElement): int {.importjs: "#.height".}
  proc jsSetElementHeight(el: JsElement; v: int) {.importjs: "#.height = #".}
  proc jsStyleSet(el: JsElement; prop, value: cstring) {.importjs: "#.style[#] = #".}
  proc jsDevicePixelRatio(): float {.importjs: "(((window.devicePixelRatio || 1) > 0) ? (window.devicePixelRatio || 1) : 1)".}
  proc jsConsoleError(msg: cstring) {.importjs: "((typeof console !== \"undefined\" && console.error) ? console.error(#) : undefined)".}

  proc ctxSave(ctx: JsCtx) {.importjs: "#.save()".}
  proc ctxRestore(ctx: JsCtx) {.importjs: "#.restore()".}
  proc ctxSetTransform(ctx: JsCtx; a, b, c, d, e, f: float) {.importjs: "#.setTransform(#,#,#,#,#,#)".}
  proc ctxClearRect(ctx: JsCtx; x, y, w, h: float) {.importjs: "#.clearRect(#,#,#,#)".}
  proc ctxFillRect(ctx: JsCtx; x, y, w, h: float) {.importjs: "#.fillRect(#,#,#,#)".}
  proc ctxFillText(ctx: JsCtx; t: cstring; x, y: float) {.importjs: "#.fillText(#,#,#)".}
  proc ctxMeasureText(ctx: JsCtx; t: cstring): float {.importjs: "#.measureText(#).width".}
  proc ctxBeginPath(ctx: JsCtx) {.importjs: "#.beginPath()".}
  proc ctxMoveTo(ctx: JsCtx; x, y: float) {.importjs: "#.moveTo(#,#)".}
  proc ctxLineTo(ctx: JsCtx; x, y: float) {.importjs: "#.lineTo(#,#)".}
  proc ctxStroke(ctx: JsCtx) {.importjs: "#.stroke()".}
  proc ctxRect(ctx: JsCtx; x, y, w, h: float) {.importjs: "#.rect(#,#,#,#)".}
  proc ctxClip(ctx: JsCtx) {.importjs: "#.clip()".}
  proc ctxDrawImage(ctx: JsCtx; img: JsImage;
                    sx, sy, sw, sh, dx, dy, dw, dh: float) {.importjs: "#.drawImage(#,#,#,#,#,#,#,#,#)".}
  proc ctxSetFillStyle(ctx: JsCtx; v: cstring) {.importjs: "#.fillStyle = #".}
  proc ctxSetStrokeStyle(ctx: JsCtx; v: cstring) {.importjs: "#.strokeStyle = #".}
  proc ctxSetFont(ctx: JsCtx; v: cstring) {.importjs: "#.font = #".}
  proc ctxSetTextBaseline(ctx: JsCtx; v: cstring) {.importjs: "#.textBaseline = #".}
  proc ctxSetLineWidth(ctx: JsCtx; v: float) {.importjs: "#.lineWidth = #".}
  proc ctxSetLetterSpacing(ctx: JsCtx; v: cstring) {.importjs: "#.letterSpacing = #".}
  proc ctxHasLetterSpacing(ctx: JsCtx): bool {.importjs: "(\"letterSpacing\" in #)".}

  proc newJsImage(): JsImage {.importjs: "new Image()".}
  proc jsImageComplete(img: JsImage): bool {.importjs: "#.complete".}
  proc jsImageNaturalWidth(img: JsImage): int {.importjs: "#.naturalWidth".}
  proc jsImageSetSrc(img: JsImage; src: cstring) {.importjs: "#.src = #".}

  var
    jsCanvasElement: JsElement
    jsCanvasContext: JsCtx
    jsImageCache: seq[(string, JsImage)]
    jsCanvasMissingWarned: bool

  proc jsCachedImage(src: string): JsImage =
    for kv in jsImageCache:
      if kv[0] == src:
        return kv[1]
    let img = newJsImage()
    jsImageCache.add (src, img)
    jsImageSetSrc(img, cstring(src))
    result = img

  type JsClipState = object
    active: bool
    x, y, w, h: float

  proc jf(node: JsonNode; key: string; def = 0.0): float =
    let v = node{key}
    if v.isNil: def else: v.getFloat(def)

  proc jsApplyClip(ctx: JsCtx; clip: JsClipState) =
    ctxBeginPath(ctx)
    ctxRect(ctx, clip.x, clip.y, clip.w, clip.h)
    ctxClip(ctx)

  proc jsExecCanvasCommands(ctx: JsCtx; cmds: seq[JsonNode]) =
    ctxSave(ctx)
    var clip = JsClipState()
    var stack: seq[JsClipState] = @[]
    for cmd in cmds:
      if cmd.kind != JObject:
        continue
      case cmd{"op"}.getStr("")
      of "rect":
        ctxSetFillStyle(ctx, cstring(cmd{"c"}.getStr("")))
        ctxFillRect(ctx, jf(cmd, "x"), jf(cmd, "y"), jf(cmd, "w"), jf(cmd, "h"))
      of "point":
        ctxSetFillStyle(ctx, cstring(cmd{"c"}.getStr("")))
        ctxFillRect(ctx, jf(cmd, "x"), jf(cmd, "y"), 1.0, 1.0)
      of "line":
        let x1 = jf(cmd, "x1")
        let y1 = jf(cmd, "y1")
        let x2 = jf(cmd, "x2")
        let y2 = jf(cmd, "y2")
        let css = cstring(cmd{"c"}.getStr(""))
        if y1 == y2:
          ctxSetFillStyle(ctx, css)
          ctxFillRect(ctx, min(x1, x2), y1, max(1.0, abs(x2 - x1) + 1.0), 1.0)
        elif x1 == x2:
          ctxSetFillStyle(ctx, css)
          ctxFillRect(ctx, x1, min(y1, y2), 1.0, max(1.0, abs(y2 - y1) + 1.0))
        else:
          ctxSetStrokeStyle(ctx, css)
          ctxSetLineWidth(ctx, 1.25)
          ctxBeginPath(ctx)
          ctxMoveTo(ctx, x1 + 0.5, y1 + 0.5)
          ctxLineTo(ctx, x2 + 0.5, y2 + 0.5)
          ctxStroke(ctx)
      of "text":
        let bg = cmd{"bg"}.getStr("")
        if bg.len > 0:
          ctxSetFillStyle(ctx, cstring(bg))
          ctxFillRect(ctx, jf(cmd, "x"), jf(cmd, "y"), jf(cmd, "w"), jf(cmd, "h"))
        ctxSetFont(ctx, cstring(cmd{"font"}.getStr("")))
        let cw = jf(cmd, "cw")
        if ctxHasLetterSpacing(ctx):
          ctxSetLetterSpacing(ctx, cstring("0px"))
          if cw > 0.0:
            let mAdv = ctxMeasureText(ctx, cstring("M"))
            ctxSetLetterSpacing(ctx, cstring($(cw - mAdv) & "px"))
        ctxSetTextBaseline(ctx, cstring("alphabetic"))
        ctxSetFillStyle(ctx, cstring(cmd{"fg"}.getStr("")))
        let ascent = jf(cmd, "ascent", 12.0)
        ctxFillText(ctx, cstring(cmd{"t"}.getStr("")), jf(cmd, "x"), jf(cmd, "y") + ascent)
        if cmd{"underline"}.getBool(false):
          ctxFillRect(ctx, jf(cmd, "x"), jf(cmd, "y") + ascent + 2.0, jf(cmd, "w"), 1.0)
        if cmd{"strike"}.getBool(false):
          ctxFillRect(ctx, jf(cmd, "x"),
                      jf(cmd, "y") + float(int(jf(cmd, "h")) div 2),
                      jf(cmd, "w"), 1.0)
      of "save":
        stack.add clip
      of "restore":
        if stack.len > 0:
          clip = stack[^1]
          stack.setLen stack.len - 1
        else:
          clip = JsClipState()
        ctxRestore(ctx)
        ctxSave(ctx)
        if clip.active:
          jsApplyClip(ctx, clip)
      of "clip":
        clip = JsClipState(active: true, x: jf(cmd, "x"), y: jf(cmd, "y"),
                           w: jf(cmd, "w"), h: jf(cmd, "h"))
        ctxRestore(ctx)
        ctxSave(ctx)
        jsApplyClip(ctx, clip)
      of "img":
        let src = cmd{"src"}.getStr("")
        if src.len > 0:
          let im = jsCachedImage(src)
          if jsImageComplete(im) and jsImageNaturalWidth(im) > 0:
            ctxDrawImage(ctx, im, jf(cmd, "sx"), jf(cmd, "sy"), jf(cmd, "sw"),
                         jf(cmd, "sh"), jf(cmd, "dx"), jf(cmd, "dy"),
                         jf(cmd, "dw"), jf(cmd, "dh"))
      of "blit":
        let src = cmd{"src"}.getStr("")
        if src.len > 0:
          let im = jsCachedImage(src)
          if jsImageComplete(im) and jsImageNaturalWidth(im) > 0:
            ctxDrawImage(ctx, im, 0.0, 0.0, jf(cmd, "dw"), jf(cmd, "dh"),
                         jf(cmd, "dx"), jf(cmd, "dy"), jf(cmd, "dw"), jf(cmd, "dh"))
      else:
        discard
    ctxRestore(ctx)

  proc jsRenderCanvasFrame(cmds: seq[JsonNode]; w, h: int) =
    ## Plays one frame onto the page's `<canvas id="uir-canvas">`. The backing
    ## store is sized in device pixels (retina) while drawing stays in CSS
    ## pixels, exactly like the server-side page template.
    if jsCanvasElement.isNil:
      jsCanvasElement = jsGetElementById(cstring("uir-canvas"))
    if jsCanvasElement.isNil:
      if not jsCanvasMissingWarned:
        jsCanvasMissingWarned = true
        jsConsoleError(cstring("[uirelays] standalone -d:canvas needs <canvas id=\"uir-canvas\"> in the page; nothing is drawn."))
      return
    if jsCanvasContext.isNil:
      jsCanvasContext = jsGetContext(jsCanvasElement, cstring("2d"))
    if jsCanvasContext.isNil:
      return
    if w <= 0 or h <= 0:
      return
    let dpr = jsDevicePixelRatio()
    let bw = max(1, int(float(w) * dpr + 0.5))
    let bh = max(1, int(float(h) * dpr + 0.5))
    if jsElementWidth(jsCanvasElement) != bw:
      jsSetElementWidth(jsCanvasElement, bw)
    if jsElementHeight(jsCanvasElement) != bh:
      jsSetElementHeight(jsCanvasElement, bh)
    jsStyleSet(jsCanvasElement, cstring("width"), cstring($w & "px"))
    jsStyleSet(jsCanvasElement, cstring("height"), cstring($h & "px"))
    ctxSetTransform(jsCanvasContext, dpr, 0.0, 0.0, dpr, 0.0, 0.0)
    ctxClearRect(jsCanvasContext, 0.0, 0.0, float(w), float(h))
    jsExecCanvasCommands(jsCanvasContext, cmds)

proc canvasRefresh() =
  inc webCore.totalFramesRendered
  webCore.canvasCommandCount = canvasCurrentCmdCount

  var cmdsNode = newJArray()
  for cmd in canvasCmdList:
    cmdsNode.add cmd
  let cmdsStr = $cmdsNode
  lastPublishedCanvasJson = cmdsStr

  let metaAndCmds = webCore.windowTitle & "|" &
                    $webCore.layout.width & "x" & $webCore.layout.height & "|" &
                    cursorToCss(webCore.currentCursor) & "|" &
                    webCore.clipboardText & "|" &
                    cmdsStr
  when defined(js):
    # No server in a `nim js` build: play the frame onto the page instead of
    # broadcasting it into the void.
    jsRenderCanvasFrame(canvasCmdList, webCore.layout.width, webCore.layout.height)

  let h = fnv1a64(metaAndCmds)
  if h != webCore.lastPayloadHash or webCore.frameId == 0:
    webCore.lastPayloadHash = h
    inc webCore.frameId
    let frameObj = %*{
      "frameId": webCore.frameId,
      "backend": "canvas",
      "title": webCore.windowTitle,
      "cursor": cursorToCss(webCore.currentCursor),
      "width": webCore.layout.width,
      "height": webCore.layout.height,
      "uiScale": webCore.layout.uiScale,
      "clipboard": webCore.clipboardText,
      "wantTextInput": webCore.wantTextInput,
      "canvasCommandCount": canvasCurrentCmdCount,
      "commands": cmdsNode
    }
    webCore.lastFrameJson = $frameObj
    broadcastSseFrame()

  webPumpServer()
  resetCanvasCommands()

proc canvasShutdown() =
  resetCanvasCommands()
  webShutdownCommon()

proc initCanvasDriver*() =
  ## Initializes the separate HTML5 <canvas> 2D backend driver.
  ## Zero WASM, 100% Nim (--mm:arc).
  initWebCore(wbkCanvas, CanvasDriverPageTemplate)
  resetCanvasCommands()

  windowRelays = WindowRelays(
    createWindow: canvasCreateWindow,
    getWindowLayout: webGetWindowLayout,
    refresh: canvasRefresh,
    saveState: canvasSaveState,
    restoreState: canvasRestoreState,
    setClipRect: canvasSetClipRect,
    setCursor: webSetCursor,
    setWindowTitle: webSetWindowTitle
  )
  fontRelays = FontRelays(
    openFont: webOpenFont,
    closeFont: webCloseFont,
    getFontMetrics: webGetFontMetrics,
    measureText: webMeasureText,
    drawText: canvasDrawText,
    drawMeasuredText: canvasDrawMeasuredText
  )
  drawRelays = DrawRelays(
    fillRect: canvasFillRect,
    drawLine: canvasDrawLine,
    drawPoint: canvasDrawPoint,
    loadImage: webLoadImage,
    freeImage: webFreeImage,
    drawImage: canvasDrawImage,
    imageSize: webImageSize,
    blitRGBA: canvasBlitRGBA
  )
  inputRelays = InputRelays(
    pollEvent: webPollEvent,
    waitEvent: webWaitEvent,
    getTicks: webGetTicks,
    sleep: webSleep,
    shutdown: canvasShutdown
  )
  clipboardRelays = ClipboardRelays(
    getText: webGetClipboardText,
    putText: webPutClipboardText
  )
