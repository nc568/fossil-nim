## Timeline - history of checkins with real SQL

import ../types
import ../storage/backend
import ../storage/sqlite_backend
import ../utils/hash
import std/[times, options, strutils, tables]

type
  TimelineEntry* = object
    rid*: Rid
    uuid*: Uuid
    date*: DateTime
    user*: string
    comment*: string
    branch*: string
    isLeaf*: bool
    parent*: seq[Uuid]
    tags*: seq[string]
    mtime*: int64

  TimelineFilter* = object
    branch*: Option[string]
    user*: Option[string]
    since*: Option[DateTime]
    until*: Option[DateTime]
    limit*: int
    offset*: int
    file*: Option[string]
    tag*: Option[string]
    typeFilter*: Option[string]

proc defaultFilter*(): TimelineFilter =
  TimelineFilter(limit: 20, offset: 0)

proc getTimelineSqlite*(backend: SqliteBackend, filter: TimelineFilter): FossilResult[seq[TimelineEntry]] =
  # SEC-07 fix: use parameterized queries
  var sql = "SELECT objid, mtime, user, comment, branch, type FROM event WHERE 1=1"
  var bindBranch = ""
  var bindUser = ""
  var bindType = ""
  var hasBranch = false
  var hasUser = false
  var hasType = false
  if filter.branch.isSome:
    sql.add " AND branch=?1"
    bindBranch = filter.branch.get
    hasBranch = true
  if filter.user.isSome:
    if hasBranch:
      sql.add " AND user=?2"
    else:
      sql.add " AND user=?1"
    bindUser = filter.user.get
    hasUser = true
  if filter.typeFilter.isSome:
    var idx = 1
    if hasBranch: inc idx
    if hasUser: inc idx
    sql.add " AND type=?" & $idx
    bindType = filter.typeFilter.get
    hasType = true
  else:
    sql.add " AND type='ci'"
  sql.add " ORDER BY mtime DESC, objid DESC"
  sql.add " LIMIT " & $filter.limit
  sql.add " OFFSET " & $filter.offset

  var entries: seq[TimelineEntry] = @[]

  {.push header: "<sqlite3.h>".}
  type
    sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_column_int64(pStmt: ptr sqlite3_stmt, iCol: cint): int64 {.importc.}
  proc sqlite3_column_text(pStmt: ptr sqlite3_stmt, iCol: cint): ptr cuchar {.importc.}
  proc sqlite3_column_double(pStmt: ptr sqlite3_stmt, iCol: cint): float64 {.importc.}
  proc sqlite3_bind_text(pStmt: ptr sqlite3_stmt, i: cint, zData: cstring, n: cint, xDel: pointer): cint {.importc.}
  {.pop.}

  const SQLITE_ROW = 100

  var stmt: ptr sqlite3_stmt
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) != 0:
    return err[seq[TimelineEntry]](feDbError, "cannot prepare timeline query")
  # Bind parameters
  var bindIdx = 1
  if hasBranch:
    discard sqlite3_bind_text(stmt, cint(bindIdx), bindBranch.cstring, -1, nil)
    inc bindIdx
  if hasUser:
    discard sqlite3_bind_text(stmt, cint(bindIdx), bindUser.cstring, -1, nil)
    inc bindIdx
  if hasType:
    discard sqlite3_bind_text(stmt, cint(bindIdx), bindType.cstring, -1, nil)

  defer: discard sqlite3_finalize(stmt)

  while sqlite3_step(stmt) == SQLITE_ROW:
    let rid = Rid(sqlite3_column_int64(stmt, 0))
    let mtimeRaw = sqlite3_column_double(stmt, 1)
    # mtime may be Julian date or Unix timestamp
    var mtimeInt: int64
    var dt: DateTime
    if mtimeRaw > 2400000.0 and mtimeRaw < 3000000.0:
      # Julian date
      let unix = (mtimeRaw - 2440587.5) * 86400.0
      mtimeInt = int64(unix)
      dt = fromUnix(int64(unix)).utc
    else:
      # Unix timestamp (could be stored as float)
      mtimeInt = int64(mtimeRaw)
      dt = fromUnix(mtimeInt).utc

    let userPtr = sqlite3_column_text(stmt, 2)
    let commentPtr = sqlite3_column_text(stmt, 3)
    let branchPtr = sqlite3_column_text(stmt, 4)
    let user = if userPtr != nil: $cast[cstring](userPtr) else: ""
    let comment = if commentPtr != nil: $cast[cstring](commentPtr) else: ""
    let branch = if branchPtr != nil: $cast[cstring](branchPtr) else: "trunk"

    var uuid = Uuid("0".repeat(64))
    # Try to get real uuid from blob table
    let infoRes = backend.getBlobInfo(rid)
    if infoRes.isOk:
      uuid = infoRes.value.uuid
    else:
      # Fallback: try getBlobBy rid and hash
      let blobRes = backend.getBlob(rid)
      if blobRes.isOk:
        uuid = hashBlob(blobRes.value)

    entries.add TimelineEntry(
      rid: rid,
      uuid: uuid,
      date: dt,
      user: user,
      comment: comment,
      branch: branch,
      mtime: mtimeInt
    )

  ok(entries)

proc getTimeline*[T: StorageBackend](backend: T, filter: TimelineFilter): FossilResult[seq[TimelineEntry]] =
  when T is SqliteBackend:
    return getTimelineSqlite(backend, filter)
  else:
    var entries: seq[TimelineEntry] = @[]
    for i in 0..<filter.limit:
      entries.add TimelineEntry(
        rid: Rid(i+1),
        uuid: Uuid(("a".repeat(60) & toHex(i, 4).toLowerAscii())),
        date: now().utc - initDuration(days=i),
        user: "user" & $i,
        comment: "commit " & $i,
        branch: if filter.branch.isSome: filter.branch.get else: "trunk",
        isLeaf: i==0,
        mtime: getTime().toUnix() - int64(i*86400)
      )
    ok(entries)

proc timelineToText*(entries: seq[TimelineEntry]): string =
  var sb = ""
  for e in entries:
    sb.add e.date.format("yyyy-MM-dd HH:mm") & " [" & ($e.uuid)[0..9] & "] " & e.comment & " (" & e.branch & ") user: " & e.user & " rid=" & $e.rid & "\n"
  sb

proc timelineToJson*(entries: seq[TimelineEntry]): string =
  var sb = "["
  var first=true
  for e in entries:
    if not first: sb.add ","
    first=false
    sb.add "{\"rid\":" & $int64(e.rid) & ",\"uuid\":\"" & $e.uuid & "\",\"comment\":\"" & e.comment.replace("\"", "\\\"") & "\",\"branch\":\"" & e.branch & "\",\"user\":\"" & e.user & "\",\"mtime\":" & $e.mtime & "}"
  sb.add "]"
  sb
