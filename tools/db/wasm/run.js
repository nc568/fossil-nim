#!/usr/bin/env node
/* Minimal host for foccil.wasm: no emscripten glue, no WASI SDK.
 * Node's built-in `wasi` shim satisfies the single import (proc_exit). */
'use strict';
const fs = require('fs');
const path = require('path');

const wasmPath = process.argv[2] || path.join(__dirname, '../../../build/db/wasm/foccil.wasm');
const mod = new WebAssembly.Module(fs.readFileSync(wasmPath));
// Import stubs: the module does no I/O, but wasi-libc's startup references a
// handful of symbols, so we satisfy them with no-ops instead of pulling in the
// whole WASI runtime.
const stub = () => 0;
const imports = {
  wasi_snapshot_preview1: new Proxy({}, {
    get: (_t, name) => (name === 'proc_exit'
      ? (c) => { throw new Error('wasm exit ' + c); }
      : stub),
  }),
};
const inst = new WebAssembly.Instance(mod, imports);
const ex = inst.exports;
const td = new TextDecoder();
const te = new TextEncoder();

function readStr(ptr) {
  const mem = new Uint8Array(ex.memory.buffer);
  let end = ptr;
  while (mem[end] !== 0) end++;
  return td.decode(mem.subarray(ptr, end));
}

/* JS strings are not auto-marshalled into wasm: allocate inside the module,
 * copy UTF-8 bytes, pass the pointer. This is the only correct way and it also
 * makes the trust boundary explicit (the host owns the buffer lifetime). */
function writeStr(str) {
  const bytes = te.encode(str + '\0');
  const ptr = ex.malloc(bytes.length);
  new Uint8Array(ex.memory.buffer, ptr, bytes.length).set(bytes);
  return ptr;
}

function exec(sql, params = '') {
  const ps = writeStr(sql);
  const pp = writeStr(params);
  ex.foccil_exec_n(ps, pp);
  const out = readStr(ex.foccil_last_ptr ? ex.foccil_last_ptr() : 0);
  ex.free(ps);
  ex.free(pp);
  return out;
}

ex.foccil_init();
console.log('module:', readStr(ex.foccil_version()));

const script = [
  ["CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT, score INT)", ''],
  ["INSERT INTO t (name, score) VALUES ('ann', 90), ('bob', 75)", ''],
  ["SELECT id, name, score FROM t ORDER BY id", ''],
  ["SELECT COUNT(*), SUM(score) FROM t", ''],
  ["SELECT name FROM t WHERE score > ?", 'i:80'],
  ["SELECT name FROM t WHERE name = ?", 's:ann'],
  ["SELECT * FROM missing_table", ''],
];

for (const [sql, p] of script) {
  console.log('---', sql);
  console.log(exec(sql, p));
}
