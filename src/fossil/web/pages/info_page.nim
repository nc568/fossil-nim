## Info page - port of info.c, event.c, finfo.c details

import ../../types
import ../../storage/sqlite_backend
import std/[strutils, times, tables, json]

type
  CheckinInfo* = object
    rid*: Rid
    uuid*: string
    mtime*: int64
    user*: string
    comment*: string
    branch*: string
    parentRids*: seq[Rid]
    childRids*: seq[Rid]
    files*: seq[tuple[name: string, rid: Rid, isNew: bool, isDeleted: bool]]
    tags*: seq[string]

proc getCheckinInfoSqlite*(backend: SqliteBackend, rid: Rid): FossilResult[CheckinInfo] =
  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_column_text(pStmt: ptr sqlite3_stmt, iCol: cint): cstring {.importc.}
  proc sqlite3_column_int64(pStmt: ptr sqlite3_stmt, iCol: cint): int64 {.importc.}
  proc sqlite3_bind_int64(pStmt: ptr sqlite3_stmt, i: cint, v: int64): cint {.importc.}
  proc sqlite3_bind_text(pStmt: ptr sqlite3_stmt, i: cint, zData: cstring, n: cint, xDel: pointer): cint {.importc.}
  {.pop.}
  const SQLITE_ROW = 100
  var info = CheckinInfo(rid: rid)

  # Get event info
  var stmt: ptr sqlite3_stmt
  let sqlEvent = "SELECT uuid, mtime, user, comment, branch FROM blob JOIN event ON blob.rid=event.objid WHERE blob.rid=?1 UNION SELECT uuid, mtime, user, comment, '' FROM blob WHERE rid=?1"
  if sqlite3_prepare_v2(backend.db, sqlEvent.cstring, -1, addr stmt, nil) == 0:
    discard sqlite3_bind_int64(stmt, 1, int64(rid))
    discard sqlite3_bind_int64(stmt, 2, int64(rid))
    if sqlite3_step(stmt) == SQLITE_ROW:
      let uuidPtr = sqlite3_column_text(stmt, 0)
      info.uuid = if uuidPtr!=nil: $uuidPtr else: ""
      info.mtime = sqlite3_column_int64(stmt, 1)
      let userPtr = sqlite3_column_text(stmt, 2)
      info.user = if userPtr!=nil: $userPtr else: ""
      let commentPtr = sqlite3_column_text(stmt, 3)
      info.comment = if commentPtr!=nil: $commentPtr else: ""
      let branchPtr = sqlite3_column_text(stmt, 4)
      info.branch = if branchPtr!=nil: $branchPtr else: "trunk"
    discard sqlite3_finalize(stmt)

  # Get parent via mlink? Actually parent is via plink table or manifest parsing. For MVP, use plink if exists
  let sqlParents = "SELECT pid FROM plink WHERE cid=?1 UNION SELECT pid FROM mlink WHERE fid=?1 LIMIT 5"
  if sqlite3_prepare_v2(backend.db, sqlParents.cstring, -1, addr stmt, nil) == 0:
    discard sqlite3_bind_int64(stmt, 1, int64(rid))
    while sqlite3_step(stmt) == SQLITE_ROW:
      let pid = sqlite3_column_int64(stmt, 0)
      info.parentRids.add Rid(pid)
    discard sqlite3_finalize(stmt)

  # Get files for this checkin via mlink
  let sqlFiles = "SELECT filename.name, mlink.fid, mlink.pid FROM mlink JOIN filename ON mlink.fnid=filename.fnid WHERE mlink.mid=?1 LIMIT 200"
  if sqlite3_prepare_v2(backend.db, sqlFiles.cstring, -1, addr stmt, nil) == 0:
    discard sqlite3_bind_int64(stmt, 1, int64(rid))
    while sqlite3_step(stmt) == SQLITE_ROW:
      let namePtr = sqlite3_column_text(stmt, 0)
      let fid = sqlite3_column_int64(stmt, 1)
      let pid = sqlite3_column_int64(stmt, 2)
      let name = if namePtr!=nil: $namePtr else: ""
      info.files.add (name: name, rid: Rid(fid), isNew: pid==0, isDeleted: fid==0)
    discard sqlite3_finalize(stmt)

  # Get tags
  let sqlTags = "SELECT tagname FROM tag JOIN tagxref ON tag.tagid=tagxref.tagid WHERE tagxref.rid=?1 AND tagxref.tagtype>0"
  if sqlite3_prepare_v2(backend.db, sqlTags.cstring, -1, addr stmt, nil) == 0:
    discard sqlite3_bind_int64(stmt, 1, int64(rid))
    while sqlite3_step(stmt) == SQLITE_ROW:
      let tagPtr = sqlite3_column_text(stmt, 0)
      if tagPtr!=nil:
        info.tags.add $tagPtr
    discard sqlite3_finalize(stmt)

  if info.uuid.len==0:
    # Try blob table directly via getBlobInfo
    let infoRes = backend.getBlobInfo(rid)
    if infoRes.isOk:
      info.uuid = $infoRes.value.uuid
    else:
      return err[CheckinInfo](feNotFound, "checkin not found", $int(rid))
  ok(info)

proc renderInfoPage*(info: CheckinInfo): string =
  var html = """<html><head><title>Check-in: """ & info.uuid[0..9] & """ - Fossil</title>
<style>
body{font-family:sans-serif;max-width:1100px;margin:20px auto;padding:0 20px;background:#f8f9fa}
h1{border-bottom:2px solid #343a40;padding-bottom:10px}
.card{background:white;border:1px solid #dee2e6;border-radius:6px;padding:20px;margin:15px 0}
.meta{display:grid;grid-template-columns:120px 1fr;gap:8px}
.meta dt{font-weight:bold;color:#495057}
.meta dd{margin:0}
.file-list{list-style:none;padding:0}
.file-list li{padding:6px 10px;margin:3px 0;background:#f8f9fa;border:1px solid #e9ecef;border-radius:4px;display:flex;justify-content:space-between}
.badge{display:inline-block;padding:2px 8px;border-radius:10px;font-size:12px;color:white}
.badge-new{background:#28a745}
.badge-del{background:#dc3545}
.badge-branch{background:#007bff}
a{color:#007bff;text-decoration:none}
a:hover{text-decoration:underline}
pre{background:#f8f9fa;padding:15px;border-radius:4px;overflow-x:auto;white-space:pre-wrap}
</style></head><body>"""
  html.add "<h1>🔍 Check-in [" & info.uuid[0..min(9,info.uuid.len-1)] & "]</h1>"
  html.add "<div class='card'><dl class='meta'>"
  html.add "<dt>UUID:</dt><dd><code>" & info.uuid & "</code></dd>"
  html.add "<dt>RID:</dt><dd>" & $int(info.rid) & "</dd>"
  html.add "<dt>Date:</dt><dd>" & fromUnix(info.mtime).format("yyyy-MM-dd HH:mm:ss") & "</dd>"
  html.add "<dt>User:</dt><dd>" & info.user & "</dd>"
  html.add "<dt>Branch:</dt><dd><span class='badge badge-branch'>" & info.branch & "</span></dd>"
  if info.tags.len>0:
    html.add "<dt>Tags:</dt><dd>" & info.tags.join(", ") & "</dd>"
  if info.parentRids.len>0:
    html.add "<dt>Parents:</dt><dd>"
    for p in info.parentRids:
      html.add "<a href='/info?rid=" & $int(p) & "'>" & $int(p) & "</a> "
    html.add "</dd>"
  html.add "</dl>"
  html.add "<h3>Comment</h3><pre>" & info.comment.replace("&","&amp;").replace("<","&lt;").replace(">","&gt;") & "</pre>"
  html.add "</div>"

  html.add "<div class='card'><h3>Files (" & $info.files.len & ")</h3><ul class='file-list'>"
  for f in info.files:
    var badge = ""
    if f.isNew: badge = "<span class='badge badge-new'>new</span>"
    elif f.isDeleted: badge = "<span class='badge badge-del'>deleted</span>"
    html.add "<li><span><a href='/file?name=" & f.name & "&rid=" & $int(f.rid) & "'>" & f.name & "</a> " & badge & "</span><span><a href='/file?name=" & f.name & "'>view</a> | <a href='/finfo?name=" & f.name & "'>history</a></span></li>"
  html.add "</ul></div>"

  html.add "<div class='card'><a href='/timeline'>← Timeline</a> | <a href='/diff?from=" & (if info.parentRids.len>0: $int(info.parentRids[0]) else: "0") & "&to=" & $int(info.rid) & "'>Diff</a> | <a href='/zip/" & info.uuid & ".zip'>ZIP</a></div>"
  html.add "</body></html>"
  html

proc renderInfoNotFound*(ridStr: string): string =
  "<html><body><h1>Not Found</h1><p>Check-in " & ridStr & " not found</p><a href='/timeline'>Timeline</a></body></html>"
