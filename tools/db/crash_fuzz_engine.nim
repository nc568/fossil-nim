## Crash fuzzer at the SQL level (task K9L-67, "crash_fuzz runs with the engine").
##
##   nim c -r --skipParentCfg:on --path:src --mm:arc tools/db/crash_fuzz_engine.nim 200
##
## `crash_fuzz.nim` cuts the bytes underneath the B+tree. This one cuts them
## underneath the *engine*: it speaks SQL, commits transactions, and then the
## bytes are truncated at a random offset. What must hold afterwards is a
## property of the database, not of the tree:
##
##   * the file reopens — a torn write never leaves an unreadable database;
##   * every transaction that reported "committed" is entirely there;
##   * no transaction is half there (that is the failure mode that silently
##     corrupts an application: a transfer counted once instead of twice);
##   * the reopened catalog still describes the table the workload created.
##
## Counted, not asserted, so a failure says how far the run got before it.

import std/[os, random, strutils, tables]
import fossil/db/[api, errors, vfs, btree, values]

const
  Txns = 6
  PerTxn = 8

type
  Run = object
    rows: int            ## rows in committed transactions
    total: int           ## their sum, so a silent overwrite is caught
    committed: int
    crashed: bool
    dbBytes, walBytes: string

proc workload(seed, crashAt: int): Run =
  let dbVfs = openMemoryVfs()
  let walVfs = openMemoryVfs()
  if crashAt > 0:
    dbVfs.crashAt = crashAt
    walVfs.crashAt = crashAt
  let db = openOnVfs(dbVfs, walVfs)
  var n = 0
  try:
    discard db.execScript("create table t(id integer primary key, tag text, n integer)")
  except DbError:
    result.crashed = true
  for txn in 0 ..< Txns:
    if result.crashed: break
    try:
      discard db.execScript("begin")
      for _ in 0 ..< PerTxn:
        inc n
        discard db.execute("insert into t(id, tag, n) values (?, ?, ?)",
                           toParams([intValue(n), textValue("s" & $seed),
                                     intValue(n mod 7)]))
      discard db.execScript("commit")
    except DbError:
      result.crashed = true
    if dbVfs.dead or walVfs.dead: result.crashed = true
    if result.crashed: break
    result.committed = txn + 1
    result.rows = n
    result.total = 0
    for i in 1 .. n: result.total += i mod 7
  result.dbBytes = dbVfs.snapshot()
  result.walBytes = walVfs.snapshot()
  if not result.crashed: db.close()

proc verify(o: Run): string =
  ## Empty string means "this crash was handled correctly".
  let dbVfs = reopenFrom(openMemoryVfs(), o.dbBytes)
  let walVfs = reopenFrom(openMemoryVfs(), o.walBytes)
  var db: Db
  try:
    db = openOnVfs(dbVfs, walVfs)
  except DbError as e:
    return "reopened but unreadable: " & e.msg
  defer: db.close()

  try:
    discard db.file.tree.verify()
  except DbError as e:
    return "structure broken: " & e.msg

  var gotRows, gotTotal: int
  try:
    let rs = db.execute("select count(*), sum(n) from t")
    gotRows = int(rs.rows[0][0].asInt)
    gotTotal = if rs.rows[0][1].kind == vkNull: 0 else: int(rs.rows[0][1].asInt)
  except DbError as e:
    # No table at all is legitimate only when nothing ever committed: the
    # CREATE TABLE itself was the first transaction and it was cut.
    if o.rows == 0 and e.msg.startsWith("no such table"):
      return ""
    return "query failed after reopen: " & e.msg

  if gotRows != o.rows:
    return "row count " & $gotRows & " != committed " & $o.rows &
           " (half-applied or lost transaction)"
  if gotTotal != o.total:
    return "sum " & $gotTotal & " != committed " & $o.total
  # the rows must also be *distinct*: a replayed commit that inserted twice
  # would keep the count right only by accident, and would be caught here
  try:
    let d = db.execute("select count(distinct id) from t")
    if int(d.rows[0][0].asInt) != gotRows:
      return "duplicate rows after replay: " & $d.rows[0][0].asInt & " distinct"
  except DbError as e:
    return "distinct query failed: " & e.msg
  ""

let iterations = if paramCount() >= 1: parseInt(paramStr(1)) else: 200
var torn = 0
var clean = 0
var failures = 0
var worst = ""

for i in 0 ..< iterations:
  let seed = i div 20
  let full = workload(seed, 0)
  if full.crashed:
    echo "workload crashed with no crash injection at iter ", i
    quit 1
  let span = max(2, full.dbBytes.len + full.walBytes.len)
  let cut = rand(1 .. span)
  let o = workload(seed, cut)
  let bad = verify(o)
  if o.crashed: inc torn else: inc clean
  if bad.len > 0:
    inc failures
    if worst.len == 0:
      worst = "iter " & $i & " seed=" & $seed & " cut=" & $cut & ": " & bad

echo "iterations    ", iterations
echo "torn crashes  ", torn
echo "clean runs    ", clean
echo "failures      ", failures
if worst.len > 0:
  echo "first failure ", worst
  quit 1
echo "verdict       no half-applied transaction, no lost commit, catalog intact"
