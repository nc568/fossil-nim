## Row storage: one interface, two backends (memory and B+tree).
##
## The executor never learns where a row lives. `TableDef` holds a `RowStore`,
## and every scan, lookup and write goes through the six operations below. That
## is the entire point of this module: the SQL layer was written and tested
## against an in-memory table, and switching a table to disk must not touch a
## single line of query code.
##
## What the disk backend is, precisely:
##
##   * all rows of all tables live in **one** B+tree, keyed by
##     `tableId (4 bytes, big-endian) ‖ rowid (8 bytes, order-preserving)`.
##     One tree means one root, and the root is already in the file header — so
##     a database needs no separate page-directory format.
##   * the key is big-endian and the rowid is stored with its sign bit flipped,
##     so lexicographic key order is numeric rowid order. A table scan is a
##     prefix scan; a rowid lookup is a single descent; `ORDER BY rowid` is free.
##   * writes are **staged**, never applied on the spot: `put`/`del` go to a
##     pending overlay, and the tree is touched at commit. Reads see the overlay.
##     This is what makes rollback free (drop the overlay, nothing was written)
##     and what makes the WAL meaningful (one commit = one atomic batch).
##
## Anything that has to be true of a row — its encoding, its key — is defined
## here once, so memory and disk cannot drift apart silently.

import std/[tables, sets, algorithm, strutils]
import ./errors, ./btree, ./values

const
  RowKeyLen* = 12
  MaxEncodedRow* = 64 * 1024 * 1024   ## mirrors btree.MaxValueSize

type
  StoreKind* = enum
    skMemory
    skDisk

  RowStore* = ref object
    case kind*: StoreKind
    of skMemory:
      m: OrderedTable[int64, Row]
      orderSeq: seq[int64]
    of skDisk:
      tree: Btree
      tid: uint32
      live: HashSet[int64]          ## rowids known to be in the tree
      pending: Table[int64, Row]    ## staged writes (rowid -> row)
      pendingDel: HashSet[int64]
      pendingOrder: seq[int64]      ## insertion order of staged *new* rowids

proc newMemStore*(): RowStore =
  RowStore(kind: skMemory, m: initOrderedTable[int64, Row]())

# ---------------------------------------------------------------------------
# Keys
# ---------------------------------------------------------------------------

func rowKey*(tid: uint32; rid: int64): string =
  ## Order-preserving: comparing two keys bytewise compares the rowids as
  ## signed 64-bit integers. Done with arithmetic, not casts, so that JS builds
  ## of this module behave identically (they never reach this code, but a module
  ## that only works on one backend is a trap for the next person).
  result = newString(RowKeyLen)
  result[0] = chr(int((tid shr 24) and 0xFF'u32))
  result[1] = chr(int((tid shr 16) and 0xFF'u32))
  result[2] = chr(int((tid shr 8) and 0xFF'u32))
  result[3] = chr(int(tid and 0xFF'u32))
  let x = rid xor low(int64)          # sign bit flipped -> unsigned order
  for i in 0 ..< 8:
    result[4 + i] = chr(int((x shr (56 - 8 * i)) and 0xFF))

func ridFromKey*(k: string; at = 4): int64 =
  var x: int64 = 0
  for i in 0 ..< 8:
    x = (x shl 8) or int64(uint8(k[at + i]))
  x xor low(int64)

func keyTid*(k: string): uint32 =
  (uint32(uint8(k[0])) shl 24) or (uint32(uint8(k[1])) shl 16) or
  (uint32(uint8(k[2])) shl 8) or uint32(uint8(k[3]))

# ---------------------------------------------------------------------------
# Row encoding
# ---------------------------------------------------------------------------
#
#   [u16 ncols] then per value: [u8 kind][payload]
#     vkNull  -
#     vkInt   8 bytes, two's complement, little-endian
#     vkReal  8 bytes IEEE-754 (bit-exact on native; text on JS, which has no
#             uint64 and, more importantly, no filesystem to store it in)
#     vkText  [u32 len][bytes]
#     vkBlob  [u32 len][bytes]
#     vkBool  1 byte
#
# Integers are split with shifts and masks rather than `cast`, because a cast on
# a negative int64 is exactly the kind of thing that behaves differently across
# backends — and a row that reads back differently is worse than no row.

proc putU32(s: var string; v: int) =
  s.add chr(v and 0xFF)
  s.add chr((v shr 8) and 0xFF)
  s.add chr((v shr 16) and 0xFF)
  s.add chr((v shr 24) and 0xFF)

func getU32(s: string; at: int): int =
  int(uint32(uint8(s[at]))) or (int(uint32(uint8(s[at + 1]))) shl 8) or
  (int(uint32(uint8(s[at + 2]))) shl 16) or (int(uint32(uint8(s[at + 3]))) shl 24)

proc encodeRow*(r: Row): string =
  if r.len > 65535: failf(range, "a row may have at most 65535 columns")
  result = newStringOfCap(16 * r.len + 8)
  result.add chr(r.len and 0xFF)
  result.add chr((r.len shr 8) and 0xFF)
  for v in r:
    result.add chr(ord(v.kind))
    case v.kind
    of vkNull: discard
    of vkInt:
      var x = v.i
      for _ in 0 ..< 8:
        result.add chr(int(x and 0xFF))
        x = x shr 8
    of vkReal:
      when defined(js):
        let t = formatReal(v.r)
        result.putU32(t.len)
        result.add t
      else:
        var u = cast[uint64](v.r)
        for _ in 0 ..< 8:
          result.add chr(int(u and 0xFF'u64))
          u = u shr 8
    of vkText:
      if v.t.len > MaxTextLen: failf(range, "text value too large")
      result.putU32(v.t.len)
      result.add v.t
    of vkBlob:
      if v.bl.len > MaxTextLen: failf(range, "blob value too large")
      result.putU32(v.bl.len)
      for b in v.bl: result.add chr(int(b))
    of vkBool:
      result.add (if v.bo: '\1' else: '\0')
  if result.len > MaxEncodedRow:
    failf(range, "encoded row of $1 bytes exceeds the $2-byte limit",
          result.len, MaxEncodedRow)

proc decodeRow*(s: string): Row =
  if s.len < 2: failf(corrupt, "row record shorter than its own header")
  let n = int(uint8(s[0])) or (int(uint8(s[1])) shl 8)
  result = newSeqOfCap[Value](n)
  var i = 2
  for _ in 0 ..< n:
    if i >= s.len: failf(corrupt, "row record ends in the middle of a value")
    let kind = int(uint8(s[i]))
    inc i
    case kind
    of 0: result.add nullValue()
    of 1:
      if i + 8 > s.len: failf(corrupt, "truncated integer in row record")
      var x: int64 = 0
      for b in 0 ..< 8:
        # `shl` wraps and does not raise, so setting bit 63 in the last step
        # produces the correct two's-complement value including for negatives.
        x = x or (int64(uint8(s[i + b])) shl (8 * b))
      inc i, 8
      result.add intValue(x)
    of 2:
      when defined(js):
        if i + 4 > s.len: failf(corrupt, "truncated real in row record")
        let L = getU32(s, i)
        if i + 4 + L > s.len: failf(corrupt, "truncated real in row record")
        result.add realValue(parseFloat(s[i + 4 ..< i + 4 + L]))
        inc i, 4 + L
      else:
        if i + 8 > s.len: failf(corrupt, "truncated real in row record")
        var u: uint64 = 0
        for b in countdown(7, 0):
          u = (u shl 8) or uint64(uint8(s[i + b]))
        inc i, 8
        result.add realValue(cast[float64](u))
    of 3, 4:
      if i + 4 > s.len: failf(corrupt, "truncated length in row record")
      let L = getU32(s, i)
      if L < 0 or i + 4 + L > s.len: failf(corrupt, "truncated value in row record")
      let payload = s[i + 4 ..< i + 4 + L]
      inc i, 4 + L
      if kind == 3:
        result.add textValue(payload)
      else:
        var bl = newSeq[byte](L)
        for k in 0 ..< L: bl[k] = uint8(payload[k])
        result.add blobValue(bl)
    of 5:
      if i >= s.len: failf(corrupt, "truncated bool in row record")
      result.add boolValue(s[i] != '\0')
      inc i
    else:
      failf(corrupt, "unknown value kind $1 in row record", kind)

# ---------------------------------------------------------------------------
# Disk store
# ---------------------------------------------------------------------------

proc newDiskStore*(tree: Btree; tid: uint32; existing: seq[int64]): RowStore =
  result = RowStore(kind: skDisk, tree: tree, tid: tid, live: initHashSet[int64](),
                    pending: initTable[int64, Row](), pendingDel: initHashSet[int64](),
                    pendingOrder: @[])
  for rid in existing: result.live.incl rid

proc rowKeys*(tree: Btree; tid: uint32): seq[int64] =
  ## Every rowid of one table, in key order. Used at open time to learn what the
  ## table contains; the B+tree has no cheap "count" and pretending otherwise
  ## would produce a wrong `len`.
  let prefix = rowKey(tid, low(int64))[0 ..< 4]
  var ks: seq[int64] = @[]
  tree.eachPrefix(prefix, proc(k, v: string) = ks.add ridFromKey(k))
  ks

proc contains*(s: RowStore; rid: int64): bool =
  case s.kind
  of skMemory: s.m.hasKey(rid)
  of skDisk:
    if s.pendingDel.contains(rid): return false
    if s.pending.hasKey(rid): return true
    if s.live.contains(rid): return true
    # Not in the live set: the row may still be on disk if the catalogue was
    # built from a partial scan. Ask the tree rather than guess.
    let (found, _) = s.tree.get(rowKey(s.tid, rid))
    found

proc get*(s: RowStore; rid: int64): tuple[found: bool, row: Row] =
  case s.kind
  of skMemory:
    if s.m.hasKey(rid): (true, s.m[rid]) else: (false, @[])
  of skDisk:
    if s.pendingDel.contains(rid): return (false, @[])
    if s.pending.hasKey(rid): return (true, s.pending[rid])
    let (found, raw) = s.tree.get(rowKey(s.tid, rid))
    if not found: (false, @[]) else: (true, decodeRow(raw))

proc put*(s: RowStore; rid: int64; row: Row) =
  case s.kind
  of skMemory:
    if not s.m.hasKey(rid): s.orderSeq.add rid
    s.m[rid] = row
  of skDisk:
    if not s.contains(rid): s.pendingOrder.add rid
    s.pendingDel.excl rid
    s.pending[rid] = row

proc del*(s: RowStore; rid: int64): bool =
  case s.kind
  of skMemory:
    if not s.m.hasKey(rid): return false
    s.m.del rid
    let p = s.orderSeq.find(rid)
    if p >= 0: s.orderSeq.delete(p)
    true
  of skDisk:
    if not s.contains(rid): return false
    s.pending.del rid
    s.pendingDel.incl rid
    true

proc rowids*(s: RowStore): seq[int64] =
  ## Scan order. Memory: insertion order (what the executor has always used).
  ## Disk: rowid order, which is what a B+tree scan produces and what SQLite
  ## produces for a rowid table — the two coincide for ordinary inserts, and
  ## where they do not, the disk answer is the one the standard leaves open.
  case s.kind
  of skMemory:
    result = s.orderSeq
  of skDisk:
    var extra: seq[int64] = @[]
    for rid in s.pendingOrder:
      if s.pending.hasKey(rid): extra.add rid
    if extra.len > 0: extra.sort()
    var i = 0
    let base = s.live
    var sortedLive = newSeqOfCap[int64](base.len)
    for rid in base: sortedLive.add rid
    sortedLive.sort()
    result = newSeqOfCap[int64](sortedLive.len + extra.len)
    var j = 0
    while i < sortedLive.len or j < extra.len:
      var takeExtra = false
      if i >= sortedLive.len: takeExtra = true
      elif j < extra.len and extra[j] < sortedLive[i]: takeExtra = true
      let rid = if takeExtra: extra[j] else: sortedLive[i]
      if takeExtra: inc j else: inc i
      if s.pendingDel.contains(rid): continue
      if s.pending.hasKey(rid) or s.live.contains(rid): result.add rid

proc len*(s: RowStore): int =
  case s.kind
  of skMemory: s.m.len
  of skDisk:
    var n = 0
    for _ in s.rowids(): inc n
    n

iterator items*(s: RowStore): Row =
  ## Convenience for tests and small tools; the executor uses `rowids` + `get`
  ## so that it never materialises a table it does not need.
  for rid in s.rowids():
    let (ok, r) = s.get(rid)
    if ok: yield r

proc clear*(s: RowStore) =
  case s.kind
  of skMemory:
    s.m.clear()
    s.orderSeq.setLen(0)
  of skDisk:
    for rid in s.live: s.pendingDel.incl rid
    s.pending.clear()
    s.pendingOrder.setLen(0)
    s.live.clear()

# ---------------------------------------------------------------------------
# Commit
# ---------------------------------------------------------------------------

proc cloneStore*(s: RowStore): RowStore =
  ## Deep-enough copy for a transaction snapshot: the rows themselves are
  ## immutable once stored (every mutation replaces the seq), so sharing them
  ## is safe; what must not be shared is the map.
  result = newMemStore()
  for rid in s.rowids():
    let (found, row) = s.get(rid)
    if found: result.put(rid, row)

proc stagedChanges*(s: RowStore): int =
  case s.kind
  of skMemory: 0
  of skDisk: s.pending.len + s.pendingDel.len

proc flush*(s: RowStore) =
  ## Applies the overlay to the tree. Called exactly once per commit, from the
  ## engine; the pages it dirties are what the WAL then makes durable.
  if s.kind != skDisk: return
  for rid in s.pendingDel:
    discard s.tree.del(rowKey(s.tid, rid))
    s.live.excl rid
  for rid, row in s.pending:
    s.tree.put(rowKey(s.tid, rid), encodeRow(row))
    s.live.incl rid
  s.pending.clear()
  s.pendingDel.clear()
  s.pendingOrder.setLen(0)

proc discardStaged*(s: RowStore) =
  ## Rollback: nothing was written, so there is nothing to undo on disk.
  if s.kind != skDisk: return
  s.pending.clear()
  s.pendingDel.clear()
  s.pendingOrder.setLen(0)
