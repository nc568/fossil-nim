#!/bin/sh
# The whole gate, one command.
#
#   sh tools/db/test.sh          # everything (~3 min)
#   sh tools/db/test.sh --quick  # skip the slow stress stages (~40 s)
#
# Every stage runs, even if an earlier one fails: a run reports the state of
# the whole tree, not the state up to the first problem. Exit status is
# non-zero if any stage failed. Per-stage logs: build/test/<stage>.log
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
TC=${TC:-$HOME/.cache/tc}
OUT=build/test
NIM=${NIM:-$TC/nim-2.2.12/bin/nim}
PATH="$TC/nim-2.2.12/bin:$TC/qbe-1.3:$PATH"
export PATH
FLAGS="--mm:arc --hints:off --warnings:off --skipParentCfg:on --path:src"
QUICK=0
[ "${1:-}" = "--quick" ] && QUICK=1

rm -rf "$OUT"; mkdir -p "$OUT" build/db
FAILED=0

# ---- stage implementations -------------------------------------------------
nimrun() { "$NIM" c -r $FLAGS --outdir:build/db "tests/db/$1.nim"; }

parity() {
  "$NIM" c -r $FLAGS --outdir:build/db tests/db/t_portable.nim > "$OUT/portable_native.txt" 2>&1
  "$NIM" js -r $FLAGS --outdir:build/db tests/db/t_portable.nim > "$OUT/portable_js.txt" 2>&1
  if cmp -s "$OUT/portable_native.txt" "$OUT/portable_js.txt"; then
    echo "native and JS agree byte for byte"; return 0
  fi
  echo "PARITY MISMATCH"; diff "$OUT/portable_native.txt" "$OUT/portable_js.txt" | head -20
  return 1
}

wasm() { sh tools/db/wasm/build.sh && node tools/db/wasm/run.js; }
difftest() { sh tools/db/difftest/run.sh; }
cprocgate() { sh tools/db/cproc/check.sh; }
stress_btree() { "$NIM" c -r $FLAGS --outdir:build/db tools/db/stress_btree.nim; }
crash_fuzz() { "$NIM" c $FLAGS --outdir:build/db tools/db/crash_fuzz.nim && ./build/db/crash_fuzz 50; }
crash_fuzz_engine() { "$NIM" c $FLAGS --outdir:build/db tools/db/crash_fuzz_engine.nim && ./build/db/crash_fuzz_engine 60; }

# ---- runner ----------------------------------------------------------------
run() {
  name=$1; shift
  start=$(date +%s)
  if "$@" > "$OUT/$name.log" 2>&1; then ok=0; else ok=1; FAILED=1; fi
  secs=$(( $(date +%s) - start ))
  if [ $ok -eq 0 ]; then
    detail=$(grep -c '\[OK\]' "$OUT/$name.log" 2>/dev/null)
    [ -z "$detail" ] && detail=0
    if [ "$detail" = "0" ]; then
      # no unittest counters (wasm, parity, difftest): show the line that says
      # what was achieved, not the last line, which is often an expected error
      detail=$(grep -m1 -E '^module:|agree byte|queries match|^PASS:' "$OUT/$name.log" \
               | cut -c1-58)
      [ -z "$detail" ] && detail=$(tail -1 "$OUT/$name.log" | cut -c1-58)
    fi
    printf '  \033[32mPASS\033[0m %-14s %3ss  %s\n' "$name" "$secs" "$detail"
    printf '%s|pass|%s\n' "$name" "$secs" >> "$OUT/summary.txt"
  else
    printf '  \033[31mFAIL\033[0m %-14s %3ss  %s\n' "$name" "$secs" \
      "$(grep -m1 -E '\[FAILED\]|Error:|error:|qbe:|PARITY|Traceback|assert' "$OUT/$name.log" | cut -c1-80)"
    printf '%s|fail|%s\n' "$name" "$secs" >> "$OUT/summary.txt"
  fi
}

echo
echo "Foccil DB — full gate ($([ $QUICK -eq 1 ] && echo quick || echo full))"
echo "----------------------------------------------------------------"

echo "0. toolchain"
run versions sh tools/db/cproc/versions.sh

echo "1. unit suites"
for t in t_core t_security t_storage t_wal t_btree t_crash t_crypto t_corrupt t_disk; do
  run "$t" nimrun "$t"
done

echo "2. minimal-float profile (the cproc/wasm profile)"
run minfloat "$NIM" c -r $FLAGS -d:foccilMinimalFloat --outdir:build/db tests/db/t_core.nim

echo "3. JavaScript backend"
run t_crypto_js "$NIM" js -r $FLAGS --outdir:build/db tests/db/t_crypto.nim
run parity_js parity

echo "4. wasm32"
run wasm wasm

echo "5. differential testing against real SQLite"
run difftest difftest

echo "6. cproc → QBE → musl"
run cproc cprocgate

if [ $QUICK -eq 0 ]; then
  echo "7. stress and crash fuzzing"
  run stress_btree stress_btree
  run crash_fuzz crash_fuzz
  run crash_fuzz_engine crash_fuzz_engine
fi

echo "----------------------------------------------------------------"
if [ $FAILED -eq 0 ]; then
  printf '\033[32mALL GREEN\033[0m — %s stages\n' "$(wc -l < "$OUT/summary.txt")"
else
  printf '\033[31mFAILURES\033[0m in: %s\n' "$(grep '|fail|' "$OUT/summary.txt" | cut -d'|' -f1 | tr '\n' ' ')"
  printf 'logs: %s/\n' "$OUT"
fi
exit $FAILED
