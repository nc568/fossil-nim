#!/bin/sh
# Build Foccil DB as a freestanding wasm32 module.
#
# Toolchain: Nim (--os:standalone) + zig (clang + wasi-libc + wasm-ld).
# No emscripten, no wasi-sdk download: `zig cc -target wasm32-wasi` provides
# both the C compiler and the linker.
set -e
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
OUT=${OUT:-$ROOT/build/db/wasm}
NIM=${NIM:-nim}
ZIGCC=${ZIGCC:-zigcc}
ZIGLD=${ZIGLD:-zigld}
NIMLIB=${NIMLIB:-$("$NIM" dump --dump.format:json 2>/dev/null | sed -n 's/.*"libpath":[[:space:]]*"\([^"]*\)".*/\1/p')}
[ -z "$NIMLIB" ] && NIMLIB=$(dirname "$(command -v "$NIM")")/../lib

mkdir -p "$OUT" "$OUT/obj"
rm -f "$OUT"/obj/*.o

"$NIM" c --os:any --cpu:wasm32 --mm:arc -d:danger -d:useMalloc \
  -d:foccilNoClock -d:noSignalHandler -d:foccilMinimalFloat --hints:off --warnings:off \
  --cc:clang --clang.exe:"$ZIGCC" --clang.linkerexe:"$ZIGLD" \
  --nimcache:"$OUT/nimcache" --compileOnly \
  "$ROOT/src/fossil/wasm/bridge.nim"

for f in "$OUT"/nimcache/*.c; do
  "$ZIGCC" -target wasm32-wasi -Oz -fno-builtin -I "$OUT/nimcache" -I "$NIMLIB" \
    -c -o "$OUT/obj/$(basename "$f").o" "$f"
done

"$ZIGLD" -target wasm32-wasi -O2 -o "$OUT/foccil.wasm" \
  -Wl,--export=foccil_version -Wl,--export=foccil_init \
  -Wl,--export=foccil_exec -Wl,--export=foccil_exec_n \
  -Wl,--export=foccil_last_len -Wl,--export=foccil_last_ptr \
  -Wl,--export=malloc -Wl,--export=free \
  -Wl,--gc-sections -Wl,--strip-all \
  "$OUT"/obj/*.o

echo "built $OUT/foccil.wasm ($(wc -c < "$OUT/foccil.wasm") bytes)"
