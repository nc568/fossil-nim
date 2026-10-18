## Storage tests: VFS + pager.
##
## The point of this suite is durability and honest accounting:
##   * data written to a file survives close/reopen;
##   * the cache actually saves I/O (measured, not assumed);
##   * a foreign or truncated file is rejected, not misread;
##   * freeing pages really reuses them;
##   * 20k random operations keep the cache bounded.

import std/[unittest, os, strutils, random]
import fossil/db/[api, errors, pager, vfs]

proc fill(v: char): string =
  result = newString(PageSize)
  for i in 0 ..< PageSize: result[i] = v

const TmpDir = "build/db/tmp"

suite "vfs":
  test "memory backend roundtrip and growth":
    let v = openMemoryVfs()
    check v.writeAt(0, "hello")
    check v.size == 5
    check v.writeAt(10, "world")
    check v.size == 15
    var got = ""
    check v.readAt(10, got, 5)
    check got == "world"
    # gap is zero-filled, never garbage
    check v.readAt(5, got, 5)
    check got == "\0\0\0\0\0"
    check not v.readAt(0, got, 100)

  test "file backend roundtrip":
    createDir(TmpDir)
    let path = TmpDir / "vfs_basic.bin"
    removeFile(path)
    block:
      let v = openFileVfs(path)
      check v.writeAt(0, "abcdef")
      v.close()
    block:
      let v = openFileVfs(path)
      var got = ""
      check v.readAt(2, got, 3)
      check got == "cde"
      check v.size == 6
      v.close()
    removeFile(path)

suite "pager basics":
  test "brand new store has a valid header":
    let p = openPager(openMemoryVfs())
    check p.nPages == 1          # header page only
    check p.integrityOk()
    p.close()

  test "alloc, write, read back":
    let p = openPager(openMemoryVfs())
    let a = p.allocPage()
    let b = p.allocPage()
    check a != b
    p.writePage(a, fill('A'))
    p.writePage(b, fill('B'))
    check p.readPage(a) == fill('A')
    check p.readPage(b) == fill('B')
    check p.nPages == 3      # 2 data pages + header
    p.close()

  test "page zero cannot be overwritten from outside":
    let p = openPager(openMemoryVfs())
    expect DbError:
      p.writePage(0, fill('X'))
    p.close()

  test "wrong page size is rejected":
    let p = openPager(openMemoryVfs())
    let a = p.allocPage()
    expect DbError:
      p.writePage(a, "too short")
    p.close()

suite "durability":
  test "data survives close and reopen on a file":
    createDir(TmpDir)
    let path = TmpDir / "durable.focdb"
    removeFile(path)
    var wrote: seq[int]
    block:
      let p = openPager(openFileVfs(path))
      for i in 0 ..< 5:
        let pid = p.allocPage()
        wrote.add pid
        p.writePage(pid, fill(chr(ord('a') + i)))
      p.close()
    block:
      let p = openPager(openFileVfs(path))
      check p.nPages == 6      # 5 data pages + header
      for i, pid in wrote:
        check p.readPage(pid) == fill(chr(ord('a') + i))
      check p.integrityOk()
      p.close()
    removeFile(path)

  test "unflushed writes are not on disk, flushed ones are":
    createDir(TmpDir)
    let path = TmpDir / "flush.focdb"
    removeFile(path)
    block:
      let p = openPager(openFileVfs(path))
      let pid = p.allocPage()
      p.writePage(pid, fill('Q'))
      # no flush, no close: process "dies" here
      check p.stats.flushes == 0
      discard pid
    block:
      let p = openPager(openFileVfs(path))
      # allocation was never flushed, so the store is still empty (header only)
      check p.nPages == 1
      p.close()
    block:
      let p = openPager(openFileVfs(path))
      let pid = p.allocPage()
      p.writePage(pid, fill('Q'))
      p.flush()
      p.close()
    block:
      let p = openPager(openFileVfs(path))
      check p.nPages == 2
      check p.readPage(1) == fill('Q')
      p.close()
    removeFile(path)

  test "closing flushes dirty pages":
    createDir(TmpDir)
    let path = TmpDir / "closing.focdb"
    removeFile(path)
    block:
      let p = openPager(openFileVfs(path))
      let pid = p.allocPage()
      p.writePage(pid, fill('Z'))
      p.close()                      # must flush on the way out
    block:
      let p = openPager(openFileVfs(path))
      check p.readPage(1) == fill('Z')
      p.close()
    removeFile(path)

suite "cache accounting":
  test "repeated reads are served from the cache":
    let p = openPager(openMemoryVfs())
    let pid = p.allocPage()
    p.writePage(pid, fill('C'))
    p.flush()
    let readsBefore = p.vfs.ioReads
    for _ in 0 ..< 100: discard p.readPage(pid)
    check p.stats.hits >= 100
    check p.vfs.ioReads == readsBefore     # zero extra I/O

  test "cache stays bounded under rotation":
    let p = openPager(openMemoryVfs(), cachePages = 8)
    for i in 0 ..< 200:
      let pid = p.allocPage()
      p.writePage(pid, fill(chr(ord('a') + (i mod 26))))
    for pid in 1 .. 200:
      discard p.readPage(pid)
    check p.stats.resident <= 8
    check p.stats.evictions > 0
    p.close()

suite "corruption":
  test "foreign file is rejected":
    createDir(TmpDir)
    let path = TmpDir / "foreign.bin"
    writeFile(path, repeat("not a database ", 400))
    let v = openFileVfs(path)
    expect DbError:
      discard openPager(v)
    v.close()
    removeFile(path)

  test "truncated file is rejected":
    createDir(TmpDir)
    let path = TmpDir / "truncated.focdb"
    writeFile(path, "FOCDB")
    let v = openFileVfs(path)
    expect DbError:
      discard openPager(v)
    v.close()
    removeFile(path)

  test "version mismatch is rejected":
    createDir(TmpDir)
    let path = TmpDir / "version.focdb"
    removeFile(path)
    block:
      let p = openPager(openFileVfs(path))
      p.close()
    var raw = readFile(path)
    raw[8] = char(99)                 # bump the version byte
    writeFile(path, raw)
    let v = openFileVfs(path)
    expect DbError:
      discard openPager(v)
    v.close()
    removeFile(path)

suite "freelist":
  test "freed pages are reused instead of growing the file":
    let p = openPager(openMemoryVfs())
    var ids: seq[int]
    for _ in 0 ..< 5: ids.add p.allocPage()
    let sizeBefore = p.nPages
    for pid in ids: p.freePage(pid)
    check p.freeCount == 5
    var reused: seq[int]
    for _ in 0 ..< 5: reused.add p.allocPage()
    check p.nPages == sizeBefore          # file did not grow
    check p.freeCount == 0
    check p.integrityOk()
    p.close()

  test "freelist is not corruptible by freeing twice":
    let p = openPager(openMemoryVfs())
    let pid = p.allocPage()
    p.freePage(pid)
    expect DbError:
      # second free of the same page must not create a cycle
      p.freePage(pid)
    p.close()

suite "stress":
  test "20k random operations keep memory and cache bounded":
    randomize(1234)
    createDir(TmpDir)
    let path = TmpDir / "stress.focdb"
    removeFile(path)
    block:
      let p = openPager(openFileVfs(path), cachePages = 16)
      var live: seq[int]
      for i in 0 ..< 20_000:
        let op = rand(2)
        if op == 0 or live.len == 0:
          live.add p.allocPage()
        elif op == 1:
          let idx = rand(live.len - 1)
          p.writePage(live[idx], fill(chr(ord('a') + (i mod 26))))
        else:
          discard p.readPage(live[rand(live.len - 1)])
        if p.stats.resident > 16: check false
      p.flush()
      check p.integrityOk()
      p.close()
    block:
      let p = openPager(openFileVfs(path))
      check p.integrityOk()
      p.close()
    removeFile(path)
