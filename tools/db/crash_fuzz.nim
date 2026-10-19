## 1000-iteration crash fuzzer (task K9L-46).
##
##   nim c -d:release --skipParentCfg:on --path:src tools/db/crash_fuzz.nim
##   ./build/db/crash_fuzz 1000
##
## Each iteration: a deterministic workload, a random crash point inside the
## bytes it writes, then a restart from exactly what survived. The verdict is
## counted, not asserted, so a failure tells you how many cases were reached
## before it — a fuzzer that dies on the first iteration tells you nothing about
## the other 999.

import std/[os, random, strutils, tables]
import fossil/db/[btree, errors, pager, store, vfs, wal]

const MaxKey = 40

proc key(i: int): string = "k" & align($i, 7, '0')

type
  Run = object
    durable: Table[string, string]
    inflight: Table[string, string]
    committed: int
    crashed: bool
    dbBytes, walBytes: string

proc workload(seed, crashAt: int): Run =
  var rng = initRand(seed)
  let dbVfs = openMemoryVfs()
  let walVfs = openMemoryVfs()
  if crashAt > 0:
    dbVfs.crashAt = crashAt
    walVfs.crashAt = crashAt
  let s = openStore(dbVfs, walVfs, cachePages = 8)
  var b = openBtree(s.p)
  var n = 0
  for txn in 0 ..< 6:
    var pending = initTable[string, string]()
    for _ in 0 ..< 8:
      let kk = key(rng.rand(MaxKey))
      let vv = $seed & ":" & $txn & ":" & $n
      b.put(kk, vv)
      pending[kk] = vv
      inc n
    if dbVfs.dead or walVfs.dead:
      result.crashed = true
      result.inflight = pending
      break
    s.commit()
    if dbVfs.dead or walVfs.dead:
      result.crashed = true
      result.inflight = pending
      break
    for kk in pending.keys: result.durable[kk] = b.get(kk).val
    inc result.committed
    if txn mod 2 == 1:
      s.checkpoint()
      if dbVfs.dead or walVfs.dead:
        result.crashed = true
        break
  result.dbBytes = dbVfs.snapshot()
  result.walBytes = walVfs.snapshot()
  if not result.crashed:
    s.p.close()
    s.w.close()

proc verify(o: Run): string =
  ## Empty string means "this crash was handled correctly".
  let dbVfs = reopenFrom(openMemoryVfs(), o.dbBytes)
  let walVfs = reopenFrom(openMemoryVfs(), o.walBytes)
  var s: Store
  var b: Btree
  try:
    s = openStore(dbVfs, walVfs, cachePages = 8)
    b = openBtree(s.p)
  except DbError as e:
    return "opened but unreadable: " & e.msg
  defer:
    s.p.close()
    s.w.close()

  try:
    discard b.verify()
  except DbError as e:
    return "structure broken: " & e.msg

  for kk, v in o.durable:
    let got = b.get(kk)
    if not got.found: return "lost committed key " & kk
    if got.val != v: return "committed key " & kk & " changed: " & got.val & " != " & v

  if o.inflight.len > 0:
    var landed = 0
    for kk, vv in o.inflight:
      let got = b.get(kk)
      if got.found and got.val == vv: inc landed
    if landed != 0 and landed != o.inflight.len:
      return "half-applied transaction: " & $landed & "/" & $o.inflight.len
  ""

let iterations = if paramCount() >= 1: parseInt(paramStr(1)) else: 1000
var torn = 0
var clean = 0
var failures = 0
var worst = ""

for i in 0 ..< iterations:
  let seed = i div 20
  let full = workload(seed, 0)
  let span = max(2, full.dbBytes.len + full.walBytes.len)
  let cut = rand(1 .. span)
  let o = workload(seed, cut)
  let bad = verify(o)
  if o.crashed: inc torn else: inc clean
  if bad.len > 0:
    inc failures
    if worst.len == 0:
      worst = "iter " & $i & " seed=" & $seed & " cut=" & $cut & ": " & bad

echo "iterations   ", iterations
echo "torn crashes ", torn
echo "clean runs   ", clean
echo "failures     ", failures
if worst.len > 0:
  echo "first failure ", worst
  quit 1
echo "verdict      no half-applied state, no lost commit, no unreadable file"
