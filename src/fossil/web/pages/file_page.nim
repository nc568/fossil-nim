## File browser page - port of file.c, doc.c, finfo.c

import ../../types
import ../../storage/sqlite_backend
import std/[strutils, tables, sequtils, times, os]

proc htmlEscape(s: string): string =
  result = s
  result = result.replace("&", "&amp;")
  result = result.replace("<", "&lt;")
  result = result.replace(">", "&gt;")
  result = result.replace("\"", "&quot;")
  result = result.replace("'", "&#39;")

type
  FileInfo* = object
    name*: string
    rid*: Rid
    uuid*: string
    mtime*: int64
    user*: string
    comment*: string
    size*: int
    isBinary*: bool

proc getFileHistorySqlite*(backend: SqliteBackend, filename: string, limit: int = 20): FossilResult[seq[FileInfo]] =
  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_column_text(pStmt: ptr sqlite3_stmt, iCol: cint): cstring {.importc.}
  proc sqlite3_column_int64(pStmt: ptr sqlite3_stmt, iCol: cint): int64 {.importc.}
  proc sqlite3_bind_text(pStmt: ptr sqlite3_stmt, i: cint, zData: cstring, n: cint, xDel: pointer): cint {.importc.}
  proc sqlite3_bind_int(pStmt: ptr sqlite3_stmt, i: cint, v: cint): cint {.importc.}
  {.pop.}
  const SQLITE_ROW = 100
  var history: seq[FileInfo] = @[]
  let sql = """
    SELECT filename.name, mlink.pid, mlink.fid, event.mtime, event.user, event.comment, blob.size
    FROM mlink
    JOIN filename ON mlink.fnid = filename.fnid
    JOIN event ON mlink.mid = event.objid
    JOIN blob ON mlink.fid = blob.rid
    WHERE filename.name = ?1
    ORDER BY event.mtime DESC LIMIT ?2
  """
  var stmt: ptr sqlite3_stmt
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) != 0:
    return ok(history)
  discard sqlite3_bind_text(stmt, 1, filename.cstring, -1, nil)
  discard sqlite3_bind_int(stmt, 2, cint(limit))
  while sqlite3_step(stmt) == SQLITE_ROW:
    let namePtr = sqlite3_column_text(stmt, 0)
    let fid = sqlite3_column_int64(stmt, 2)
    let mtime = sqlite3_column_int64(stmt, 3)
    let userPtr = sqlite3_column_text(stmt, 4)
    let commentPtr = sqlite3_column_text(stmt, 5)
    let size = sqlite3_column_int64(stmt, 6)
    let name = if namePtr!=nil: $namePtr else: filename
    let user = if userPtr!=nil: $userPtr else: ""
    let comment = if commentPtr!=nil: $commentPtr else: ""
    history.add FileInfo(name: name, rid: Rid(fid), mtime: mtime, user: user, comment: comment, size: int(size))
  discard sqlite3_finalize(stmt)
  ok(history)

proc listFilesSqlite*(backend: SqliteBackend, pattern: string = "", limit: int = 100): FossilResult[seq[string]] =
  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_column_text(pStmt: ptr sqlite3_stmt, iCol: cint): cstring {.importc.}
  proc sqlite3_bind_text(pStmt: ptr sqlite3_stmt, i: cint, zData: cstring, n: cint, xDel: pointer): cint {.importc.}
  proc sqlite3_bind_int(pStmt: ptr sqlite3_stmt, i: cint, v: cint): cint {.importc.}
  {.pop.}
  const SQLITE_ROW = 100
  var files: seq[string] = @[]
  var sql = "SELECT name FROM filename ORDER BY name LIMIT ?1"
  if pattern.len>0:
    sql = "SELECT name FROM filename WHERE name LIKE ?1 ORDER BY name LIMIT ?2"
  var stmt: ptr sqlite3_stmt
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) != 0:
    return ok(files)
  if pattern.len>0:
    discard sqlite3_bind_text(stmt, 1, ("%" & pattern & "%").cstring, -1, nil)
    discard sqlite3_bind_int(stmt, 2, cint(limit))
  else:
    discard sqlite3_bind_int(stmt, 1, cint(limit))
  while sqlite3_step(stmt) == SQLITE_ROW:
    let namePtr = sqlite3_column_text(stmt, 0)
    if namePtr!=nil:
      files.add $namePtr
  discard sqlite3_finalize(stmt)
  ok(files)

proc getFileContentSqlite*(backend: SqliteBackend, filename: string, rid: Rid = Rid(0)): FossilResult[string] =
  if filename.len==0:
    return err[string](feInvalidArg, "filename required")
  var targetRid = rid
  if int(targetRid)==0:
    let histRes = getFileHistorySqlite(backend, filename, 1)
    if histRes.isErr or histRes.value.len==0:
      return err[string](feNotFound, "file not found", filename)
    targetRid = histRes.value[0].rid
  let blobRes = backend.getBlob(targetRid)
  if blobRes.isErr:
    return err[string](blobRes.error.code, blobRes.error.msg)
  ok(blobRes.value.data)

proc renderFileListPage*(files: seq[string], pattern: string = ""): string =
  var html = """<html><head><title>Files - Fossil</title>
<style>
body{font-family:sans-serif;max-width:1000px;margin:40px auto;padding:0 20px;background:#f8f9fa}
h1{border-bottom:2px solid #343a40;padding-bottom:10px}
.file-list{list-style:none;padding:0}
.file-list li{padding:8px 12px;margin:4px 0;background:white;border:1px solid #dee2e6;border-radius:4px;display:flex;justify-content:space-between}
.file-list li:hover{background:#e9ecef}
a{color:#007bff;text-decoration:none}
a:hover{text-decoration:underline}
.search-box{margin:20px 0;padding:10px;width:300px;border:1px solid #ced4da;border-radius:4px}
</style></head><body>"""
  html.add "<h1>📁 File Browser</h1>"
  html.add "<form method='get' action='/file'><input class='search-box' name='pattern' placeholder='Search files...' value='" & pattern & "'><button type='submit'>Search</button></form>"
  html.add "<ul class='file-list'>"
  for f in files:
    let esc = f.replace("&","&amp;").replace("<","&lt;").replace(">","&gt;")
    html.add "<li><a href='/file?name=" & f & "'>" & esc & "</a><span><a href='/finfo?name=" & f & "'>history</a> | <a href='/blame?name=" & f & "'>blame</a></span></li>"
  html.add "</ul>"
  html.add "<hr><a href='/'>Home</a> | <a href='/timeline'>Timeline</a>"
  html.add "</body></html>"
  html

proc renderFileContentPage*(filename: string, content: string, history: seq[FileInfo]): string =
  let lineCount = content.splitLines().len
  var html = """<html><head><meta charset="UTF-8"><title>File: """ & filename & """ - Fossil</title>
<style>
body{font-family:-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,sans-serif;max-width:1400px;margin:0 auto;padding:20px;background:#f8f9fa;color:#212529}
h1{border-bottom:2px solid #0d6efd;padding-bottom:10px;word-break:break-all;font-size:22px}
.meta{background:#fff;padding:14px 16px;border:1px solid #dee2e6;border-radius:8px;margin:12px 0;display:flex;gap:12px;flex-wrap:wrap;align-items:center;box-shadow:0 1px 3px rgba(0,0,0,0.06)}
.content{background:#fff;border:1px solid #dee2e6;border-radius:8px;overflow:hidden;box-shadow:0 1px 3px rgba(0,0,0,0.06)}
.code-container{display:flex;overflow-x:auto}
.line-numbers{background:#f8f9fa;border-right:1px solid #dee2e6;padding:12px 8px;text-align:right;color:#6c757d;font-family:monospace;font-size:13px;line-height:1.5;user-select:none;min-width:50px}
.code{padding:12px 16px;font-family:monospace;font-size:13px;line-height:1.5;white-space:pre;flex:1;overflow-x:auto}
.code-line{display:block}
.code-line:hover{background:#fff3cd}
.history{margin-top:24px}
.history table{width:100%;border-collapse:collapse;background:#fff;border-radius:8px;overflow:hidden;box-shadow:0 1px 3px rgba(0,0,0,0.06)}
.history th,.history td{padding:10px 12px;border-bottom:1px solid #eee;text-align:left;font-size:13px}
.history th{background:#343a40;color:#fff;font-weight:600}
.history tr:hover{background:#f8f9fa}
.btn{padding:6px 12px;border-radius:6px;border:1px solid #ced4da;background:#fff;cursor:pointer;text-decoration:none;font-size:12px;display:inline-block}
.btn-primary{background:#0d6efd;color:#fff;border-color:#0d6efd}
.btn:hover{opacity:0.9}
a{color:#0d6efd;text-decoration:none}
a:hover{text-decoration:underline}
.toolbar{display:flex;gap:8px;flex-wrap:wrap}
</style></head><body>"""
  html.add "<h1>📄 " & filename & " <small style='color:#6c757d;font-size:14px'>" & $content.len & " bytes • " & $lineCount & " lines</small></h1>"
  html.add "<div class='meta'><a href='/file' class='btn'>← File list</a><a href='/finfo?name=" & filename & "' class='btn'>📜 History</a><a href='/blame?name=" & filename & "' class='btn'>👤 Blame</a><a href='/diff?name=" & filename & "' class='btn'>🔍 Diff</a><a href='/raw?name=" & filename & "' class='btn'>⬇️ Raw</a><span style='margin-left:auto'><button class='btn' onclick='toggleWrap()'>↔️ Wrap</button><button class='btn' onclick='toggleLineNos()'>#️⃣ Lines</button></span></div>"
  let isBinary = content.contains("\0")
  if isBinary:
    html.add "<div class='content' style='padding:20px'><em>Binary file, size: " & $content.len & " bytes</em> <a href='/raw?name=" & filename & "' class='btn btn-primary'>Download Raw</a></div>"
  else:
    # Build line numbers and code with spans
    var lines = content.splitLines()
    var lineNosHtml = ""
    var codeHtml = ""
    for i, line in lines:
      let esc = line.replace("&","&amp;").replace("<","&lt;").replace(">","&gt;")
      lineNosHtml.add($(i+1) & "\n")
      codeHtml.add("<span class='code-line' id='L" & $(i+1) & "'>" & (if esc.len==0: " " else: esc) & "</span>\n")
    html.add "<div class='content'><div class='code-container'><div class='line-numbers' id='lineNos'>" & lineNosHtml & "</div><div class='code' id='codeBlock'>" & codeHtml & "</div></div></div>"
    html.add "<script>let wrap=false, showNos=true; function toggleWrap(){wrap=!wrap; document.getElementById('codeBlock').style.whiteSpace=wrap?'pre-wrap':'pre';} function toggleLineNos(){showNos=!showNos; document.getElementById('lineNos').style.display=showNos?'block':'none';} document.querySelectorAll('.code-line').forEach(el=>{el.addEventListener('click', ()=>{const n=el.id.substring(1); history.replaceState(null,'','#L'+n); navigator.clipboard.writeText(window.location.href);});}); if(window.location.hash){const el=document.querySelector(window.location.hash); if(el){el.style.background='#fff3cd'; el.scrollIntoView();}}</script>"
  if history.len>0:
    html.add "<div class='history'><h2>📜 Recent History (" & $history.len & ")</h2><table><tr><th>Date</th><th>User</th><th>Comment</th><th>Size</th><th>Actions</th></tr>"
    for h in history:
      let date = fromUnix(h.mtime).format("yyyy-MM-dd HH:mm")
      html.add "<tr><td>" & htmlEscape(date) & "</td><td>" & htmlEscape(h.user) & "</td><td>" & htmlEscape(h.comment) & "</td><td>" & $h.size & "</td><td><a href='/file?name=" & htmlEscape(filename) & "&rid=" & $int(h.rid) & "' class='btn'>View</a> <a href='/diff?name=" & htmlEscape(filename) & "&from=" & $int(h.rid) & "' class='btn'>Diff</a></td></tr>"
    html.add "</table></div>"
  html.add "</body></html>"
  html

proc renderFinfoPage*(filename: string, history: seq[FileInfo]): string =
  var html = """<html><head><title>History: """ & filename & """ - Fossil</title>
<style>
body{font-family:sans-serif;max-width:1000px;margin:20px auto;padding:0 20px;background:#f8f9fa}
h1{border-bottom:2px solid #343a40;padding-bottom:10px}
table{width:100%;border-collapse:collapse;background:white;margin:20px 0}
th,td{padding:10px 12px;border:1px solid #dee2e6;text-align:left}
th{background:#343a40;color:white}
tr:hover{background:#f1f3f5}
a{color:#007bff;text-decoration:none}
a:hover{text-decoration:underline}
</style></head><body>"""
  html.add "<h1>📜 History of " & filename & "</h1>"
  html.add "<a href='/file?name=" & filename & "'>View file</a> | <a href='/file'>File list</a>"
  html.add "<table><tr><th>Date</th><th>User</th><th>Comment</th><th>RID</th><th>Size</th><th>Actions</th></tr>"
  for h in history:
    let date = fromUnix(h.mtime).format("yyyy-MM-dd HH:mm:ss")
    html.add "<tr><td>" & htmlEscape(date) & "</td><td>" & htmlEscape(h.user) & "</td><td>" & htmlEscape(h.comment) & "</td><td>" & $int(h.rid) & "</td><td>" & $h.size & "</td><td><a href='/file?name=" & htmlEscape(filename) & "&rid=" & $int(h.rid) & "'>view</a> | <a href='/diff?from=" & $int(h.rid) & "'>diff</a></td></tr>"
  html.add "</table></body></html>"
  html
