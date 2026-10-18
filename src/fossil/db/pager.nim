## Pager: fixed-size pages over a VFS, with an LRU cache and dirty tracking.
##
## Design choices that matter:
##   * page size is 4 KiB — one page per syscall, page-aligned with the OS and
##     with the filesystem block size on anything we care about;
##   * the header is its own page and carries a magic + version + counters, so a
##     file that is not ours (or a truncated one) is rejected instead of being
##     interpreted as valid pages;
##   * dirty pages are flushed in one pass and `sync` is called once, not per
##     page: on the energy side, fsync dominates everything else;
##   * eviction prefers clean pages and never drops a dirty one silently.

import std/[tables, sets]
import fossil/db/[errors, vfs]

const
  PageSize* = 4096
  DbMagic* = "FOCDB\x01\x00\x00"   ## 8 bytes: name + format generation
  DbVersion* = 1'i32
  HeaderSize = 32                   ## used part of page 0
  PageZero = '\0'
  DefaultCachePages* = 64           ## 256 KiB resident by default

type
  Pager* = ref object
    vfs*: Vfs
    pages: Table[int, string]
    dirty: HashSet[int]
    lru: seq[int]                   ## least recent first
    capacity: int
    nPages*: int                    ## logical page count (excluding page 0)
    freeHead*: int                  ## first page of the freelist, 0 = none
    root*: int                      ## B+tree root page, 0 = no tree yet
    hits*, misses*, evictions*, flushes*: int

  PagerStats* = object
    pages*: int
    hits*, misses*, evictions*, flushes*: int
    ioReads*, ioWrites*: int
    resident*: int

proc blankPage(): string =
  result = newString(PageSize)
  for i in 0 ..< PageSize: result[i] = PageZero

# ---------------------------------------------------------------------------
# header
# ---------------------------------------------------------------------------

proc readI32(s: string; at: int): int32 =
  var v: uint32 = 0
  for i in 0 .. 3:
    v = (v shl 8) or uint32(uint8(s[at + i]))
  int32(v)

proc writeI32(s: var string; at: int; v: int32) =
  let u = uint32(v)
  s[at + 0] = char((u shr 24) and 0xFF)
  s[at + 1] = char((u shr 16) and 0xFF)
  s[at + 2] = char((u shr 8) and 0xFF)
  s[at + 3] = char(u and 0xFF)

proc makeHeader(nPages, freeHead, root: int): string =
  result = blankPage()
  for i in 0 ..< DbMagic.len: result[i] = DbMagic[i]
  writeI32(result, 8, DbVersion)
  writeI32(result, 12, int32(nPages))
  writeI32(result, 16, int32(freeHead))
  writeI32(result, 20, int32(root))

proc parseHeader(p: Pager; hdr: string): bool =
  for i in 0 ..< DbMagic.len:
    if hdr[i] != DbMagic[i]: return false
  if readI32(hdr, 8) != DbVersion: return false
  p.nPages = int(readI32(hdr, 12))
  p.freeHead = int(readI32(hdr, 16))
  p.root = int(readI32(hdr, 20))
  if p.nPages < 0 or p.freeHead < 0 or p.root < 0: return false
  true

# ---------------------------------------------------------------------------
# cache
# ---------------------------------------------------------------------------

proc flush*(p: Pager)   # forward: eviction may force a flush

proc touch(p: Pager; pid: int) =
  var i = 0
  while i < p.lru.len:
    if p.lru[i] == pid:
      p.lru.delete(i)
      break
    inc i
  p.lru.add pid

proc evictOne(p: Pager) =
  ## Drops the least recently used *clean* page. Dirty pages are flushed first
  ## if there is nothing clean to drop, because evicting a dirty page without
  ## writing it would lose data.
  if p.pages.len < p.capacity: return
  for pid in p.lru:
    if pid notin p.dirty:
      p.pages.del pid
      let idx = p.lru.find(pid)
      if idx >= 0: p.lru.delete(idx)
      inc p.evictions
      return
  p.flush()
  for pid in p.lru:
    p.pages.del pid
    inc p.evictions
    break
  let first = p.lru[0]
  p.pages.del first
  p.lru.delete(0)

proc loadPage(p: Pager; pid: int): string =
  result = blankPage()
  let off = pid * PageSize
  var buf = ""
  if p.vfs.readAt(off, buf, PageSize) and buf.len == PageSize:
    result = buf
  # A page beyond the file end is legal: it is a fresh, zero-filled page.

proc readPage*(p: Pager; pid: int): string =
  ## Returns a copy. Copies keep the cache honest: nothing outside the pager can
  ## hold a reference to a page that may be evicted or overwritten.
  if pid < 0: failf(range, "page $1 out of range", pid)
  if p.pages.hasKey(pid):
    inc p.hits
    p.touch(pid)
    return p.pages[pid]
  inc p.misses
  p.evictOne()
  let page = p.loadPage(pid)
  p.pages[pid] = page
  p.touch(pid)
  result = page

proc writePage*(p: Pager; pid: int; data: string) =
  if pid < 1: fail(range, "cannot write page 0 directly; use the header API")
  if data.len != PageSize:
    failf(mismatch, "page must be $1 bytes, got $2", PageSize, data.len)
  if p.pages.hasKey(pid):
    p.pages[pid] = data
  else:
    p.evictOne()
    p.pages[pid] = data
  p.touch(pid)
  p.dirty.incl pid
  if pid >= p.nPages: p.nPages = pid + 1

proc flush*(p: Pager) =
  ## Writes every dirty page, then the header, then syncs once.
  for pid in p.dirty:
    if not p.vfs.writeAt(pid * PageSize, p.pages[pid]):
      failf(ioErr, "write failed on page $1", pid)
  p.dirty.clear()
  let hdr = makeHeader(p.nPages, p.freeHead, p.root)
  if not p.vfs.writeAt(0, hdr):
    fail(ioErr, "cannot write header")
  p.vfs.sync()
  inc p.flushes

# ---------------------------------------------------------------------------
# allocation
# ---------------------------------------------------------------------------

proc allocPage*(p: Pager): int =
  ## Reuses a freed page when possible; otherwise extends the file by one page.
  if p.nPages < 1: p.nPages = 1        # page 0 is the header
  if p.freeHead != 0:
    result = p.freeHead
    let raw = if p.pages.hasKey(result): p.pages[result]
              else: p.loadPage(result)
    p.freeHead = int(readI32(raw, 0))
    p.writePage(result, blankPage())
    return
  result = p.nPages
  p.writePage(result, blankPage())
  p.nPages = result + 1

proc freePage*(p: Pager; pid: int) =
  if pid <= 0 or pid >= p.nPages: failf(range, "cannot free page $1", pid)
  # A second free would point the page at itself and turn the freelist into a
  # cycle, which is exactly how a database eats itself. Refuse it.
  var cur = p.freeHead
  var guard = 0
  while cur != 0:
    if cur == pid: failf(misuse, "page $1 is already free", pid)
    if guard > p.nPages: fail(corrupt, "freelist is not acyclic")
    cur = int(readI32(p.readPage(cur), 0))
    inc guard
  var raw = blankPage()
  writeI32(raw, 0, int32(p.freeHead))
  p.freeHead = pid
  p.writePage(pid, raw)

proc freeCount*(p: Pager): int =
  var pid = p.freeHead
  var guard = 0
  while pid != 0 and guard <= p.nPages:
    inc result
    let raw = p.readPage(pid)
    pid = int(readI32(raw, 0))
    inc guard

# ---------------------------------------------------------------------------
# lifecycle
# ---------------------------------------------------------------------------

proc openPager*(vfs: Vfs; cachePages = DefaultCachePages): Pager =
  result = Pager(vfs: vfs, capacity: max(cachePages, 4),
                 pages: initTable[int, string](), dirty: initHashSet[int]())
  if vfs.size == 0:
    # Brand new store. Page 0 is the header, so the first data page is 1.
    result.nPages = 1
    result.freeHead = 0
    discard vfs.writeAt(0, makeHeader(0, 0, 0))
    return
  var hdr = ""
  if not vfs.readAt(0, hdr, PageSize) or hdr.len != PageSize:
    fail(corrupt, "database file is shorter than one page")
  if not result.parseHeader(hdr):
    fail(corrupt, "not a Foccil DB file, or written by another format version")
  if result.nPages < 1: result.nPages = 1   # tolerate headers written before page 0 was counted

proc close*(p: Pager) =
  ## Flushes, then releases. Closing never discards dirty pages.
  if p.dirty.len > 0: p.flush()
  p.pages.clear()
  p.lru.setLen(0)
  p.vfs.close()

proc stats*(p: Pager): PagerStats =
  PagerStats(pages: p.nPages, hits: p.hits, misses: p.misses,
             evictions: p.evictions, flushes: p.flushes,
             ioReads: p.vfs.ioReads, ioWrites: p.vfs.ioWrites,
             resident: p.pages.len)

proc integrityOk*(p: Pager): bool =
  ## Cheap structural check: every cached page has the right size and the
  ## freelist is acyclic and inside the file.
  for pid, page in p.pages:
    if page.len != PageSize: return false
    if pid < 0 or pid >= p.nPages: return false
  var seen = initHashSet[int]()
  var pid = p.freeHead
  var guard = 0
  while pid != 0:
    if guard > p.nPages: return false
    if seen.containsOrIncl(pid): return false
    if pid <= 0 or pid >= p.nPages: return false
    let raw = p.readPage(pid)
    pid = int(readI32(raw, 0))
    inc guard
  true
