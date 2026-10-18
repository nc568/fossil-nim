#!/bin/sh
# Build the QBE toolchain used by the cproc compatibility gate.
#   qbe   - the QBE backend compiler
#   cproc - a C11 compiler that emits QBE IL
#   musl  - libc that cproc is designed against (glibc headers use GNU
#           extensions cproc cannot parse)
set -e
TC=${TC:-$HOME/.cache/tc}
mkdir -p "$TC"; cd "$TC"

[ -d qbe-1.2 ] || { curl -sSLO https://c9x.me/compile/release/qbe-1.2.tar.xz; tar xf qbe-1.2.tar.xz; }
[ -x qbe-1.2/qbe ] || { cd qbe-1.2; make -j"$(nproc)"; cd ..; }

[ -d cproc-src ] || git clone --depth 1 https://github.com/michaelforney/cproc.git cproc-src
if [ ! -x "$TC/cproc/bin/cproc" ]; then
  cd cproc-src
  PATH="$TC/qbe-1.2:$PATH" ./configure --prefix="$TC/cproc"
  PATH="$TC/qbe-1.2:$PATH" make -j"$(nproc)"
  PATH="$TC/qbe-1.2:$PATH" make install
  cd ..
fi

[ -d musl-1.2.5 ] || { curl -sSLO https://musl.libc.org/releases/musl-1.2.5.tar.gz; tar xf musl-1.2.5.tar.gz; }
if [ ! -f "$TC/musl/lib/libc.a" ]; then
  cd musl-1.2.5
  ./configure --prefix="$TC/musl" --disable-shared
  make -j"$(nproc)" && make install
  cd ..
fi
echo "qbe=$(ls "$TC/qbe-1.2/qbe") cproc=$TC/cproc/bin/cproc musl=$TC/musl"
