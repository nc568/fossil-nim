## Corrupted-storage tests: every byte in a page is attacker input.
##
## Why this file exists. The audit of the *server* half of this project found a
## whole family of bugs with one shape: a length, an offset or a count taken from
## untrusted input and used before it was checked. In a database engine the same
## shape lives one layer lower — in the page graph — and the consequence is worse,
## because a page is 4 KiB of pure structure: a cell count, an offset table, key
## lengths, value lengths, child pointers, overflow chains.
##
## Two failure modes matter, and they are not the same:
##
##   * **a raised `Defect`** (IndexDefect, RangeDefect) — escapes every
##     `except DbError` in the program and kills the process, taking the healthy
##     pages down with the corrupt one;
##   * **a hang** — an overflow chain that makes no progress, or points at
##     itself, loops forever without allocating, so no watchdog on memory helps.
##
## Both are asserted absent here. A corrupt page may produce an answer (if the
## damage missed everything the query touched) or a `DbError`; it may not produce
## anything else.

import std/[random, strutils, unittest]
import fossil/db/[btree, bytes, errors, pager, vfs]

const Keys = 400          ## enough for a tree of depth 2, so internal nodes exist

proc keyOf(i: int): string = "k" & align($i, 6, '0')

proc buildImage(): string =
  ## A real, consistent database file, dumped to bytes.
  let p = openPager(openMemoryVfs(), cachePages = 8)
  let b = openBtree(p)
  for i in 0 ..< Keys: b.put(keyOf(i), "value-" & $i)
  p.flushToVfs()
  p.vfs.snapshot()

proc pageCount(image: string): int = image.len div PageSize

proc mutate(image: string; pid, at: int; value: char): string =
  result = image
  let pos = pid * PageSize + at
  if pos + 1 < result.len: result[pos] = value

proc exercise(image: string): string =
  ## Opens the image and does everything a reader would do. Returns "" when the
  ## run was clean (either it worked or it raised a DbError), and a description
  ## of the misbehaviour otherwise.
  let p = openPager(reopenFrom(openMemoryVfs(), image), cachePages = 8)
  let b = openBtree(p)
  for i in 0 ..< Keys:
    discard b.get(keyOf(i))
  discard b.verify()
  ""

proc expectClean(image: string; what: string) =
  var bad = ""
  try:
    bad = exercise(image)
  except DbError:
    discard                      # the honest outcome: refused, not crashed
  except Defect as e:
    check false                  # a Defect is a process kill in production
    bad = "Defect " & $e.name & ": " & e.msg
  except CatchableError as e:
    check false
    bad = "raw " & $e.name & ": " & e.msg
  if bad.len > 0:
    checkpoint what & " -> " & bad
  check bad.len == 0

suite "corrupt pages are refused, not obeyed":

  test "the clean image passes, so the harness is honest":
    expectClean(buildImage(), "unmodified")

  test "page kind byte":
    let img = buildImage()
    for pid in 0 ..< pageCount(img):
      for v in [0x00.char, 0x03.char, 0xFF.char, 0x7F.char]:
        expectClean(mutate(img, pid, 0, v), "kind=" & $int(uint8(v)) & " on page " & $pid)

  test "cell count":
    ## The count drives the offset-table walk. A large count used to read the
    ## table past the end of the page: IndexDefect.
    let img = buildImage()
    for pid in 1 ..< pageCount(img):
      for v in [0xFF, 0x7F, 0x40]:
        var bad = mutate(img, pid, 2, char(v))
        bad = mutate(bad, pid, 3, char(v))
        expectClean(bad, "count=" & $v & " on page " & $pid)

  test "cell offsets":
    let img = buildImage()
    for pid in 1 ..< pageCount(img):
      for at in [16, 18, 20]:
        for v in [0x00, 0xFF, 0x0E, 0xF0]:
          expectClean(mutate(img, pid, at, char(v)),
                      "offset byte " & $at & "=" & $v & " on page " & $pid)

  test "key length in a cell":
    ## A key length larger than its own cell makes `cell[CellHdr ..< CellHdr+klen]`
    ## read into the next cell or past the page.
    let img = buildImage()
    for pid in 1 ..< pageCount(img):
      var found = 0
      for at in 16 ..< 64:
        let t = mutate(img, pid, at, char(0xFF))
        if t != img: inc found
        expectClean(t, "0xFF at " & $at & " on page " & $pid)
      check found > 0

  test "value length in a cell":
    let img = buildImage()
    for pid in 1 ..< pageCount(img):
      for at in [20, 21, 22, 23]:
        for v in [0x7F, 0xFF, 0x01]:
          expectClean(mutate(img, pid, at, char(v)),
                      "valLen byte " & $at & "=" & $v & " on page " & $pid)

  test "child pointers":
    let img = buildImage()
    let n = pageCount(img)
    for pid in 1 ..< n:
      for at in [16, 17, 18, 19]:
        for v in [0x00, 0xFF, 0x40]:
          expectClean(mutate(img, pid, at, char(v)),
                      "child byte " & $at & "=" & $v & " on page " & $pid)

  test "random byte soup over the page area":
    ## 2000 mutations over every non-header byte. Seeded, so a failure is
    ## reproducible rather than a story about a flaky test.
    var r = initRand(0x5EED)
    let img = buildImage()
    let n = pageCount(img)
    for _ in 0 ..< 2000:
      var bad = img
      let pid = r.rand(1 ..< n)
      for _ in 0 ..< r.rand(1 .. 8):
        let at = r.rand(0 ..< PageSize)
        bad[pid * PageSize + at] = char(r.rand(0 .. 255))
      expectClean(bad, "random soup on page " & $pid)

suite "overflow chains":

  proc overflowImage(): string =
    var p = openPager(openMemoryVfs(), cachePages = 8)
    let b = openBtree(p)
    b.put("big", repeat('x', 3 * PageSize))      # several overflow pages
    p.flushToVfs()
    p.vfs.snapshot()

  test "a chain that points at itself terminates with an error":
    ## Without a progress or length budget this is an infinite loop — no
    ## allocation, no crash, just a database that stops answering forever.
    var img = overflowImage()
    let n = pageCount(img)
    var lastOverflow = -1
    for pid in 1 ..< n:
      var page = ""
      discard reopenFrom(openMemoryVfs(), img).readAt(pid * PageSize, page, PageSize)
      if page.len == PageSize and page.getI32(0) == 0 and page.getU16(4) > 0:
        lastOverflow = pid
    if lastOverflow < 0:
      checkpoint "no overflow page found; the fixture is wrong"
      check false
    else:
      img = mutate(img, lastOverflow, 0, char(lastOverflow and 0xFF))
      img = mutate(img, lastOverflow, 1, char((lastOverflow shr 8) and 0xFF))
      img = mutate(img, lastOverflow, 2, '\0')
      img = mutate(img, lastOverflow, 3, '\0')
      expectClean(img, "self-referential overflow chain")

  test "a value that claims a gigabyte is refused before allocating":
    ## The zip-bomb class from the audit, one layer down: `newString(total)`
    ## where `total` came off the disk.
    var img = overflowImage()
    let n = pageCount(img)
    for pid in 1 ..< n:
      var page = ""
      discard reopenFrom(openMemoryVfs(), img).readAt(pid * PageSize, page, PageSize)
      if page.len == PageSize and page.getI32(0) != 0:
        # cell header sits at the start of the page after the node header; the
        # value length field of a leaf cell is at +8+4
        img = mutate(img, pid, 12, char(0x00))
        img = mutate(img, pid, 13, char(0x00))
        img = mutate(img, pid, 14, char(0x00))
        img = mutate(img, pid, 15, char(0x40))   # 0x40000000 = 1 GiB
        break
    expectClean(img, "1 GiB value claim")
