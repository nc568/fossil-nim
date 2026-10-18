## Branch management - real SQL

import ../types
import ../storage/backend
import ../storage/sqlite_backend
import std/[options, strutils, tables, times]

type
  BranchInfo* = object
    name*: string
    isPrivate*: bool
    isClosed*: bool
    tipRid*: Rid
    tipUuid*: Option[Uuid]
    count*: int
    lastMtime*: int64

proc listBranchesSqlite*(backend: SqliteBackend): FossilResult[seq[BranchInfo]] =
  {.push header: "<sqlite3.h>".}
  type
    sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_column_int64(pStmt: ptr sqlite3_stmt, iCol: cint): int64 {.importc.}
  proc sqlite3_column_text(pStmt: ptr sqlite3_stmt, iCol: cint): ptr cuchar {.importc.}
  {.pop.}

  const SQLITE_ROW = 100

  let sql = """
    SELECT tagname,
           (SELECT COUNT(*) FROM tagxref WHERE tagid=tag.tagid AND tagtype>0) as cnt,
           (SELECT MAX(mtime) FROM event WHERE objid IN (SELECT rid FROM tagxref WHERE tagid=tag.tagid))
    FROM tag WHERE tagname LIKE 'sym-%' ORDER BY tagname
  """

  var branches: seq[BranchInfo] = @[]
  var stmt: ptr sqlite3_stmt
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) != 0:
    let sql2 = "SELECT branch, COUNT(*), MAX(mtime) FROM event WHERE type='ci' GROUP BY branch"
    var stmt2: ptr sqlite3_stmt
    if sqlite3_prepare_v2(backend.db, sql2.cstring, -1, addr stmt2, nil) != 0:
      return ok(@[BranchInfo(name: "trunk", count: 0, tipRid: invalidRid())])
    defer: discard sqlite3_finalize(stmt2)
    while sqlite3_step(stmt2) == SQLITE_ROW:
      let branchPtr = sqlite3_column_text(stmt2, 0)
      let cnt = sqlite3_column_int64(stmt2, 1)
      let maxMtime = sqlite3_column_int64(stmt2, 2)
      let branchName = if branchPtr != nil: $cast[cstring](branchPtr) else: "trunk"
      branches.add BranchInfo(name: branchName, count: int(cnt), lastMtime: maxMtime, tipRid: invalidRid())
    if branches.len==0:
      branches.add BranchInfo(name: "trunk", count: 0, tipRid: invalidRid())
    return ok(branches)

  defer: discard sqlite3_finalize(stmt)
  while sqlite3_step(stmt) == SQLITE_ROW:
    let tagPtr = sqlite3_column_text(stmt, 0)
    let cnt = sqlite3_column_int64(stmt, 1)
    let maxMtime = sqlite3_column_int64(stmt, 2)
    let tagName = if tagPtr != nil: $cast[cstring](tagPtr) else: ""
    if not tagName.startsWith("sym-"): continue
    let branchName = tagName[4..^1]
    var isClosed = false
    var isPrivate = false
    branches.add BranchInfo(name: branchName, count: int(cnt), lastMtime: maxMtime, tipRid: invalidRid(), isClosed: isClosed, isPrivate: isPrivate)

  if branches.len==0:
    branches.add BranchInfo(name: "trunk", count: 0, tipRid: invalidRid())

  ok(branches)

proc listBranches*[T: StorageBackend](backend: T): FossilResult[seq[BranchInfo]] =
  when T is SqliteBackend:
    return listBranchesSqlite(backend)
  else:
    ok(@[BranchInfo(name: "trunk", count: 0, tipRid: invalidRid())])

proc createBranch*[T: StorageBackend](backend: var T, name: string, isPrivate: bool = false): FossilResult[void] =
  if name.len==0:
    return errVoid(feInvalidArg, "branch name empty")
  if " " in name or "\n" in name:
    return errVoid(feInvalidArg, "invalid branch name")
  when T is SqliteBackend:
    # SEC-07 fix: use bind
    {.push header: "<sqlite3.h>".}
    type sqlite3_stmt_b {.importc: "sqlite3_stmt", incompleteStruct.} = object
    proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt_b, pzTail: pointer): cint {.importc.}
    proc sqlite3_finalize(pStmt: ptr sqlite3_stmt_b): cint {.importc.}
    proc sqlite3_step(pStmt: ptr sqlite3_stmt_b): cint {.importc.}
    proc sqlite3_bind_text(pStmt: ptr sqlite3_stmt_b, i: cint, zData: cstring, n: cint, xDel: pointer): cint {.importc.}
    {.pop.}
    var stmt: ptr sqlite3_stmt_b
    let sql = "INSERT OR IGNORE INTO tag(tagname) VALUES(?1)"
    if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil)==0:
      let tagName = "sym-" & name
      discard sqlite3_bind_text(stmt, 1, tagName.cstring, -1, nil)
      discard sqlite3_step(stmt)
      discard sqlite3_finalize(stmt)
  okVoid()

proc closeBranch*[T: StorageBackend](backend: var T, name: string): FossilResult[void] =
  when T is SqliteBackend:
    {.push header: "<sqlite3.h>".}
    type sqlite3_stmt_bc {.importc: "sqlite3_stmt", incompleteStruct.} = object
    proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt_bc, pzTail: pointer): cint {.importc.}
    proc sqlite3_finalize(pStmt: ptr sqlite3_stmt_bc): cint {.importc.}
    proc sqlite3_step(pStmt: ptr sqlite3_stmt_bc): cint {.importc.}
    proc sqlite3_bind_text(pStmt: ptr sqlite3_stmt_bc, i: cint, zData: cstring, n: cint, xDel: pointer): cint {.importc.}
    {.pop.}
    var stmt: ptr sqlite3_stmt_bc
    let sql = "INSERT OR IGNORE INTO tag(tagname) VALUES(?1)"
    if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil)==0:
      let tagName = "sym-" & name & "-closed"
      discard sqlite3_bind_text(stmt, 1, tagName.cstring, -1, nil)
      discard sqlite3_step(stmt)
      discard sqlite3_finalize(stmt)
  okVoid()

proc getBranchTip*[T: StorageBackend](backend: T, branchName: string): FossilResult[Option[Rid]] =
  when T is SqliteBackend:
    {.push header: "<sqlite3.h>".}
    type
      sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
    proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
    proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
    proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
    proc sqlite3_column_int64(pStmt: ptr sqlite3_stmt, iCol: cint): int64 {.importc.}
    proc sqlite3_bind_text(pStmt: ptr sqlite3_stmt, i: cint, zData: cstring, n: cint, xDel: pointer): cint {.importc.}
    {.pop.}
    const SQLITE_ROW = 100
    let sql = "SELECT objid FROM event WHERE branch=?1 AND type='ci' ORDER BY mtime DESC LIMIT 1"
    var stmt: ptr sqlite3_stmt
    if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) != 0:
      return ok(none(Rid))
    discard sqlite3_bind_text(stmt, 1, branchName.cstring, -1, nil)
    defer: discard sqlite3_finalize(stmt)
    if sqlite3_step(stmt) == SQLITE_ROW:
      let rid = Rid(sqlite3_column_int64(stmt, 0))
      return ok(some(rid))
    return ok(none(Rid))
  else:
    ok(none(Rid))
