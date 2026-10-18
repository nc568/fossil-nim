## Stash - save/restore working tree changes with real SQL

import ../types
import ../storage/backend
import ../storage/sqlite_backend
import ../vcs/diff
import std/[times, options, strutils]

type
  StashEntry* = object
    id*: int
    message*: string
    date*: int64
    branch*: string
    diff*: Blob
    uuid*: Uuid
    rid*: Rid

  StashList* = seq[StashEntry]

proc saveStashSqlite*(backend: var SqliteBackend, message: string, workingDiff: Blob): FossilResult[StashEntry] =
  if workingDiff.isEmpty:
    return err[StashEntry](feInvalidArg, "nothing to stash")

  {.push header: "<sqlite3.h>".}
  type
    sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_column_int64(pStmt: ptr sqlite3_stmt, iCol: cint): int64 {.importc.}
  proc sqlite3_bind_text(pStmt: ptr sqlite3_stmt, i: cint, zData: cstring, n: cint, xDel: pointer): cint {.importc.}
  proc sqlite3_bind_int64(pStmt: ptr sqlite3_stmt, i: cint, iValue: int64): cint {.importc.}
  proc sqlite3_last_insert_rowid(db: pointer): int64 {.importc.}
  {.pop.}

  const SQLITE_ROW = 100
  const SQLITE_DONE = 101

  # Ensure stash table exists (it's in CheckoutSchema, but for repo we use config or create)
  discard backend.execSql("CREATE TABLE IF NOT EXISTS stash(stashid INTEGER PRIMARY KEY, vid INTEGER, comment TEXT, ctime TIMESTAMP)")

  # Insert stash entry
  var stmt: ptr sqlite3_stmt
  let sql = "INSERT INTO stash(comment, ctime) VALUES(?, ?)"
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) != 0:
    return err[StashEntry](feDbError, "prepare stash insert failed")
  defer: discard sqlite3_finalize(stmt)
  let msg = if message.len>0: message else: "WIP"
  discard sqlite3_bind_text(stmt, 1, msg.cstring, -1, nil)
  discard sqlite3_bind_int64(stmt, 2, getTime().toUnix())
  if sqlite3_step(stmt) != SQLITE_DONE:
    return err[StashEntry](feDbError, "stash insert failed")

  let stashId = int(sqlite3_last_insert_rowid(backend.db))

  # Store diff as blob with unique uuid
  let uuidStr = "s" & toHex(stashId, 8).toLowerAscii() & "0".repeat(55)
  let uuidRes = uuidFromHex(uuidStr)
  if uuidRes.isErr:
    return err[StashEntry](feInvalidArg, "uuid gen failed")
  let uuid = uuidRes.value

  let putRes = backend.putBlob(uuid, workingDiff, false)
  if putRes.isErr:
    return err[StashEntry](putRes.error.code, putRes.error.msg)

  ok(StashEntry(id: stashId, message: msg, date: getTime().toUnix(), diff: workingDiff, uuid: uuid, rid: putRes.value))

proc saveStash*[T: StorageBackend](backend: var T, message: string, workingDiff: Blob): FossilResult[StashEntry] =
  when T is SqliteBackend:
    return saveStashSqlite(backend, message, workingDiff)
  else:
    if workingDiff.isEmpty:
      return err[StashEntry](feInvalidArg, "nothing to stash")
    let entry = StashEntry(
      id: 1,
      message: if message.len>0: message else: "WIP",
      date: getTime().toUnix(),
      diff: workingDiff,
      uuid: Uuid("s".repeat(64))
    )
    let putRes = backend.putBlob(entry.uuid, workingDiff, false)
    if putRes.isErr:
      return err[StashEntry](putRes.error.code, putRes.error.msg)
    ok(entry)

proc listStashesSqlite*(backend: SqliteBackend): FossilResult[StashList] =
  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_column_int64(pStmt: ptr sqlite3_stmt, iCol: cint): int64 {.importc.}
  proc sqlite3_column_text(pStmt: ptr sqlite3_stmt, iCol: cint): ptr cuchar {.importc.}
  {.pop.}
  const SQLITE_ROW = 100

  var list: StashList = @[]
  var stmt: ptr sqlite3_stmt
  let sql = "SELECT stashid, comment, ctime FROM stash ORDER BY ctime DESC"
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) != 0:
    return ok(list) # table may not exist, return empty

  defer: discard sqlite3_finalize(stmt)
  while sqlite3_step(stmt) == SQLITE_ROW:
    let id = int(sqlite3_column_int64(stmt, 0))
    let commentPtr = sqlite3_column_text(stmt, 1)
    let ctime = sqlite3_column_int64(stmt, 2)
    let comment = if commentPtr != nil: $cast[cstring](commentPtr) else: "WIP"
    list.add StashEntry(id: id, message: comment, date: ctime)

  ok(list)

proc listStashes*[T: StorageBackend](backend: T): FossilResult[StashList] =
  when T is SqliteBackend:
    return listStashesSqlite(backend)
  else:
    ok(@[])

proc applyStashSqlite*(backend: SqliteBackend, id: int): FossilResult[Blob] =
  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_column_text(pStmt: ptr sqlite3_stmt, iCol: cint): ptr cuchar {.importc.}
  {.pop.}
  const SQLITE_ROW = 100

  # Get stash comment to find uuid? For MVP, we stored diff as blob with uuid s + hex id
  let uuidStr = "s" & toHex(id, 8).toLowerAscii() & "0".repeat(55)
  let uuidRes = uuidFromHex(uuidStr)
  if uuidRes.isErr:
    return err[Blob](feInvalidArg, "invalid stash id")
  let blobRes = backend.getBlobByUuid(uuidRes.value)
  if blobRes.isErr:
    return err[Blob](feNotFound, "stash not found", $id)
  ok(blobRes.value)

proc applyStash*[T: StorageBackend](backend: T, id: int): FossilResult[Blob] =
  when T is SqliteBackend:
    return applyStashSqlite(backend, id)
  else:
    err[Blob](feNotFound, "stash not found", $id)

proc dropStashSqlite*(backend: var SqliteBackend, id: int): FossilResult[void] =
  # SEC-07 fix: use bind
  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt_drop {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt_drop, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt_drop): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt_drop): cint {.importc.}
  proc sqlite3_bind_int64(pStmt: ptr sqlite3_stmt_drop, i: cint, v: int64): cint {.importc.}
  proc sqlite3_bind_text(pStmt: ptr sqlite3_stmt_drop, i: cint, zData: cstring, n: cint, xDel: pointer): cint {.importc.}
  {.pop.}
  var stmt: ptr sqlite3_stmt_drop
  let sql1 = "DELETE FROM stash WHERE stashid=?1"
  if sqlite3_prepare_v2(backend.db, sql1.cstring, -1, addr stmt, nil)==0:
    discard sqlite3_bind_int64(stmt, 1, int64(id))
    discard sqlite3_step(stmt)
    discard sqlite3_finalize(stmt)
  let uuidStr = "s" & toHex(id, 8).toLowerAscii() & "0".repeat(55)
  var stmt2: ptr sqlite3_stmt_drop
  let sql2 = "DELETE FROM blob WHERE uuid=?1"
  if sqlite3_prepare_v2(backend.db, sql2.cstring, -1, addr stmt2, nil)==0:
    discard sqlite3_bind_text(stmt2, 1, uuidStr.cstring, -1, nil)
    discard sqlite3_step(stmt2)
    discard sqlite3_finalize(stmt2)
  okVoid()

proc dropStash*[T: StorageBackend](backend: var T, id: int): FossilResult[void] =
  when T is SqliteBackend:
    return dropStashSqlite(backend, id)
  else:
    okVoid()
