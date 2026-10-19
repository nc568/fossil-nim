#!/bin/sh
# cproc/QBE compatibility gate.
#
# Goal: `nim c` output must be compilable by cproc, and then by QBE.
# Status is measured, never assumed: this script compiles every generated C
# translation unit with cproc and classifies the failures by root cause.
#
# What the gate deliberately changes, and why (all of it is shimmed *around*
# the engine, never inside it):
#
#   nimbase.h   cproc implements C11 without GNU extensions; nimbase assumes
#               GCC. A prelude fills in `__CHAR_BIT__` etc. and switches off
#               `__attribute__`; a postlude makes NIM_CONST empty, because
#               cproc rejects the const-void* casts Nim emits for const globals
#               passed by pointer (the objects are never written either way).
#   stdlib      three constructs cproc cannot parse live in Nim's own standard
#               library, and `import std/x` resolves *past* the search path, so
#               they cannot be shadowed from the project (patchFile() does not
#               apply to std/ imports either). shimgen.py rewrites the two
#               stdlib files in the installed toolchain, keeping .foccil-orig
#               backups and deriving every time from those backups, so the
#               change is idempotent and revertible. The engine source is not
#               touched.
#
# Usage: sh tools/db/cproc/check.sh
set -e
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
HERE=$ROOT/tools/db/cproc
TC=${TC:-$HOME/.cache/tc}
OUT=$ROOT/build/cproc
NIM=${NIM:-nim}
ENTRY=${ENTRY:-$ROOT/src/fossil/wasm/bridge.nim}
CPROC=$TC/cproc/bin/cproc
MUSL=$TC/musl
QBE=${QBE:-$TC/qbe-1.3}

[ -x "$CPROC" ] || { echo "missing cproc; run tools/db/cproc/build.sh"; exit 2; }
[ -d "$QBE" ] || { echo "missing qbe (expected $QBE); run tools/db/cproc/build.sh"; exit 2; }

rm -rf "$OUT/nc" "$OUT/probe"; mkdir -p "$OUT/probe"
# 0) is this the toolchain the gate was calibrated on?
sh "$HERE/versions.sh"

# 1) stdlib shims, derived from the Nim that will do the codegen, and applied
#    to the installed toolchain (see the header comment for why)
python3 "$HERE/shimgen.py" "$HERE/shim" --install

# 2) cproc-compatible nimbase.h: prelude + the stock header with the two
#    non-standard inline spellings flattened + postlude.
cat "$HERE/nimbase_cproc.h" > "$OUT/probe/nimbase.h"
NIMLIB=$(dirname "$(command -v "$NIM")")/../lib
sed -e 's/^#include "nimbase.h"//' \
    -e 's/#  define N_INLINE(rettype, name) rettype __inline name/#  define N_INLINE(rettype, name) inline rettype name/' \
    "$NIMLIB/nimbase.h" >> "$OUT/probe/nimbase.h"
cat >> "$OUT/probe/nimbase.h" <<'EOF'
/* cproc rejects `T *p = &constGlobal` even where C allows the qualification
 * drop, and Nim emits exactly that for every const global passed by pointer
 * (RTTI tables, const sets, default parameter values). Making NIM_CONST empty
 * moves those objects from .rodata to .data: no semantic change, since the
 * engine never writes them, and 7 of 22 units start compiling. */
#undef NIM_CONST
#define NIM_CONST
EOF

# 3) generate C the same way the native build does (--skipParentCfg keeps the
#    repo-root config.nims, which links sqlite3 for the test builds, out)
"$NIM" c --os:any --cpu:amd64 --mm:arc -d:danger -d:useMalloc \
  -d:noSignalHandler -d:foccilNoClock -d:foccilMinimalFloat --hints:off --warnings:off \
  --cc:gcc --skipParentCfg:on --nimcache:"$OUT/nc" --compileOnly "$ENTRY"

# 4) compile every unit with cproc against musl headers
total=0; ok=0
: > "$OUT/failures.txt"
for f in "$OUT"/nc/*.c; do
  total=$((total+1))
  if PATH="$QBE:$PATH" "$CPROC" -std=c11 -O1 -nostdinc -isystem "$MUSL/include" \
       -I "$OUT/probe" -I "$HERE/shim" -I "$OUT/nc" -c -o "$OUT/tmp.o" "$f" \
       >"$OUT/err.log" 2>&1; then
    ok=$((ok+1))
  else
    printf '%s\t%s\n' "$(basename "$f")" "$(head -1 "$OUT/err.log" | cut -c1-200)" \
      >> "$OUT/failures.txt"
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
# 5) end to end: build a real program with cproc, link it with musl, run it.
#    A green compile that produces a binary which does not work is not a gate.
SMOKE=$ROOT/tools/db/cproc/smoke.nim
"$NIM" c --os:any --cpu:amd64 --mm:arc -d:danger -d:useMalloc \
  -d:noSignalHandler -d:foccilNoClock -d:foccilMinimalFloat --hints:off --warnings:off \
  --cc:gcc --skipParentCfg:on --path:"$ROOT/src" --nimcache:"$OUT/smoke_nc" \
  --compileOnly "$SMOKE"
rm -rf "$OUT/smoke_obj"; mkdir -p "$OUT/smoke_obj"
for f in "$OUT"/smoke_nc/*.c; do
  PATH="$QBE:$PATH" "$CPROC" -std=c11 -O1 -nostdinc -isystem "$MUSL/include" \
    -I "$OUT/probe" -I "$HERE/shim" -I "$OUT/smoke_nc" -c \
    -o "$OUT/smoke_obj/$(basename "$f" .c).o" "$f" >"$OUT/err.log" 2>&1 || {
      echo "FAIL (link stage): $(basename "$f"): $(head -1 "$OUT/err.log")"; exit 1; }
done
"$MUSL/bin/musl-gcc" -static -o "$OUT/smoke" "$OUT"/smoke_obj/*.o
EXPECTED='1 alpha 1.5
2 beta 2.25
3 gamma 0.5
count=3 max=2.25
smoke: ok'
ACTUAL=$("$OUT/smoke")
if [ "$ACTUAL" != "$EXPECTED" ]; then
  echo "FAIL: the cproc-built binary ran but printed the wrong thing:"
  printf '%s\n' "$ACTUAL"
  echo "--- expected:"; printf '%s\n' "$EXPECTED"
  exit 1
fi
echo "PASS: cproc->QBE->musl binary compiles, links and runs correctly"
