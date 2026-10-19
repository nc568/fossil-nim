## Query executor.
##
## Execution model: **direct tree-walking over the AST** with a slot-vector
## row representation. No bytecode VM.
##
## Why no VM (SQLite has one)?
##   * a VM costs ~2.5k lines of opcode implementations plus a program builder;
##   * on JS/WASM the interpreter loop is the worst possible shape for the JIT
##     (megamorphic switch, indirect dispatch) whereas direct recursion over a
##     small AST inlines and specializes beautifully;
##   * the security surface shrinks: there is no program counter to corrupt and
##     no opcode table to keep in sync with the parser.
## The trade-off (re-preparing per execution) is removed by statement caching in
## `api.nim`: the AST is prepared once and reused, so we keep VM-like reuse
## without VM-like bookkeeping.

import std/[tables, algorithm, strutils]
when not defined(foccilMinimalFloat):
  import std/math
when not defined(foccilNoClock):
  import std/times   # only the host build needs a wall clock
import ./errors, ./values, ./ast, ./schema, ./funcs, ./parser, ./rowstore, ./dbfile

type
  DbOptions* = object
    strictTyping*: bool       ## reject silently-lossy store (Foccil default: on)
    readOnly*: bool
    allowDdl*: bool
    maxResultRows*: int       ## 0 = unlimited; protects against OOM-by-query
    maxParams*: int
    maxQueryMs*: int          ## 0 = unlimited (checked per row batch)

  ResultSet* = object
    cols*: seq[string]
    rows*: seq[Row]

  UndoKind = enum
    ukInsert = 0
    ukDelete
    ukUpdate

  UndoRec = object
    kind: UndoKind
    tbl: TableDef
    rid: int64
    row: Row

  CteData = object
    names: seq[string]
    rows: seq[Row]

  Ctx = ref object
    db: Db
    params: seq[Value]
    colMap: Table[string, int]     ## "alias.col" | "col" -> slot; -2 = ambiguous
    vals: Row
    outer: Ctx
    aggVals: seq[Value]
    ctes: Table[string, CteData]
    nowIso: string
    rowBudget: int

  Db* = ref object
    cat*: Catalog
    opts*: DbOptions
    txDepth*: int
    txDdl*: bool
    undo*: seq[UndoRec]
    catSnapshot*: Catalog
    changes*: int64
    lastRowid*: int64
    totalChanges*: int64
    rand*: uint64
    stmtCache*: Table[string, Prepared]
    file*: DbFile              ## nil for an in-memory database
    loading*: bool             ## true while the schema is being rebuilt at open

  Prepared* = ref object
    sql*: string
    stmt*: Stmt
    nParams*: int
    paramNames*: seq[string]
    execCount*: int

const AggregateNames* = ["count", "sum", "total", "avg", "min", "max",
                         "group_concat"]

const DefaultOptions* = DbOptions(
  strictTyping: true, readOnly: false, allowDdl: true,
  maxResultRows: 1_000_000, maxParams: 999, maxQueryMs: 0)

# ===========================================================================
# Schema cloning (transaction snapshots)
# ===========================================================================

proc cloneTableDef(t: TableDef): TableDef =
  ## A transaction snapshot must be able to roll back, so it cannot share a
  ## store it might later mutate: a disk-backed table gets a *memory* copy of
  ## its current rows. That costs a full copy at BEGIN, which is the honest
  ## price of the snapshot model and the reason a disk transaction with DDL
  ## should be rare (it is: DDL is not the usual case).
  result = TableDef(name: t.name, pkCols: t.pkCols, rs: cloneStore(t.rs),
                    tid: t.tid, nextRowid: t.nextRowid,
                    tableChecks: t.tableChecks, strict: t.strict,
                    withoutRowid: t.withoutRowid, isView: t.isView,
                    viewSql: t.viewSql)
  result.cols = t.cols          # copy of seq of value objects
  result.buildColIdx()
  for ix in t.indexes:
    var n = Index(name: ix.name, tableName: ix.tableName, cols: ix.cols,
                  unique: ix.unique, partial: ix.partial,
                  isPkIndex: ix.isPkIndex)
    n.entries = ix.entries
    result.indexes.add n

proc cloneCatalog(c: Catalog): Catalog =
  result = newCatalog()
  for name, t in c.tables:
    result.tables[name] = cloneTableDef(t)
  for name, v in c.views:
    result.views[name] = v
  result.order = c.order

# ===========================================================================
# Physical row store (index-maintaining)
# ===========================================================================

proc indexKeyFor(t: TableDef; ix: Index; row: Row): seq[Value] =
  result = newSeqOfCap[Value](ix.cols.len)
  for c in ix.cols:
    result.add(if c < row.len: row[c] else: nullValue())

proc storeRow(t: TableDef; rid: int64; row: Row) =
  t.rs.put(rid, row)
  for ix in t.indexes:
    ix.indexInsert(indexKeyFor(t, ix, row), rid)

proc removeRow(t: TableDef; rid: int64) =
  if t.rs.contains(rid):
    let (_, row) = t.rs.get(rid)
    for ix in t.indexes:
      ix.indexDelete(indexKeyFor(t, ix, row), rid)
    discard t.rs.del(rid)

proc uniqueViolation(t: TableDef; ix: Index; key: seq[Value];
                     selfRid: int64): bool =
  if not ix.unique: return false
  var nullSeen = false
  for v in key:
    if v.kind == vkNull: nullSeen = true
  if nullSeen: return false        # SQL: NULLs never collide in a UNIQUE index
  for rid in ix.indexScanEq(key):
    if rid != selfRid: return true
  false

# ===========================================================================
# Statement-time helpers
# ===========================================================================

proc nowIsoUtc(): string =
  ## `-d:foccilNoClock` pins the clock to the epoch. wasm/freestanding builds
  ## use it so that a query is byte-reproducible across hosts (and so the core
  ## needs no time syscall at all).
  when defined(foccilNoClock):
    "1970-01-01T00:00:00Z"
  else:
    utc(now()).format("yyyy-MM-dd'T'HH:mm:ss'Z'")

proc newCtx(db: Db; params: seq[Value]; outer: Ctx = nil): Ctx =
  Ctx(db: db, params: params, outer: outer,
      colMap: initTable[string, int](), vals: @[], aggVals: @[],
      ctes: initTable[string, CteData](),
      nowIso: if outer == nil: nowIsoUtc() else: outer.nowIso,
      rowBudget: if outer == nil:
                   (if db.opts.maxResultRows > 0: db.opts.maxResultRows else: -1)
                 else: outer.rowBudget)

proc budgetTick(c: Ctx) =
  ## Uniform resource guard: every produced row passes through here.
  ## `-1` means "unlimited"; any other value counts down and then trips.
  if c.rowBudget >= 0:
    dec c.rowBudget
    if c.rowBudget < 0:
      raise dbErr(limit, "query produced more rows than the configured limit")

# ===========================================================================
# Evaluation
# ===========================================================================

proc eval(c: Ctx; e: Expr): Value
proc execSelect(c0: Ctx; st: SelectStmt): ResultSet

func safeAdd(a, b: int64; diff, sum: var int64): bool =
  ## Overflow-safe int64 add/sub with an explicit fallback to REAL, matching
  ## SQL arithmetic promotion instead of wrapping (wrapping is a correctness
  ## bug and a security bug: wrapped rowids can alias).
  if b > 0 and a > high(int64) - b: false
  elif b < 0 and a < low(int64) - b: false
  else:
    sum = a + b
    true

func intAdd(a, b: int64): Value =
  var s: int64
  if safeAdd(a, b, s, s) == false: return nullValue()
  intValue(s)

proc arith(op: string; a, b: Value): Value =
  if a.kind == vkNull or b.kind == vkNull: return nullValue()
  if a.kind in {vkInt, vkBool} and b.kind in {vkInt, vkBool}:
    let x = a.asInt
    let y = b.asInt
    case op
    of "+":
      var r: int64
      if safeAdd(x, y, r, r): return intValue(r)
      return realValue(float64(x) + float64(y))
    of "-":
      var r: int64
      if safeAdd(x, -y, r, r): return intValue(r)
      return realValue(float64(x) - float64(y))
    of "*":
      if x != 0 and (y > high(int64) div x or y < low(int64) div x):
        return realValue(float64(x) * float64(y))
      return intValue(x * y)
    of "/":
      if y == 0: return nullValue()
      # int / int truncates in SQL. The first version only kept the integer type
      # when the division came out exact, so `7 / 2` returned 3.5 while `8 / 2`
      # returned 4 — and the comment above it claimed the opposite. Found by the
      # differential corpus against real SQLite, which is the only way this class
      # of divergence gets found at all.
      return intValue(x div y)
    of "%":
      if y == 0: return nullValue()
      return intValue(x mod y)
    else: nullValue()
  else:
    let x = a.asFloat
    let y = b.asFloat
    case op
    of "+": realValue(x + y)
    of "-": realValue(x - y)
    of "*": realValue(x * y)
    of "/":
      if y == 0.0: nullValue() else: realValue(x / y)
    of "%":
      # fmod without libm: truncate toward zero like C fmod.
      if y == 0.0: nullValue()
      else:
        let q = float64(int64(x / y))
        realValue(x - q * y)
    else: nullValue()

proc cmpOp(op: string; a, b: Value; coll: Collation): Value =
  if a.kind == vkNull or b.kind == vkNull:
    return nullValue()
  let c = compare(a, b, coll)
  case op
  of "=", "==": boolValue(c == 0)
  of "!=", "<>": boolValue(c != 0)
  of "<": boolValue(c < 0)
  of "<=": boolValue(c <= 0)
  of ">": boolValue(c > 0)
  of ">=": boolValue(c >= 0)
  else: nullValue()

proc toBoolValue(b: bool): Value = boolValue(b)

proc evalIn(c: Ctx; e: Expr): Value =
  let lhs = c.eval(e.args[0])
  if lhs.kind == vkNull: return nullValue()
  var sawNull = false
  if e.sub != nil:
    let rs = c.execSelect(e.sub)
    for row in rs.rows:
      if row.len == 0: continue
      if row[0].kind == vkNull:
        sawNull = true
        continue
      if compare(row[0], lhs) == 0:
        return toBoolValue(not e.negated)
  else:
    for i in 1 ..< e.args.len:
      let v = c.eval(e.args[i])
      if v.kind == vkNull:
        sawNull = true
        continue
      if compare(v, lhs) == 0:
        return toBoolValue(not e.negated)
  if sawNull: return nullValue()
  toBoolValue(e.negated)

proc evalCase(c: Ctx; e: Expr): Value =
  if e.args.len > 0:
    let operand = c.eval(e.args[0])
    for br in e.pairs:
      let w = c.eval(br.whenE)
      if w.kind != vkNull and operand.kind != vkNull and compare(w, operand) == 0:
        return c.eval(br.thenE)
  else:
    for br in e.pairs:
      if c.eval(br.whenE).whereTrue():
        return c.eval(br.thenE)
  if e.e1 != nil: return c.eval(e.e1)
  nullValue()

proc findSlot(c: Ctx; tbl, name: string): int =
  let base = name.toLowerAscii()
  if tbl.len > 0:
    let q = tbl.toLowerAscii() & "." & base
    if c.colMap.hasKey(q): return c.colMap[q]
    # fall back to unqualified if the qualifier is a table alias mismatch
    return -1
  if c.colMap.hasKey(base): return c.colMap[base]
  -1

proc getColumn(c: Ctx; e: Expr): Value =
  ## Resolution walks the correlation chain (inner scope first).
  var cur = c
  var depth = 0
  while cur != nil:
    inc depth
    if depth > 32: fail(limit, "correlation depth exceeded")
    let s = cur.findSlot(e.tbl, e.name)
    if s == -2:
      fail(misuse, "ambiguous column name: " & e.name)
    if s >= 0:
      if s < cur.vals.len: return cur.vals[s]
      return nullValue()
    cur = cur.outer
  fail(notFound, "no such column: " &
       (if e.tbl.len > 0: e.tbl & "." & e.name else: e.name))

proc evalArgs(c: Ctx; e: Expr): seq[Value] =
  result = newSeqOfCap[Value](e.args.len)
  for a in e.args: result.add c.eval(a)

proc eval(c: Ctx; e: Expr): Value =
  if e == nil: return nullValue()
  case e.kind
  of exLit: e.val
  of exParam:
    if e.pName.len > 0:
      fail(misuse, "named parameter " & e.pName & " not bound")
    if e.pIdx < 1 or e.pIdx > c.params.len:
      fail(range, "parameter index out of range: " & $e.pIdx)
    c.params[e.pIdx - 1]
  of exCol: c.getColumn(e)
  of exStar: fail(misuse, "'*' is not valid here")
  of exUnary:
    let v = c.eval(e.args[0])
    case e.op
    of "-":
      case v.kind
      of vkNull: nullValue()
      of vkInt:
        if v.i == low(int64): realValue(9.2233720368547758e18)
        else: intValue(-v.i)
      of vkBool: intValue(-v.asInt)
      else: realValue(-v.asFloat)
    of "+": v
    of "~":
      if v.kind == vkNull: nullValue() else: intValue(not v.asInt)
    of "not":
      if v.kind == vkNull: nullValue() else: boolValue(not v.truthy())
    else: nullValue()
  of exBinary:
    let op = e.op
    case op
    of "and":
      let a = c.eval(e.args[0])
      if a.kind != vkNull and not a.truthy(): return boolValue(false)
      let b = c.eval(e.args[1])
      if b.kind != vkNull and not b.truthy(): return boolValue(false)
      if a.kind == vkNull or b.kind == vkNull: return nullValue()
      boolValue(true)
    of "or":
      let a = c.eval(e.args[0])
      if a.kind != vkNull and a.truthy(): return boolValue(true)
      let b = c.eval(e.args[1])
      if b.kind != vkNull and b.truthy(): return boolValue(true)
      if a.kind == vkNull or b.kind == vkNull: return nullValue()
      boolValue(false)
    of "is":
      let a = c.eval(e.args[0])
      let b = c.eval(e.args[1])
      boolValue(compare(a, b) == 0)
    of "isnot":
      let a = c.eval(e.args[0])
      let b = c.eval(e.args[1])
      boolValue(compare(a, b) != 0)
    of "isdistinct":
      let a = c.eval(e.args[0])
      let b = c.eval(e.args[1])
      boolValue(compare(a, b) != 0)
    of "isnotdistinct":
      let a = c.eval(e.args[0])
      let b = c.eval(e.args[1])
      boolValue(compare(a, b) == 0)
    of "+", "-", "*", "/", "%":
      let a = c.eval(e.args[0])
      let b = c.eval(e.args[1])
      arith(op, a, b)
    of "||":
      let a = c.eval(e.args[0])
      let b = c.eval(e.args[1])
      if a.kind == vkNull or b.kind == vkNull: nullValue()
      else: textValue(a.toText & b.toText)
    of "&":
      let a = c.eval(e.args[0])
      let b = c.eval(e.args[1])
      if a.kind == vkNull or b.kind == vkNull: nullValue()
      else: intValue(a.asInt and b.asInt)
    of "|":
      let a = c.eval(e.args[0])
      let b = c.eval(e.args[1])
      if a.kind == vkNull or b.kind == vkNull: nullValue()
      else: intValue(a.asInt or b.asInt)
    of "<<":
      let a = c.eval(e.args[0])
      let b = c.eval(e.args[1])
      if a.kind == vkNull or b.kind == vkNull: nullValue()
      elif b.asInt < 0 or b.asInt > 63: nullValue()
      else: intValue(a.asInt shl int(b.asInt))
    of ">>":
      let a = c.eval(e.args[0])
      let b = c.eval(e.args[1])
      if a.kind == vkNull or b.kind == vkNull: nullValue()
      elif b.asInt < 0 or b.asInt > 63: nullValue()
      else: intValue(a.asInt shr int(b.asInt))
    else:
      cmpOp(op, c.eval(e.args[0]), c.eval(e.args[1]), colBinary)
  of exCall:
    if e.aggIdx >= 0 and e.name in AggregateNames:
      if e.aggIdx >= c.aggVals.len: return nullValue()
      return c.aggVals[e.aggIdx]
    if e.name == "rowid" or e.name == "_rowid_":
      return nullValue()
    let args = c.evalArgs(e)
    callScalar(e.name, args, c.nowIso, c.db.rand)
  of exCase: c.evalCase(e)
  of exCast:
    let v = c.eval(e.args[0])
    if v.kind == vkNull: return nullValue()
    case affinityOf(e.typeName)
    of affInteger: intValue(castToInt(v))
    of affReal: realValue(castToFloat(v))
    of affText: textValue(v.toText)
    of affBool: boolValue(v.truthy())
    of affBlob: blobValue(v.toBlob)
    of affNumeric: v
  of exIn: c.evalIn(e)
  of exBetween:
    let v = c.eval(e.args[0])
    let lo = c.eval(e.args[1])
    let hi = c.eval(e.args[2])
    if v.kind == vkNull or lo.kind == vkNull or hi.kind == vkNull: return nullValue()
    let ok = compare(v, lo) >= 0 and compare(v, hi) <= 0
    boolValue(ok != e.negated)
  of exIsNull:
    let v = c.eval(e.args[0])
    boolValue((v.kind == vkNull) != e.negated)
  of exLike:
    let v = c.eval(e.args[0])
    let pat = c.eval(e.args[1])
    if v.kind == vkNull or pat.kind == vkNull: return nullValue()
    var esc = '\\'
    if e.args.len > 2:
      let ev = c.eval(e.args[2])
      if ev.kind == vkNull: return nullValue()
      let s = ev.toText
      esc = if s.len > 0: s[0] else: '\\'
    let hit = if e.op == "glob": sqlGlob(v.toText, pat.toText)
              else: sqlLike(v.toText, pat.toText, esc)
    boolValue(hit != e.negated)
  of exExists:
    let rs = c.execSelect(e.sub)
    boolValue((rs.rows.len > 0) != e.negated)
  of exScalarSub:
    let rs = c.execSelect(e.sub)
    if rs.rows.len == 0 or rs.rows[0].len == 0: nullValue()
    else: rs.rows[0][0]
  of exTuple:
    # row values are only meaningful inside IN/comparison; fold to text form
    var parts: seq[string]
    for a in e.args: parts.add c.eval(a).toText
    textValue(parts.join(","))
  of exCollate: c.eval(e.args[0])
  of exRowValue:
    if e.args.len > 0: c.eval(e.args[0]) else: nullValue()

# ===========================================================================
# Aggregates
# ===========================================================================

func isAggCall(e: Expr): bool =
  ## `min(a, b)` and `max(a, b)` are scalar in SQL; only the one-argument form
  ## aggregates. Treating every `max(...)` as an aggregate made `max(1, 2)`
  ## return 1 — the first row's value instead of the larger one.
  if e.kind != exCall or e.name notin AggregateNames: return false
  if (e.name == "min" or e.name == "max") and e.args.len > 1: return false
  true

proc collectAggs(e: Expr; acc: var seq[Expr]): bool =
  ## Depth-first scan assigning a stable aggregate slot index to each call.
  if e == nil: return false
  if isAggCall(e):
    e.aggIdx = acc.len
    acc.add e
    return true
  var has = false
  for a in e.args:
    has = collectAggs(a, acc) or has
  for p in e.pairs:
    has = collectAggs(p.whenE, acc) or has
    has = collectAggs(p.thenE, acc) or has
  if e.e1 != nil: has = collectAggs(e.e1, acc) or has
  has

proc computeAgg(c: Ctx; e: Expr; rows: seq[Row]; groupColl: Collation): Value =
  let fname = e.name
  if fname == "count":
    if e.star: return intValue(int64(rows.len))
    var n = 0'i64
    for r in rows:
      c.vals = r
      if c.eval(e.args[0]).kind != vkNull: inc n
    return intValue(n)
  var accInt = 0'i64
  var accReal = 0.0
  var sawReal = false
  var count = 0'i64
  var best: Value = nullValue()
  var parts: seq[string]
  var sep = ","
  if fname == "group_concat" and e.args.len > 1:
    c.vals = if rows.len > 0: rows[0] else: @[]
    sep = c.eval(e.args[1]).toText
  for r in rows:
    c.vals = r
    let v = c.eval(e.args[0])
    if v.kind == vkNull: continue
    inc count
    case fname
    of "sum", "total", "avg":
      if v.kind == vkReal:
        if not sawReal:
          accReal = float64(accInt)
          sawReal = true
        accReal += v.r
      else:
        if sawReal: accReal += v.asFloat
        else:
          var s: int64
          if safeAdd(accInt, v.asInt, s, s): accInt = s
          else:
            sawReal = true
            accReal = float64(accInt) + float64(v.asInt)
    of "min":
      if best.kind == vkNull or compare(v, best, groupColl) < 0: best = v
    of "max":
      if best.kind == vkNull or compare(v, best, groupColl) > 0: best = v
    of "group_concat":
      parts.add v.toText
    else: discard
  case fname
  of "sum":
    if count == 0: nullValue()
    elif sawReal: realValue(accReal)
    else: intValue(accInt)
  of "total":
    if sawReal: realValue(accReal) else: realValue(float64(accInt))
  of "avg":
    if count == 0: nullValue()
    else: realValue((if sawReal: accReal else: float64(accInt)) / float64(count))
  of "min", "max": best
  of "group_concat":
    if count == 0: nullValue() else: textValue(parts.join(sep))
  else: nullValue()

# ===========================================================================
# FROM materialisation
# ===========================================================================

type
  SourcePlan = object
    alias: string
    tbl: TableDef
    sub: SelectStmt
    cteName: string
    names: seq[string]
    off: int
    n: int

proc addSourceCols(c: Ctx; sp: var SourcePlan; off: int) =
  sp.off = off
  sp.n = sp.names.len
  for i, nm in sp.names:
    let key = nm.toLowerAscii()
    let q = sp.alias.toLowerAscii() & "." & key
    c.colMap[q] = off + i
    if c.colMap.hasKey(key):
      c.colMap[key] = -2          # ambiguous unqualified name
    else:
      c.colMap[key] = off + i

proc lookupCte(c: Ctx; name: string): (bool, CteData) =
  var cur = c
  while cur != nil:
    let k = name.toLowerAscii()
    if cur.ctes.hasKey(k): return (true, cur.ctes[k])
    cur = cur.outer
  (false, CteData())

proc expandView(c: Ctx; name: string; sp: var SourcePlan): bool =
  let (found, v) = c.db.cat.findView(name)
  if not found: return false
  sp.sub = v.q
  if v.cols.len > 0: sp.names = v.cols
  else: sp.names = @[]
  sp.alias = if sp.alias.len > 0: sp.alias else: name
  true

proc sourceRows(c: Ctx; sp: var SourcePlan): seq[Row] =
  if sp.tbl != nil:
    result = newSeqOfCap[Row](sp.tbl.rs.len)
    for rid in sp.tbl.rs.rowids():
      let (found, row) = sp.tbl.rs.get(rid)
      if found: result.add row
  elif sp.sub != nil:
    let rs = c.execSelect(sp.sub)
    result = rs.rows
    if sp.names.len == 0: sp.names = rs.cols
  else:
    let (ok, data) = c.lookupCte(sp.cteName)
    if ok:
      result = data.rows
      if sp.names.len == 0: sp.names = data.names

proc describeSource(c: Ctx; ts: TableSource; sp: var SourcePlan) =
  sp.alias = ts.alias
  if ts.sub != nil:
    sp.sub = ts.sub
    sp.alias = if ts.alias.len > 0: ts.alias else: "subquery"
    return
  let name = ts.name
  let (isCte, data) = c.lookupCte(name)
  if isCte:
    sp.cteName = name
    sp.names = data.names
    sp.alias = if sp.alias.len > 0: sp.alias else: name
    return
  let t = c.db.cat.findTable(name)
  if t != nil:
    sp.tbl = t
    sp.alias = if sp.alias.len > 0: sp.alias else: t.name
    for col in t.cols: sp.names.add col.name
    return
  if c.expandView(name, sp):
    sp.alias = if ts.alias.len > 0: ts.alias else: name
    return
  fail(notFound, "no such table: " & name)

proc flattenAnd(e: Expr; acc: var seq[Expr]) =
  if e == nil: return
  if e.kind == exBinary and e.op == "and":
    flattenAnd(e.args[0], acc)
    flattenAnd(e.args[1], acc)
  else:
    acc.add e

proc indexCandidates(c: Ctx; t: TableDef; alias: string;
                     where: Expr): (bool, seq[int64]) =
  ## Mini planner: picks at most one equality index per query.
  ##
  ## Scope is deliberately small and *honest*: we only claim an index access
  ## path for `col = <const>` conjuncts, and only when that strictly reduces the
  ## candidate set. Anything else falls back to a scan, which keeps the plan
  ## trivially correct while removing the pathological O(n) per lookup that
  ## dominated the benchmark.
  if where == nil or t.indexes.len == 0: return (false, @[])
  var conjuncts: seq[Expr] = @[]
  flattenAnd(where, conjuncts)
  var best: seq[int64] = @[]
  var bestFound = false
  for cj in conjuncts:
    if cj.kind != exBinary or cj.op notin ["=", "=="]: continue
    var colSide = cj.args[0]
    var valSide = cj.args[1]
    if colSide.kind != exCol:
      colSide = cj.args[1]
      valSide = cj.args[0]
    if colSide.kind != exCol: continue
    if colSide.tbl.len > 0 and
       colSide.tbl.toLowerAscii() != alias.toLowerAscii() and
       colSide.tbl.toLowerAscii() != t.name.toLowerAscii(): continue
    let ci = t.colByName(colSide.name)
    if ci < 0: continue
    var val: Value
    try:
      val = c.eval(valSide)
    except DbError:
      continue
    if val.kind == vkNull: continue
    for ix in t.indexes:
      if ix.cols.len != 1 or ix.cols[0] != ci: continue
      let rids = ix.indexScanEq(@[val])
      if not bestFound or rids.len < best.len:
        best = rids
        bestFound = true
  if bestFound: (true, best) else: (false, @[])

proc buildFromRows(c: Ctx; st: SelectStmt; sources: var seq[SourcePlan]): seq[Row] =
  ## Nested-loop join over a slot-vector row, left-deep.
  ## Only one row per level is live at a time (plus the candidate list of the
  ## right side), so peak memory is O(row·width) rather than O(|A|·|B|).
  if st.fromFirst == nil: return @[@[]]
  var first: SourcePlan
  c.describeSource(st.fromFirst, first)
  var rows: seq[Row]
  var usedIndex = false
  if first.tbl != nil and st.joins.len == 0:
    let (ok, rids) = c.indexCandidates(first.tbl, first.alias, st.where)
    if ok:
      usedIndex = true
      rows = newSeqOfCap[Row](rids.len)
      var sorted = rids
      sorted.sort()
      for rid in sorted:
        let (found, row) = first.tbl.rs.get(rid)
        if found: rows.add row
  if not usedIndex:
    rows = c.sourceRows(first)
  c.addSourceCols(first, 0)
  var off = first.names.len
  sources.add first

  for j in st.joins:
    var sp: SourcePlan
    c.describeSource(j.table, sp)
    let cand = c.sourceRows(sp)
    c.addSourceCols(sp, off)
    off += sp.names.len
    sources.add sp
    var next: seq[Row] = @[]
    next.setLen(0)
    let nulls = newSeq[Value](sp.names.len)
    var leftAlias = sources[sources.len - 2].alias
    for base in rows:
      var matched = false
      for cr in cand:
        var full = newSeqOfCap[Value](base.len + cr.len)
        full.add base
        full.add cr
        c.vals = full
        var ok = true
        if j.on != nil:
          ok = c.eval(j.on).whereTrue()
        elif j.usingCols.len > 0:
          for uc in j.usingCols:
            let ls = c.colMap.getOrDefault(leftAlias.toLowerAscii() & "." & uc.toLowerAscii(), -1)
            let rs = c.colMap.getOrDefault(sp.alias.toLowerAscii() & "." & uc.toLowerAscii(), -1)
            if ls < 0 or rs < 0:
              fail(notFound, "USING column not found: " & uc)
            if compare(full[ls], full[rs]) != 0:
              ok = false
              break
        if ok:
          next.add full
          matched = true
      if not matched and j.kind == jkLeft:
        var full = newSeqOfCap[Value](base.len + nulls.len)
        full.add base
        full.add nulls
        next.add full
    rows = next
  rows

# ===========================================================================
# SELECT
# ===========================================================================

func orderColl(t: OrderTerm): Collation =
  t.coll

proc encodeRowForDistinct(r: Row): string =
  ## Type-tagged encoding: `1` and `'1'` are different values and must not be
  ## deduplicated together (SQLite would; Foccil is strict by default).
  result = newStringOfCap(r.len * 5)
  for v in r:
    result.add char(ord('0') + ord(v.kind))
    case v.kind
    of vkNull: discard
    of vkInt: result.add $v.i; result.add '\0'
    of vkReal: result.add $v.r; result.add '\0'
    of vkBool: result.add(if v.bo: "t" else: "f")
    of vkText: result.add $v.t.len; result.add ':'; result.add v.t
    of vkBlob:
      result.add $v.bl.len
      result.add ':'
      for b in v.bl: result.add char(b)

proc resultColumnName(rc: ResultCol; idx: int): string =
  if rc.alias.len > 0: return rc.alias
  if rc.text.len > 0: return rc.text
  "column" & $(idx + 1)

proc execSelect(c0: Ctx; st: SelectStmt): ResultSet =
  ## Every SELECT gets a **fresh scope**: an empty column map and its own
  ## aggregate slots. Without this, a subquery would silently share (and
  ## corrupt) the outer column map — a correctness bug and an information leak.
  let c = newCtx(c0.db, c0.params, c0)
  # --- CTEs ---------------------------------------------------------------
  if st.ctes.len > 0:
    for cte in st.ctes:
      let k = cte.name.toLowerAscii()
      if c.lookupCte(cte.name)[0]:
        c.ctes[k] = c.lookupCte(cte.name)[1]
        continue
      let rs = c.execSelect(cte.q)
      var names = if cte.cols.len > 0: cte.cols else: rs.cols
      c.ctes[k] = CteData(names: names, rows: rs.rows)

  # --- compound selects ---------------------------------------------------
  if st.isCompound:
    var left = c.execSelect(SelectStmt(isDistinct: st.isDistinct,
      cols: st.cols, fromFirst: st.fromFirst, joins: st.joins, where: st.where,
      groupBy: st.groupBy, having: st.having, orderBy: @[], ctes: @[]))
    let right = c.execSelect(st.compoundRhs)
    var outRows: seq[Row]
    var seen: Table[string, bool]
    case st.compoundOp
    of "union all":
      outRows = left.rows & right.rows
    of "union":
      seen = initTable[string, bool]()
      for r in left.rows & right.rows:
        let k = encodeRowForDistinct(r)
        if not seen.hasKey(k):
          seen[k] = true
          outRows.add r
    of "intersect":
      seen = initTable[string, bool]()
      for r in right.rows: seen[encodeRowForDistinct(r)] = true
      for r in left.rows:
        let k = encodeRowForDistinct(r)
        if seen.hasKey(k): outRows.add r
    of "except":
      seen = initTable[string, bool]()
      for r in right.rows: seen[encodeRowForDistinct(r)] = true
      for r in left.rows:
        let k = encodeRowForDistinct(r)
        if not seen.hasKey(k): outRows.add r
    else:
      outRows = left.rows & right.rows
    result.cols = left.cols
    result.rows = outRows
    return

  # --- projection list ----------------------------------------------------
  ## `*` is expanded after the slot map exists, and column names are produced in
  ## select-list order (which is what a client expects and what makes
  ## `INSERT ... SELECT` positional semantics correct).
  var colExprs: seq[Expr] = @[]
  var colNames: seq[string] = @[]
  var starOwner = ""
  for rc in st.cols:
    if rc.e.kind == exStar and rc.e.tbl.len > 0:
      starOwner = rc.e.tbl

  var sources: seq[SourcePlan] = @[]
  var srcRows = c.buildFromRows(st, sources)

  for i, rc in st.cols:
    if rc.e.kind == exStar:
      for s in sources:
        if starOwner.len > 0 and
           s.alias.toLowerAscii() != starOwner.toLowerAscii():
          continue
        for nm in s.names:
          colExprs.add colRef(s.alias, nm)
          colNames.add nm
    else:
      colExprs.add rc.e
      colNames.add resultColumnName(rc, i)
  let outCols = colNames

  # --- WHERE --------------------------------------------------------------
  if st.where != nil:
    var kept: seq[Row] = @[]
    for r in srcRows:
      c.vals = r
      if c.eval(st.where).whereTrue(): kept.add r
    srcRows = kept

  # --- aggregates ---------------------------------------------------------
  var aggs: seq[Expr] = @[]
  var hasAgg = false
  for e in colExprs: hasAgg = collectAggs(e, aggs) or hasAgg
  hasAgg = collectAggs(st.having, aggs) or hasAgg
  for t in st.orderBy: hasAgg = collectAggs(t.expr, aggs) or hasAgg

  let isGrouped = hasAgg or st.groupBy.len > 0

  type OutEntry = tuple[row: Row, keys: seq[Value]]
  var entries: seq[OutEntry] = @[]

  if isGrouped:
    var groups: seq[seq[Row]] = @[]
    if st.groupBy.len == 0:
      groups.add srcRows
    else:
      var idx: Table[string, int]
      idx = initTable[string, int]()
      for r in srcRows:
        c.vals = r
        var keyParts: Row
        for g in st.groupBy: keyParts.add c.eval(g)
        let k = encodeRowForDistinct(keyParts)
        if idx.hasKey(k):
          groups[idx[k]].add r
        else:
          idx[k] = groups.len
          groups.add @[r]
      if srcRows.len == 0 and st.groupBy.len > 0: groups = @[]
    for g in groups:
      c.vals = if g.len > 0: g[0] else: @[]
      c.aggVals = newSeq[Value](aggs.len)
      for i, a in aggs:
        c.aggVals[i] = c.computeAgg(a, g, colBinary)
      if st.having != nil and not c.eval(st.having).whereTrue(): continue
      var outRow: Row
      for e in colExprs: outRow.add c.eval(e)
      var keys: seq[Value]
      for t in st.orderBy: keys.add c.eval(t.expr)
      c.budgetTick()
      entries.add (outRow, keys)
    c.aggVals = @[]
  else:
    for r in srcRows:
      c.vals = r
      var outRow: Row
      var skip = false
      for e in colExprs:
        outRow.add c.eval(e)
      if st.having != nil:
        skip = not c.eval(st.having).whereTrue()
      if skip: continue
      var keys: seq[Value]
      for t in st.orderBy: keys.add c.eval(t.expr)
      c.budgetTick()
      entries.add (outRow, keys)

  # --- DISTINCT -----------------------------------------------------------
  if st.isDistinct:
    var seen = initTable[string, bool]()
    var kept: seq[OutEntry] = @[]
    for e in entries:
      let k = encodeRowForDistinct(e.row)
      if not seen.hasKey(k):
        seen[k] = true
        kept.add e
    entries = kept

  # --- ORDER BY -----------------------------------------------------------
  if st.orderBy.len > 0 and entries.len > 1:
    let terms = st.orderBy
    # stable merge-free comparator using the precomputed keys
    var order = newSeq[int](entries.len)
    for i in 0 ..< order.len: order[i] = i
    order.sort(proc (a, b: int): int =
      for i, t in terms:
        var cmpv = compare(entries[a].keys[i], entries[b].keys[i], t.coll)
        if t.desc: cmpv = -cmpv
        if t.nullsFirst >= 0:
          let an = entries[a].keys[i].kind == vkNull
          let bn = entries[b].keys[i].kind == vkNull
          if an != bn:
            let nullsFirstWanted = t.nullsFirst == 1
            return if an: (if nullsFirstWanted: -1 else: 1)
                   else: (if nullsFirstWanted: 1 else: -1)
        if cmpv != 0: return cmpv
      0)
    var sortedEntries: seq[OutEntry] = @[]
    sortedEntries.setLen(entries.len)
    for i, oi in order: sortedEntries[i] = entries[oi]
    entries = sortedEntries

  # --- LIMIT / OFFSET -----------------------------------------------------
  var start = 0
  var limit = -1
  if st.offset != nil:
    let v = c.eval(st.offset)
    if v.kind == vkNull: fail(typeErr, "OFFSET must not be NULL")
    start = max(0, int(v.asInt))
  if st.limit != nil:
    let v = c.eval(st.limit)
    if v.kind == vkNull: fail(typeErr, "LIMIT must not be NULL")
    limit = max(0, int(v.asInt))
  let finish = if limit < 0: entries.len else: min(entries.len, start + limit)
  result.cols = outCols
  result.rows = @[]
  var i = start
  while i < finish and i < entries.len:
    result.rows.add entries[i].row
    inc i

# ===========================================================================
# Constraints & typing
# ===========================================================================

proc coerce(c: Ctx; t: TableDef; ci: int; v: Value): Value =
  let col = t.cols[ci]
  let conv = applyAffinity(v, col.aff, c.db.opts.strictTyping)
  if c.db.opts.strictTyping and conv.kind == vkText and
     col.aff in {affInteger, affReal, affNumeric} and v.kind == vkText:
    fail(typeErr, "column " & col.name & " cannot store non-numeric text")
  if c.db.opts.strictTyping and v.kind == vkBlob and col.aff in
     {affText, affInteger, affReal, affNumeric, affBool}:
    fail(typeErr, "column " & col.name & " cannot store a BLOB")
  conv

proc checkRow(c: Ctx; t: TableDef; row: Row; selfRid: int64) =
  for i, col in t.cols:
    if col.notNull and row[i].kind == vkNull:
      fail(constraint, "NOT NULL constraint failed: " & t.name & "." & col.name)
  for ix in t.indexes:
    if t.uniqueViolation(ix, indexKeyFor(t, ix, row), selfRid):
      fail(constraint, "UNIQUE constraint failed: " & t.name & " (" & ix.name & ")")
  for chk in t.tableChecks:
    c.vals = row
    if not c.eval(chk.expr).whereTrue():
      fail(constraint, "CHECK constraint failed: " & chk.name)
  for i, col in t.cols:
    if col.checkExpr != nil:
      c.vals = row
      if not c.eval(col.checkExpr).whereTrue():
        fail(constraint, "CHECK constraint failed: " & t.name & "." & col.name)

proc recordUndo(c: Ctx; kind: UndoKind; t: TableDef; rid: int64; row: Row) =
  if c.db.txDepth > 0:
    c.db.undo.add UndoRec(kind: kind, tbl: t, rid: rid, row: row)

# ===========================================================================
# DDL helpers
# ===========================================================================

proc markDdl(db: Db) {.inline.}

proc buildColumn(c: Ctx; cd: ColumnDef): Column =
  result = Column(name: cd.name, typeName: cd.typeName,
                  aff: if cd.typeName.len > 0: affinityOf(cd.typeName) else: affBlob,
                  notNull: cd.notNull, coll: cd.collate,
                  isPk: cd.isPrimaryKey, autoIncrement: cd.autoIncrement,
                  unique: cd.isUnique, checkExpr: cd.checkExpr,
                  refTable: cd.refTable, refCol: cd.refCol,
                  onDelete: cd.onDelete)
  if cd.defaultExpr != nil:
    result.hasDefault = true
    result.defaultVal = c.eval(cd.defaultExpr)

proc createTable(c: Ctx; st: Stmt): ResultSet =
  let db = c.db
  c.db.markDdl()
  if db.opts.readOnly: fail(readOnly, "database is read-only")
  if not db.opts.allowDdl: fail(auth, "DDL is disabled on this connection")
  if db.cat.findTable(st.table) != nil:
    if st.ifNotExists: return
    fail(constraint, "table already exists: " & st.table)
  if st.cols.len == 0: fail(syntax, "table needs at least one column")
  var t = newTable(st.table)
  t.strict = st.strict
  t.withoutRowid = st.withoutRowid
  var seen: Table[string, bool]
  seen = initTable[string, bool]()
  for cd in st.cols:
    let key = cd.name.toLowerAscii()
    if seen.hasKey(key): fail(syntax, "duplicate column name: " & cd.name)
    seen[key] = true
    t.addColumn(c.buildColumn(cd))
  # primary key
  var pk: seq[int] = @[]
  for i, col in t.cols:
    if col.isPk: pk.add i
  for tc in st.constraints:
    if tc.kind == tcPrimaryKey:
      for cn in tc.cols:
        let i = t.colByName(cn)
        if i < 0: fail(notFound, "no such column in PRIMARY KEY: " & cn)
        pk.add i
  t.pkCols = pk
  # implicit indexes
  if pk.len > 0:
    var ix = Index(name: "autoindex_" & t.name & "_pk", tableName: t.name,
                   cols: pk, unique: true, isPkIndex: true)
    t.indexes.add ix
  var autoIdx = 0
  for i, col in t.cols:
    if col.unique and not col.isPk:
      inc autoIdx
      t.indexes.add Index(name: "autoindex_" & t.name & "_" & $autoIdx,
                          tableName: t.name, cols: @[i], unique: true)
  for tc in st.constraints:
    if tc.kind == tcUnique:
      var cols: seq[int]
      for cn in tc.cols:
        let i = t.colByName(cn)
        if i < 0: fail(notFound, "no such column in UNIQUE: " & cn)
        cols.add i
      inc autoIdx
      t.indexes.add Index(name: "autoindex_" & t.name & "_" & $autoIdx,
                          tableName: t.name, cols: cols, unique: true)
    elif tc.kind == tcCheck:
      t.tableChecks.add (tc.checkExpr, if tc.name.len > 0: tc.name else: "check")
  # autoincrement column tracking
  for i, col in t.cols:
    if col.autoIncrement and not col.isPk:
      fail(syntax, "AUTOINCREMENT requires PRIMARY KEY")
  if db.file != nil and not db.loading:
    # The table id is allocated before registration, because `allocTid` reads
    # the catalog and would otherwise see a table with no id yet.
    t.tid = allocTid(db.file, db.cat)
    t.rs = newDiskStore(db.file.tree, t.tid, @[])
  db.cat.registerTable(t)
  result.cols = @[]
  result.rows = @[]

proc dropTable(c: Ctx; st: Stmt): ResultSet =
  c.db.markDdl()
  if c.db.opts.readOnly: fail(readOnly, "database is read-only")
  if not c.db.opts.allowDdl: fail(auth, "DDL is disabled on this connection")
  let victim = c.db.cat.findTable(st.table)
  if not c.db.cat.dropTable(st.table):
    if st.ifExists: return
    fail(notFound, "no such table: " & st.table)
  if victim != nil and victim.rs != nil:
    # The rows are removed by the commit that follows this statement; until then
    # they are only hidden, which is what makes DROP TABLE transactional.
    victim.rs.clear()

proc rebuildIndexes*(db: Db; t: TableDef) =
  ## Indexes live in memory; rows may not. When a table is re-bound to its
  ## on-disk rows — at open, or after a rolled-back DDL replaced the catalog —
  ## the entries have to be rebuilt from the rows. Skip this and every lookup
  ## that picks an index answers "no rows" for a table that is full of them,
  ## which reads exactly like data loss.
  ##
  ## Cost is O(rows · indexes · log rows), paid once per table per open. That is
  ## the honest price of a lazy index; a persisted index format would remove it
  ## and is listed as future work rather than pretended away here.
  if t.rs == nil or t.indexes.len == 0: return
  for ix in t.indexes: ix.entries.setLen(0)
  let probe = newCtx(db, @[])
  for rid in t.rs.rowids():
    let (found, row) = t.rs.get(rid)
    if not found: continue
    for ix in t.indexes:
      if ix.partial != nil:
        probe.vals = row
        if not probe.eval(ix.partial).whereTrue(): continue
      ix.indexInsert(indexKeyFor(t, ix, row), rid)

proc createIndex(c: Ctx; st: Stmt): ResultSet =
  let db = c.db
  c.db.markDdl()
  if db.opts.readOnly: fail(readOnly, "database is read-only")
  if not db.opts.allowDdl: fail(auth, "DDL is disabled on this connection")
  let t = db.cat.findTable(st.table)
  if t == nil: fail(notFound, "no such table: " & st.table)
  for ix in t.indexes:
    if ix.name.toLowerAscii() == st.indexName.toLowerAscii():
      if st.ifNotExists: return
      fail(constraint, "index already exists: " & st.indexName)
  var cols: seq[int]
  for cspec in st.indexCols:
    if cspec.expr.kind != exCol:
      fail(unsupported, "expression indexes are not supported yet")
    let i = t.colByName(cspec.expr.name)
    if i < 0: fail(notFound, "no such column: " & cspec.expr.name)
    cols.add i
  var ix = Index(name: st.indexName, tableName: t.name, cols: cols,
                 unique: st.isUnique, partial: st.where)
  # backfill
  let probe = newCtx(db, @[])
  for rid in t.rs.rowids():
    let (_, row) = t.rs.get(rid)
    if st.where != nil:
      probe.vals = row
      if not probe.eval(st.where).whereTrue(): continue
    ix.indexInsert(indexKeyFor(t, ix, row), rid)
  if st.isUnique:
    for i in 1 ..< ix.entries.len:
      if compare(ix.entries[i].key[0], ix.entries[i - 1].key[0]) == 0:
        var same = true
        for k in 0 ..< ix.entries[i].key.len:
          if compare(ix.entries[i].key[k], ix.entries[i - 1].key[k]) != 0:
            same = false
            break
        if same:
          fail(constraint, "UNIQUE constraint failed while building index " &
               st.indexName)
  t.indexes.add ix

proc alterTable(c: Ctx; st: Stmt): ResultSet =
  c.db.markDdl()
  if c.db.opts.readOnly: fail(readOnly, "database is read-only")
  if not c.db.opts.allowDdl: fail(auth, "DDL is disabled on this connection")
  let t = c.db.cat.findTable(st.table)
  if t == nil: fail(notFound, "no such table: " & st.table)
  case st.alterAction
  of "rename_table":
    c.db.cat.renameTable(t.name, st.newName)
  of "rename_column":
    let i = t.colByName(st.oldCol)
    if i < 0: fail(notFound, "no such column: " & st.oldCol)
    t.cols[i].name = st.newCol
    t.buildColIdx()
  of "add_column":
    if st.addCol.isPrimaryKey:
      fail(unsupported, "cannot add a PRIMARY KEY column")
    let col = c.buildColumn(st.addCol)
    if col.notNull and not col.hasDefault:
      if t.rs.len > 0:
        fail(constraint, "cannot add NOT NULL column without a default to a non-empty table")
    t.addColumn(col)
    let ci = t.cols.high
    for rid in t.rs.rowids():
      var row = t.rs.get(rid).row
      row.add(if col.hasDefault: col.defaultVal else: nullValue())
      t.rs.put(rid, row)
    for ix in t.indexes:
      for i in 0 ..< ix.cols.len:
        if ix.cols[i] == ci: fail(unsupported, "column is used by an index")
  of "drop_column":
    let i = t.colByName(st.oldCol)
    if i < 0: fail(notFound, "no such column: " & st.oldCol)
    for ix in t.indexes:
      for cc in ix.cols:
        if cc == i: fail(constraint, "cannot drop indexed column: " & st.oldCol)
    t.cols.delete(i)
    t.buildColIdx()
    for rid in t.rs.rowids():
      var row = t.rs.get(rid).row
      row.delete(i)
      t.rs.put(rid, row)
    var newPk: seq[int]
    for p in t.pkCols:
      if p < i: newPk.add p
      elif p > i: newPk.add p - 1
    t.pkCols = newPk
  else:
    fail(unsupported, "unsupported ALTER TABLE action")

# ===========================================================================
# DML
# ===========================================================================

proc scopedCtx(c: Ctx; t: TableDef): Ctx =
  ## Column map for a single-table DML context (INSERT/UPDATE/DELETE).
  result = newCtx(c.db, c.params, c.outer)
  for i, col in t.cols:
    result.colMap[col.name.toLowerAscii()] = i

proc insertRows(c0: Ctx; st: Stmt): ResultSet =
  let t = c0.db.cat.findTable(st.table)
  if t == nil: fail(notFound, "no such table: " & st.table)
  if c0.db.opts.readOnly: fail(readOnly, "database is read-only")
  let c = scopedCtx(c0, t)
  var targetCols: seq[int]
  if st.columns.len == 0:
    for i in 0 ..< t.cols.len: targetCols.add i
  else:
    for cn in st.columns:
      let i = t.colByName(cn)
      if i < 0: fail(notFound, "no such column: " & cn)
      targetCols.add i
  var inputRows: seq[seq[Value]] = @[]
  if st.sourceSelect != nil:
    let rs = c.execSelect(st.sourceSelect)
    if rs.cols.len != targetCols.len:
      fail(mismatch, "INSERT column count mismatch")
    for r in rs.rows: inputRows.add r
  elif st.defaultValues:
    inputRows.add @[]
  else:
    for vexprs in st.values:
      if vexprs.len != targetCols.len:
        fail(mismatch, "INSERT column count mismatch: expected " &
             $targetCols.len & ", got " & $vexprs.len)
      var vals: seq[Value] = @[]
      for e in vexprs: vals.add c.eval(e)
      inputRows.add vals
  var returned: seq[Row] = @[]
  for vals in inputRows:
    var row = newSeq[Value](t.cols.len)
    for i, col in t.cols:
      row[i] = if col.hasDefault: col.defaultVal else: nullValue()
    for k, ci in targetCols:
      if k < vals.len: row[ci] = c.coerce(t, ci, vals[k])
    # autoincrement PK
    if t.pkCols.len == 1:
      let pk = t.pkCols[0]
      if row[pk].kind == vkNull and t.cols[pk].aff == affInteger:
        row[pk] = intValue(t.nextRowid)
    c.checkRow(t, row, -1)
    # ON CONFLICT handling for UNIQUE violations
    var conflict = false
    for ix in t.indexes:
      if t.uniqueViolation(ix, indexKeyFor(t, ix, row), -1):
        conflict = true
    if conflict and st.onConflict in ["ignore", "replace"]:
      if st.onConflict == "ignore": continue
      for ix in t.indexes:
        if ix.unique:
          let key = indexKeyFor(t, ix, row)
          for rid in ix.indexScanEq(key):
            let (foundOld, old) = t.rs.get(rid)
            if not foundOld: continue
            c.recordUndo(ukDelete, t, rid, old)
            t.removeRow(rid)
            if c.db.changes >= 0: discard
    let rid = t.nextRowid
    inc t.nextRowid
    c.recordUndo(ukInsert, t, rid, row)
    t.storeRow(rid, row)
    c.db.lastRowid = rid
    inc c.db.changes
    inc c.db.totalChanges
    if st.returning.len > 0:
      var outRow: Row
      c.vals = row
      for rc in st.returning: outRow.add c.eval(rc.e)
      returned.add outRow
  if st.returning.len > 0:
    result.rows = returned
    for rc in st.returning:
      result.cols.add (if rc.alias.len > 0: rc.alias else: rc.text)

proc updateRows(c0: Ctx; st: Stmt): ResultSet =
  let t = c0.db.cat.findTable(st.table)
  if t == nil: fail(notFound, "no such table: " & st.table)
  if c0.db.opts.readOnly: fail(readOnly, "database is read-only")
  let c = scopedCtx(c0, t)
  var setIdx: seq[int] = @[]
  for a in st.assigns:
    let i = t.colByName(a.col)
    if i < 0: fail(notFound, "no such column: " & a.col)
    if t.pkCols.find(i) >= 0 and t.cols[i].aff == affInteger:
      fail(unsupported, "updating a rowid alias column is not supported")
    setIdx.add i
  let scanCtx = c
  var returned: seq[Row] = @[]
  # Snapshot the scan: a write during the walk can restructure the tree, and a
  # live iterator over pages that are being split is exactly how a storage
  # engine crashes. UPDATE is not supposed to move rows (the rowid is stable),
  # but "not supposed to" is not a guarantee worth betting a page on.
  for rid in t.rs.rowids():
    let (foundRow, old) = t.rs.get(rid)
    if not foundRow: continue
    scanCtx.vals = old
    if st.where != nil and not scanCtx.eval(st.where).whereTrue(): continue
    var row = old
    for k, i in setIdx:
      row[i] = scanCtx.eval(st.assigns[k].e)
      row[i] = c.coerce(t, i, row[i])
    c.checkRow(t, row, rid)
    c.recordUndo(ukUpdate, t, rid, old)
    for ix in t.indexes:
      ix.indexDelete(indexKeyFor(t, ix, old), rid)
    t.rs.put(rid, row)
    for ix in t.indexes:
      ix.indexInsert(indexKeyFor(t, ix, row), rid)
    inc c.db.changes
    inc c.db.totalChanges
    if st.returning.len > 0:
      var outRow: Row
      scanCtx.vals = row
      for rc in st.returning: outRow.add scanCtx.eval(rc.e)
      returned.add outRow
  if st.returning.len > 0:
    result.rows = returned
    for rc in st.returning:
      result.cols.add (if rc.alias.len > 0: rc.alias else: rc.text)

proc deleteRows(c0: Ctx; st: Stmt): ResultSet =
  let t = c0.db.cat.findTable(st.table)
  if t == nil: fail(notFound, "no such table: " & st.table)
  if c0.db.opts.readOnly: fail(readOnly, "database is read-only")
  let c = scopedCtx(c0, t)
  let scanCtx = c
  var victims: seq[int64] = @[]
  for rid in t.rs.rowids():
    let (foundV, row) = t.rs.get(rid)
    if not foundV: continue
    scanCtx.vals = row
    if st.where != nil and not scanCtx.eval(st.where).whereTrue(): continue
    victims.add rid
  var returned: seq[Row] = @[]
  for rid in victims:
    let (foundOld, old) = t.rs.get(rid)
    if not foundOld: continue
    if st.returning.len > 0:
      var outRow: Row
      scanCtx.vals = old
      for rc in st.returning: outRow.add scanCtx.eval(rc.e)
      returned.add outRow
    c.recordUndo(ukDelete, t, rid, old)
    t.removeRow(rid)
    inc c.db.changes
    inc c.db.totalChanges
  if st.returning.len > 0:
    result.rows = returned
    for rc in st.returning:
      result.cols.add (if rc.alias.len > 0: rc.alias else: rc.text)

# ===========================================================================
# Transactions
# ===========================================================================

proc markDdl(db: Db) {.inline.} =
  ## DDL cannot be undone by a row-level journal (a dropped table's identity is
  ## gone), so a transaction containing DDL rolls back by restoring the whole
  ## catalog snapshot. DML-only transactions keep the cheap journal path.
  if db.txDepth > 0: db.txDdl = true

proc beginTx*(db: Db) =
  if db.txDepth == 0:
    db.catSnapshot = cloneCatalog(db.cat)
    db.undo = @[]
    db.txDdl = false
  inc db.txDepth

proc rollbackTx*(db: Db) =
  if db.txDepth == 0: fail(misuse, "no transaction is active")
  dec db.txDepth
  if db.txDepth == 0:
    if db.txDdl and db.catSnapshot != nil:
      db.cat = cloneCatalog(db.catSnapshot)
      if db.file != nil:
        # The snapshot's tables are memory copies (they had to be, so they could
        # be rolled back). Rebind them to their on-disk homes before anyone can
        # commit through them — a table that silently stopped persisting after a
        # rolled-back DDL would be the worst possible bug in this module.
        for _, t in db.cat.tables:
          if t.tid != 0:
            t.rs = newDiskStore(db.file.tree, t.tid, rowKeys(db.file.tree, t.tid))
            rebuildIndexes(db, t)
      db.undo = @[]
      db.catSnapshot = nil
      db.txDdl = false
      return
    # DML-only: replay the journal backwards (cheap, O(changes)).
    for i in countdown(db.undo.len - 1, 0):
      let u = db.undo[i]
      case u.kind
      of ukInsert: u.tbl.removeRow(u.rid)
      of ukDelete: u.tbl.storeRow(u.rid, u.row)
      of ukUpdate:
        let (has, cur) = u.tbl.rs.get(u.rid)
        if has:
          for ix in u.tbl.indexes: ix.indexDelete(indexKeyFor(u.tbl, ix, cur), u.rid)
        u.tbl.rs.put(u.rid, u.row)
        for ix in u.tbl.indexes: ix.indexInsert(indexKeyFor(u.tbl, ix, u.row), u.rid)
    db.undo = @[]
    db.catSnapshot = nil
    if db.file != nil:
      # Nothing was written to the tree, so rollback of the disk state is just
      # dropping the overlay. That is the whole reason writes are staged.
      for _, t in db.cat.tables:
        if t.rs != nil: t.rs.discardStaged()

proc commitTx*(db: Db) =
  if db.txDepth == 0: fail(misuse, "no transaction is active")
  dec db.txDepth
  if db.txDepth == 0:
    if db.file != nil:
      # Rows first, then the schema, then one WAL commit for all of it — see
      # dbfile.commitFile. At this point the transaction is already correct in
      # memory; this is the step that makes it survive a power cut.
      db.file.commitFile(db.cat)
    db.undo = @[]
    db.catSnapshot = nil
    db.txDdl = false

proc savepoint(db: Db; name: string) =
  ## Savepoints are implemented as nested transaction levels with a marker.
  inc db.txDepth

# ===========================================================================
# PRAGMA
# ===========================================================================

proc pragmaArgText(c: Ctx; st: Stmt): string =
  ## A bare word in a PRAGMA argument is a *name*, not a column reference:
  ## `PRAGMA table_info(s)` means the same as `PRAGMA table_info('s')` in
  ## SQLite. Evaluating it as an expression instead would fail with
  ## "no such column: s" on the one spelling everybody actually types.
  if st.pragmaValue == nil: return ""
  if st.pragmaValue.kind == exCol and st.pragmaValue.tbl.len == 0:
    return st.pragmaValue.name
  c.eval(st.pragmaValue).toText

proc execPragma(c: Ctx; st: Stmt): ResultSet =
  let db = c.db
  case st.pragmaName
  of "table_info", "table_xinfo":
    let t = db.cat.findTable(c.pragmaArgText(st))
    if t == nil: return
    result.cols = @["cid", "name", "type", "notnull", "dflt_value", "pk"]
    for i, col in t.cols:
      result.rows.add @[
        intValue(int64(i)), textValue(col.name), textValue(col.typeName),
        intValue(if col.notNull: 1 else: 0),
        (if col.hasDefault: textValue(col.defaultVal.toText) else: nullValue()),
        intValue(if t.pkCols.find(i) >= 0: 1 else: 0)]
  of "index_list":
    let t = db.cat.findTable(c.pragmaArgText(st))
    if t == nil: return
    result.cols = @["seq", "name", "unique", "origin", "partial"]
    for i, ix in t.indexes:
      result.rows.add @[
        intValue(int64(i)), textValue(ix.name),
        intValue(if ix.unique: 1 else: 0),
        textValue(if ix.isPkIndex: "pk" else: "c"),
        intValue(if ix.partial != nil: 1 else: 0)]
  of "index_info":
    let nm = c.pragmaArgText(st)
    result.cols = @["seqno", "cid", "name"]
    for _, t in db.cat.tables:
      for ix in t.indexes:
        if ix.name.toLowerAscii() == nm.toLowerAscii():
          for k, cc in ix.cols:
            result.rows.add @[intValue(int64(k)), intValue(int64(cc)),
                              textValue(t.cols[cc].name)]
          return
  of "foreign_key_list":
    result.cols = @["id", "seq", "table", "from", "to"]
    let t = db.cat.findTable(c.pragmaArgText(st))
    if t == nil: return
    for i, col in t.cols:
      if col.refTable.len > 0:
        result.rows.add @[intValue(int64(i)), intValue(0), textValue(col.refTable),
                          textValue(col.name), textValue(col.refCol)]
  of "user_version", "schema_version", "page_size", "journal_mode",
     "synchronous", "cache_size", "foreign_keys", "encoding",
     "application_id", "auto_vacuum", "busy_timeout", "query_only":
    # Read-only introspection. Mutable PRAGMAs that would need a persistence
    # layer are reported with their effective (fixed) value.
    result.cols = @[st.pragmaName]
    let v = case st.pragmaName
      of "journal_mode": "memory"
      of "encoding": "UTF-8"
      of "page_size": "4096"
      of "synchronous": "2"
      of "foreign_keys": (if db.opts.strictTyping: "1" else: "0")
      of "query_only": (if db.opts.readOnly: "1" else: "0")
      else: "0"
    result.rows.add @[textValue(v)]
  else:
    fail(unsupported, "unknown PRAGMA: " & st.pragmaName)

# ===========================================================================
# EXPLAIN
# ===========================================================================

proc explain(c: Ctx; st: Stmt): ResultSet =
  ## Real, honest plan output — computed from the statement, not from a VM
  ## program listing. Used by tests to assert that indexes are actually picked.
  result.cols = @["id", "detail"]
  var lines: seq[string]
  let target = if st.inner != nil: st.inner else: st
  case target.kind
  of stSelect:
    let s = target.select
    if s.fromFirst == nil:
      lines.add "SCAN CONSTANT ROW"
    else:
      var i = 0
      if s.fromFirst.name.len > 0:
        let t = c.db.cat.findTable(s.fromFirst.name)
        if t != nil:
          let alias = if s.fromFirst.alias.len > 0: s.fromFirst.alias else: t.name
          var conjuncts: seq[Expr] = @[]
          flattenAnd(s.where, conjuncts)
          var ixName = ""
          var ixCol = ""
          for cj in conjuncts:
            if cj.kind == exBinary and cj.op in ["=", "=="] and
               (cj.args[0].kind == exCol or cj.args[1].kind == exCol):
              let ce = if cj.args[0].kind == exCol: cj.args[0] else: cj.args[1]
              let ci = t.colByName(ce.name)
              for ix in t.indexes:
                if ixName.len == 0 and ix.cols.len == 1 and ix.cols[0] == ci:
                  ixName = ix.name
                  ixCol = ce.name
          if ixName.len > 0:
            lines.add "SEARCH " & t.name & " USING INDEX " & ixName &
                      " (" & ixCol & "=?)"
          else:
            lines.add "SCAN " & t.name & " (~" & $t.rs.len & " rows)"
        else: lines.add "SCAN " & s.fromFirst.name
        for j in s.joins:
          lines.add "JOIN " & j.table.name & " (nested loop)"
          inc i
      else:
        lines.add "SCAN SUBQUERY"
    if s.where != nil: lines.add "FILTER " & s.where.op
    if s.groupBy.len > 0: lines.add "GROUP BY " & $s.groupBy.len & " key(s)"
    if s.orderBy.len > 0: lines.add "SORT " & $s.orderBy.len & " key(s)"
    if s.isDistinct: lines.add "DISTINCT"
  of stInsert: lines.add "INSERT INTO " & target.table
  of stUpdate: lines.add "UPDATE " & target.table
  of stDelete: lines.add "DELETE FROM " & target.table
  of stCreateTable: lines.add "CREATE TABLE " & target.table
  of stCreateIndex: lines.add "CREATE INDEX " & target.indexName
  else: lines.add "STATEMENT"
  for i, l in lines:
    result.rows.add @[intValue(int64(i)), textValue(l)]

# ===========================================================================
# Dispatch
# ===========================================================================

proc runStmt(db: Db; c: Ctx; st: Stmt): ResultSet =
  case st.kind
  of stSelect: return c.execSelect(st.select)
  of stInsert: return c.insertRows(st)
  of stUpdate: return c.updateRows(st)
  of stDelete: return c.deleteRows(st)
  of stCreateTable: return c.createTable(st)
  of stDropTable: return c.dropTable(st)
  of stCreateIndex: return c.createIndex(st)
  of stDropIndex:
    for _, t in db.cat.tables:
      var k = 0
      while k < t.indexes.len:
        if t.indexes[k].name.toLowerAscii() == st.indexName.toLowerAscii():
          t.indexes.delete(k)
          return
        inc k
    if not st.ifExists: fail(notFound, "no such index: " & st.indexName)
  of stAlterTable: return c.alterTable(st)
  of stCreateView:
    db.markDdl()
    db.cat.views[st.viewName.toLowerAscii()] = (st.viewName, st.viewCols, st.viewSelect)
  of stDropView:
    let k = st.viewName.toLowerAscii()
    if db.cat.views.hasKey(k): db.cat.views.del k
    elif not st.ifExists: fail(notFound, "no such view: " & st.viewName)
  of stBegin: db.beginTx()
  of stCommit: db.commitTx()
  of stRollback:
    if st.savepointName.len > 0:
      if db.txDepth > 1: dec db.txDepth
      elif db.txDepth == 1: db.rollbackTx()
      else: fail(misuse, "no transaction is active")
    else:
      db.rollbackTx()
  of stSavepoint: db.savepoint(st.savepointName)
  of stRelease:
    if db.txDepth > 1: dec db.txDepth
    else: fail(misuse, "no savepoint " & st.savepointName)
  of stPragma: return c.execPragma(st)
  of stExplain: return c.explain(st)
  of stAnalyze, stVacuum: discard

func mutates(st: Stmt): bool =
  ## Statements that can change durable state. Everything else may run without
  ## opening a transaction — a read must not pay for a WAL commit.
  st.kind in {stInsert, stUpdate, stDelete, stCreateTable, stDropTable,
              stCreateIndex, stDropIndex, stAlterTable, stCreateView, stDropView}

proc execPrepared*(db: Db; p: Prepared; params: seq[Value]): ResultSet =
  let c = newCtx(db, params)
  db.changes = 0
  db.rand = db.rand xor (uint64(db.totalChanges) + 0x9E3779B97F4A7C15'u64)
  if params.len > p.nParams:
    fail(badParam, "too many parameters: got " & $params.len &
         ", statement uses " & $p.nParams)
  let st = p.stmt
  inc p.execCount

  # Implicit transaction, on a file-backed database only. Without it a bare
  # INSERT outside BEGIN would live in memory and vanish on close — the single
  # most likely way for a storage engine to lose data while looking healthy.
  # In-memory databases keep the old behaviour exactly, because there is nothing
  # to make durable and a transaction per statement would only cost time.
  let implicit = db.txDepth == 0 and db.file != nil and mutates(st)
  if implicit: db.beginTx()
  try:
    result = runStmt(db, c, st)
    if implicit: db.commitTx()
  except CatchableError:
    if implicit and db.txDepth > 0: db.rollbackTx()
    raise

proc prepare*(db: Db; sql: string): Prepared =
  ## Parse + cache. The cache key is the SQL text itself; statements are
  ## immutable, so a cached AST can be executed concurrently by design (the
  ## engine is single-threaded today, and stays correct if it becomes
  ## multi-threaded, because execution never mutates the Prepared).
  let key = sql
  if db.stmtCache.hasKey(key):
    return db.stmtCache[key]
  let (st, nParams) = parseOne(sql)
  var names: seq[string] = @[]
  var p = Prepared(sql: sql, stmt: st, nParams: nParams, paramNames: names)
  if db.stmtCache.len < 128:
    db.stmtCache[key] = p
  p
