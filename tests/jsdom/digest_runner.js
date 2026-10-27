#!/usr/bin/env node
// digest_runner.js -- runs a standalone uirelays page that was compiled with
// `-d:sharksSelftest` inside jsdom and prints the `SHARKS_DIGEST` line the app
// logs. That line is the browser half of the cross-backend comparison CI does:
// the very same scene, rendered by the very same Nim code compiled to
// JavaScript, must produce the very same primitive digest as the native
// backends produce.
//
//   node tests/jsdom/digest_runner.js <page.html> [--width=1024] [--height=640]
//        [--dpr=1] [--timeout=120000]
//
// exit 0  a SHARKS_DIGEST line was seen and no page error happened
// exit 1  timeout, a page error, or a malformed digest line
// exit 2  bad usage

"use strict";

const fs = require("fs");
const path = require("path");
const { JSDOM, VirtualConsole } = require("jsdom");
const { installLayout } = require("./monkey_harness.js");

function parseArgs(argv) {
  const opts = { file: "", width: 1024, height: 640, dpr: 1, timeout: 120000 };
  for (const a of argv.slice(2)) {
    if (a.startsWith("--width=")) opts.width = parseInt(a.slice(8), 10);
    else if (a.startsWith("--height=")) opts.height = parseInt(a.slice(9), 10);
    else if (a.startsWith("--dpr=")) opts.dpr = parseFloat(a.slice(6));
    else if (a.startsWith("--timeout=")) opts.timeout = parseInt(a.slice(10), 10);
    else if (!a.startsWith("--")) opts.file = a;
  }
  return opts;
}

const opts = parseArgs(process.argv);
if (!opts.file || !fs.existsSync(opts.file)) {
  console.error("usage: digest_runner.js <page.html> [--width=N] [--height=N] " +
                "[--dpr=N] [--timeout=ms]");
  process.exit(2);
}

const html = fs.readFileSync(opts.file, "utf8");
const errors = [];
let digest = null;

const vc = new VirtualConsole();
vc.on("log", (...args) => {
  const line = args.map((a) => String(a)).join(" ");
  if (line.indexOf("SHARKS_DIGEST") === 0) {
    digest = line;
    console.log(line);
  }
});
vc.on("jsdomError", (e) => {
  errors.push("jsdomError: " + (e && e.message ? e.message : String(e)));
});
vc.on("error", (...args) => {
  errors.push("console.error: " + args.map(String).join(" "));
});

const dom = new JSDOM(html, {
  runScripts: "dangerously",
  pretendToBeVisual: true,
  url: "file://" + path.resolve(opts.file),
  virtualConsole: vc,
  beforeParse(window) { installLayout(window, opts); }
});

const started = Date.now();
const timer = setInterval(() => {
  if (digest !== null) {
    clearInterval(timer);
    // A digest that arrived together with page errors is not a pass: the
    // scene may have rendered around a failure.
    if (errors.length > 0) {
      console.error("PAGE ERRORS (" + errors.length + "):");
      for (const e of errors.slice(0, 10)) console.error("  " + e);
      dom.window.close();
      process.exit(1);
    }
    dom.window.close();
    process.exit(0);
  }
  if (Date.now() - started > opts.timeout) {
    clearInterval(timer);
    console.error("no SHARKS_DIGEST within " + opts.timeout + " ms");
    const vp = dom.window.document.getElementById("uir-viewport");
    console.error("viewport nodes: " + (vp ? vp.querySelectorAll("*").length : "no #uir-viewport"));
    console.error("blit nodes:     " + (vp ? vp.querySelectorAll(".uir-blit").length : 0));
    if (errors.length > 0) {
      console.error("PAGE ERRORS (" + errors.length + "):");
      for (const e of errors.slice(0, 10)) console.error("  " + e);
    }
    dom.window.close();
    process.exit(1);
  }
}, 50);
