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

// ---------------------------------------------------------------------------
// D3 -- a frame must be reconciled into the live DOM, not rewritten over it.
//
// `viewport.innerHTML = frame` throws the whole subtree away every frame.
// The markup can come out byte-identical and the page still loses focus,
// text selection and scroll position, because the nodes that held them are
// gone. So the assertion is about *identity*, not about content: when a
// frame changes nothing, the elements must still be the same objects.
// ---------------------------------------------------------------------------

function installReconcileProbe(window, vp, appId) {
  if (!vp || vp.id !== "uir-viewport") return null;   // canvas backend: N/A
  const probe = {
    appId: appId,
    innerHtmlWrites: 0,   // wholesale rewrites of the viewport subtree
    nodesAdded: 0,
    nodesRemoved: 0,
    nodesTouched: 0,      // in-place attribute / text updates
    repaints: 0,          // frames that actually restructured the DOM
    nodeCountSamples: 0,  // samples where the driver published a node count
    nodeCountMismatches: 0,
    reportedCountMismatch: false,
    steadySamples: 0,     // samples where nothing structural moved
    identityBreaks: 0,    // steady samples that still replaced nodes
    prevNodes: null,
    lastAdded: 0, lastRemoved: 0, lastTouched: 0
  };

  // Shadow the inherited innerHTML accessor on this one element, so any
  // `vp.innerHTML = ...` the bundle performs is counted instead of silently
  // wiping the tree.
  const desc = Object.getOwnPropertyDescriptor(window.Element.prototype, "innerHTML");
  if (desc && desc.set) {
    Object.defineProperty(vp, "innerHTML", {
      configurable: true,
      enumerable: false,
      get() { return desc.get.call(this); },
      set(v) { probe.innerHtmlWrites += 1; return desc.set.call(this, v); }
    });
  }

  probe.observer = new window.MutationObserver((records) => {
    let structural = false;
    for (const r of records) {
      if (r.type === "childList") {
        probe.nodesAdded += r.addedNodes.length;
        probe.nodesRemoved += r.removedNodes.length;
        structural = true;
      } else {
        probe.nodesTouched += 1;
      }
    }
    // One batch per animation frame, so this counts the frames that really
    // repainted -- the denominator the churn ratio needs. Counting harness
    // steps instead would flatter a driver that rewrites everything, because
    // deduplication hides most of the rewrites.
    if (structural) probe.repaints += 1;
  });
  probe.observer.observe(vp, {
    childList: true, subtree: true, attributes: true, characterData: true
  });
  window.__uirReconcileProbe = probe;
  return probe;
}

function checkReconcile(window, nodes, errs) {
  const probe = window.__uirReconcileProbe;
  if (!probe) return;
  const churn = (probe.nodesAdded - probe.lastAdded) +
                (probe.nodesRemoved - probe.lastRemoved) +
                (probe.nodesTouched - probe.lastTouched);
  probe.lastAdded = probe.nodesAdded;
  probe.lastRemoved = probe.nodesRemoved;
  probe.lastTouched = probe.nodesTouched;

  if (churn !== 0) {
    // Something legitimately changed this sample; identity says nothing.
    probe.prevNodes = Array.prototype.slice.call(nodes);
    return;
  }
  // The driver publishes how many elements the frame it just rendered should
  // have put in the viewport. Comparing that with the live DOM catches a
  // reconciler that leaks a node, drops one, or inserts one twice -- which no
  // amount of markup inspection would notice, because the leaked node can be
  // an exact copy of a legitimate one.
  // The driver publishes how many elements the frame it just rendered should
  // have put in the viewport. Comparing that with the live DOM catches a
  // reconciler that leaks a node, drops one, or inserts one twice -- which no
  // amount of markup inspection would notice, because the leaked node can be
  // an exact copy of a legitimate one.
  //
  // Three primitives carry an inner element of their own (a diagonal line is
  // an <svg> wrapping a <line>, an image and a blit are a <div> wrapping an
  // <img>), so those have to be added to the declared count before comparing.
  const published = window.__uirDomNodeCount;
  if (typeof published === "number") {
    // `tagName` is uppercase for HTML elements and lowercase for SVG ones, so
    // fold it before comparing -- an <img> missed here looks exactly like a
    // leaked node.
    let inner = 0;
    for (let i = 0; i < nodes.length; i++) {
      const t = (nodes[i].tagName || "").toUpperCase();
      if (t === "LINE" || t === "IMG") inner++;
    }
    probe.nodeCountSamples += 1;
    if (published + inner !== nodes.length) {
      probe.nodeCountMismatches += 1;
      if (errs.length < 40 && !probe.reportedCountMismatch) {
        probe.reportedCountMismatch = true;
        errs.push(probe.appId + ": the frame declares " + published + " node(s)" +
          " (+" + inner + " inner) but the viewport holds " + nodes.length +
          " -- the reconciler leaked or dropped elements");
      }
    }
  }

  // A quiet frame: no mutation of any kind was recorded. Every element must
  // therefore still be the same object as last sample. A full `innerHTML`
  // rewrite cannot get here at all -- it always records churn -- and a
  // rebuild-that-happens-to-match fails the pointer comparison below.
  probe.steadySamples += 1;
  if (probe.prevNodes && probe.prevNodes.length === nodes.length) {
    let replaced = 0;
    for (let i = 0; i < nodes.length; i++) {
      if (nodes[i] !== probe.prevNodes[i]) replaced++;
    }
    if (replaced > 0) {
      probe.identityBreaks += 1;
      if (errs.length < 40) {
        errs.push(probe.appId + ": a frame that changed nothing replaced " +
          replaced + "/" + nodes.length + " DOM nodes (rewrite, not reconcile)");
      }
    }
  }
  probe.prevNodes = Array.prototype.slice.call(nodes);

}

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
        report.errors.push("malformed inline style on ." +
          (el.getAttribute("class") || el.tagName) + ": " +
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
  if (report.errors) checkReconcile(window, nodes, report.errors);
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
    // The floor in force is the larger of what this test asked for and what
    // the application declared with `setMinViewport`: an embedder can give an
    // app more room, never less than the app says it needs.
    const appMin = w.__uirAppMinViewport;
    const needW = Math.max(floorW, appMin && appMin.w > 0 ? appMin.w : 0);
    const needH = Math.max(floorH, appMin && appMin.h > 0 ? appMin.h : 0);
    if (r.width < needW || r.height < needH) {
      errs.push("[" + label + "] viewport fell below the floor " +
                needW + "x" + needH + (appMin ? " (app declared " + appMin.w +
                "x" + appMin.h + ")" : "") + " at stage " + sw + "x" + sh +
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

// ---------------------------------------------------------------------------
// Does the app's own canvas follow the window?
//
// Measured off the full-window background rectangle the app paints first, not
// off its text: a fixed instruction string legitimately stays put when the
// window resizes, so text position cannot tell a responsive layout from a
// dead one. The background rect is the app's own declaration of "this is how
// big I think I am", and it is what has to track the size it was handed.
//
// Three things must hold after the window settles:
//   1. the canvas covers the viewport -- otherwise part of the window shows
//      the shell's background instead of the app;
//   2. shrinking the window shrinks the canvas -- otherwise the resize never
//      reached the app at all;
//   3. nothing is drawn wholly outside the canvas -- an element starting past
//      the app's own right edge is unreachable at every window size, which is
//      what a hardcoded coordinate produces.
//
// `#uir-viewport` carries `overflow:hidden` and `contain:paint`, so the one
// frame where the previous layout is still up is clipped rather than spilled.
// That transient is what `maxTextOverflowPx` sometimes reports.
// ---------------------------------------------------------------------------

function parseStylePx(style, prop) {
  // jsdom normalises `style.cssText` to "left: 0px; top: 0px; ...", so both
  // the separator and the colon can be followed by a space.
  const m = new RegExp("(?:^|;)\\s*" + prop + ":\\s*(-?[0-9.]+)px").exec(style || "");
  return m ? Math.round(parseFloat(m[1])) : null;
}

function appCanvas(window) {
  const vp = window.document.getElementById("uir-viewport");
  if (!vp) return null;
  const box = vp.getBoundingClientRect();
  // The app's background: the rect anchored at its own origin, biggest first.
  let best = null;
  for (const el of vp.querySelectorAll(".uir-rect")) {
    const st = el.getAttribute("style") || "";
    if (parseStylePx(st, "left") !== 0 || parseStylePx(st, "top") !== 0) continue;
    const w = parseStylePx(st, "width"), h = parseStylePx(st, "height");
    if (w === null || h === null) continue;
    if (!best || w * h > best.w * best.h) best = { w, h };
  }
  // Anything drawn wholly past the canvas cannot be reached at any size.
  // Except inside a `.uir-clip`: that container exists precisely to hide
  // content scrolled out of a panel, so an editor line at x=1547 in a 480px
  // window is the clip doing its job, not a misplaced element.
  // Labels and images only. Rects, points and lines are deliberately left
  // out: they are the *payload* of a drawing app, not its chrome. `paint`
  // stores every stroke at the absolute position the drag put it, so when the
  // window shrinks the old strokes are legitimately outside the new canvas --
  // that is a painting, not a misplaced button. A caption or an image past the
  // edge is always a layout bug, because it is how the app labels itself.
  const offscreen = [];
  if (best) {
    const prims = vp.querySelectorAll(".uir-text,.uir-img-crop,.uir-blit-clip");
    for (const el of prims) {
      // Inside a `.uir-clip` the whole point is that content is hidden, so
      // scrolled-out rows of an editor or a list are not a misplacement.
      if (typeof el.closest === "function" && el.closest(".uir-clip")) continue;
      const st = el.getAttribute("style") || "";
      const x = parseStylePx(st, "left");
      const y = parseStylePx(st, "top");
      // The app's own background is the canvas itself; skip anything that
      // spans it, since "starts at 0 and covers the window" is the goal.
      const w = parseStylePx(st, "width") || 0;
      const h = parseStylePx(st, "height") || 0;
      if (x === 0 && y === 0 && w >= best.w && h >= best.h) continue;
      if ((x !== null && x >= best.w) || (y !== null && y >= best.h)) {
        offscreen.push({
          x: x, y: y, cls: el.getAttribute("class"),
          text: (el.textContent || "").slice(0, 30)
        });
      }
    }
  }
  return { vpW: Math.round(box.width), vpH: Math.round(box.height),
           canvas: best, offscreen };
}

async function settleStorm(window, errs, label) {
  const stage = window.__uirStage;
  if (!stage) return null;
  const orig = { w: stage.w, h: stage.h };

  const settle = async () => {
    if (typeof window.__uirTriggerResizeObservers === "function") {
      window.__uirTriggerResizeObservers();
    }
    window.dispatchEvent(new window.Event("resize"));
    if (typeof window.__uirSyncViewportSize === "function") window.__uirSyncViewportSize();
    for (let i = 0; i < 12; i++) {
      if (typeof window.__uirRequestStep === "function") {
        try { window.__uirRequestStep(); } catch (e) { /* the loop may be done */ }
      }
      await sleep(25);
    }
  };

  const measure = async (sw, sh) => {
    stage.w = sw; stage.h = sh;
    await settle();
    return appCanvas(window);
  };

  const wide = await measure(Math.max(orig.w, 1280), Math.max(orig.h, 400));
  const narrow = await measure(360, 640);
  const back = await measure(orig.w, orig.h);

  for (const [name, m] of [["wide", wide], ["narrow", narrow], ["back", back]]) {
    if (!m || !m.canvas) continue;
    // 1. the app must paint over the whole window it was given
    if (m.canvas.w < m.vpW || m.canvas.h < m.vpH) {
      errs.push("[" + label + "] " + name + ": the app canvas " + m.canvas.w +
        "x" + m.canvas.h + " does not cover the " + m.vpW + "x" + m.vpH +
        " window it was handed");
    }
    // 3. nothing may sit wholly outside the app's own canvas
    if (m.offscreen.length > 0) {
      const o = m.offscreen[0];
      errs.push("[" + label + "] " + name + ": " + m.offscreen.length +
        " element(s) start past the app's own " + m.canvas.w + "x" +
        m.canvas.h + " canvas and can never be seen, e.g. ." + o.cls +
        " \"" + o.text + "\" at (" + o.x + "," + o.y + ")");
    }
  }
  // 2. the canvas has to follow the window down
  if (wide && narrow && wide.canvas && narrow.canvas &&
      narrow.canvas.w >= wide.canvas.w) {
    errs.push("[" + label + "] the canvas ignored the window shrinking from " +
      wide.vpW + "px to " + narrow.vpW + "px: it is still " +
      narrow.canvas.w + "px wide (it was " + wide.canvas.w + "px when wide)");
  }
  return { wide, narrow, back };
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
  // No Escape: it is the quit key for hello, paint and web_showcase. A monkey
  // that kills the app halfway through leaves a frozen DOM behind, and every
  // measurement after that point describes a corpse rather than the backend.
  // Quitting is worth testing -- in the server monkey, where it is the point.
  ["ArrowLeft", "ArrowLeft"], ["ArrowRight", "ArrowRight"],
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

  // D3: from the first painted frame on, watch what the driver does to the
  // live DOM instead of trusting the markup it leaves behind.
  installReconcileProbe(window, vp, appId);

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

  const probe = window.__uirReconcileProbe;
  if (probe) {
    // What repainting every one of these frames from scratch would have
    // cost, in node insertions + removals: every element out, every element
    // back in, once per frame that actually repainted.
    const rewriteCost = Math.max(1, report.maxNodes * probe.repaints * 2);
    const structural = probe.nodesAdded + probe.nodesRemoved;
    report.reconcile.push({
      app: appId,
      steadySamples: probe.steadySamples,
      identityBreaks: probe.identityBreaks,
      innerHtmlWrites: probe.innerHtmlWrites,
      nodesAdded: probe.nodesAdded,
      nodesRemoved: probe.nodesRemoved,
      nodesTouched: probe.nodesTouched,
      nodeCountSamples: probe.nodeCountSamples,
      nodeCountMismatches: probe.nodeCountMismatches,
      domNodes: report.maxNodes,
      repaints: probe.repaints,
      churnVsRewrite: Math.round(structural / rewriteCost * 1000) / 1000
    });
    if (probe.innerHtmlWrites > 0) {
      report.errors.push(appId + ": the viewport subtree was rewritten " +
        "wholesale " + probe.innerHtmlWrites + " time(s) via innerHTML " +
        "instead of being reconciled");
    }
    // A probe that never saw a quiet frame proved nothing, so say so rather
    // than reporting a vacuous pass.
    if (probe.steadySamples === 0 && vp.id === "uir-viewport") {
      report.errors.push(appId + ": no unchanged frame was ever observed, " +
        "so the D3 reconcile check never ran");
    }
    if (probe.observer) probe.observer.disconnect();
    window.__uirReconcileProbe = null;
  }
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
    missingShellElements: [],
    reconcile: [],
    settle: []
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
      maxTextOverflowPx: 0, textClicks: 0, reconcile: []
    };
    const rendered = await monkeyOneApp(window, appId, opts, sub);
    for (const r of sub.reconcile) report.reconcile.push(r);
    checkBridge(window, sub.errors, appId || "standalone");
    await resizeStorm(window, sub.errors, appId || "standalone");
    await floorStorm(window, sub.errors, appId || "standalone", 500, 400);
    checkBridge(window, sub.errors, appId || "standalone");
    const settled = await settleStorm(window, sub.errors, appId || "standalone");
    if (settled) {
      const c = (m) => (m && m.canvas ? m.canvas.w + "x" + m.canvas.h : "none");
      report.settle.push({
        app: appId || "(standalone)",
        wide: c(settled.wide) + " in " + (settled.wide ? settled.wide.vpW + "x" + settled.wide.vpH : "?"),
        narrow: c(settled.narrow) + " in " + (settled.narrow ? settled.narrow.vpW + "x" + settled.narrow.vpH : "?"),
        back: c(settled.back) + " in " + (settled.back ? settled.back.vpW + "x" + settled.back.vpH : "?")
      });
    }
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

  // D3 roll-up: the whole point is that an unchanged frame costs nothing.
  const rec = report.reconcile;
  report.reconcileTotals = {
    appsProbed: rec.length,
    steadySamples: rec.reduce((a, r) => a + r.steadySamples, 0),
    identityBreaks: rec.reduce((a, r) => a + r.identityBreaks, 0),
    innerHtmlWrites: rec.reduce((a, r) => a + r.innerHtmlWrites, 0),
    nodesAdded: rec.reduce((a, r) => a + r.nodesAdded, 0),
    nodesRemoved: rec.reduce((a, r) => a + r.nodesRemoved, 0),
    nodesTouched: rec.reduce((a, r) => a + r.nodesTouched, 0),
    nodeCountSamples: rec.reduce((a, r) => a + r.nodeCountSamples, 0),
    nodeCountMismatches: rec.reduce((a, r) => a + r.nodeCountMismatches, 0),
    worstChurnVsRewrite: rec.reduce((a, r) => Math.max(a, r.churnVsRewrite), 0)
  };
  // Reconciling means the structural work tracks what actually changed. A
  // driver that rebuilds the subtree scores 1.0 of the rewrite budget on
  // every repainted frame, so anything near that is not diffing at all.
  if (report.reconcileTotals.worstChurnVsRewrite > 0.75 && errors.length < 40) {
    const worst = rec.filter((r) => r.churnVsRewrite ===
      report.reconcileTotals.worstChurnVsRewrite)[0];
    errors.push("D3: " + (worst ? worst.app : "?") + " rebuilt " +
      Math.round(report.reconcileTotals.worstChurnVsRewrite * 100) +
      "% of a full DOM rewrite every frame -- the frame is not being diffed");
  }
  if (report.reconcileTotals.identityBreaks > 0 && errors.length < 40) {
    errors.push("D3: " + report.reconcileTotals.identityBreaks +
      " unchanged frame(s) still rebuilt their DOM nodes");
  }
  if (report.reconcileTotals.nodeCountMismatches > 0 && errors.length < 40) {
    errors.push("D3: " + report.reconcileTotals.nodeCountMismatches + " of " +
      report.reconcileTotals.nodeCountSamples +
      " samples had a DOM whose element count did not match the frame");
  }
  if (report.reconcileTotals.innerHtmlWrites > 0 && errors.length < 40) {
    errors.push("D3: the viewport was rewritten via innerHTML " +
      report.reconcileTotals.innerHtmlWrites + " time(s)");
  }

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
