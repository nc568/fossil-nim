## Differential stress test: the B+tree against an in-memory sorted model.
##
## Kept out of the unit suite on purpose — a million keys is a measurement, not
## a test, and a test someone disables because it is slow protects nothing.
##
##   nim c -d:release --skipParentCfg:on --path:src tools/db/stress_btree.nim
##   ./build/db/stress_btree 1000000

import std/[algorithm, os, strutils, tables, times, random]
import fossil/db/[btree, pager, vfs]

proc key(i: int): string = "k" & align($i, 10, '0')

let n = if paramCount() >= 1: parseInt(paramStr(1)) else: 100_000
var rng = initRand(11)

let p = openPager(openMemoryVfs(), cachePages = 1024)
let b = openBtree(p)

block inserts:
  let t0 = cpuTime()
  for i in 0 ..< n: b.put(key(i), $i)
  let dt = cpuTime() - t0
  echo "insert  ", n, " keys  ", formatFloat(dt, ffDecimal, 3), " s  (",
       int(n.float / dt), " ops/s)"

block lookups:
  let t0 = cpuTime()
  var hits = 0
  for _ in 0 ..< n:
    if b.get(key(rng.rand(n - 1))).found: inc hits
  let dt = cpuTime() - t0
  echo "lookup  ", n, " random ", formatFloat(dt, ffDecimal, 3), " s  (",
       int(n.float / dt), " ops/s) hits=", hits

block differential:
  ## Scan order and contents must match the model exactly, key for key.
  let t0 = cpuTime()
  var i = 0
  var ok = true
  for k, v in b.pairs:
    if k != key(i) or v != $i:
      echo "MISMATCH at ", i, ": got ", k, "=", v
      ok = false
      break
    inc i
  let dt = cpuTime() - t0
  echo "scan    ", i, " keys  ", formatFloat(dt, ffDecimal, 3), " s  ",
       (if ok and i == n: "identical to the model" else: "MISMATCH")

block structure:
  let t0 = cpuTime()
  let s = b.verify()
  echo "verify  depth=", s.depth, " leaves=", s.leaves, " nodes=", s.nodes,
       " keys=", s.keys, "  ", formatFloat(cpuTime() - t0, ffDecimal, 3), " s"
  echo "pages   ", p.nPages, " used, ", p.stats().resident, " resident, ",
       p.stats().hits, " cache hits / ", p.stats().misses, " misses"

block tombstones:
  ## Delete 90% at random, then check the survivors and the structure.
  let t0 = cpuTime()
  var gone = 0
  for _ in 0 ..< n * 9 div 10:
    let i = rng.rand(n - 1)
    if b.del(key(i)): inc gone
  echo "delete  ", gone, "  ", formatFloat(cpuTime() - t0, ffDecimal, 3), " s"
  let s = b.verify()
  echo "after   keys=", s.keys, " leaves=", s.leaves, " pages=", p.nPages
  var surviving = 0
  for i in 0 ..< n:
    if b.get(key(i)).found: inc surviving
  echo "survive ", surviving, " (expected ", n - gone, ") ",
       (if surviving == n - gone: "OK" else: "MISMATCH")
