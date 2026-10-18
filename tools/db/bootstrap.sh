#!/bin/sh
# Reproducible toolchain for the sandbox / CI.
#
#   ~/.cache/tc/nim-2.2.12        Nim
#   ~/.cache/tc/qbe-1.2           QBE
#   ~/.cache/tc/cproc             cproc
#   ~/.cache/tc/musl              musl (cproc's reference libc)
#   ~/.cache/tc/zig-linux-x86_64  zig (clang + wasm-ld + wasi-libc)
#   ~/.cache/tc/zigcc, zigld      wrappers so Nim can drive zig as a C compiler
#
# Nothing is installed system-wide; everything lives in the user cache.
set -e
TC=${TC:-$HOME/.cache/tc}
mkdir -p "$TC"
cd "$TC"

if [ ! -x "$TC/nim-2.2.12/bin/nim" ]; then
  curl -sSLO https://nim-lang.org/download/nim-2.2.12-linux_x64.tar.xz
  tar xf nim-2.2.12-linux_x64.tar.xz
fi

if [ ! -x "$TC/zig-linux-x86_64-0.13.0/zig" ]; then
  curl -sSLO https://ziglang.org/download/0.13.0/zig-linux-x86_64-0.13.0.tar.xz
  tar xf zig-linux-x86_64-0.13.0.tar.xz
fi
cat > "$TC/zigcc" <<W
#!/bin/sh
exec "$TC/zig-linux-x86_64-0.13.0/zig" cc "\$@"
W
cat > "$TC/zigld" <<W
#!/bin/sh
exec "$TC/zig-linux-x86_64-0.13.0/zig" cc "\$@"
W
chmod +x "$TC/zigcc" "$TC/zigld"

# --- upstream workaround -----------------------------------------------------
# Nim 2.2.12: `lib/system/arc.nim` references `emulatedThreadVars`, which is not
# imported on freestanding targets (wasm), so `--mm:arc --os:any --cpu:wasm32`
# fails to compile. One-line patch, idempotent, applies only once.
ARCNIM="$TC/nim-2.2.12/lib/system/arc.nim"
if grep -q '^elif emulatedThreadVars:' "$ARCNIM" 2>/dev/null; then
  cp "$ARCNIM" "$ARCNIM.orig"
  sed -i 's/^elif emulatedThreadVars:/elif compileOption("tlsEmulation"):/' "$ARCNIM"
  echo "patched arc.nim (wasm/ARC)"
fi

[ -x "$TC/cproc/bin/cproc" ] || sh "$(dirname "$0")/cproc/build.sh"

echo "toolchain ready in $TC"
