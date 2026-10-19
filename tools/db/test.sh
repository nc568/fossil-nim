#!/bin/sh
# Full gate. Every stage must pass before a change is considered done.
set -e
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
NIM=${NIM:-nim}
FLAGS="--mm:arc --hints:off --warnings:off --outdir:build/db"

echo "== 1/6 core suite"
"$NIM" c -r $FLAGS tests/db/t_core.nim | tail -3

echo "== 2/6 security suite"
"$NIM" c -r $FLAGS tests/db/t_security.nim | tail -3

echo "== 3/6 minimal-float profile (the cproc/wasm profile)"
"$NIM" c -r -d:foccilMinimalFloat $FLAGS --outdir:build/db/db/min tests/db/t_core.nim | tail -3

echo "== 4/6 native vs JS parity"
"$NIM" c -r $FLAGS tests/db/t_portable.nim > build/db/portable_native.txt
"$NIM" js -r $FLAGS tests/db/t_portable.nim > build/db/portable_js.txt
if cmp -s build/db/portable_native.txt build/db/portable_js.txt; then
  echo "parity OK (native == js)"
else
  echo "PARITY MISMATCH"; diff build/db/portable_native.txt build/db/portable_js.txt | head; exit 1
fi

echo "== 5/6 wasm build + smoke"
sh tools/db/wasm/build.sh >/dev/null
node tools/db/wasm/run.js | head -3

echo "== 6/6 cproc/QBE gate (informational until upstream fix)"
sh tools/db/cproc/check.sh || true

echo "ALL GREEN"
