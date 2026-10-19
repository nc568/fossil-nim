#!/bin/sh
# cproc/QBE compatibility gate.
#
# Goal: `nim c` output must be compilable by cproc (and then by QBE).
# Status is measured, never assumed: this script compiles every generated C
# translation unit with cproc and classifies the failures by root cause.
#
# Usage: sh tools/db/cproc/check.sh [entry.nim]
set -e
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TC=${TC:-$HOME/.cache/tc}
ENTRY=${1:-$ROOT/src/fossil/wasm/bridge.nim}
OUT=$ROOT/build/cproc
NIM=${NIM:-nim}
CPROC=$TC/cproc/bin/cproc
MUSL=$TC/musl

[ -x "$CPROC" ] || { echo "missing cproc; run tools/db/cproc/build.sh"; exit 2; }

rm -rf "$OUT/shim" "$OUT/nc"; mkdir -p "$OUT/shim"
# 1) cproc-compatible nimbase.h: prelude + the stock header with the two
#    non-standard inline spellings flattened.
cat "$ROOT/tools/db/cproc/nimbase_cproc.h" > "$OUT/shim/nimbase.h"
sed -e 's/^#include "nimbase.h"//' \
    -e 's/#  define N_INLINE(rettype, name) rettype __inline name/#  define N_INLINE(rettype, name) inline rettype name/' \
    "$(dirname "$(command -v "$NIM")")/../lib/nimbase.h" >> "$OUT/shim/nimbase.h"

# 2) generate C the same way the native build does
"$NIM" c --os:any --cpu:amd64 --mm:arc -d:danger -d:useMalloc \
  -d:noSignalHandler -d:foccilNoClock -d:foccilMinimalFloat --hints:off --warnings:off \
  --cc:gcc --nimcache:"$OUT/nc" --compileOnly "$ENTRY"

# 3) compile every unit with cproc against musl headers
export PATH="$TC/qbe-1.2:$PATH"
total=0; ok=0
: > "$OUT/failures.txt"
for f in "$OUT"/nc/*.c; do
  total=$((total+1))
  if "$CPROC" -std=c11 -O1 -nostdinc -isystem "$MUSL/include" \
       -I "$OUT/shim" -I "$OUT/nc" -c -o "$OUT/tmp.o" "$f" >"$OUT/err.log" 2>&1; then
    ok=$((ok+1))
  else
    printf '%s\t%s\n' "$(basename "$f")" "$(head -1 "$OUT/err.log" | cut -c1-200)" >> "$OUT/failures.txt"
  fi
done

echo "cproc gate: $ok/$total translation units compiled"
if [ -s "$OUT/failures.txt" ]; then
  echo "--- failures grouped by root cause:"
  cut -f2 "$OUT/failures.txt" | sed -e 's/.*error: //' -e 's/.*qbe:-[0-9]*: //' \
    | sort | uniq -c | sort -rn | head -12
  echo "--- details: $OUT/failures.txt"
  exit 1
fi
echo "PASS: the whole engine compiles with cproc -> QBE"
