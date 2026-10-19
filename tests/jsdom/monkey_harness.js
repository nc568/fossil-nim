/*
 * monkey_harness.js -- headless DOM monkey test for the UIRelays standalone
 * HTML backend (`nim js -d:html`, exported with tools/export_interactive_html.nim).
 *
 * Runs the exported bundle in jsdom -- no browser binary, no network -- and
 * throws random input at it while checking invariants after every step.
 *
 * jsdom has no layout engine, so the harness synthesises one: every drawing
 * primitive the backend emits is an absolutely positioned element with inline
 * `left/top/width/height` in pixels, which is enough to give every element a
 * real box. That makes hit-testing, `getBoundingClientRect()` and
 * "does this text run off the edge of the window" all answerable.
 *
 * Usage:
 *   node monkey_harness.js <bundle.html> [options]
 *
 * Options:
 *   --steps=N           monkey steps per app (default 120)
 *   --apps=a,b,c        only these app ids (default: all found in the bundle)
 *   --width=N           stage width in CSS pixels (default 1024)
 *   --height=N          stage height in CSS pixels (default 700)
 *   --seed=N            PRNG seed (default 12345)
 *   --dpr=N             window.devicePixelRatio (default 2, exercises retina paths)
 *   --json              print only the final JSON report
 *   --quiet             do not print progress
 */

"use strict";

const fs = require("fs");
const path = require("path");
const { JSDOM, VirtualConsole } = require("jsdom");

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

function parseArgs(argv) {
  const opts = {
    file: null, steps: 120, apps: null, width: 1024, height: 700,
    seed: 12345, dpr: 2, json: false, quiet: false, debug: false
  };
  for (const a of argv.slice(2)) {
    if (a.startsWith("--")) {
      const eq = a.indexOf("=");
      const key = (eq < 0 ? a.slice(2) : a.slice(2, eq)).replace(/-/g, "_");
      const val = eq < 0 ? "true" : a.slice(eq + 1);
      if (key === "steps" || key === "width" || key === "height" || key === "seed") {
        opts[key] = parseInt(val, 10);
      } else if (key === "dpr") {
        opts[key] = parseFloat(val);
      } else if (key === "apps") {
        opts[key] = val.split(",").map((s) => s.trim()).filter((s) => s.length > 0);
      } else if (key in opts) {
        opts[key] = val === "true" ? true : (val === "false" ? false : val);
      }
    } else if (opts.file === null) {
      opts.file = a;
    }
  }
  return opts;
}

// Deterministic PRNG (mulberry32) so a failure can be replayed from its seed.
function makeRandom(seed) {
  let a = seed >>> 0;
  return function () {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ---------------------------------------------------------------------------
// Synthesised layout
// ---------------------------------------------------------------------------

function installLayout(window, opts) {
  // Mutable so the monkey can resize: every reader below goes through it.
  const stage = { w: opts.width, h: opts.height };
  window.__uirStage = stage;

  function stylePx(el, prop) {
    if (!el || !el.style || typeof el.style.getPropertyValue !== "function") return null;
    const raw = el.style.getPropertyValue(prop);
    if (!raw) return null;
    const m = /^(-?[0-9.]+)px$/.exec(String(raw).trim());
    return m ? parseFloat(m[1]) : null;
  }

  function boxOf(el) {
    if (!el || el.nodeType !== 1) return { x: 0, y: 0, w: 0, h: 0 };
    const id = el.id || "";
    if (id === "uir-stage") return { x: 0, y: 0, w: stage.w, h: stage.h };
    let x = 0, y = 0, cur = el;
    while (cur && cur.nodeType === 1) {
      if (cur.id === "uir-viewport" || cur.id === "uir-stage") break;
      const l = stylePx(cur, "left");
      const t = stylePx(cur, "top");
      if (l !== null) x += l;
      if (t !== null) y += t;
      cur = cur.parentElement;
    }
    let w = stylePx(el, "width");
    let h = stylePx(el, "height");
    if (id === "uir-viewport" || id === "uir-canvas") {
      if (w === null) w = stage.w;
      if (h === null) h = stage.h;
    }
    return { x, y, w: w === null ? 0 : w, h: h === null ? 0 : h };
  }

  const ElemProto = window.HTMLElement.prototype;

  Object.defineProperty(ElemProto, "getBoundingClientRect", {
    configurable: true,
    writable: true,
    value: function () {
      const b = boxOf(this);
      return {
        x: b.x, y: b.y, left: b.x, top: b.y,
        right: b.x + b.w, bottom: b.y + b.h,
        width: b.w, height: b.h,
        toJSON() { return this; }
      };
    }
  });

  Object.defineProperty(ElemProto, "clientWidth", {
    configurable: true,
    get() {
      if (this.id === "uir-stage") return stage.w;
      const b = boxOf(this);
      return Math.round(b.w);
    }
  });
  Object.defineProperty(ElemProto, "clientHeight", {
    configurable: true,
    get() {
      if (this.id === "uir-stage") return stage.h;
      const b = boxOf(this);
      return Math.round(b.h);
    }
  });
  Object.defineProperty(ElemProto, "offsetWidth", {
    configurable: true,
    get() {
      const b = boxOf(this);
      return Math.round(b.w);
    }
  });
  Object.defineProperty(ElemProto, "offsetHeight", {
    configurable: true,
    get() {
      const b = boxOf(this);
      return Math.round(b.h);
    }
  });

  Object.defineProperty(window.Document.prototype, "hidden", {
    configurable: true, get() { return false; }
  });
  Object.defineProperty(window.Document.prototype, "visibilityState", {
    configurable: true, get() { return "visible"; }
  });

  Object.defineProperty(window, "devicePixelRatio", {
    configurable: true, get() { return opts.dpr; }
  });
  Object.defineProperty(window, "innerWidth", {
    configurable: true, get() { return STAGE_W; }
  });
  Object.defineProperty(window, "innerHeight", {
    configurable: true, get() { return STAGE_H; }
  });

  // ResizeObserver: jsdom has none, and the harness drives resizes itself.
  const observers = [];
  window.ResizeObserver = class ResizeObserver {
    constructor(cb) { this.cb = cb; this.targets = []; observers.push(this); }
    observe(t) { this.targets.push(t); }
    unobserve(t) { this.targets = this.targets.filter((x) => x !== t); }
    disconnect() { this.targets = []; }
  };
  window.__uirTriggerResizeObservers = function () {
    for (const o of observers) {
      try { o.cb.call(o, o.targets.map((t) => ({ target: t })), o); } catch (e) { /* ignored */ }
    }
  };

  // jsdom has no real canvas. Hand back a recording 2D context: enough for the
  // text metrics the proportional font path asks for, and enough to assert
  // that a standalone -d:canvas build actually draws something.
  const canvasLog = { calls: 0, byOp: {}, badNumbers: 0 };
  window.__uirCanvasLog = canvasLog;
  function makeMockContext(canvas) {
    const record = (name, args) => {
      canvasLog.calls++;
      canvasLog.byOp[name] = (canvasLog.byOp[name] || 0) + 1;
      for (const a of args) {
        if (typeof a === "number" && !Number.isFinite(a)) canvasLog.badNumbers++;
      }
    };
    const ctx = {
      canvas,
      font: "", fillStyle: "", strokeStyle: "", textBaseline: "", lineWidth: 1,
      letterSpacing: "",
      save() { record("save", []); },
      restore() { record("restore", []); },
      setTransform() { record("setTransform", [...arguments]); },
      clearRect() { record("clearRect", [...arguments]); },
      fillRect() { record("fillRect", [...arguments]); },
      fillText() { record("fillText", [...arguments]); },
      beginPath() { record("beginPath", []); },
      moveTo() { record("moveTo", [...arguments]); },
      lineTo() { record("lineTo", [...arguments]); },
      stroke() { record("stroke", []); },
      rect() { record("rect", [...arguments]); },
      clip() { record("clip", []); },
      drawImage() { record("drawImage", [...arguments].slice(1)); },
      measureText(t) {
        record("measureText", []);
        // Rough but deterministic advance model; the point is to prove the
        // measurement path is taken and cached, not to match a real font.
        const size = parseFloat(/([0-9.]+)px/.exec(this.font || "15px")?.[1] || "15");
        let w = 0;
        for (const ch of String(t)) w += ch.charCodeAt(0) > 0x2000 ? size : size * 0.55;
        return { width: w };
      }
    };
    return ctx;
  }
  const CanvasProto = window.HTMLCanvasElement.prototype;
  CanvasProto.getContext = function (kind) {
    if (kind !== "2d") return null;
    if (!this.__uirMockCtx) this.__uirMockCtx = makeMockContext(this);
    return this.__uirMockCtx;
  };

  // Clipboard: the harness must be able to see what putClipboardText wrote.
  const clipboard = { text: "", writes: 0, execCopy: 0 };
  window.__uirClipboardWrites = clipboard;
  if (!window.navigator.clipboard) {
    Object.defineProperty(window.navigator, "clipboard", {
      configurable: true,
      value: {
        writeText(t) {
          clipboard.writes++;
          clipboard.text = String(t);
          return Promise.resolve();
        }
      }
    });
  }
  window.document.execCommand = function (cmd) {
    if (cmd === "copy") {
      clipboard.execCopy++;
      const ta = window.document.getElementById("uir-clipboard-offscreen");
      if (ta) clipboard.text = ta.value;
    }
    return true;
  };

  return { boxOf, stylePx };
}

// ---------------------------------------------------------------------------
// Invariants
// ---------------------------------------------------------------------------

const BAD_STYLE = /NaN|undefined|Infinity|null/;

function checkViewport(window, report) {
  const vp = window.document.getElementById("uir-viewport") ||
             window.document.getElementById("uir-canvas");
  if (!vp) {
    report.errors.push("no #uir-viewport in the page");
    return;
  }
  const vpW = vp.clientWidth;
  const vpH = vp.clientHeight;
  report.viewport = { w: vpW, h: vpH };

  const nodes = vp.querySelectorAll("*");
  report.maxNodes = Math.max(report.maxNodes, nodes.length);

  let overflow = 0;
  let bad = 0;
  let huge = 0;
  for (let i = 0; i < nodes.length; i++) {
    const el = nodes[i];
    const styleAttr = el.getAttribute("style") || "";
    if (BAD_STYLE.test(styleAttr)) {
      if (bad < 5) {
        report.errors.push("malformed inline style on ." + el.className + ": " +
          styleAttr.slice(0, 120));
      }
      bad++;
      continue;
    }
    if (el.classList.contains("uir-text")) {
      // Text inside a `.uir-clip` is cut off by the clip rectangle, so running
      // past the window edge is not a layout bug there.
      if (typeof el.closest === "function" && el.closest(".uir-clip")) continue;
      const b = el.getBoundingClientRect();
      const right = b.left + b.width;
      const bottom = b.top + b.height;
      const over = Math.max(right - vpW, bottom - vpH);
      if (over > overflow) {
        overflow = Math.round(over);
        report.worstOverflow = {
          app: report.currentApp || "?",
          text: (el.textContent || "").slice(0, 40),
          box: { x: Math.round(b.left), y: Math.round(b.top), w: Math.round(b.width), h: Math.round(b.height) },
          viewport: { w: vpW, h: vpH }
        };
      }
    }
    const b = el.getBoundingClientRect();
    if (b.width > 100000 || b.height > 100000 || Math.abs(b.left) > 100000) huge++;
  }
  report.badStyles += bad;
  report.hugeNodes += huge;
  report.maxTextOverflowPx = Math.max(report.maxTextOverflowPx, overflow);
}

// ---------------------------------------------------------------------------
// D7 / D8 / D9 -- the browser must not dictate the layout.
//
// The relays own their viewport: minViewport is a floor, the inset is zero
// unless the embedder says otherwise, the device pixel ratio is honoured for
// the backing store but never for the logical size, and every element the
// backend asks the shell to create must actually exist.
// ---------------------------------------------------------------------------

function checkBridge(window, errs, label) {
  const tag = "[" + label + "] ";
  const w = window;

  // D7: the embedder may publish a minimum viewport; the backend must honour
  // it. It need not publish one -- the backend then uses its own floor.
  const mv = w.__uirMinViewport;
  if (mv !== undefined && mv !== null &&
      (typeof mv.w !== "number" || typeof mv.h !== "number" ||
       !(mv.w > 0) || !(mv.h > 0))) {
    errs.push(tag + "D7 __uirMinViewport is malformed: " + JSON.stringify(mv));
  }
  // D8: an inset is opt-in. A hard-coded one is the bug this guards against.
  const inset = w.__uirViewportInset;
  if (inset !== undefined && inset !== null &&
      (typeof inset.x !== "number" || typeof inset.y !== "number" ||
       inset.x < 0 || inset.y < 0)) {
    errs.push(tag + "D8 __uirViewportInset is malformed: " + JSON.stringify(inset));
  }
  // D9: the device pixel ratio drives the backing store only. The HTML
  // backend never publishes one (it has no backing store); the canvas
  // backend must, and its canvas must be sized in device pixels.
  const dpr = w.__uirDpr;
  const canvas = w.document.getElementById("uir-canvas");
  if (dpr !== undefined || canvas !== null) {
    if (typeof dpr !== "number" || !(dpr > 0) || !(dpr < 16)) {
      errs.push(tag + "D9 __uirDpr is missing or absurd: " + dpr);
    }
  }
  if (canvas !== null && typeof dpr === "number" && dpr > 0) {
    const r = canvas.getBoundingClientRect();
    const wantW = Math.max(1, Math.round(r.width * dpr));
    const wantH = Math.max(1, Math.round(r.height * dpr));
    if (canvas.width !== wantW || canvas.height !== wantH) {
      errs.push(tag + "D9 backing store is " + canvas.width + "x" + canvas.height +
                ", expected " + wantW + "x" + wantH + " at dpr " + dpr);
    }
  }
  const missing = w.__uirMissingElements;
  if (Array.isArray(missing) && missing.length > 0) {
    errs.push(tag + "shell is missing elements: " + missing.join(","));
  }
  for (const fn of ["__uirRequestStep", "__uirSetTitle", "__uirCopyToSystem",
                    "__uirTriggerResizeObservers", "__uirSyncViewportSize"]) {
    if (typeof w[fn] !== "function") errs.push(tag + "bridge is missing " + fn);
  }
  // A measured string must never come back as zero or as a non-finite number,
  // and the cache must not grow without bound.
  const cache = w.__uirMeasureCache;
  if (cache && typeof cache.forEach === "function") {
    let bad = 0, n = 0;
    cache.forEach((v) => {
      n += 1;
      if (typeof v !== "number" || !isFinite(v) || v <= 0 || v > 1e6) bad += 1;
    });
    if (bad > 0) errs.push(tag + "D2 " + bad + " bad entries in the text measure cache");
    if (n > 20000) errs.push(tag + "D2 the text measure cache grows without bound: " + n);
  }
  return errs.length;
}

// Ask for a floor that is bigger than the natural one, then squeeze the stage.
// Whatever the shell does, the app must never be told about a viewport
// smaller than the floor it was given.
async function floorStorm(window, errs, label, floorW, floorH) {
  const w = window;
  const prevMin = w.__uirMinViewport;
  const prevInset = w.__uirViewportInset;
  w.__uirMinViewport = { w: floorW, h: floorH };
  w.__uirViewportInset = { x: 0, y: 0 };
  const stage = w.__uirStage;
  if (!stage) { w.__uirMinViewport = prevMin; w.__uirViewportInset = prevInset; return; }
  const orig = { w: stage.w, h: stage.h };
  for (const [sw, sh] of [[30, 20], [1, 1], [0, 0], [100, 100]]) {
    stage.w = sw;
    stage.h = sh;
    if (typeof w.__uirTriggerResizeObservers === "function") w.__uirTriggerResizeObservers();
    w.dispatchEvent(new w.Event("resize"));
    await sleep(10);
    if (typeof w.__uirSyncViewportSize === "function") w.__uirSyncViewportSize();
    await sleep(10);
    if (typeof w.__uirRequestStep === "function") {
      try { w.__uirRequestStep(); } catch (e) { /* the loop may be done */ }
    }
    await sleep(10);
    const vp = w.document.getElementById("uir-viewport");
    if (!vp) { errs.push("[" + label + "] the viewport vanished during a resize storm"); break; }
    const r = vp.getBoundingClientRect();
    if (r.width < floorW || r.height < floorH) {
      errs.push("[" + label + "] viewport fell below the requested floor " +
                floorW + "x" + floorH + " at stage " + sw + "x" + sh +
                ": " + r.width + "x" + r.height);
    }
  }
  stage.w = orig.w;
  stage.h = orig.h;
  w.__uirMinViewport = prevMin;
  w.__uirViewportInset = prevInset;
  if (typeof w.__uirTriggerResizeObservers === "function") w.__uirTriggerResizeObservers();
  if (typeof w.__uirSyncViewportSize === "function") w.__uirSyncViewportSize();
  await sleep(30);
}

// Squeeze the stage down to nothing and back. An app that survives this is an
// app that does not care what the window manager says.
async function resizeStorm(window, errs, label) {
  const stage = window.__uirStage;
  if (!stage) return;
  const sizes = [[320, 240], [120, 90], [40, 30], [1, 1], [stage.w, stage.h],
                 [stage.w + 400, stage.h + 200], [200, 800]];
  for (const [w, h] of sizes) {
    stage.w = w;
    stage.h = h;
    if (typeof window.__uirTriggerResizeObservers === "function") {
      window.__uirTriggerResizeObservers();
    }
    window.dispatchEvent(new window.Event("resize"));
    await sleep(10);
    if (typeof window.__uirRequestStep === "function") {
      try { window.__uirRequestStep(); } catch (e) { /* the loop may be done */ }
    }
    await sleep(10);
    const vp = window.document.getElementById("uir-viewport");
    if (!vp) {
      errs.push("[" + label + "] the viewport vanished during a resize storm");
      return;
    }
    const r = vp.getBoundingClientRect();
    if (!(r.width > 0) || !(r.height > 0)) {
      errs.push("[" + label + "] viewport collapsed to " + r.width + "x" +
                r.height + " after resizing to " + w + "x" + h);
    }
  }
  stage.w = sizes[sizes.length - 3][0];
  stage.h = sizes[sizes.length - 3][1];
  if (typeof window.__uirTriggerResizeObservers === "function") {
    window.__uirTriggerResizeObservers();
  }
  await sleep(30);
}

// ---------------------------------------------------------------------------
// Monkey
// ---------------------------------------------------------------------------

const KEYS = [
  ["a", "KeyA"], ["b", "KeyB"], ["z", "KeyZ"], ["0", "Digit0"], ["7", "Digit7"],
  ["Enter", "Enter"], ["Backspace", "Backspace"], ["Tab", "Tab"], [" ", "Space"],
  ["Escape", "Escape"], ["ArrowLeft", "ArrowLeft"], ["ArrowRight", "ArrowRight"],
  ["ArrowUp", "ArrowUp"], ["ArrowDown", "ArrowDown"], ["Home", "Home"],
  ["End", "End"], ["Delete", "Delete"], ["PageUp", "PageUp"], ["PageDown", "PageDown"],
  [".", "Period"], [",", "Comma"], ["-", "Minus"], ["=", "Equal"], ["/", "Slash"],
  ["F1", "F1"], ["F5", "F5"]
];

function fireMouse(window, vp, type, x, y, button, detail, mods) {
  const ev = new window.MouseEvent(type, {
    bubbles: true, cancelable: true, clientX: x, clientY: y,
    button: button || 0, detail: detail || 1,
    shiftKey: !!(mods && mods.shift), ctrlKey: !!(mods && mods.ctrl),
    altKey: !!(mods && mods.alt), metaKey: !!(mods && mods.meta)
  });
  vp.dispatchEvent(ev);
}

function fireWheel(window, vp, dy, dx) {
  const ev = new window.WheelEvent("wheel", {
    bubbles: true, cancelable: true, deltaY: dy, deltaX: dx
  });
  vp.dispatchEvent(ev);
}

function fireKey(window, vp, type, key, code, mods) {
  const ev = new window.KeyboardEvent(type, {
    bubbles: true, cancelable: true, key: key, code: code,
    shiftKey: !!(mods && mods.shift), ctrlKey: !!(mods && mods.ctrl),
    altKey: !!(mods && mods.alt), metaKey: !!(mods && mods.meta)
  });
  vp.dispatchEvent(ev);
}

function firePaste(window, vp, text) {
  const ev = new window.Event("paste", { bubbles: true, cancelable: true });
  try {
    ev.clipboardData = { getData: () => text };
  } catch (e) { /* read-only in some engines; the handler tolerates that */ }
  vp.dispatchEvent(ev);
}

async function monkeyOneApp(window, appId, opts, report) {
  const rnd = makeRandom(opts.seed + appId.length * 7919);
  const doc = window.document;

  if (typeof window.switchUirApp === "function" && appId) {
    window.switchUirApp(appId);
  }

  // Wait for the first frame.
  let vp = null;
  for (let i = 0; i < 200; i++) {
    await sleep(2);
    vp = doc.getElementById("uir-viewport") || doc.getElementById("uir-canvas");
    if (vp && vp.querySelectorAll("*").length > 0) break;
  }
  if (!vp) {
    report.errors.push("app " + appId + " never rendered a frame");
    return false;
  }
  const vw = vp.clientWidth;
  const vh = vp.clientHeight;

  const pick = (arr) => arr[Math.floor(rnd() * arr.length) % arr.length];
  const rndX = () => Math.floor(rnd() * (vw + 40)) - 20;
  const rndY = () => Math.floor(rnd() * (vh + 40)) - 20;

  let textClicks = 0;
  for (let step = 0; step < opts.steps; step++) {
    const roll = rnd();
    const wasResize = roll >= 0.97;
    if (roll < 0.30) {
      fireMouse(window, vp, "mousemove", rndX(), rndY(), 0, 1, null);
    } else if (roll < 0.55) {
      // Aim at something that looks clickable: the centre of a random label.
      const texts = vp.querySelectorAll(".uir-text");
      let x = rndX(), y = rndY();
      if (texts.length > 0 && rnd() < 0.75) {
        const el = texts[Math.floor(rnd() * texts.length) % texts.length];
        const b = el.getBoundingClientRect();
        x = Math.round(b.left + b.width / 2);
        y = Math.round(b.top + b.height / 2);
        textClicks++;
      }
      const detail = rnd() < 0.12 ? 2 : 1;
      fireMouse(window, vp, "mousedown", x, y, 0, detail, null);
      fireMouse(window, vp, "mouseup", x, y, 0, detail, null);
    } else if (roll < 0.62) {
      const btn = rnd() < 0.7 ? 2 : 1;
      fireMouse(window, vp, "mousedown", rndX(), rndY(), btn, 1, null);
      fireMouse(window, vp, "mouseup", rndX(), rndY(), btn, 1, null);
    } else if (roll < 0.72) {
      fireWheel(window, vp, rnd() < 0.5 ? -120 : 120, 0);
      fireWheel(window, vp, 0, rnd() < 0.5 ? -3 : 3);
    } else if (roll < 0.94) {
      const [key, code] = pick(KEYS);
      const mods = rnd() < 0.18 ? { ctrl: true } : (rnd() < 0.12 ? { shift: true } : null);
      fireKey(window, vp, "keydown", key, code, mods);
      fireKey(window, vp, "keyup", key, code, mods);
    } else if (roll < 0.97) {
      firePaste(window, vp, "pasted-" + Math.floor(rnd() * 1000));
    } else {
      // Resize: shrink, grow, and go through the ResizeObserver path.
      const stages = [[420, 320], [opts.width, opts.height], [360, 640], [1280, 400]];
      const [w, h] = pick(stages);
      if (window.__uirStage) {
        window.__uirStage.w = w;
        window.__uirStage.h = h;
      }
      if (typeof window.__uirTriggerResizeObservers === "function") {
        window.__uirTriggerResizeObservers();
      }
      window.dispatchEvent(new window.Event("resize"));
      if (opts.debug) {
        for (const wait of [20, 60, 150, 400]) {
          await sleep(wait);
          const probe = { errors: [], badStyles: 0, hugeNodes: 0, maxNodes: 0, maxTextOverflowPx: 0, worstOverflow: null, currentApp: "probe" };
          checkViewport(window, probe);
          const v2 = doc.getElementById("uir-viewport");
          console.log("   resize ->", w + "x" + h, "waited", wait,
            "vp=" + (v2 ? v2.clientWidth + "x" + v2.clientHeight : "?"),
            "overflow=" + probe.maxTextOverflowPx,
            probe.worstOverflow ? JSON.stringify(probe.worstOverflow) : "");
        }
      }
    }

    // Let the app draw the frame this input caused before judging the result:
    // a resize in particular is only visible after the next step runs.
    await sleep(wasResize ? 40 : 2);
    checkViewport(window, report);
    if (report.errors.length > 40) break; // stop flooding
  }

  await sleep(30);
  checkViewport(window, report);
  report.textClicks += textClicks;
  return true;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main() {
  const opts = parseArgs(process.argv);
  if (!opts.file) {
    console.error("usage: node monkey_harness.js <bundle.html> [--steps=N] [--apps=a,b] [--seed=N]");
    process.exit(2);
  }
  const html = fs.readFileSync(opts.file, "utf8");

  const errors = [];
  const consoleErrors = [];
  const virtualConsole = new VirtualConsole();
  virtualConsole.on("jsdomError", (e) => {
    errors.push("jsdomError: " + (e && e.message ? e.message : String(e)));
  });
  virtualConsole.on("error", (msg) => { consoleErrors.push(String(msg)); });
  virtualConsole.on("warn", () => { /* the backend warns about the shell contract on purpose */ });

  const dom = new JSDOM(html, {
    runScripts: "dangerously",
    pretendToBeVisual: true,
    url: "file://" + path.resolve(opts.file),
    virtualConsole,
    beforeParse(window) { installLayout(window, opts); }
  });

  const window = dom.window;
  const report = {
    file: path.basename(opts.file),
    apps: [],
    stepsPerApp: opts.steps,
    seed: opts.seed,
    dpr: opts.dpr,
    stage: { w: opts.width, h: opts.height },
    errors: errors,
    consoleErrors: consoleErrors,
    badStyles: 0,
    hugeNodes: 0,
    maxNodes: 0,
    maxTextOverflowPx: 0,
    worstOverflow: null,
    textClicks: 0,
    canvasCalls: 0,
    canvasByOp: {},
    canvasBadNumbers: 0,
    clipboardWrites: 0,
    missingShellElements: []
  };

  await sleep(60);
  report.missingShellElements = window.__uirMissingElements || [];
  const startupBridge = [];
  checkBridge(window, startupBridge, "startup");
  report.bridgeViolations = startupBridge.slice();
  for (const e of startupBridge) errors.push(e);

  let appIds = opts.apps;
  if (!appIds || appIds.length === 0) {
    appIds = Object.keys(window.UIR_APPS || {});
  }
  if (appIds.length === 0) {
    appIds = [null]; // a single standalone app page
  }

  for (const appId of appIds) {
    const before = errors.length;
    const perApp = {
      app: appId || "(standalone)",
      errors: 0,
      domNodes: 0,
      maxTextOverflowPx: 0,
      rendered: false
    };
    const sub = {
      errors: [], badStyles: 0, hugeNodes: 0, maxNodes: 0,
      maxTextOverflowPx: 0, textClicks: 0
    };
    const rendered = await monkeyOneApp(window, appId, opts, sub);
    checkBridge(window, sub.errors, appId || "standalone");
    await resizeStorm(window, sub.errors, appId || "standalone");
    await floorStorm(window, sub.errors, appId || "standalone", 500, 400);
    checkBridge(window, sub.errors, appId || "standalone");
    perApp.rendered = rendered;
    perApp.errors = sub.errors.length;
    perApp.domNodes = sub.maxNodes;
    perApp.maxTextOverflowPx = sub.maxTextOverflowPx;
    const postNodes = window.document.getElementById("uir-viewport")
      ? window.document.getElementById("uir-viewport")
          .querySelectorAll("*").length + 1
      : 0;
    if (postNodes > perApp.domNodes) perApp.domNodes = postNodes;
    if (sub.maxTextOverflowPx > report.maxTextOverflowPx) report.worstOverflow = sub.worstOverflow;
    for (const e of sub.errors) errors.push("[" + (appId || "standalone") + "] " + e);
    report.maxTextOverflowPx = Math.max(report.maxTextOverflowPx, sub.maxTextOverflowPx);
    report.maxNodes = Math.max(report.maxNodes, sub.maxNodes);
    report.textClicks += sub.textClicks;
    report.apps.push(perApp);
    if (!opts.quiet) {
      console.log((perApp.errors === 0 && rendered ? "  PASS  " : "  FAIL  ") +
        perApp.app + "  nodes=" + perApp.domNodes +
        " overflow=" + perApp.maxTextOverflowPx + "px" +
        (perApp.errors ? " errors=" + perApp.errors : ""));
    }
    void before;
  }

  const log = window.__uirCanvasLog;
  if (log) {
    report.canvasCalls = log.calls;
    report.canvasByOp = log.byOp;
    report.canvasBadNumbers = log.badNumbers;
  }
  const clip = window.__uirClipboardWrites;
  if (clip) report.clipboardWrites = clip.writes;

  report.ok = errors.length === 0 && report.badStyles === 0 && report.hugeNodes === 0;
  if (opts.json) {
    console.log(JSON.stringify(report, null, 2));
  } else {
    console.log("--- monkey report ---");
    console.log(JSON.stringify({
      ok: report.ok,
      apps: report.apps.length,
      errors: report.errors.length,
      badStyles: report.badStyles,
      hugeNodes: report.hugeNodes,
      maxNodes: report.maxNodes,
      maxTextOverflowPx: report.maxTextOverflowPx,
      worstOverflow: report.worstOverflow,
      textClicks: report.textClicks,
      canvasCalls: report.canvasCalls,
      canvasBadNumbers: report.canvasBadNumbers,
      clipboardWrites: report.clipboardWrites,
      firstErrors: report.errors.slice(0, 10)
    }, null, 2));
  }

  window.close();
  process.exit(report.ok ? 0 : 1);
}

main().catch((e) => {
  console.error("harness crashed:", e && e.stack ? e.stack : e);
  process.exit(3);
});
