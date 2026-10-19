#!/bin/sh
# Build the toolchain used by the cproc compatibility gate.
#   qbe   - the QBE backend compiler  (1.3, NOT 1.2 — see below)
#   cproc - a C11 compiler that emits QBE IL
#   musl  - libc that cproc is designed against (glibc headers use GNU
#           extensions cproc cannot parse)
#
# The QBE version is a hard requirement, not a preference: cproc (>= d1c53dd)
# emits `extern $g` for globals with external linkage, which is QBE 1.3 syntax.
# With QBE 1.2 the toolchain builds fine and then fails on every unit that
# touches an extern global — 18 of 22 for this engine — with a message that
# names neither cproc nor a version. We paid for that once, hence the probe.
set -e
TC=${TC:-$HOME/.cache/tc}
mkdir -p "$TC"; cd "$TC"

[ -d qbe-1.3 ] || { curl -sSLO https://c9x.me/compile/release/qbe-1.3.tar.xz; tar xf qbe-1.3.tar.xz; }
[ -x qbe-1.3/qbe ] || { cd qbe-1.3; make -j"$(nproc)"; cd ..; }

[ -d cproc-src ] || git clone --depth 1 https://github.com/michaelforney/cproc.git cproc-src
if [ ! -x "$TC/cproc/bin/cproc" ]; then
  cd cproc-src
  PATH="$TC/qbe-1.3:$PATH" ./configure --prefix="$TC/cproc"
  PATH="$TC/qbe-1.3:$PATH" make -j"$(nproc)"
  PATH="$TC/qbe-1.3:$PATH" make install
  cd ..
fi

[ -d musl-1.2.5 ] || { curl -sSLO https://musl.libc.org/releases/musl-1.2.5.tar.gz; tar xf musl-1.2.5.tar.gz; }
if [ ! -f "$TC/musl/lib/libc.a" ]; then
  cd musl-1.2.5
  ./configure --prefix="$TC/musl" --disable-shared
  make -j"$(nproc)" && make install
  cd ..
fi
# refuse a QBE that cannot parse cproc's output
printf 'export function w $f() {\n@start\n\t%%r =w loadw extern $probe\n\tret %%r\n}\n' > /tmp/qbe_probe.ssa
if ! "$TC/qbe-1.3/qbe" -o /dev/null /tmp/qbe_probe.ssa 2>/dev/null; then
  echo "qbe at $TC/qbe-1.3 does not understand 'extern data': cproc needs QBE >= 1.3"; exit 1
fi
rm -f /tmp/qbe_probe.ssa

echo "qbe=$(ls "$TC/qbe-1.3/qbe") cproc=$TC/cproc/bin/cproc musl=$TC/musl"
echo "note: the gate also patches two stdlib files; run tools/db/cproc/check.sh"
