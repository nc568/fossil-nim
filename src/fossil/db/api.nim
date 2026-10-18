## Public API of Foccil DB.
##
## The API is deliberately *parameter-first*: there is no helper that splices a
## value into SQL text. The only way to get user data into a statement is a
## bound parameter, which removes the entire string-concatenation injection
## class by construction rather than by convention.

import std/[tables, strutils]
import ./errors, ./values, ./engine, ./schema, ./parser, ./ast

export errors, values, engine, schema.Catalog

export codeName

type
  DbHandle* = Db

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

proc openDb*(opts = DefaultOptions): Db =
  Db(cat: newCatalog(), opts: opts, txDepth: 0, undo: @[],
     changes: 0, lastRowid: 0, totalChanges: 0,
     rand: 0x2545F4914F6CDD1D'u64, stmtCache: initTable[string, Prepared]())

proc openMemory*(): Db = openDb()

proc close*(db: Db) =
  ## Rolls back an open transaction instead of silently committing it — a
  ## dropped connection must never make half-finished work durable.
  if db.txDepth > 0:
    db.rollbackTx()
  db.stmtCache.clear()

# ---------------------------------------------------------------------------
# Parameters
# ---------------------------------------------------------------------------

type
  Params* = seq[Value]

func toParams*(args: openArray[Value]): Params =
  result = newSeqOfCap[Value](args.len)
  for a in args: result.add a

# ---------------------------------------------------------------------------
# Execution
# ---------------------------------------------------------------------------

proc execute*(db: Db; sql: string; params: Params = @[]): ResultSet =
  ## Prepare (cached) + execute. Returns rows for SELECT/RETURNING/PRAGMA.
  let st = db.prepare(sql)
  db.execPrepared(st, params)

proc changes*(db: Db): int64 = db.changes
proc lastInsertRowid*(db: Db): int64 = db.lastRowid
proc totalChanges*(db: Db): int64 = db.totalChanges

proc execScript*(db: Db; sql: string; params: Params = @[]): int =
  ## Runs several statements; returns how many produced rows.
  ## `params` is forwarded to every statement (a script with different
  ## parameter sets per statement should use `execute` per statement).
  var n = 0
  for stmt in parseScript(sql):
    let p = Prepared(sql: "", stmt: stmt, nParams: 0)
    let rs = db.execPrepared(p, params)
    if rs.rows.len > 0: inc n
  n

# ---------------------------------------------------------------------------
# Typed, bounds-checked cell readers.
#
# `Row` is `seq[Value]`, so the index operator is the built-in one; these
# helpers exist only to give call sites a *typed* and *non-raising-on-NULL*
# vocabulary. They never dereference anything unchecked.
# ---------------------------------------------------------------------------

proc cell*(r: Row; i: int): Value =
  if i < 0 or i >= r.len:
    fail(range, "column index out of range: " & $i)
  r[i]

proc asText*(r: Row; i: int): string = r.cell(i).toText
proc asInt*(r: Row; i: int): int64 = r.cell(i).asInt
proc asInt32*(r: Row; i: int): int = int(r.cell(i).asInt)
proc asFloat*(r: Row; i: int): float64 = r.cell(i).asFloat
proc asBool*(r: Row; i: int): bool = r.cell(i).truthy()
proc isNullAt*(r: Row; i: int): bool = r.cell(i).kind == vkNull

proc colIndex*(rs: ResultSet; name: string): int =
  for i, cname in rs.cols:
    if cname.toLowerAscii() == name.toLowerAscii(): return i
  -1

proc getCell*(r: Row; rs: ResultSet; name: string): Value =
  let i = rs.colIndex(name)
  if i < 0: fail(notFound, "no such result column: " & name)
  r[i]

proc sqliteVersion*(): string = "foccil-db 0.1.0 (arc)"

proc tableExists*(db: Db; name: string): bool =
  db.cat.findTable(name) != nil

proc tableNames*(db: Db): seq[string] =
  for name in db.cat.order: result.add name

proc rowCount*(db: Db; tableName: string): int =
  let t = db.cat.findTable(tableName)
  if t == nil: return -1
  t.rows.len
