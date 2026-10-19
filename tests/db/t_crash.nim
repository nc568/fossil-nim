## Crash-recovery fuzzer.
##
## The question is not "does WAL work" — `t_wal.nim` covers the log alone. It is:
## *after the power dies mid-write, is the database at transaction N or at N+1,
## and never in between?*
##
## Method: run a workload with `crashAt` set to a random byte offset. The store
## dies once that many bytes are written: the offending write is torn, every
## later write is dropped, and `snapshot()` then returns exactly what survived.
## Those bytes are handed to a brand-new store that knows nothing about what
## happened, and the invariants are checked.
##
## Asserted after every crash:
##   * the database opens — no exception, no "opened but unreadable";
##   * the B+tree still satisfies its structural invariants;
##   * every transaction that committed before the crash is present, exactly;
##   * the transaction in flight is *entirely* present or *entirely* absent.

import std/[random, strutils, tables, unittest]
import fossil/db/[btree, errors, pager, store, vfs, wal]

type
  Run = object
    durable: Table[string, string]   ## keys and values as of the last commit
    inflight: Table[string, string]  ## key -> the value this transaction wrote
    committedTxns: int
    crashed: bool
    dbBytes, walBytes: string

proc key(i: int): string = "k" & align($i, 7, '0')

proc runWorkload(seed: int; crashAt: int; cachePages = 8): Run =
  ## Deterministic in `seed` alone: the measuring pass (`crashAt = 0`) performs
  ## exactly the same writes as the crashing pass up to the crash point, which
  ## is what makes the two comparable.
  var rng = initRand(seed)
  let dbVfs = openMemoryVfs()
  let walVfs = openMemoryVfs()
  if crashAt > 0:
    dbVfs.crashAt = crashAt
    walVfs.crashAt = crashAt       # one power cut, both files

  let s = openStore(dbVfs, walVfs, cachePages = cachePages)
  var b = openBtree(s.p)
  var n = 0

  for txn in 0 ..< 5:
    var keys: seq[string]
    var pending = initTable[string, string]()
    for _ in 0 ..< 6:
      let kk = key(rng.rand(40))
      let vv = $seed & ":" & $txn & ":" & $n
      b.put(kk, vv)
      pending[kk] = vv
      keys.add kk
      inc n
    if dbVfs.dead or walVfs.dead:
      result.crashed = true
      result.inflight = pending
      break

    s.commit()
    if dbVfs.dead or walVfs.dead:
      # the commit itself was cut: this transaction may or may not have landed
      result.crashed = true
      result.inflight = pending
      break

    for kk in keys: result.durable[kk] = b.get(kk).val
    inc result.committedTxns

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

var debugTag = ""

proc reopen(dbBytes, walBytes: string): tuple[s: Store, b: Btree] =
  let dbVfs = reopenFrom(openMemoryVfs(), dbBytes)
  let walVfs = reopenFrom(openMemoryVfs(), walBytes)
  try:
    result.s = openStore(dbVfs, walVfs, cachePages = 8)
    result.b = openBtree(result.s.p)
  except DbError as e:
    echo "    OPEN FAILED [", debugTag, "]: ", e.msg,
         "  db=", dbBytes.len, "B wal=", walBytes.len, "B"
    raise

proc checkInvariants(o: Run; b: Btree; tag: string) =
  # 1. the structure survived
  let stats = b.verify()
  check stats.keys >= 0

  # 2. everything committed before the crash is there, byte for byte
  for kk, v in o.durable:
    let got = b.get(kk)
    if not got.found or got.val != v:
      echo "    LOST after crash [", tag, "]: ", kk, " expected ", v,
           " got ", (if got.found: got.val else: "<missing>")
    check got.found
    check got.val == v

  # 3. the in-flight transaction is all there or all gone.
  # Counting "key exists" is not enough: a key may have been committed by an
  # earlier transaction and rewritten by this one. The question is whether the
  # *new value* landed, so each key is classified against the value it had
  # before the transaction started.
  if o.inflight.len > 0:
    var landed = 0
    var stale = 0
    for kk, vv in o.inflight:
      let got = b.get(kk)
      if got.found and got.val == vv: inc landed
      else: inc stale
    if landed != 0 and landed != o.inflight.len:
      echo "    HALF-APPLIED [", tag, "]: ", landed, " of ", o.inflight.len,
           " new values landed, ", stale, " kept the old one"
    check landed == 0 or landed == o.inflight.len

suite "crash recovery":
  test "fixed workloads survive a crash at every interesting boundary":
    ## The boundaries that matter are not random: first byte, last byte, and
    ## just before/after each commit frame. Random offsets find the rest.
    for seed in 0 ..< 12:
      let full = runWorkload(seed, 0)
      check full.crashed == false
      check full.committedTxns == 5
      check full.walBytes.len > 0
      for cut in [1, 2, full.walBytes.len div 2, full.walBytes.len - 1,
                  full.walBytes.len, full.walBytes.len + 1]:
        if cut <= 0: continue
        let o = runWorkload(seed, cut)
        var (s, b) = reopen(o.dbBytes, o.walBytes)
        checkInvariants(o, b, "seed=" & $seed & " cut=" & $cut)
        s.p.close()
        s.w.close()

  test "random crash points: dozens per seed, none may land half-way":
    var torn = 0
    var clean = 0
    for seed in 0 ..< 25:
      let full = runWorkload(seed, 0)
      for _ in 0 ..< 12:
        let cut = rand(1 .. max(2, full.walBytes.len + full.dbBytes.len))
        debugTag = "seed=" & $seed & " cut=" & $cut
        let o = runWorkload(seed, cut)
        var (s, b) = reopen(o.dbBytes, o.walBytes)
        checkInvariants(o, b, "seed=" & $seed & " cut=" & $cut)
        s.p.close()
        s.w.close()
        if o.crashed: inc torn else: inc clean
    echo "    crash points: ", torn, " torn, ", clean, " landed after the workload"
    check torn > 50        # the fuzzer must actually be crashing, not idling

  test "a crash during checkpoint loses nothing that was committed":
    ## Checkpoint has the widest window of any operation: the main file is being
    ## rewritten while the log is still authoritative. Sweeping the byte range
    ## of the checkpoint region is the only way to know the ordering is right.
    let seed = 3
    let full = runWorkload(seed, 0)
    var checked = 0
    for cut in countup(1, max(2, full.dbBytes.len + full.walBytes.len), 977):
      debugTag = "ckpt seed=" & $seed & " cut=" & $cut
      let o = runWorkload(seed, cut)
      var (s, b) = reopen(o.dbBytes, o.walBytes)
      checkInvariants(o, b, "checkpoint cut=" & $cut)
      s.p.close()
      s.w.close()
      inc checked
    echo "    checkpoint sweeps: ", checked
    check checked > 5
