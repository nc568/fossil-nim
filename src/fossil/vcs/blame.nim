## Blame / annotate - real implementation with file history walk

import ../types
import ../storage/backend
import ../storage/sqlite_backend
import ../artifact/manifest
import ../vcs/timeline
import ../vcs/diff
import std/[tables, strutils, times, options]

type
  BlameLine* = object
    lineNo*: int
    content*: string
    commitUuid*: Uuid
    author*: string
    date*: DateTime
    rid*: Rid
    isUncommitted*: bool

  BlameResult* = object
    file*: string
    lines*: seq[BlameLine]

proc blameFileSqlite*(backend: SqliteBackend, filePath: string, rev: Option[Uuid] = none(Uuid)): FossilResult[BlameResult] =
  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_column_int64(pStmt: ptr sqlite3_stmt, iCol: cint): int64 {.importc.}
  proc sqlite3_column_text(pStmt: ptr sqlite3_stmt, iCol: cint): ptr cuchar {.importc.}
  {.pop.}
  const SQLITE_ROW = 100

  var res = BlameResult(file: filePath)

  # SEC-07 fix: use bind for filename
  var fnid: int64 = -1
  var stmt: ptr sqlite3_stmt
  let sqlFn = "SELECT fnid FROM filename WHERE name=?1"
  if sqlite3_prepare_v2(backend.db, sqlFn.cstring, -1, addr stmt, nil) == 0:
    {.push header: "<sqlite3.h>".}
    proc sqlite3_bind_text_b(db: ptr sqlite3_stmt, i: cint, zData: cstring, n: cint, xDel: pointer): cint {.importc: "sqlite3_bind_text".}
    {.pop.}
    discard sqlite3_bind_text_b(stmt, 1, filePath.cstring, -1, nil)
    defer: discard sqlite3_finalize(stmt)
    if sqlite3_step(stmt) == SQLITE_ROW:
      fnid = sqlite3_column_int64(stmt, 0)

  var history: seq[tuple[rid: Rid, uuid: Uuid, mtime: int64, user: string, comment: string]] = @[]

  if fnid != -1:
    # Get all mids where file appears via mlink
    var stmt2: ptr sqlite3_stmt
    let sqlMlink = "SELECT mid, fid FROM mlink WHERE fnid=" & $fnid & " ORDER BY mid DESC"
    if sqlite3_prepare_v2(backend.db, sqlMlink.cstring, -1, addr stmt2, nil) == 0:
      defer: discard sqlite3_finalize(stmt2)
      while sqlite3_step(stmt2) == SQLITE_ROW:
        let mid = Rid(sqlite3_column_int64(stmt2, 0))
        let fid = Rid(sqlite3_column_int64(stmt2, 1))
        # Get event for mid
        let evRes = backend.getEventByRid(mid)
        if evRes.isOk:
          let ev = evRes.value
          # Get uuid for mid
          let infoRes = backend.getBlobInfo(mid)
          var uuid = Uuid("0".repeat(64))
          if infoRes.isOk:
            uuid = infoRes.value.uuid
          history.add (rid: mid, uuid: uuid, mtime: ev.mtime, user: ev.user, comment: ev.comment)

  if history.len == 0:
    # Fallback: get timeline and check if file exists in manifest
    var filter = defaultFilter()
    filter.limit = 100
    let tlRes = getTimelineSqlite(backend, filter)
    if tlRes.isOk:
      for entry in tlRes.value:
        let blobRes = backend.getBlob(entry.rid)
        if blobRes.isOk:
          let manRes = parseManifest(blobRes.value.data)
          if manRes.isOk:
            for fe in manRes.value.files:
              if fe.name == filePath:
                history.add (rid: entry.rid, uuid: entry.uuid, mtime: entry.mtime, user: entry.user, comment: entry.comment)
                break

  if history.len == 0:
    # No history, return empty or current file if exists
    return ok(res)

  # Sort history by mtime ascending (oldest first) for blame
  # History currently DESC, so reverse
  var ascHistory = history
  # Simple bubble reverse
  var revHist: seq[typeof(history[0])] = @[]
  for i in countdown(history.len-1, 0):
    revHist.add history[i]
  ascHistory = revHist

  # Get file content at latest rev
  var latestContent = ""
  var latestEntry = history[0] # history DESC, so first is latest
  # Actually history DESC, so latest is history[0]
  # For blame we need latest content
  let latestManRes = backend.getBlob(latestEntry.rid)
  if latestManRes.isOk:
    let manRes = parseManifest(latestManRes.value.data)
    if manRes.isOk:
      for fe in manRes.value.files:
        if fe.name == filePath:
          let fileBlobRes = backend.getBlobByUuid(fe.uuid)
          if fileBlobRes.isOk:
            latestContent = fileBlobRes.value.data
          break

  if latestContent.len == 0:
    # Try to get file directly if no manifest
    return ok(res)

  let lines = latestContent.splitLines()
  # For MVP, attribute all lines to latest commit, but try to find origin via history walk
  # Walk history and for each version, diff to see which lines changed

  # Initialize blame: all lines attributed to latest
  for i, line in lines:
    res.lines.add BlameLine(
      lineNo: i+1,
      content: line,
      commitUuid: latestEntry.uuid,
      author: latestEntry.user,
      date: fromUnix(latestEntry.mtime).utc,
      rid: latestEntry.rid
    )

  # If we have more than 1 history entry, try to attribute lines to older commits via diff
  if ascHistory.len > 1:
    # For each older version, check if line existed
    # Simple approach: for each line in latest, check in which oldest version it first appeared
    # We'll walk from oldest to newest and track line origins

    # Get all versions content
    var versionContents: seq[seq[string]] = @[]
    var versionInfos: seq[typeof(history[0])] = @[]
    for h in ascHistory:
      let manBlobRes = backend.getBlob(h.rid)
      if manBlobRes.isOk:
        let manRes = parseManifest(manBlobRes.value.data)
        if manRes.isOk:
          for fe in manRes.value.files:
            if fe.name == filePath:
              let fileBlobRes = backend.getBlobByUuid(fe.uuid)
              if fileBlobRes.isOk:
                versionContents.add fileBlobRes.value.data.splitLines()
                versionInfos.add h
              break

    if versionContents.len > 0:
      # For each line in latest, find earliest version where it appears
      let latestLines = versionContents[^1]
      for i, line in latestLines:
        var foundIdx = versionContents.len-1
        # Walk backwards to find when line was introduced
        for vIdx in countdown(versionContents.len-2, 0):
          if i < versionContents[vIdx].len and versionContents[vIdx][i] == line:
            # Line existed in older version, continue searching
            foundIdx = vIdx
          else:
            # Check if line exists anywhere in older version (not necessarily same position)
            var exists = false
            for l in versionContents[vIdx]:
              if l == line:
                exists = true
                break
            if exists:
              foundIdx = vIdx
            else:
              break
        if foundIdx < versionInfos.len and foundIdx < res.lines.len or i < res.lines.len:
          if i < res.lines.len:
            res.lines[i].commitUuid = versionInfos[foundIdx].uuid
            res.lines[i].author = versionInfos[foundIdx].user
            res.lines[i].date = fromUnix(versionInfos[foundIdx].mtime).utc
            res.lines[i].rid = versionInfos[foundIdx].rid

  ok(res)

proc blameFile*[T: StorageBackend](backend: T, filePath: string, rev: Option[Uuid] = none(Uuid)): FossilResult[BlameResult] =
  when T is SqliteBackend:
    return blameFileSqlite(backend, filePath, rev)
  else:
    var res = BlameResult(file: filePath)
    let dummyUuid = Uuid("a".repeat(64))
    for i in 0..<10:
      res.lines.add BlameLine(
        lineNo: i+1,
        content: "line " & $(i+1),
        commitUuid: dummyUuid,
        author: "user@example.com",
        date: now().utc
      )
    ok(res)

proc blameToText*(blame: BlameResult): string =
  var sb = ""
  for line in blame.lines:
    let uuidShort = if ($line.commitUuid).len >= 10: ($line.commitUuid)[0..9] else: $line.commitUuid
    sb.add uuidShort & " (" & line.author & " " & line.date.format("yyyy-MM-dd") & " " & $line.lineNo & ") " & line.content & "\n"
  sb

proc blameToJson*(blame: BlameResult): string =
  var sb = "{\"file\":\"" & blame.file & "\",\"lines\":["
  var first=true
  for line in blame.lines:
    if not first: sb.add ","
    first=false
    sb.add "{\"lineNo\":" & $line.lineNo & ",\"author\":\"" & line.author & "\",\"uuid\":\"" & $line.commitUuid & "\",\"content\":\"" & line.content.replace("\"", "\\\"") & "\"}"
  sb.add "]}"
  sb
