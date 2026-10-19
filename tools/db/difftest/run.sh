#!/bin/sh
# Differential corpus: Foccil DB vs the real SQLite.
#
# The point is not that both engines agree on what they implement — it is that
# every disagreement is *known*. A query added here without a matching entry in
# known-divergences.md is a query nobody has thought about.
set -e
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
OUT=$ROOT/build/difftest
mkdir -p "$OUT"
cd "$ROOT"
NIM=${NIM:-nim}
"$NIM" c --skipParentCfg:on --mm:arc --hints:off --warnings:off \
    --path:src --outdir:"$OUT/bin" tools/db/difftest/runner.nim
"$OUT/bin/runner" tools/db/difftest > "$OUT/foccil.txt"
python3 tools/db/difftest/reference.py tools/db/difftest > "$OUT/sqlite.txt"
total=$(wc -l < "$OUT/sqlite.txt" | tr -d ' ')
if diff -u "$OUT/sqlite.txt" "$OUT/foccil.txt" > "$OUT/diff.txt"; then
  echo "difftest: $total/$total queries match SQLite"
else
  bad=$(grep -c '^<q' "$OUT/diff.txt" || true)
  echo "difftest: $bad of $total queries differ — see $OUT/diff.txt"
  grep '^[-+]q' "$OUT/diff.txt" | head -20
  exit 1
fi
