## Search subsystem - FTS5 based search for wiki, tickets, files

import ../types
import ../storage/backend
import ../storage/sqlite_backend
import std/[strutils, times, json]

type
  SearchResult* = object
    kind*: string # "wiki", "ticket", "file", "commit"
    id*: string
    title*: string
    snippet*: string
    rank*: float
    mtime*: int64

  SearchOptions* = object
    query*: string
    limit*: int
    offset*: int
    kinds*: seq[string] # filter by kinds

proc defaultSearchOptions*(query: string): SearchOptions =
  SearchOptions(query: query, limit: 20, offset: 0, kinds: @[])

proc initSearchIndexSqlite*(backend: var SqliteBackend): FossilResult[bool] =
  ## Create FTS5 virtual table for search
  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  {.pop.}
  let sqls = @[
    "CREATE TABLE IF NOT EXISTS search_meta(key TEXT PRIMARY KEY, value TEXT)",
    "CREATE VIRTUAL TABLE IF NOT EXISTS search_fts USING fts5(id, kind, title, content, tokenize='porter unicode61')",
    "CREATE TABLE IF NOT EXISTS search_index(id TEXT PRIMARY KEY, kind TEXT, title TEXT, content TEXT, mtime INTEGER)"
  ]
  for sql in sqls:
    var stmt: ptr sqlite3_stmt
    if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) == 0:
      discard sqlite3_step(stmt)
      discard sqlite3_finalize(stmt)
  ok(true)

proc indexDocumentSqlite*(backend: var SqliteBackend, kind: string, id: string, title: string, content: string, mtime: int64 = 0): FossilResult[bool] =
  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_bind_text(pStmt: ptr sqlite3_stmt, i: cint, zData: cstring, n: cint, xDel: pointer): cint {.importc.}
  proc sqlite3_bind_int64(pStmt: ptr sqlite3_stmt, i: cint, v: int64): cint {.importc.}
  {.pop.}
  let mt = if mtime==0: getTime().toUnix() else: mtime
  # Delete old FTS entry first (FTS5 has no UNIQUE on id column, so REPLACE doesn't dedup)
  var stmtDel: ptr sqlite3_stmt
  let sqlDelFts = "DELETE FROM search_fts WHERE id=?1"
  if sqlite3_prepare_v2(backend.db, sqlDelFts.cstring, -1, addr stmtDel, nil) == 0:
    discard sqlite3_bind_text(stmtDel, 1, id.cstring, -1, nil)
    discard sqlite3_step(stmtDel)
    discard sqlite3_finalize(stmtDel)
  # Insert or replace in search_index
  var stmt: ptr sqlite3_stmt
  let sqlIdx = "INSERT OR REPLACE INTO search_index(id, kind, title, content, mtime) VALUES(?1, ?2, ?3, ?4, ?5)"
  if sqlite3_prepare_v2(backend.db, sqlIdx.cstring, -1, addr stmt, nil) != 0:
    return err[bool](feIoError, "cannot prepare search_index insert")
  discard sqlite3_bind_text(stmt, 1, id.cstring, -1, nil)
  discard sqlite3_bind_text(stmt, 2, kind.cstring, -1, nil)
  discard sqlite3_bind_text(stmt, 3, title.cstring, -1, nil)
  discard sqlite3_bind_text(stmt, 4, content.cstring, -1, nil)
  discard sqlite3_bind_int64(stmt, 5, mt)
  discard sqlite3_step(stmt)
  discard sqlite3_finalize(stmt)

  # Insert into FTS
  let sqlFts = "INSERT OR REPLACE INTO search_fts(id, kind, title, content) VALUES(?1, ?2, ?3, ?4)"
  if sqlite3_prepare_v2(backend.db, sqlFts.cstring, -1, addr stmt, nil) != 0:
    return err[bool](feIoError, "cannot prepare fts insert")
  discard sqlite3_bind_text(stmt, 1, id.cstring, -1, nil)
  discard sqlite3_bind_text(stmt, 2, kind.cstring, -1, nil)
  discard sqlite3_bind_text(stmt, 3, title.cstring, -1, nil)
  discard sqlite3_bind_text(stmt, 4, content.cstring, -1, nil)
  discard sqlite3_step(stmt)
  discard sqlite3_finalize(stmt)
  ok(true)

proc searchSqlite*(backend: SqliteBackend, opts: SearchOptions): FossilResult[seq[SearchResult]] =
  if opts.query.len==0:
    return err[seq[SearchResult]](feInvalidArg, "empty query")
  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_bind_text(pStmt: ptr sqlite3_stmt, i: cint, zData: cstring, n: cint, xDel: pointer): cint {.importc.}
  proc sqlite3_bind_int(pStmt: ptr sqlite3_stmt, i: cint, v: cint): cint {.importc.}
  proc sqlite3_column_text(pStmt: ptr sqlite3_stmt, iCol: cint): cstring {.importc.}
  proc sqlite3_column_int64(pStmt: ptr sqlite3_stmt, iCol: cint): int64 {.importc.}
  proc sqlite3_column_double(pStmt: ptr sqlite3_stmt, iCol: cint): float64 {.importc.}
  {.pop.}
  const SQLITE_ROW = 100
  var results: seq[SearchResult] = @[]
  # Build query - use FTS5 MATCH with snippet and rank
  # SEC-07 fix: use bind for kinds, validate kinds are safe alphanumeric
  var safeKinds: seq[string] = @[]
  for k in opts.kinds:
    var ok = true
    for c in k:
      if c notin {'a'..'z', 'A'..'Z', '0'..'9', '-', '_'}:
        ok = false
        break
    if ok and k.len>0:
      safeKinds.add k
  var sql = "SELECT s.id, s.kind, s.title, snippet(search_fts, 2, '<b>', '</b>', '...', 20) as snippet, rank, i.mtime FROM search_fts s JOIN search_index i ON s.id=i.id WHERE search_fts MATCH ?1"
  if safeKinds.len>0:
    sql.add " AND s.kind IN ("
    for idx, _ in safeKinds:
      if idx>0: sql.add ","
      sql.add "?" & $(idx+2)
    sql.add ")"
  let limitIdx = safeKinds.len + 2
  let offsetIdx = safeKinds.len + 3
  sql.add " ORDER BY rank LIMIT ?" & $limitIdx & " OFFSET ?" & $offsetIdx
  var stmt: ptr sqlite3_stmt
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) != 0:
    # Fallback to LIKE search if FTS5 not available
    var fallbackResults: seq[SearchResult] = @[]
    let likeSql = "SELECT id, kind, title, substr(content,1,200) as snippet, 0 as rank, mtime FROM search_index WHERE title LIKE ?1 OR content LIKE ?1 LIMIT ?2 OFFSET ?3"
    var stmt2: ptr sqlite3_stmt
    if sqlite3_prepare_v2(backend.db, likeSql.cstring, -1, addr stmt2, nil) == 0:
      let pattern = "%" & opts.query & "%"
      discard sqlite3_bind_text(stmt2, 1, pattern.cstring, -1, nil)
      discard sqlite3_bind_int(stmt2, 2, cint(opts.limit))
      discard sqlite3_bind_int(stmt2, 3, cint(opts.offset))
      while sqlite3_step(stmt2) == SQLITE_ROW:
        let idPtr = sqlite3_column_text(stmt2, 0)
        let kindPtr = sqlite3_column_text(stmt2, 1)
        let titlePtr = sqlite3_column_text(stmt2, 2)
        let snippetPtr = sqlite3_column_text(stmt2, 3)
        let mtime = sqlite3_column_int64(stmt2, 5)
        let id = if idPtr!=nil: $idPtr else: ""
        let kind = if kindPtr!=nil: $kindPtr else: ""
        let title = if titlePtr!=nil: $titlePtr else: ""
        let snippet = if snippetPtr!=nil: $snippetPtr else: ""
        fallbackResults.add SearchResult(kind: kind, id: id, title: title, snippet: snippet, rank: 0.0, mtime: mtime)
      discard sqlite3_finalize(stmt2)
      return ok(fallbackResults)
    return err[seq[SearchResult]](feIoError, "cannot prepare search")

  discard sqlite3_bind_text(stmt, 1, opts.query.cstring, -1, nil)
  discard sqlite3_bind_int(stmt, 2, cint(opts.limit))
  discard sqlite3_bind_int(stmt, 3, cint(opts.offset))
  while sqlite3_step(stmt) == SQLITE_ROW:
    let idPtr = sqlite3_column_text(stmt, 0)
    let kindPtr = sqlite3_column_text(stmt, 1)
    let titlePtr = sqlite3_column_text(stmt, 2)
    let snippetPtr = sqlite3_column_text(stmt, 3)
    let rank = sqlite3_column_double(stmt, 4)
    let mtime = sqlite3_column_int64(stmt, 5)
    let id = if idPtr!=nil: $idPtr else: ""
    let kind = if kindPtr!=nil: $kindPtr else: ""
    let title = if titlePtr!=nil: $titlePtr else: ""
    let snippet = if snippetPtr!=nil: $snippetPtr else: ""
    results.add SearchResult(kind: kind, id: id, title: title, snippet: snippet, rank: rank, mtime: mtime)
  discard sqlite3_finalize(stmt)
  ok(results)

proc search*[T: StorageBackend](backend: T, opts: SearchOptions): FossilResult[seq[SearchResult]] =
  when T is SqliteBackend:
    searchSqlite(backend, opts)
  else:
    ok(newSeq[SearchResult]())

proc indexWikiPage*[T: StorageBackend](backend: var T, name: string, content: string): FossilResult[bool] =
  when T is SqliteBackend:
    indexDocumentSqlite(backend, "wiki", "wiki-" & name, name, content)
  else:
    ok(true)

proc indexTicket*[T: StorageBackend](backend: var T, id: string, title: string, content: string): FossilResult[bool] =
  when T is SqliteBackend:
    indexDocumentSqlite(backend, "ticket", id, title, content)
  else:
    ok(true)

proc indexFileContentsSqlite*(backend: var SqliteBackend, limit: int = 500): FossilResult[int] =
  ## Index file contents from mlink+filename+blob
  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_column_text(pStmt: ptr sqlite3_stmt, iCol: cint): cstring {.importc.}
  proc sqlite3_column_int64(pStmt: ptr sqlite3_stmt, iCol: cint): int64 {.importc.}
  proc sqlite3_bind_int(pStmt: ptr sqlite3_stmt, i: cint, v: cint): cint {.importc.}
  {.pop.}
  const SQLITE_ROW = 100
  var count = 0
  var stmt: ptr sqlite3_stmt
  # Get distinct latest files
  let sql = "SELECT filename.name, blob.rid, blob.size FROM filename JOIN mlink ON filename.fnid=mlink.fnid JOIN blob ON mlink.fid=blob.rid GROUP BY filename.name ORDER BY max(event.mtime) DESC LIMIT ?1"
  # Fallback simpler query if event join fails
  let sqlSimple = "SELECT filename.name, mlink.fid FROM filename JOIN mlink ON filename.fnid=mlink.fnid GROUP BY filename.name LIMIT ?1"
  var usedSql = sqlSimple
  # Try complex first, if fails use simple
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) == 0:
    usedSql = sql
    discard sqlite3_finalize(stmt)
  else:
    usedSql = sqlSimple

  if sqlite3_prepare_v2(backend.db, usedSql.cstring, -1, addr stmt, nil) != 0:
    return ok(0)
  discard sqlite3_bind_int(stmt, 1, cint(limit))
  var files: seq[tuple[name: string, rid: int64]] = @[]
  while sqlite3_step(stmt) == SQLITE_ROW:
    let namePtr = sqlite3_column_text(stmt, 0)
    let rid = sqlite3_column_int64(stmt, 1)
    if namePtr!=nil:
      files.add (name: $namePtr, rid: rid)
  discard sqlite3_finalize(stmt)

  for f in files:
    if f.name.len==0: continue
    # Skip binary files by extension
    let ext = f.name.split(".")[^1].toLowerAscii()
    if ext in ["png","jpg","jpeg","gif","bmp","ico","zip","gz","bz2","xz","pdf","exe","dll","so","o","a","bin"]:
      continue
    let blobRes = backend.getBlob(Rid(f.rid))
    if blobRes.isErr: continue
    let content = blobRes.value.data
    if content.len==0 or content.len>200000: continue # skip huge files
    if content.contains("\0"): continue # binary
    # Index first 50k chars
    let toIndex = if content.len>50000: content[0..49999] else: content
    let id = "file-" & f.name
    discard indexDocumentSqlite(backend, "file", id, f.name, toIndex)
    inc count
  ok(count)

proc indexCommitsSqlite*(backend: var SqliteBackend, limit: int = 1000): FossilResult[int] =
  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_column_text(pStmt: ptr sqlite3_stmt, iCol: cint): cstring {.importc.}
  proc sqlite3_column_int64(pStmt: ptr sqlite3_stmt, iCol: cint): int64 {.importc.}
  proc sqlite3_bind_int(pStmt: ptr sqlite3_stmt, i: cint, v: cint): cint {.importc.}
  {.pop.}
  const SQLITE_ROW = 100
  var count = 0
  var stmt: ptr sqlite3_stmt
  let sql = "SELECT blob.rid, blob.uuid, event.mtime, event.user, event.comment, event.branch FROM event JOIN blob ON event.objid=blob.rid ORDER BY event.mtime DESC LIMIT ?1"
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) != 0:
    return ok(0)
  discard sqlite3_bind_int(stmt, 1, cint(limit))
  while sqlite3_step(stmt) == SQLITE_ROW:
    let rid = sqlite3_column_int64(stmt, 0)
    let uuidPtr = sqlite3_column_text(stmt, 1)
    let mtime = sqlite3_column_int64(stmt, 2)
    let userPtr = sqlite3_column_text(stmt, 3)
    let commentPtr = sqlite3_column_text(stmt, 4)
    let branchPtr = sqlite3_column_text(stmt, 5)
    let uuid = if uuidPtr!=nil: $uuidPtr else: $rid
    let user = if userPtr!=nil: $userPtr else: ""
    let comment = if commentPtr!=nil: $commentPtr else: ""
    let branch = if branchPtr!=nil: $branchPtr else: "trunk"
    let content = branch & " " & user & " " & comment
    let title = "[" & branch & "] " & comment.splitLines()[0]
    discard indexDocumentSqlite(backend, "commit", "commit-" & uuid, title, content, mtime)
    inc count
  discard sqlite3_finalize(stmt)
  ok(count)

proc indexBranchesSqlite*(backend: var SqliteBackend): FossilResult[int] =
  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_column_text(pStmt: ptr sqlite3_stmt, iCol: cint): cstring {.importc.}
  {.pop.}
  const SQLITE_ROW = 100
  var count = 0
  var stmt: ptr sqlite3_stmt
  let sql = "SELECT name FROM tag WHERE substr(name,1,4)='sym-' ORDER BY name"
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) != 0:
    return ok(0)
  while sqlite3_step(stmt) == SQLITE_ROW:
    let namePtr = sqlite3_column_text(stmt, 0)
    if namePtr!=nil:
      let full = $namePtr
      let branchName = if full.startsWith("sym-"): full[4..^1] else: full
      discard indexDocumentSqlite(backend, "branch", "branch-" & branchName, branchName, "branch " & branchName)
      inc count
  discard sqlite3_finalize(stmt)
  ok(count)

proc reindexAllSqlite*(backend: var SqliteBackend, fileLimit: int = 500, commitLimit: int = 1000): FossilResult[int] =
  ## Reindex everything: files, commits, branches, plus existing wiki/ticket/forum stay
  discard initSearchIndexSqlite(backend)
  var total = 0
  let fc = indexFileContentsSqlite(backend, fileLimit)
  if fc.isOk: total += fc.value
  let cc = indexCommitsSqlite(backend, commitLimit)
  if cc.isOk: total += cc.value
  let bc = indexBranchesSqlite(backend)
  if bc.isOk: total += bc.value
  # Wiki
  block:
    {.push header: "<sqlite3.h>".}
    type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
    proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
    proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
    proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
    proc sqlite3_column_text(pStmt: ptr sqlite3_stmt, iCol: cint): cstring {.importc.}
    {.pop.}
    const SQLITE_ROW = 100
    var stmt: ptr sqlite3_stmt
    let sql = "SELECT tagname FROM tag WHERE tagname LIKE 'wiki-%'"
    if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) == 0:
      while sqlite3_step(stmt) == SQLITE_ROW:
        let tagPtr = sqlite3_column_text(stmt, 0)
        if tagPtr!=nil:
          let tag = $tagPtr
          let name = if tag.startsWith("wiki-"): tag[5..^1] else: tag
          # Get content via blob? For MVP, index tag name only
          discard indexDocumentSqlite(backend, "wiki", "wiki-" & name, name, name)
          inc total
      discard sqlite3_finalize(stmt)
  ok(total)

proc reindexAll*[T: StorageBackend](backend: var T, fileLimit: int = 500, commitLimit: int = 1000): FossilResult[int] =
  when T is SqliteBackend:
    reindexAllSqlite(backend, fileLimit, commitLimit)
  else:
    ok(0)

proc searchToJson*(results: seq[SearchResult]): JsonNode =
  var arr = newJArray()
  for r in results:
    var obj = newJObject()
    obj["kind"] = newJString(r.kind)
    obj["id"] = newJString(r.id)
    obj["title"] = newJString(r.title)
    obj["snippet"] = newJString(r.snippet)
    obj["rank"] = newJFloat(r.rank)
    obj["mtime"] = newJInt(r.mtime)
    arr.add obj
  arr
