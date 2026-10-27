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
  # $1 = candidate nim binary. Returns 0 when it is a Nim $WANT_MAJOR.$WANT_MINOR+
  # compiler. Must not write to stdout: this script's stdout is a contract --
  # it prints the path to a usable nim and nothing else, so callers can do
  # `nim=$(sh tools/bootstrap_nim.sh)`.
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
  [ "$major" -gt "$WANT_MAJOR" ] 2>/dev/null && return 0
  [ "$major" -eq "$WANT_MAJOR" ] 2>/dev/null && [ "$minor" -ge "$WANT_MINOR" ] 2>/dev/null && return 0
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

# The bootstrap compiler: a C snapshot of an older Nim. ~2 minutes, no network
# after the clone. Both the clone and the build are skipped when bin/nim is
# already there, so re-running this script is cheap -- and so is re-running it
# after the csources_v2 pruning below has removed that 1.8 GB again.
if [ ! -x bin/nim ]; then
  if [ ! -d csources_v2 ]; then
    git clone --depth 1 https://github.com/nim-lang/csources_v2 csources_v2
  fi
  (cd csources_v2 && sh build.sh >/dev/null)
fi

# csources builds `bin/nim` and nothing else. `koch` is not a shell script in
# 2.2.x -- it is a Nim program that has to be compiled before it can be run,
# and forgetting this step fails with a bare "./koch: not found". These are the
# flags Nim's own build_all.sh uses.
if [ ! -x ./koch ]; then
  ./bin/nim c --noNimblePath --skipUserCfg --skipParentCfg --hints:off koch >/dev/null
fi

# `koch boot` builds the real compiler from Nim sources and verifies it is
# reproducible ("executables are equal: SUCCESS!"). Note: `--skipCleanup` is
# not a valid option in 2.2.x and makes koch fail.
PATH="$src/Nim/bin:$PATH" ./koch boot -d:release --skipUserCfg --skipParentCfg --hints:off >/dev/null

# csources_v2 is 1.8 GB of generated C that only existed to produce the
# bootstrap compiler, and nimcache is another 58 MB of build scratch. Neither
# is needed to run Nim, and keeping them makes any cache of this directory
# (which is what CI does) twenty times bigger than the toolchain itself.
# Removing them is safe: once bin/nim exists this script never rebuilds.
rm -rf csources_v2 nimcache

mkdir -p "$(dirname "$dest")"
if [ "$src/Nim" != "$dest" ]; then
  rm -rf "$dest"
  cp -a "$src/Nim" "$dest"
fi
# The upstream git metadata is of no use to an installed toolchain either.
rm -rf "$dest/.git"

if have_nim "$dest/bin/nim"; then
  echo "$dest/bin/nim"
  echo "bootstrap_nim: add this to your PATH:" >&2
  echo "  export PATH=\"$dest/bin:\$PATH\"" >&2
else
  echo "bootstrap_nim: the build finished but $dest/bin/nim is not usable" >&2
  exit 1
fi
