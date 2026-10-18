## WAL tests.
##
## The rules being tested are the ones a user actually depends on:
##   * a committed transaction survives;
##   * an interrupted transaction disappears completely, never half-applied;
##   * a torn frame is detected by its checksum, not by luck;
##   * one commit costs one sync, regardless of how many pages it covers;
##   * a checkpoint makes old frames unreplayable.

import std/[unittest, os, algorithm]
import fossil/db/[errors, pager, vfs, wal]

const TmpDir = "build/db/tmp"

proc fill(v: char): string =
  result = newString(PageSize)
  for i in 0 ..< PageSize: result[i] = v

proc freshPager(): Pager = openPager(openMemoryVfs())

proc tearFrame(w: Wal; off: int) =
  ## Simulates a write that died in the middle of a frame: the first bytes of
  ## the frame header are on disk, the rest never arrived.
  var zeros = newString(24)
  for i in 0 ..< 24: zeros[i] = '\0'
  discard w.vfs.writeAt(off, zeros)

suite "crc":
  test "known vector":
    # CRC-32 of "123456789" is 0xCBF43926
    check crc32("123456789") == 0xCBF43926

  test "empty input":
    check crc32("") == 0

suite "frames":
  test "append and commit account correctly":
    let w = openWal(openMemoryVfs())
    check w.stats.salt == 1
    w.appendFrame(1, fill('A'))
    w.appendFrame(2, fill('B'))
    check w.pending == 2
    w.commit(3)
    check w.pending == 0
    check w.stats.commits == 1
    check w.logBytes == WalHeaderPage + 2 * (12 + PageSize) + (12 + PageSize)

  test "invalid page id is refused":
    let w = openWal(openMemoryVfs())
    expect DbError:
      w.appendFrame(0, fill('A'))
    expect DbError:
      w.appendFrame(-2, fill('A'))

  test "wrong payload size is refused":
    let w = openWal(openMemoryVfs())
    expect DbError:
      w.appendFrame(1, "short")

suite "recovery":
  test "committed pages are replayed":
    let w = openWal(openMemoryVfs())
    w.appendFrame(1, fill('A'))
    w.appendFrame(2, fill('B'))
    w.commit(3)
    let p = freshPager()
    check p.recover(w) == 2
    check p.readPage(1)[0] == 'A'
    check p.readPage(2)[0] == 'B'
    check p.nPages == 3

  test "uncommitted tail is discarded entirely":
    let w = openWal(openMemoryVfs())
    w.appendFrame(1, fill('A'))
    w.commit(2)
    # a transaction that never committed
    w.appendFrame(2, fill('B'))
    w.appendFrame(3, fill('C'))
    let p = freshPager()
    check p.recover(w) == 1
    check p.readPage(1)[0] == 'A'
    check p.nPages == 2            # page 2 was never committed
    # reading the uncommitted page returns a zero page, not 'B'
    check p.readPage(2)[0] == '\0'

  test "torn frame in the middle stops replay at the safe point":
    let w = openWal(openMemoryVfs())
    w.appendFrame(1, fill('A'))
    w.commit(2)
    let secondFrameOff = WalHeaderPage + 2 * (12 + PageSize)   # after frame + commit
    w.appendFrame(2, fill('B'))
    w.commit(3)
    # the second transaction's frame header never made it to disk
    w.tearFrame(secondFrameOff)
    let p = freshPager()
    check p.recover(w) == 1
    check p.readPage(1)[0] == 'A'
    check p.readPage(2)[0] == '\0'

  test "bit flip in a payload is detected":
    let w = openWal(openMemoryVfs())
    w.appendFrame(1, fill('A'))
    w.commit(2)
    var raw = ""
    discard w.vfs.readAt(WalHeaderPage + 12, raw, PageSize)
    raw[100] = char(ord(raw[100]) xor 0x01)
    discard w.vfs.writeAt(WalHeaderPage + 12, raw)
    let p = freshPager()
    check p.recover(w) == 0        # nothing is trustworthy, nothing is applied
    check p.readPage(1)[0] == '\0'

  test "salt mismatch from another generation is ignored":
    createDir(TmpDir)
    let path = TmpDir / "generation.wal"
    removeFile(path)
    block:
      let w = openWal(openFileVfs(path))
      w.appendFrame(1, fill('A'))
      w.commit(2)
      w.close()
    # rewrite the header with a different generation salt, checksum included
    var raw = readFile(path)
    raw[11] = char(99)                       # salt is bytes 8..11, big-endian
    let crc = crc32(raw[0 .. 15])            # checksum covers the first 16 bytes
    raw[16] = char((uint32(crc) shr 24) and 0xFF)
    raw[17] = char((uint32(crc) shr 16) and 0xFF)
    raw[18] = char((uint32(crc) shr 8) and 0xFF)
    raw[19] = char(uint32(crc) and 0xFF)
    writeFile(path, raw)
    block:
      # reopening reads salt 99 from the header; the frames still say 1
      let w = openWal(openFileVfs(path))
      check w.salt == 99
      let p = freshPager()
      check p.recover(w) == 0
      w.close()
    removeFile(path)

  test "multiple commits replay in order, last write wins":
    let w = openWal(openMemoryVfs())
    w.appendFrame(1, fill('A'))
    w.commit(2)
    w.appendFrame(1, fill('Z'))
    w.commit(2)
    let p = freshPager()
    check p.recover(w) == 2
    check p.readPage(1)[0] == 'Z'

suite "energy":
  test "one commit costs exactly one sync, whatever it covers":
    let w = openWal(openMemoryVfs())
    let before = w.vfs.syncs
    for i in 1 .. 20:
      w.appendFrame(i, fill('x'))
    w.commit(21)
    check w.vfs.syncs - before == 1

  test "twenty separate commits cost twenty syncs (and why that is the tradeoff)":
    let w = openWal(openMemoryVfs())
    let before = w.vfs.syncs
    for i in 1 .. 20:
      w.appendFrame(i, fill('x'))
      w.commit(i + 1)
    check w.vfs.syncs - before == 20

suite "checkpoint":
  test "checkpoint folds the log into the store and starts a new generation":
    createDir(TmpDir)
    let path = TmpDir / "ckpt.focdb"
    removeFile(path)
    let p = openPager(openFileVfs(path))
    let w = openWal(openMemoryVfs())
    p.writePage(p.allocPage(), fill('A'))
    w.appendFrame(1, fill('A'))
    w.commit(2)
    let saltBefore = w.stats.salt
    p.checkpoint(w)
    check w.stats.salt == saltBefore + 1
    check w.pending == 0
    check p.readPage(1)[0] == 'A'
    p.close()
    block:
      let p2 = openPager(openFileVfs(path))
      check p2.readPage(1)[0] == 'A'
      p2.close()
    removeFile(path)

  test "old frames are not replayable after a checkpoint":
    let w = openWal(openMemoryVfs())
    w.appendFrame(1, fill('A'))
    w.commit(2)
    let p = freshPager()
    discard p.recover(w)
    p.checkpoint(w)
    # the pager that replays now sees a different generation
    let p2 = freshPager()
    check p2.recover(w) == 0

  test "appending after a checkpoint lands after the header, not on top of it":
    let w = openWal(openMemoryVfs())
    w.appendFrame(1, fill('A'))
    w.commit(2)
    let p = freshPager()
    discard p.recover(w)
    p.checkpoint(w)
    w.appendFrame(2, fill('B'))
    w.commit(3)
    let p2 = freshPager()
    check p2.recover(w) == 1
    check p2.readPage(2)[0] == 'B'

suite "reopen":
  test "log survives close and reopen, and appends at the right offset":
    createDir(TmpDir)
    let path = TmpDir / "walreopen.wal"
    removeFile(path)
    block:
      let w = openWal(openFileVfs(path))
      w.appendFrame(1, fill('A'))
      w.commit(2)
      w.close()
    block:
      let w = openWal(openFileVfs(path))
      check w.stats.salt == 1
      w.appendFrame(2, fill('B'))
      w.commit(3)
      w.close()
    block:
      let w = openWal(openFileVfs(path))
      let p = freshPager()
      check p.recover(w) == 2
      check p.readPage(1)[0] == 'A'
      check p.readPage(2)[0] == 'B'
      w.close()
    removeFile(path)
