## Schema catalog: tables, columns, indexes, constraints.
##
## Storage strategy for v0.1 (in-memory engine):
##  * `rows` is an insertion-ordered map rowid -> Row;
##  * secondary indexes are sorted vectors of (key, rowid) so that both
##    equality and range lookups are O(log n) probes, without a B-tree yet.
## The public API of this module is what the paged storage engine will
## implement later, so swapping the backend does not touch the executor.

import std/[tables, algorithm, strutils]
import ./errors, ./values, ./ast, ./rowstore

type
  Column* = object
    name*: string
    typeName*: string
    aff*: Affinity
    notNull*: bool
    defaultVal*: Value
    hasDefault*: bool
    coll*: Collation
    isPk*: bool
    autoIncrement*: bool
    unique*: bool
    checkExpr*: Expr
    refTable*: string
    refCol*: string
    onDelete*: string

  IndexEntry* = object
    key*: seq[Value]
    rid*: int64

  Index* = ref object
    name*: string
    tableName*: string
    cols*: seq[int]          ## column ordinals in the table
    unique*: bool
    partial*: Expr           ## WHERE for partial indexes (nil = full)
    entries*: seq[IndexEntry]  ## kept sorted by (key…, rid)
    isPkIndex*: bool

  TableDef* = ref object
    name*: string
    cols*: seq[Column]
    colIdx*: Table[string, int]
    pkCols*: seq[int]
    rs*: RowStore              ## rows, in memory or in a B+tree — see rowstore.nim
    tid*: uint32               ## table id, the key prefix on disk (0 = memory)
    nextRowid*: int64
    indexes*: seq[Index]
    tableChecks*: seq[tuple[expr: Expr, name: string]]
    strict*: bool              ## STRICT typing (Foccil default)
    withoutRowid*: bool
    isView*: bool
    viewSql*: string

  Catalog* = ref object
    tables*: Table[string, TableDef]
    views*: Table[string, tuple[name: string, cols: seq[string], q: SelectStmt]]
    order*: seq[string]

# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------

func colByName*(t: TableDef; name: string): int =
  ## O(1) column lookup; the map is built once at CREATE/load time.
  t.colIdx.getOrDefault(name.toLowerAscii(), -1)

proc buildColIdx*(t: TableDef) =
  t.colIdx = initTable[string, int](t.cols.len * 2)
  for i, c in t.cols:
    t.colIdx[c.name.toLowerAscii()] = i

proc newTable*(name: string): TableDef =
  TableDef(name: name, rs: newMemStore(), tid: 0,
        nextRowid: 1, pkCols: @[], indexes: @[],
        tableChecks: @[], strict: true)

proc addColumn*(t: TableDef; c: Column) =
  t.cols.add c
  t.colIdx[c.name.toLowerAscii()] = t.cols.high

proc addIndex*(t: TableDef; idx: Index) = t.indexes.add idx

func pkIndex*(t: TableDef): Index =
  ## The implicit index on the primary key, or the rowid if there is none.
  for ix in t.indexes:
    if ix.isPkIndex: return ix
  nil

# ---------------------------------------------------------------------------
# Index maintenance
# ---------------------------------------------------------------------------

func cmpIndexEntry(a, b: IndexEntry): int =
  let n = min(a.key.len, b.key.len)
  for i in 0 ..< n:
    let c = compare(a.key[i], b.key[i])
    if c != 0: return c
  if a.key.len != b.key.len: return cmp(a.key.len, b.key.len)
  cmp(a.rid, b.rid)

proc lowerBound(ix: Index; key: seq[Value]): int =
  ## First position whose key >= `key` (rowid ignored).
  var lo = 0
  var hi = ix.entries.len
  while lo < hi:
    let mid = (lo + hi) div 2
    var c = 0
    let n = min(key.len, ix.entries[mid].key.len)
    for i in 0 ..< n:
      c = compare(ix.entries[mid].key[i], key[i])
      if c != 0: break
    if c == 0: c = cmp(ix.entries[mid].key.len, key.len)
    if c < 0: lo = mid + 1 else: hi = mid
  lo

proc indexInsert*(ix: Index; key: seq[Value]; rid: int64) =
  let entry = IndexEntry(key: key, rid: rid)
  var pos = ix.lowerBound(key)
  # keep equal keys ordered by rowid for deterministic scans
  while pos < ix.entries.len and cmpIndexEntry(ix.entries[pos], entry) < 0:
    inc pos
  ix.entries.insert(entry, pos)

proc indexDelete*(ix: Index; key: seq[Value]; rid: int64) =
  var pos = ix.lowerBound(key)
  while pos < ix.entries.len:
    let e = ix.entries[pos]
    if e.rid == rid and e.key.len == key.len:
      var same = true
      for i in 0 ..< key.len:
        if compare(e.key[i], key[i]) != 0:
          same = false
          break
      if same:
        ix.entries.delete(pos)
        return
    elif compare(e.key[0], key[0]) > 0:
      return
    inc pos

proc indexScanEq*(ix: Index; key: seq[Value]): seq[int64] =
  ## All rowids whose index key equals `key`, in insertion order of the index.
  result = @[]
  var pos = ix.lowerBound(key)
  while pos < ix.entries.len:
    let e = ix.entries[pos]
    if e.key.len != key.len: break
    var same = true
    for i in 0 ..< key.len:
      if compare(e.key[i], key[i]) != 0:
        same = false
        break
    if not same: break
    result.add e.rid
    inc pos

proc indexScanPrefix*(ix: Index; prefix: seq[Value]): seq[int64] =
  ## Range scan on a leading prefix (used by `x > ?`, BETWEEN, LIKE 'abc%').
  result = @[]
  var pos = ix.lowerBound(prefix)
  while pos < ix.entries.len:
    let e = ix.entries[pos]
    if e.key.len < prefix.len: break
    var same = true
    for i in 0 ..< prefix.len:
      if compare(e.key[i], prefix[i]) != 0:
        same = false
        break
    if not same: break
    result.add e.rid
    inc pos

proc indexAll*(ix: Index): seq[int64] =
  result = newSeqOfCap[int64](ix.entries.len)
  for e in ix.entries: result.add e.rid

# ---------------------------------------------------------------------------
# Row access
# ---------------------------------------------------------------------------

proc insertRow*(t: TableDef; row: Row): int64 =
  let rid = t.nextRowid
  inc t.nextRowid
  t.rs.put(rid, row)
  rid

proc deleteRow*(t: TableDef; rid: int64) =
  discard t.rs.del(rid)

proc updateRow*(t: TableDef; rid: int64; row: Row) =
  t.rs.put(rid, row)

proc scanRowids*(t: TableDef): seq[int64] = t.rs.rowids()

proc rowCount*(t: TableDef): int = t.rs.len

# ---------------------------------------------------------------------------
# Catalog
# ---------------------------------------------------------------------------

proc newCatalog*(): Catalog =
  Catalog(tables: initTable[string, TableDef](),
          views: initTable[string, tuple[name: string, cols: seq[string], q: SelectStmt]](),
          order: @[])

func normName*(s: string): string = s.toLowerAscii()

proc findTable*(c: Catalog; name: string): TableDef =
  c.tables.getOrDefault(normName(name), nil)

proc findView*(c: Catalog; name: string): (bool, tuple[name: string, cols: seq[string], q: SelectStmt]) =
  let k = normName(name)
  if c.views.hasKey(k): (true, c.views[k]) else: (false, (name: "", cols: @[], q: nil))

proc registerTable*(c: Catalog; t: TableDef) =
  t.buildColIdx()
  c.tables[normName(t.name)] = t
  c.order.add t.name

proc dropTable*(c: Catalog; name: string): bool =
  let k = normName(name)
  if c.tables.hasKey(k):
    c.tables.del k
    let pos = c.order.find(name)
    if pos >= 0: c.order.delete(pos)
    return true
  false

proc renameTable*(c: Catalog; oldName, newName: string) =
  let k = normName(oldName)
  if not c.tables.hasKey(k):
    fail(notFound, "no such table: " & oldName)
  if c.tables.hasKey(normName(newName)):
    fail(constraint, "table already exists: " & newName)
  let t = c.tables[k]
  c.tables.del k
  t.name = newName
  c.tables[normName(newName)] = t
  for i in 0 ..< c.order.len:
    if c.order[i] == oldName: c.order[i] = newName
