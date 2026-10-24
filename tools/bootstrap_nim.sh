#!/bin/sh
# Get a working Nim 2.2+ toolchain onto PATH.
#
# The test suite needs nothing but Nim, node and npm -- but a fresh clone has
# no Nim in it, and D12 was precisely the complaint that these tests could not
# be reproduced on a clean checkout. So this script is the documented answer:
# run it once, then run the tests.
#
#   sh tools/bootstrap_nim.sh            # builds into ~/.local/nim-2.2.4
#   sh tools/bootstrap_nim.sh /some/dir  # builds somewhere else
#   NIM=/path/to/nim nim c -r tests/...  # or just point the tests at your own
#
# If a suitable Nim is already on PATH it prints the path and does nothing, so
# it is safe to run in CI on every build.
set -e

WANT_MAJOR=2
WANT_MINOR=2
VERSION=2.2.4

dest="${1:-$HOME/.local/nim-$VERSION}"

have_nim() {
  # $1 = candidate nim binary. Echoes "ok" when it is new enough.
  [ -x "$1" ] || return 1
  v=$("$1" --version 2>/dev/null | head -1 | sed -e 's/.*Version //' -e 's/ .*//')
  # Anything that is not a Nim compiler prints something that is not a version
  # number; reject it quietly instead of feeding it to the shell's arithmetic.
  case "$v" in
    *[!0-9.]*) return 1 ;;
    "" ) return 1 ;;
  esac
  major=$(echo "$v" | cut -d. -f1)
  minor=$(echo "$v" | cut -d. -f2)
  [ -n "$major" ] && [ -n "$minor" ] || return 1
  [ "$major" -gt "$WANT_MAJOR" ] 2>/dev/null && { echo "ok"; return 0; }
  [ "$major" -eq "$WANT_MAJOR" ] 2>/dev/null && [ "$minor" -ge "$WANT_MINOR" ] 2>/dev/null && { echo "ok"; return 0; }
  return 1
}

# 1. An explicit NIM= wins: the test wrappers all honour it.
if [ -n "$NIM" ]; then
  if have_nim "$NIM"; then
    echo "$NIM"
    exit 0
  fi
  echo "bootstrap_nim: NIM=$NIM is not a Nim $WANT_MAJOR.$WANT_MINOR+ compiler" >&2
  exit 1
fi

# 2. Then whatever is already installed.
for cand in nim "$dest/bin/nim"; do
  found=$(command -v "$cand" 2>/dev/null || echo "$cand")
  if have_nim "$found"; then
    echo "$found"
    exit 0
  fi
done

# 3. Nothing usable, so build one. Nim ships its own bootstrap: csources_v2 is
#    a C snapshot of an older compiler that builds the current one. Needs a C
#    compiler, git, and reachability of github.com.
echo "bootstrap_nim: no Nim $WANT_MAJOR.$WANT_MINOR+ found; building $VERSION into $dest" >&2
for tool in git gcc; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "bootstrap_nim: $tool is required to build Nim from source" >&2
    exit 1
  }
done

src="$dest-src"
mkdir -p "$src"
cd "$src"

if [ ! -d Nim/.git ]; then
  git clone --depth 1 --branch "v$VERSION" https://github.com/nim-lang/Nim Nim
fi
cd Nim

if [ ! -d csources_v2 ]; then
  git clone --depth 1 https://github.com/nim-lang/csources_v2 csources_v2
fi

# The bootstrap compiler. ~2 minutes, no network after the clones.
(cd csources_v2 && sh build.sh >/dev/null)

# `koch boot` builds the real compiler from Nim sources and verifies it is
# reproducible ("executables are equal: SUCCESS!"). Note: `--skipCleanup` is
# not a valid option in 2.2.x and makes koch fail.
PATH="$src/Nim/bin:$PATH" ./koch boot -d:release >/dev/null

mkdir -p "$(dirname "$dest")"
if [ "$src/Nim" != "$dest" ]; then
  rm -rf "$dest"
  cp -a "$src/Nim" "$dest"
fi

if have_nim "$dest/bin/nim"; then
  echo "$dest/bin/nim"
  echo "bootstrap_nim: add this to your PATH:" >&2
  echo "  export PATH=\"$dest/bin:\$PATH\"" >&2
else
  echo "bootstrap_nim: the build finished but $dest/bin/nim is not usable" >&2
  exit 1
fi
