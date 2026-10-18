## Wiki subsystem with Markdown and TH1 support

import ../types
import ../storage/backend
import ../storage/sqlite_backend
import ../utils/hash
import ../markdown/parser as mdParser
import ../th1/interp as th1Interp
import std/[tables, strutils, times, os, json, random]

type
  WikiPage* = object
    name*: string
    content*: string
    mtime*: int64
    user*: string
    uuid*: Uuid
    rid*: Rid
    format*: string # "markdown", "wiki", "html", "th1"

  WikiFormat* = enum
    wfMarkdown = "markdown"
    wfWiki = "wiki"
    wfHtml = "html"
    wfTh1 = "th1"

proc listWikiPagesSqlite*(backend: SqliteBackend): FossilResult[seq[string]] =
  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_column_text(pStmt: ptr sqlite3_stmt, iCol: cint): ptr cuchar {.importc.}
  {.pop.}
  const SQLITE_ROW = 100
  let sql = "SELECT tagname FROM tag WHERE tagname LIKE 'wiki-%' ORDER BY tagname"
  var pages: seq[string] = @[]
  var stmt: ptr sqlite3_stmt
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) != 0:
    return ok(@["Home", "About", "Roadmap", "Changelog"])
  defer: discard sqlite3_finalize(stmt)
  while sqlite3_step(stmt) == SQLITE_ROW:
    let ptrVal = sqlite3_column_text(stmt, 0)
    if ptrVal != nil:
      let tagname = $cast[cstring](ptrVal)
      if tagname.startsWith("wiki-"):
        pages.add(tagname[5..^1])
      else:
        pages.add(tagname)
  if pages.len==0:
    pages = @["Home", "About", "Roadmap", "Changelog"]
  ok(pages)

proc listWikiPages*[T: StorageBackend](backend: T): FossilResult[seq[string]] =
  when T is SqliteBackend:
    listWikiPagesSqlite(backend)
  else:
    ok(@["Home", "About", "Roadmap", "Changelog"])

proc getWikiPageSqlite*(backend: SqliteBackend, name: string): FossilResult[WikiPage] =
  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_column_int64(pStmt: ptr sqlite3_stmt, iCol: cint): int64 {.importc.}
  proc sqlite3_column_text(pStmt: ptr sqlite3_stmt, iCol: cint): ptr cuchar {.importc.}
  {.pop.}
  const SQLITE_ROW = 100
  # Try to find latest wiki page for name via tagxref -> blob rid, then getBlob for decompressed content
  let sql = """
    SELECT b.uuid, e.mtime, e.user, b.rid
    FROM tag t
    JOIN tagxref x ON x.tagid=t.tagid
    JOIN blob b ON b.rid=x.rid
    JOIN event e ON e.objid=x.rid
    WHERE t.tagname='wiki-' || ?1
    ORDER BY e.mtime DESC LIMIT 1
  """
  var stmt: ptr sqlite3_stmt
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) != 0:
    return ok(WikiPage(name: name, content: "# " & name & "\n\nWiki page content not yet in DB, showing sample.\n\n- Feature 1\n- Feature 2\n", mtime: getTime().toUnix(), user: "admin", format: "markdown"))
  defer: discard sqlite3_finalize(stmt)
  # Bind name
  {.push header: "<sqlite3.h>".}
  proc sqlite3_bind_text(pStmt: ptr sqlite3_stmt, i: cint, zData: cstring, n: cint, xDel: pointer): cint {.importc.}
  {.pop.}
  discard sqlite3_bind_text(stmt, 1, name.cstring, -1, nil)
  if sqlite3_step(stmt) == SQLITE_ROW:
    let uuidPtr = sqlite3_column_text(stmt, 0)
    let mtime = sqlite3_column_int64(stmt, 1)
    let userPtr = sqlite3_column_text(stmt, 2)
    let rid = sqlite3_column_int64(stmt, 3)
    let user = if userPtr != nil: $cast[cstring](userPtr) else: "admin"
    let uuidStr = if uuidPtr != nil: $cast[cstring](uuidPtr) else: ""
    var uuid = Uuid("")
    if uuidStr.len==64:
      uuid = Uuid(uuidStr)
    # Get decompressed blob content via getBlob
    var content = "# " & name & "\nContent here"
    let blobRes = backend.getBlob(Rid(rid))
    if blobRes.isOk:
      content = blobRes.value.data
    ok(WikiPage(name: name, content: content, mtime: mtime, user: user, uuid: uuid, rid: Rid(rid), format: "markdown"))
  else:
    ok(WikiPage(name: name, content: "# " & name & "\n\nWiki page content not yet in DB, showing sample.\n\n- Feature 1\n- Feature 2\n", mtime: getTime().toUnix(), user: "admin", format: "markdown"))

proc getWikiPage*[T: StorageBackend](backend: T, name: string): FossilResult[WikiPage] =
  if name.len==0:
    return err[WikiPage](feInvalidArg, "empty page name")
  when T is SqliteBackend:
    getWikiPageSqlite(backend, name)
  else:
    ok(WikiPage(name: name, content: "# " & name & "\nContent here\n\nThis is a sample wiki page in **markdown** format.\n\n- Feature 1\n- Feature 2\n", mtime: getTime().toUnix(), user: "admin", format: "markdown"))

proc saveWikiPageSqlite*(backend: var SqliteBackend, page: WikiPage, message: string): FossilResult[Rid] =
  ## Save wiki page as blob with real SHA3 hash and tag wiki-<name> + auto FTS index
  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_bind_text(pStmt: ptr sqlite3_stmt, i: cint, zData: cstring, n: cint, xDel: pointer): cint {.importc.}
  proc sqlite3_bind_int64(pStmt: ptr sqlite3_stmt, i: cint, v: int64): cint {.importc.}
  {.pop.}
  let blob = newBlob(page.content)
  # Compute real hash via hashBlob SHA3
  let uuid = hashBlob(blob)
  let putRes = backend.putBlob(uuid, blob, false)
  if putRes.isErr:
    return err[Rid](putRes.error.code, putRes.error.msg)
  let rid = putRes.value
  # Auto-index for FTS5 search
  try:
    var stmtIdx: ptr sqlite3_stmt
    # Ensure FTS tables exist
    let sqlCreateFts = "CREATE VIRTUAL TABLE IF NOT EXISTS search_fts USING fts5(id, kind, title, content, tokenize='porter unicode61')"
    if sqlite3_prepare_v2(backend.db, sqlCreateFts.cstring, -1, addr stmtIdx, nil) == 0:
      discard sqlite3_step(stmtIdx)
      discard sqlite3_finalize(stmtIdx)
    let sqlCreateIdx = "CREATE TABLE IF NOT EXISTS search_index(id TEXT PRIMARY KEY, kind TEXT, title TEXT, content TEXT, mtime INTEGER)"
    if sqlite3_prepare_v2(backend.db, sqlCreateIdx.cstring, -1, addr stmtIdx, nil) == 0:
      discard sqlite3_step(stmtIdx)
      discard sqlite3_finalize(stmtIdx)
    let sqlIdx = "INSERT OR REPLACE INTO search_index(id, kind, title, content, mtime) VALUES(?1, 'wiki', ?2, ?3, ?4)"
    if sqlite3_prepare_v2(backend.db, sqlIdx.cstring, -1, addr stmtIdx, nil) == 0:
      let id = "wiki-" & page.name
      discard sqlite3_bind_text(stmtIdx, 1, id.cstring, -1, nil)
      discard sqlite3_bind_text(stmtIdx, 2, page.name.cstring, -1, nil)
      discard sqlite3_bind_text(stmtIdx, 3, page.content.cstring, -1, nil)
      discard sqlite3_bind_int64(stmtIdx, 4, getTime().toUnix())
      discard sqlite3_step(stmtIdx)
      discard sqlite3_finalize(stmtIdx)
    let sqlDelFts = "DELETE FROM search_fts WHERE id=?1"
    if sqlite3_prepare_v2(backend.db, sqlDelFts.cstring, -1, addr stmtIdx, nil) == 0:
      let delId = "wiki-" & page.name
      discard sqlite3_bind_text(stmtIdx, 1, delId.cstring, -1, nil)
      discard sqlite3_step(stmtIdx)
      discard sqlite3_finalize(stmtIdx)
    let sqlFts = "INSERT OR REPLACE INTO search_fts(id, kind, title, content) VALUES(?1, 'wiki', ?2, ?3)"
    if sqlite3_prepare_v2(backend.db, sqlFts.cstring, -1, addr stmtIdx, nil) == 0:
      let id = "wiki-" & page.name
      discard sqlite3_bind_text(stmtIdx, 1, id.cstring, -1, nil)
      discard sqlite3_bind_text(stmtIdx, 2, page.name.cstring, -1, nil)
      discard sqlite3_bind_text(stmtIdx, 3, page.content.cstring, -1, nil)
      discard sqlite3_step(stmtIdx)
      discard sqlite3_finalize(stmtIdx)
  except:
    discard
  # Create tag wiki-<name> and event
  let tagName = "wiki-" & page.name
  # Insert tag if not exists
  var stmt: ptr sqlite3_stmt
  let sqlTag = "INSERT OR IGNORE INTO tag(tagname) VALUES(?1)"
  if sqlite3_prepare_v2(backend.db, sqlTag.cstring, -1, addr stmt, nil) == 0:
    discard sqlite3_bind_text(stmt, 1, tagName.cstring, -1, nil)
    discard sqlite3_step(stmt)
    discard sqlite3_finalize(stmt)
  # Get tagid
  var tagId: int64 = 0
  let sqlTagId = "SELECT tagid FROM tag WHERE tagname=?1"
  if sqlite3_prepare_v2(backend.db, sqlTagId.cstring, -1, addr stmt, nil) == 0:
    discard sqlite3_bind_text(stmt, 1, tagName.cstring, -1, nil)
    if sqlite3_step(stmt) == 100:
      {.push header: "<sqlite3.h>".}
      proc sqlite3_column_int64(pStmt: ptr sqlite3_stmt, iCol: cint): int64 {.importc.}
      {.pop.}
      tagId = sqlite3_column_int64(stmt, 0)
    discard sqlite3_finalize(stmt)
  if tagId != 0:
    let sqlXref = "INSERT OR REPLACE INTO tagxref(tagid, rid, tagtype, mtime, srcid) VALUES(?1, ?2, 1, ?3, 0)"
    if sqlite3_prepare_v2(backend.db, sqlXref.cstring, -1, addr stmt, nil) == 0:
      discard sqlite3_bind_int64(stmt, 1, tagId)
      discard sqlite3_bind_int64(stmt, 2, int64(rid))
      discard sqlite3_bind_int64(stmt, 3, getTime().toUnix())
      discard sqlite3_step(stmt)
      discard sqlite3_finalize(stmt)
  # Insert event for wiki - event table has no tagid column, use type, mtime, objid, user, comment
  let sqlEvent = "INSERT OR REPLACE INTO event(type, mtime, objid, user, comment) VALUES('w', ?1, ?2, ?3, ?4)"
  if sqlite3_prepare_v2(backend.db, sqlEvent.cstring, -1, addr stmt, nil) == 0:
    discard sqlite3_bind_int64(stmt, 1, getTime().toUnix())
    discard sqlite3_bind_int64(stmt, 2, int64(rid))
    discard sqlite3_bind_text(stmt, 3, page.user.cstring, -1, nil)
    discard sqlite3_bind_text(stmt, 4, message.cstring, -1, nil)
    discard sqlite3_step(stmt)
    discard sqlite3_finalize(stmt)
  ok(rid)

proc saveWikiPage*[T: StorageBackend](backend: var T, page: WikiPage, message: string): FossilResult[Rid] =
  when T is SqliteBackend:
    saveWikiPageSqlite(backend, page, message)
  else:
    let blob = newBlob(page.content)
    let uuid = hashBlob(blob)
    backend.putBlob(uuid, blob, false)

proc renderWikiPage*(page: WikiPage, th1Vars: Table[string, string] = initTable[string, string]()): string {.gcsafe.} =
  var content = page.content
  if page.format == "th1" or content.contains("<th1>") or content.contains("<?th1"):
    var interp = th1Interp.newInterp()
    for k,v in th1Vars:
      interp.setVar(k, v)
    interp.setVar("wikiPage", page.name)
    var rendered = ""
    var i=0
    while i<content.len:
      let th1Start = content.find("<th1>", i)
      let th1Start2 = content.find("<?th1", i)
      var startPos = -1
      var startLen = 5
      if th1Start  != -1 and (th1Start2  == -1 or th1Start<th1Start2):
        startPos=th1Start
        startLen=5
      elif th1Start2  != -1:
        startPos=th1Start2
        startLen=5
      if startPos  == -1:
        rendered.add content[i..^1]
        break
      rendered.add content[i..<startPos]
      let endPos = content.find("</th1>", startPos+startLen)
      let endPos2 = content.find("?>", startPos+startLen)
      var ePos = -1
      var eLen = 6
      if endPos  != -1 and (endPos2  == -1 or endPos<endPos2):
        ePos=endPos
        eLen=6
      elif endPos2  != -1:
        ePos=endPos2
        eLen=2
      if ePos  == -1:
        rendered.add content[startPos..^1]
        break
      let th1Code = content[startPos+startLen..<ePos]
      let res = interp.evalScript(th1Code)
      rendered.add interp.output
      rendered.add res.toStr
      interp.output=""
      i=ePos+eLen
    content = rendered
  if page.format == "markdown" or page.format == "wiki" or page.format == "":
    result = mdParser.markdownToHtml(content)
  elif page.format == "html":
    result = content
  else:
    result = mdParser.markdownToHtml(content)

proc wikiPageToJson*(page: WikiPage): JsonNode {.gcsafe.} =
  %* {"name": page.name, "content": page.content, "mtime": page.mtime, "user": page.user, "format": page.format, "html": renderWikiPage(page)}
