## Write-ahead log.
##
## The contract, in one sentence: **a transaction is durable if and only if its
## commit frame is on disk with a valid checksum**, and recovery never applies
## anything else.
##
## Frame layout (uniform, so replay is a loop, not a parser):
##
##   offset 0            magic "FOCWAL01", generation salt, base page count, crc
##   offset P, P*2, ...  [pid:i32][salt:i32][crc:i32][payload: PageSize]
##
##   pid >= 1   -> a page image
##   pid == -1  -> commit marker; payload[0..3] is the resulting page count
##
## Why it is built this way:
##   * the generation salt invalidates every stale frame at once, so a checkpoint
##     never has to truncate or rewrite the log — old frames simply stop matching;
##   * the checksum covers pid, salt and payload, so a torn write is detected at
##     the frame, not after it has corrupted a page;
##   * one sync per commit, and a commit can cover any number of staged frames:
##     that is the group-commit path, and it is the only thing that costs energy.
##
## Deliberately absent: any notion of a second writer. A single-writer log is the
## whole reason SQLite users get "database is locked" at 3 a.m.

import std/tables
import fossil/db/[bytes, errors, pager, vfs]

const
  WalMagic* = "FOCWAL01"
  WalHeaderPage* = PageSize           ## the log header occupies one whole page
  # Positive sentinel on purpose: a negative value would have to survive a
  # round-trip through unsigned decoding, and "pid == -1" silently became
  # "pid == 4294967295" — the commit marker was never recognised.
  CommitPid = 0x7FFFFFFF
  MaxPageId = CommitPid - 1
  MaxFrames = 1_000_000               ## hard stop against unbounded replay

type
  Wal* = ref object
    vfs*: Vfs
    salt*: int
    basePages*: int
    nextOff: int
    staged*: int                      ## frames written but not yet committed
    commits*: int
    appliedOnRecovery*: int
    index*: Table[int, int]           ## pid -> offset of its newest live frame

  WalStats* = object
    salt*: int
    basePages*: int
    staged*: int
    commits*: int

# ---------------------------------------------------------------------------
# binary helpers — big-endian, no casts, no pointers
# ---------------------------------------------------------------------------

proc crc32*(data: string; fromPos = 0; toPos = -1): int =
  ## CRC-32 (IEEE 802.3), computed bitwise.
  ##
  ## Bitwise on purpose: a 256-entry table is 1 KiB of constants that would show
  ## up in the wasm artifact, and this runs once per frame, not per byte of a
  ## query. Every intermediate stays below 2^32, so JavaScript computes the same
  ## number as C — which the parity test depends on.
  var c: uint32 = 0xFFFFFFFF'u32
  let last = if toPos < 0: data.len - 1 else: toPos
  for i in fromPos .. last:
    c = c xor uint32(uint8(data[i]))
    for _ in 0 .. 7:
      if (c and 1'u32) != 0:
        c = (c shr 1) xor 0xEDB88320'u32
      else:
        c = c shr 1
  # `int(bits)` raises in JavaScript as soon as the top bit is set, because Nim's
  # `int` is range-checked there while C is not — the two backends would disagree
  # on roughly half of all checksums. Casting through int32 keeps the same bits
  # and behaves identically in both.
  cast[int32](c xor 0xFFFFFFFF'u32).int

proc frameCrc(pid, salt: int; payload: string): int =
  ## Checksum covers pid, salt and payload — and *not* the checksum field
  ## itself. Computing it over the finished header silently checksums
  ## uninitialised memory, which is how the first version rejected every frame.
  var pre = newString(8)
  pre.putI32(0, pid)
  pre.putI32(4, salt)
  crc32(pre & payload)

# ---------------------------------------------------------------------------
# header
# ---------------------------------------------------------------------------

proc makeHeader(salt, basePages: int): string =
  result = newString(WalHeaderPage)
  for i in 0 ..< WalHeaderPage: result[i] = '\0'
  for i in 0 ..< WalMagic.len: result[i] = WalMagic[i]
  result.putI32(8, salt)
  result.putI32(12, basePages)

proc sealHeader(h: var string) =
  h.putI32(16, crc32(h, 0, 15))

proc parseHeader(raw: string): tuple[ok: bool; salt, basePages: int] =
  if raw.len < WalHeaderPage: return (false, 0, 0)
  for i in 0 ..< WalMagic.len:
    if raw[i] != WalMagic[i]: return (false, 0, 0)
  if crc32(raw, 0, 15) != raw.getI32(16): return (false, 0, 0)
  (true, raw.getI32(8), raw.getI32(12))

# ---------------------------------------------------------------------------
# lifecycle
# ---------------------------------------------------------------------------

proc openWal*(vfs: Vfs; basePages = 1): Wal =
  ## Opens (or initialises) a log. An empty or foreign file becomes a fresh
  ## generation — a log we cannot parse is not a log we may replay.
  result = Wal(vfs: vfs, salt: 1, basePages: basePages,
               nextOff: WalHeaderPage, staged: 0, commits: 0)
  if vfs.size >= WalHeaderPage:
    var raw = ""
    if vfs.readAt(0, raw, WalHeaderPage):
      let (ok, salt, base) = parseHeader(raw)
      if ok:
        result.salt = salt
        result.basePages = base
        # find the end of the valid prefix so appends land after it
        var off = WalHeaderPage
        while off + 12 + PageSize <= vfs.size:
          var hdr = ""
          if not vfs.readAt(off, hdr, 12): break
          let pid = hdr.getI32(0)
          if hdr.getI32(4) != salt: break
          var payload = ""
          if not vfs.readAt(off + 12, payload, PageSize): break
          if frameCrc(pid, salt, payload) != hdr.getI32(8): break
          if pid < 0 or pid > CommitPid: break
          off += 12 + PageSize
        result.nextOff = off
        return
  var hdr = makeHeader(result.salt, result.basePages)
  hdr.sealHeader()
  discard vfs.writeAt(0, hdr)

proc close*(w: Wal) =
  w.vfs.close()

proc stats*(w: Wal): WalStats =
  WalStats(salt: w.salt, basePages: w.basePages, staged: w.staged,
           commits: w.commits)

# ---------------------------------------------------------------------------
# append
# ---------------------------------------------------------------------------

proc appendFrame*(w: Wal; pid: int; payload: string): int =
  ## Stages one page image. No sync: durability is decided by `commit`.
  ## Returns the frame's offset, which is how the pager later finds a page whose
  ## newest image only exists here.
  if payload.len != PageSize:
    failf(mismatch, "WAL payload must be $1 bytes, got $2", PageSize, payload.len)
  # Page 0 is the header page. It has to travel through the log like any other
  # page, otherwise a transaction that changes the page count is only half
  # durable: the pages land, the count does not.
  if pid < 0 or pid > CommitPid:      # CommitPid is the commit marker itself
    failf(range, "invalid page id in WAL: $1", pid)
  var hdr = newString(12)
  hdr.putI32(0, pid)
  hdr.putI32(4, w.salt)
  hdr.putI32(8, frameCrc(pid, w.salt, payload))
  result = w.nextOff
  discard w.vfs.writeAt(w.nextOff, hdr & payload)
  w.nextOff += 12 + PageSize
  inc w.staged

proc appendPage*(w: Wal; pid: int; page: string): int =
  ## Convenience for closed page images.
  w.appendFrame(pid, page)

proc commit*(w: Wal; nPages: int) =
  ## Writes the commit marker and performs exactly one sync.
  var payload = newString(PageSize)
  for i in 0 ..< PageSize: payload[i] = '\0'
  payload.putI32(0, nPages)
  discard w.appendFrame(CommitPid, payload)
  w.vfs.sync()
  w.staged = 0
  inc w.commits

proc pending*(w: Wal): int = w.staged

# ---------------------------------------------------------------------------
# recovery
# ---------------------------------------------------------------------------

proc readFrame(w: Wal; off: int; pid: var int; payload: var string): bool =
  ## A frame is valid only if it is complete *and* checksummed correctly
  ## *and* belongs to the current generation.
  if off + 12 + PageSize > w.vfs.size: return false
  var hdr = ""
  if not w.vfs.readAt(off, hdr, 12): return false
  if hdr.getI32(4) != w.salt: return false          # stale generation
  if not w.vfs.readAt(off + 12, payload, PageSize): return false
  pid = hdr.getI32(0)
  if frameCrc(pid, hdr.getI32(4), payload) != hdr.getI32(8): return false
  pid >= 0 and pid <= CommitPid

proc readFrameAt*(w: Wal; off: int; payload: var string): bool =
  ## Payload of the frame at `off`, checked. Used by the pager to serve a read
  ## for a page whose newest image only exists in the log.
  var pid = 0
  w.readFrame(off, pid, payload)

proc recover*(p: Pager; w: Wal): int =
  ## Replays the committed prefix of the log into the pager.
  ##
  ## Frames after the last valid commit marker are ignored: an interrupted
  ## transaction must vanish entirely, not partially. Returns the number of
  ## frames applied.
  var off = WalHeaderPage
  var pendingPages: seq[tuple[pid: int, payload: string]]
  var committedPages = 0
  var lastNPages = -1
  var frames = 0

  while frames < MaxFrames:
    var pid = 0
    var payload = ""
    if not w.readFrame(off, pid, payload): break
    if pid == CommitPid:
      committedPages += pendingPages.len
      pendingPages.setLen(0)
      lastNPages = payload.getI32(0)
    else:
      pendingPages.add (pid, payload)
    off += 12 + PageSize
    inc frames

  # Second pass, applying only up to the last commit boundary.
  off = WalHeaderPage
  var applied = 0
  var seen = 0
  while seen < frames:
    var pid = 0
    var payload = ""
    if not w.readFrame(off, pid, payload): break
    if pid == CommitPid:
      if applied >= committedPages: break        # boundary reached
    else:
      if applied >= committedPages: break
      if pid == 0:
        p.applyHeaderPage(payload)        # page count, freelist, tree root
      else:
        if pid >= p.nPages: p.nPages = pid + 1
        p.writePage(pid, payload)
      w.index[pid] = off
      inc applied
    off += 12 + PageSize
    inc seen

  if applied > 0 and lastNPages >= 1 and lastNPages > p.nPages:
    p.nPages = lastNPages
  w.appliedOnRecovery = applied
  applied

# ---------------------------------------------------------------------------
# checkpoint
# ---------------------------------------------------------------------------

proc checkpoint*(p: Pager; w: Wal) =
  ## Folds the log into the main store, then starts a new generation.
  ##
  ## The old frames are not truncated away: the salt changes, so replay stops
  ## dead at the first old frame. Truncation would be an extra rewrite of a file
  ## that is about to be appended to anyway.
  p.flush()
  w.salt += 1
  w.basePages = p.nPages
  w.nextOff = WalHeaderPage
  w.staged = 0
  var hdr = makeHeader(w.salt, w.basePages)
  hdr.sealHeader()
  discard w.vfs.writeAt(0, hdr)
  w.vfs.sync()

proc logBytes*(w: Wal): int = w.vfs.size
