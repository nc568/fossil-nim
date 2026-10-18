## B+tree tests.
##
## The point of this file is not "does get return what put stored" — that would
## pass on a single-page array. It is: does the structure survive the operations
## that break trees, *and* does `verify` catch it if it does not. Every heavy
## test therefore ends with a full structural walk against a reference model.

import std/[algorithm, os, random, sequtils, strutils, tables, unittest]
import fossil/db/[btree, bytes, errors, pager, vfs]

const TmpDir = "build/db/btreetmp"

proc freshPager(): Pager = openPager(openMemoryVfs(), cachePages = 32)

proc key(i: int): string = "k" & align($i, 8, '0')
  ## Zero-padded so lexicographic order matches numeric order — otherwise the
  ## test's own expectations would be wrong, not the tree's.

proc bigValue(n: int): string =
  result = newString(n)
  for i in 0 ..< n: result[i] = char(ord('a') + i mod 26)

suite "bytes":
  test "round trip across the sign boundary":
    var s = newString(8)
    for v in [-1, 0, 1, 65_535, -2_147_483_648, 2_147_483_647]:
      s.putI32(0, v)
      check s.getI32(0) == v
  test "16-bit fields stay inside their field":
    var s = newString(4)
    s.putU16(0, 0xBEEF)
    s.putU16(2, 0x1234)
    check s.getU16(0) == 0xBEEF
    check s.getU16(2) == 0x1234

suite "basics":
  test "a fresh tree is an empty leaf":
    let b = openBtree(freshPager())
    check b.height == 0
    check b.get("anything").found == false
    let s = b.verify()
    check s.keys == 0
    check s.leaves == 1

  test "put then get, and ordering ignores insertion order":
    let b = openBtree(freshPager())
    for k in ["b", "d", "a", "c", "e"]: b.put(k, k.toUpperAscii)
    for k in ["a", "b", "c", "d", "e"]:
      check b.get(k).val == k.toUpperAscii
    var seen: seq[string]
    for k, _ in b.pairs: seen.add k
    check seen == @["a", "b", "c", "d", "e"]

  test "putting the same key twice replaces, it does not duplicate":
    let b = openBtree(freshPager())
    b.put("x", "one")
    b.put("x", "two")
    check b.get("x").val == "two"
    check b.verify().keys == 1

  test "keys beyond the size limit are refused, not truncated":
    let b = openBtree(freshPager())
    expect DbError:
      b.put(repeat('k', MaxKeySize + 1), "v")
    check b.get(repeat('k', MaxKeySize)).found == false

suite "growth":
  test "many inserts keep the tree valid and ordered":
    let b = openBtree(freshPager())
    for i in 0 ..< 5000: b.put(key(i), "v" & $i)
    let s = b.verify()
    check s.keys == 5000
    check s.leaves > 1          # it really did split
    check s.depth >= 1          # and grew a root
    for i in 0 ..< 5000:
      check b.get(key(i)).val == "v" & $i

  test "all leaves sit at the same depth even with adversarial insert order":
    # ascending order is the worst case for a naive split: every insert lands in
    # the rightmost leaf and every split propagates to the root
    let b = openBtree(freshPager())
    for i in 0 ..< 3000: b.put(key(i), "a")
    # and descending order into the same tree
    for i in countdown(2999, 0): b.put(key(i), "b")
    check b.verify().keys == 3000
    check b.get(key(1500)).val == "b"

  test "random order gives the same set as sorted order":
    var rng = initRand(2026)
    var order = toSeq(0 ..< 4000)
    rng.shuffle(order)
    let b = openBtree(freshPager())
    for i in order: b.put(key(i), $i)
    var prev = ""
    var n = 0
    for k, _ in b.pairs:
      check prev.len == 0 or prev < k
      prev = k
      inc n
    check n == 4000
    check b.verify().keys == 4000

suite "deletion":
  test "deleting a missing key reports false and changes nothing":
    let b = openBtree(freshPager())
    b.put("a", "1")
    check b.del("zzz") == false
    check b.verify().keys == 1

  test "deleting everything leaves a valid empty tree":
    let b = openBtree(freshPager())
    for i in 0 ..< 800: b.put(key(i), $i)
    for i in 0 ..< 800: check b.del(key(i)) == true
    let s = b.verify()
    check s.keys == 0
    check s.leaves == 1
    check b.get(key(10)).found == false

  test "random deletes match a reference table":
    var rng = initRand(7)
    var model = initTable[string, string]()
    let b = openBtree(freshPager())
    for i in 0 ..< 2000:
      let k = key(i)
      let v = "v" & $i
      model[k] = v
      b.put(k, v)
    var order = toSeq(0 ..< 2000)
    rng.shuffle(order)
    for n, i in order:
      let k = key(i)
      if n mod 2 == 0:
        check b.del(k) == true
        model.del(k)
      else:
        check b.get(k).val == model[k]
    check b.verify().keys == model.len
    for k, v in model: check b.get(k).val == v
    for k in model.keys: check b.get(k).found

  test "deleting from the middle keeps the leaf chain walkable":
    let b = openBtree(freshPager())
    for i in 0 ..< 1200: b.put(key(i), $i)
    for i in countup(0, 1199, 3): discard b.del(key(i))   # punch holes everywhere
    var prev = ""
    var n = 0
    for k, _ in b.pairs:
      check prev.len == 0 or prev < k
      prev = k
      inc n
    check n == 800
    check b.verify().keys == 800

suite "overflow values":
  test "a value past the inline ceiling comes back byte for byte":
    let b = openBtree(freshPager())
    let big = bigValue(40_000)
    b.put("big", big)
    let got = b.get("big")
    check got.found
    check got.val.len == 40_000
    check got.val == big
    check b.verify().keys == 1

  test "overwriting an overflow value frees the old chain":
    let b = openBtree(freshPager())
    b.put("k", bigValue(20_000))
    let before = b.p.nPages
    b.put("k", "small")
    b.put("k", bigValue(20_000))
    check b.get("k").val.len == 20_000
    # the freelist must have handed the old chain back, not leaked it
    check b.p.nPages <= before + 6
    check b.verify().keys == 1

  test "deleting an overflow value frees its chain":
    let b = openBtree(freshPager())
    b.put("k", bigValue(30_000))
    let afterPut = b.p.nPages
    check b.del("k")
    for i in 0 ..< 3: b.put("filler" & $i, "x")
    check b.p.nPages <= afterPut + 1

  test "overflow and inline values mix in one leaf":
    let b = openBtree(freshPager())
    for i in 0 ..< 40:
      let size = if i mod 7 == 0: 9000 else: 10
      b.put(key(i), bigValue(size))
    for i in 0 ..< 40:
      let size = if i mod 7 == 0: 9000 else: 10
      check b.get(key(i)).val.len == size
    check b.verify().keys == 40

suite "scans":
  test "scanFrom starts where asked and does not skip the first hit":
    let b = openBtree(freshPager())
    for i in 0 ..< 500: b.put(key(i), $i)
    var n = 0
    for k, _ in b.scanFrom(key(400)):
      inc n
    check n == 100

  test "range is half-open on the right":
    let b = openBtree(freshPager())
    for i in 0 ..< 20: b.put(key(i + 10), $i)
    var seen: seq[string]
    for k, _ in b.range(key(12), key(15)): seen.add k
    check seen == @[key(12), key(13), key(14)]

  test "range on an empty tree yields nothing":
    let b = openBtree(freshPager())
    var n = 0
    for k, _ in b.range("a", "z"): inc n
    check n == 0

suite "persistence":
  test "the tree survives close and reopen":
    createDir(TmpDir)
    let path = TmpDir / "tree.db"
    removeFile(path)
    block:
      let b = openBtree(openPager(openFileVfs(path), cachePages = 8))
      for i in 0 ..< 1500: b.put(key(i), "v" & $i)
      discard b.del(key(700))
      b.p.close()
    block:
      let b = openBtree(openPager(openFileVfs(path), cachePages = 8))
      check b.verify().keys == 1499
      check b.get(key(700)).found == false
      check b.get(key(1499)).val == "v1499"
      b.p.close()
    removeFile(path)

  test "reopening an empty tree does not create a second root":
    createDir(TmpDir)
    let path = TmpDir / "empty.db"
    removeFile(path)
    var firstRoot = 0
    block:
      let b = openBtree(openPager(openFileVfs(path)))
      firstRoot = b.root
      b.p.close()
    block:
      let b = openBtree(openPager(openFileVfs(path)))
      check b.root == firstRoot
      b.p.close()
    removeFile(path)

suite "clear":
  test "clear empties the tree and keeps it usable":
    let b = openBtree(freshPager())
    for i in 0 ..< 600: b.put(key(i), $i)
    b.clear()
    check b.verify().keys == 0
    b.put("again", "1")
    check b.get("again").val == "1"

suite "model check":
  test "interleaved inserts and deletes match a table model over 20 seeds":
    ## The single-purpose tests above each exercise one path. This one mixes
    ## every path in an order nobody designed, which is where the interesting
    ## bugs live — both of the ones found in this file's first run were
    ## ordering bugs, not logic bugs.
    for seed in 0 .. 19:
      var rng = initRand(seed)
      var model = initTable[string, string]()
      let b = openBtree(freshPager())
      for _ in 0 ..< 400:
        let k = key(rng.rand(199))
        if rng.rand(3) == 0:
          let removed = b.del(k)
          check removed == model.hasKey(k)
          model.del(k)
        else:
          let v = "v" & $rng.rand(1_000_000)
          b.put(k, v)
          model[k] = v
      let s = b.verify()
      check s.keys == model.len
      var seen = 0
      var prev = ""
      for k, v in b.pairs:
        check v == model[k]
        check prev.len == 0 or prev < k
        prev = k
        inc seen
      check seen == model.len
      for k, v in model:
        check b.get(k).val == v
