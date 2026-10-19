#!/bin/sh
# Print the toolchain the gate is running on, and fail if it is not the pinned
# one. Versions are facts here, not prose: a gate result is only meaningful for
# a known compiler set.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/versions.env"
TC=${TC:-$HOME/.cache/tc}
NIM=${NIM:-$TC/nim-2.2.12/bin/nim}
[ -x "$NIM" ] || NIM=nim
bad=0

nimver=$("$NIM" --version 2>/dev/null | head -1 | sed -n 's/.*Version \([0-9.]*\).*/\1/p')
[ "$nimver" = "$NIM_VERSION" ] || { echo "MISMATCH nim: found '${nimver:-none}', pinned $NIM_VERSION"; bad=1; }

# QBE prints no version, so build.sh stamps the tree it built from. Fall back to
# the directory name if there is no stamp.
qbe=$(cat "$TC/qbe-1.3/.foccil-version" 2>/dev/null)
[ -z "$qbe" ] && qbe=$(sed -n 's/.*-\([0-9][0-9.]*\)$/\1/p' <<EOF2
$TC/qbe-1.3
EOF2
)
[ -z "$qbe" ] && qbe=$(basename "$TC"/qbe-* 2>/dev/null | head -1 | sed 's/qbe-//')
[ "$qbe" = "$QBE_VERSION" ] || { echo "MISMATCH qbe: found '${qbe:-none}', pinned $QBE_VERSION"; bad=1; }

cproc=$(cat "$TC/cproc/.foccil-commit" 2>/dev/null | cut -c1-7)
[ "$cproc" = "$CPROC_COMMIT" ] || { echo "MISMATCH cproc: found '${cproc:-unknown}', pinned $CPROC_COMMIT"; bad=1; }

musl=$(cat "$TC/musl/.foccil-version" 2>/dev/null)
[ "$musl" = "$MUSL_VERSION" ] || { echo "MISMATCH musl: found '${musl:-none}', pinned $MUSL_VERSION"; bad=1; }

echo "nim=$nimver qbe=$qbe cproc=$cproc musl=$musl"
exit $bad
