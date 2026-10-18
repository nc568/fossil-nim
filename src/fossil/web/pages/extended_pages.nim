## Extended web pages - remaining Fossil parity
## Implements: /stat, /reportlist, /report, /attach, /attachlist, /rss, /timeline.rss, /wcontent, /whistory, /leaves, /tinfo

import ../../types
import ../../storage/sqlite_backend
import std/[strutils, tables, sequtils, times, os, json]

proc htmlEscape*(s: string): string =
  result = s
  result = result.replace("&", "&amp;")
  result = result.replace("<", "&lt;")
  result = result.replace(">", "&gt;")
  result = result.replace("\"", "&quot;")
  result = result.replace("'", "&#39;")

type
  RepoStats* = object
    totalCommits*: int
    totalFiles*: int
    totalWiki*: int
    totalTickets*: int
    totalForumThreads*: int
    totalForumPosts*: int
    totalChatMessages*: int
    totalBranches*: int
    totalTags*: int
    totalArtifacts*: int
    repoSize*: int64
    firstCommit*: int64
    lastCommit*: int64

proc getRepoStatsSqlite*(backend: SqliteBackend): RepoStats =
  result = RepoStats()
  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_column_int64(pStmt: ptr sqlite3_stmt, iCol: cint): int64 {.importc.}
  proc sqlite3_column_text(pStmt: ptr sqlite3_stmt, iCol: cint): cstring {.importc.}
  {.pop.}
  const SQLITE_ROW = 100
  var stmt: ptr sqlite3_stmt

  # Commits
  var sql = "SELECT COUNT(*), MIN(mtime), MAX(mtime) FROM event WHERE type='ci'"
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) == 0:
    if sqlite3_step(stmt) == SQLITE_ROW:
      result.totalCommits = int(sqlite3_column_int64(stmt, 0))
      result.firstCommit = sqlite3_column_int64(stmt, 1)
      result.lastCommit = sqlite3_column_int64(stmt, 2)
    discard sqlite3_finalize(stmt)

  # Files
  sql = "SELECT COUNT(*) FROM filename"
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) == 0:
    if sqlite3_step(stmt) == SQLITE_ROW:
      result.totalFiles = int(sqlite3_column_int64(stmt, 0))
    discard sqlite3_finalize(stmt)

  # Wiki
  sql = "SELECT COUNT(*) FROM tag WHERE tagname LIKE 'wiki-%'"
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) == 0:
    if sqlite3_step(stmt) == SQLITE_ROW:
      result.totalWiki = int(sqlite3_column_int64(stmt, 0))
    discard sqlite3_finalize(stmt)

  # Tickets
  sql = "SELECT COUNT(*) FROM ticket"
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) == 0:
    if sqlite3_step(stmt) == SQLITE_ROW:
      result.totalTickets = int(sqlite3_column_int64(stmt, 0))
    discard sqlite3_finalize(stmt)

  # Forum threads
  sql = "SELECT COUNT(*) FROM forum_thread"
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) == 0:
    if sqlite3_step(stmt) == SQLITE_ROW:
      result.totalForumThreads = int(sqlite3_column_int64(stmt, 0))
    discard sqlite3_finalize(stmt)

  # Forum posts
  sql = "SELECT COUNT(*) FROM forum_post"
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) == 0:
    if sqlite3_step(stmt) == SQLITE_ROW:
      result.totalForumPosts = int(sqlite3_column_int64(stmt, 0))
    discard sqlite3_finalize(stmt)

  # Chat
  sql = "SELECT COUNT(*) FROM chat_message"
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) == 0:
    if sqlite3_step(stmt) == SQLITE_ROW:
      result.totalChatMessages = int(sqlite3_column_int64(stmt, 0))
    discard sqlite3_finalize(stmt)

  # Branches
  sql = "SELECT COUNT(*) FROM tag WHERE tagname LIKE 'sym-%'"
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) == 0:
    if sqlite3_step(stmt) == SQLITE_ROW:
      result.totalBranches = int(sqlite3_column_int64(stmt, 0))
    discard sqlite3_finalize(stmt)

  # Tags
  sql = "SELECT COUNT(*) FROM tag"
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) == 0:
    if sqlite3_step(stmt) == SQLITE_ROW:
      result.totalTags = int(sqlite3_column_int64(stmt, 0))
    discard sqlite3_finalize(stmt)

  # Artifacts
  sql = "SELECT COUNT(*), SUM(size) FROM blob"
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) == 0:
    if sqlite3_step(stmt) == SQLITE_ROW:
      result.totalArtifacts = int(sqlite3_column_int64(stmt, 0))
      result.repoSize = sqlite3_column_int64(stmt, 1)
    discard sqlite3_finalize(stmt)

proc renderStatPage*(stats: RepoStats): string =
  let firstDate = if stats.firstCommit>0: fromUnix(stats.firstCommit).format("yyyy-MM-dd HH:mm") else: "N/A"
  let lastDate = if stats.lastCommit>0: fromUnix(stats.lastCommit).format("yyyy-MM-dd HH:mm") else: "N/A"
  let sizeMb = stats.repoSize div (1024*1024)
  result = """
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Statistics - Fossil-Nim</title>
<style>
body{font-family:-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,sans-serif;background:#f8f9fa;margin:0;padding:0}
.navbar{background:#343a40;color:#fff;padding:10px 20px;display:flex;gap:15px}
.navbar a{color:#fff;text-decoration:none}
.navbar a:hover{text-decoration:underline}
.container{max-width:1000px;margin:20px auto;padding:0 20px}
.card{background:#fff;border:1px solid #dee2e6;border-radius:6px;padding:20px;margin-bottom:20px}
.stat-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:15px}
.stat-item{background:#f8f9fa;border:1px solid #e9ecef;border-radius:6px;padding:15px;text-align:center}
.stat-number{font-size:2em;font-weight:bold;color:#0d6efd}
.stat-label{color:#6c757d;margin-top:5px}
h1{color:#343a40}
h2{color:#495057;border-bottom:2px solid #0d6efd;padding-bottom:5px}
</style></head><body>
<div class="navbar"><a href="/">Home</a><a href="/timeline">Timeline</a><a href="/file">Files</a><a href="/brlist">Branches</a><a href="/stat">Stat</a><a href="/help">Help</a></div>
<div class="container">
<h1>📊 Repository Statistics</h1>
<div class="card">
<h2>Overview</h2>
<div class="stat-grid">
<div class="stat-item"><div class="stat-number">""" & $stats.totalCommits & """</div><div class="stat-label">Commits</div></div>
<div class="stat-item"><div class="stat-number">""" & $stats.totalFiles & """</div><div class="stat-label">Files</div></div>
<div class="stat-item"><div class="stat-number">""" & $stats.totalBranches & """</div><div class="stat-label">Branches</div></div>
<div class="stat-item"><div class="stat-number">""" & $stats.totalTags & """</div><div class="stat-label">Tags</div></div>
<div class="stat-item"><div class="stat-number">""" & $stats.totalWiki & """</div><div class="stat-label">Wiki Pages</div></div>
<div class="stat-item"><div class="stat-number">""" & $stats.totalTickets & """</div><div class="stat-label">Tickets</div></div>
<div class="stat-item"><div class="stat-number">""" & $stats.totalForumThreads & """</div><div class="stat-label">Forum Threads</div></div>
<div class="stat-item"><div class="stat-number">""" & $stats.totalForumPosts & """</div><div class="stat-label">Forum Posts</div></div>
<div class="stat-item"><div class="stat-number">""" & $stats.totalChatMessages & """</div><div class="stat-label">Chat Messages</div></div>
<div class="stat-item"><div class="stat-number">""" & $stats.totalArtifacts & """</div><div class="stat-label">Artifacts</div></div>
</div>
</div>
<div class="card">
<h2>Details</h2>
<table style="width:100%;border-collapse:collapse">
<tr><td style="padding:8px;border-bottom:1px solid #eee"><b>First Commit</b></td><td style="padding:8px;border-bottom:1px solid #eee">""" & firstDate & """</td></tr>
<tr><td style="padding:8px;border-bottom:1px solid #eee"><b>Last Commit</b></td><td style="padding:8px;border-bottom:1px solid #eee">""" & lastDate & """</td></tr>
<tr><td style="padding:8px;border-bottom:1px solid #eee"><b>Repository Size</b></td><td style="padding:8px;border-bottom:1px solid #eee">""" & $stats.repoSize & """ bytes (~""" & $sizeMb & """ MB)</td></tr>
<tr><td style="padding:8px;border-bottom:1px solid #eee"><b>Storage Backend</b></td><td style="padding:8px;border-bottom:1px solid #eee">SQLite (with FTS5)</td></tr>
<tr><td style="padding:8px"><b>Version</b></td><td style="padding:8px">Fossil-Nim 2.26.0-nim</td></tr>
</table>
</div>
<div class="card">
<h2>Quick Links</h2>
<ul>
<li><a href="/timeline">Timeline</a> - """ & $stats.totalCommits & """ commits from """ & firstDate & """ to """ & lastDate & """</li>
<li><a href="/file">Files</a> - """ & $stats.totalFiles & """ tracked files</li>
<li><a href="/brlist">Branches</a> - """ & $stats.totalBranches & """ branches</li>
<li><a href="/wiki/list">Wiki</a> - """ & $stats.totalWiki & """ pages</li>
<li><a href="/ticket/list">Tickets</a> - """ & $stats.totalTickets & """ tickets</li>
<li><a href="/forum/list">Forum</a> - """ & $stats.totalForumThreads & """ threads</li>
<li><a href="/chat">Chat</a> - """ & $stats.totalChatMessages & """ messages</li>
<li><a href="/search">Search</a> - FTS5 full-text search</li>
</ul>
</div>
</div></body></html>"""

proc renderReportlistPage*(reports: seq[tuple[id: int, name: string, title: string, count: int]]): string =
  result = """
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Reports - Fossil-Nim</title>
<style>
body{font-family:sans-serif;background:#f8f9fa;margin:0;padding:0}
.navbar{background:#343a40;color:#fff;padding:10px 20px;display:flex;gap:15px}
.navbar a{color:#fff;text-decoration:none}
.container{max-width:1000px;margin:20px auto;padding:0 20px}
.card{background:#fff;border:1px solid #dee2e6;border-radius:6px;padding:20px}
.report-table{width:100%;border-collapse:collapse}
.report-table th{background:#e9ecef;padding:10px;text-align:left}
.report-table td{padding:10px;border-top:1px solid #eee}
.badge{background:#0d6efd;color:#fff;padding:2px 6px;border-radius:10px;font-size:0.8em}
</style></head><body>
<div class="navbar"><a href="/">Home</a><a href="/timeline">Timeline</a><a href="/ticket/list">Tickets</a><a href="/stat">Stat</a><a href="/help">Help</a></div>
<div class="container">
<h1>📋 Ticket Reports</h1>
<div class="card">
<table class="report-table"><tr><th>ID</th><th>Name</th><th>Title</th><th>Count</th><th>Actions</th></tr>
"""
  for r in reports:
    result.add "<tr><td>" & $r.id & "</td><td><span class='badge'>report</span> " & r.name & "</td><td>" & r.title & "</td><td>" & $r.count & "</td><td><a href='/report?id=" & $r.id & "'>View</a> | <a href='/ticket/list?report=" & $r.id & "'>Tickets</a></td></tr>\n"
  result.add """
</table>
</div>
<div class="card" style="margin-top:20px">
<h2>Predefined Reports</h2>
<ul>
<li><b>Open Tickets</b> - All open tickets sorted by priority</li>
<li><b>Closed Tickets</b> - Closed/resolved tickets</li>
<li><b>My Tickets</b> - Tickets assigned to current user</li>
<li><b>Recent Tickets</b> - Tickets modified in last 7 days</li>
<li><b>By Type</b> - Grouped by bug/feature/task</li>
</ul>
<p><a href="/ticket/new">Create New Ticket</a></p>
</div>
</div></body></html>"""

proc renderReportPage*(reportId: int, reportName: string, tickets: seq[tuple[id: string, title: string, status: string, typ: string, priority: int, mtime: int64]]): string =
  result = """
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Report: """ & htmlEscape(reportName) & """</title>
<style>
body{font-family:sans-serif;background:#f8f9fa;margin:0;padding:0}
.navbar{background:#343a40;color:#fff;padding:10px 20px;display:flex;gap:15px}
.navbar a{color:#fff;text-decoration:none}
.container{max-width:1200px;margin:20px auto;padding:0 20px}
.card{background:#fff;border:1px solid #dee2e6;border-radius:6px;padding:20px}
.ticket-table{width:100%;border-collapse:collapse}
.ticket-table th{background:#e9ecef;padding:8px;text-align:left;font-size:0.9em}
.ticket-table td{padding:8px;border-top:1px solid #eee;font-size:0.9em}
.status-open{color:#0d6efd;font-weight:bold}
.status-closed{color:#6c757d}
.priority-high{color:#dc3545;font-weight:bold}
</style></head><body>
<div class="navbar"><a href="/">Home</a><a href="/reportlist">Reports</a><a href="/ticket/list">Tickets</a><a href="/stat">Stat</a></div>
<div class="container">
<h1>📋 Report: """ & htmlEscape(reportName) & """ (ID """ & $reportId & """)</h1>
<div class="card">
<table class="ticket-table"><tr><th>ID</th><th>Title</th><th>Status</th><th>Type</th><th>Priority</th><th>Modified</th></tr>
"""
  for t in tickets:
    let dateStr = fromUnix(t.mtime).format("yyyy-MM-dd")
    let statusClass = if t.status=="open": "status-open" else: "status-closed"
    let prioClass = if t.priority>=3: "priority-high" else: ""
    result.add "<tr><td><a href='/ticket?id=" & t.id & "'>" & t.id[0..7] & "</a></td><td>" & t.title & "</td><td class='" & statusClass & "'>" & t.status & "</td><td>" & t.typ & "</td><td class='" & prioClass & "'>" & $t.priority & "</td><td>" & dateStr & "</td></tr>\n"
  result.add "</table></div></div></body></html>"

proc renderAttachPage*(attachments: seq[tuple[id: string, filename: string, size: int, mtime: int64, user: string, ticketId: string]]): string =
  result = """
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Attachments - Fossil-Nim</title>
<style>
body{font-family:sans-serif;background:#f8f9fa;margin:0;padding:0}
.navbar{background:#343a40;color:#fff;padding:10px 20px;display:flex;gap:15px}
.navbar a{color:#fff;text-decoration:none}
.container{max-width:1000px;margin:20px auto;padding:0 20px}
.card{background:#fff;border:1px solid #dee2e6;border-radius:6px;padding:20px}
.attach-table{width:100%;border-collapse:collapse}
.attach-table th{background:#e9ecef;padding:10px;text-align:left}
.attach-table td{padding:10px;border-top:1px solid #eee}
</style></head><body>
<div class="navbar"><a href="/">Home</a><a href="/ticket/list">Tickets</a><a href="/stat">Stat</a><a href="/help">Help</a></div>
<div class="container">
<h1>📎 Attachments</h1>
<div class="card">
<table class="attach-table"><tr><th>Filename</th><th>Size</th><th>User</th><th>Date</th><th>Ticket/Wiki</th><th>Actions</th></tr>
"""
  for a in attachments:
    let dateStr = fromUnix(a.mtime).format("yyyy-MM-dd HH:mm")
    # SEC FIX XSS-01: Escape filename, user, ticketId, id
    result.add "<tr><td>📎 " & htmlEscape(a.filename) & "</td><td>" & $a.size & " bytes</td><td>" & htmlEscape(a.user) & "</td><td>" & dateStr & "</td><td>" & htmlEscape(a.ticketId) & "</td><td><a href='/raw?id=" & htmlEscape(a.id) & "'>Download</a></td></tr>\n"
  if attachments.len==0:
    result.add "<tr><td colspan='6' style='text-align:center;color:#6c757d'>No attachments found. Attachments are stored via chat messages and ticket comments with files.</td></tr>\n"
  result.add """
</table>
</div>
<div class="card" style="margin-top:20px">
<h2>About Attachments</h2>
<p>In Fossil-Nim, attachments can be added via:</p>
<ul>
<li>Chat messages with <code>attachment</code> field - <a href="/chat">Chat</a></li>
<li>Ticket comments with file references</li>
<li>Wiki pages with embedded files</li>
</ul>
<p>Use <a href="/api/v1/chat/send">API /api/v1/chat/send</a> with attachment URL.</p>
</div>
</div></body></html>"""

proc renderRssPage*(items: seq[tuple[title: string, link: string, description: string, pubDate: string, author: string]], feedTitle: string, feedLink: string): string =
  result = """<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">
<channel>
<title>""" & feedTitle & """</title>
<link>""" & feedLink & """</link>
<description>Fossil-Nim repository timeline RSS feed</description>
<language>en-us</language>
<atom:link href="""" & feedLink & """/timeline.rss" rel="self" type="application/rss+xml"/>
"""
  for it in items:
    result.add "<item>\n<title>" & it.title.replace("&","&amp;").replace("<","&lt;") & "</title>\n"
    result.add "<link>" & it.link & "</link>\n"
    result.add "<description>" & it.description.replace("&","&amp;").replace("<","&lt;") & "</description>\n"
    result.add "<pubDate>" & it.pubDate & "</pubDate>\n"
    result.add "<author>" & htmlEscape(it.author) & "</author>\n"
    result.add "</item>\n"
  result.add "</channel>\n</rss>"

proc renderWikiHistoryPage*(pageName: string, history: seq[tuple[rid: string, mtime: int64, user: string, comment: string]]): string =
  result = """
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Wiki History: """ & pageName & """</title>
<style>
body{font-family:sans-serif;background:#f8f9fa;margin:0;padding:0}
.navbar{background:#343a40;color:#fff;padding:10px 20px;display:flex;gap:15px}
.navbar a{color:#fff;text-decoration:none}
.container{max-width:1000px;margin:20px auto;padding:0 20px}
.card{background:#fff;border:1px solid #dee2e6;border-radius:6px;padding:20px}
.history-table{width:100%;border-collapse:collapse}
.history-table th{background:#e9ecef;padding:10px;text-align:left}
.history-table td{padding:10px;border-top:1px solid #eee}
</style></head><body>
<div class="navbar"><a href="/">Home</a><a href="/wiki/list">Wiki List</a><a href="/wiki?name=""" & pageName & """">View """ & pageName & """</a><a href="/wiki/edit?name=""" & pageName & """">Edit</a></div>
<div class="container">
<h1>📜 Wiki History: """ & pageName & """</h1>
<div class="card">
<table class="history-table"><tr><th>Date</th><th>User</th><th>Comment</th><th>Actions</th></tr>
"""
  for h in history:
    let dateStr = fromUnix(h.mtime).format("yyyy-MM-dd HH:mm")
    result.add "<tr><td>" & dateStr & "</td><td>" & h.user & "</td><td>" & h.comment & "</td><td><a href='/wcontent?name=" & pageName & "&rid=" & h.rid & "'>Content</a> | <a href='/wiki?name=" & pageName & "&rid=" & h.rid & "'>View</a></td></tr>\n"
  if history.len==0:
    result.add "<tr><td colspan='4' style='text-align:center;color:#6c757d'>No history found. Wiki pages are versioned via tags wiki-*</td></tr>\n"
  result.add """
</table>
</div>
</div></body></html>"""

proc renderWikiContentPage*(pageName: string, content: string, rid: string, mtime: int64, user: string): string =
  let dateStr = if mtime>0: fromUnix(mtime).format("yyyy-MM-dd HH:mm") else: "N/A"
  result = """
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Wiki Content: """ & htmlEscape(pageName) & """</title>
<style>
body{font-family:sans-serif;background:#f8f9fa;margin:0;padding:0}
.navbar{background:#343a40;color:#fff;padding:10px 20px;display:flex;gap:15px}
.navbar a{color:#fff;text-decoration:none}
.container{max-width:1000px;margin:20px auto;padding:0 20px}
.card{background:#fff;border:1px solid #dee2e6;border-radius:6px;padding:20px;margin-bottom:20px}
.content{white-space:pre-wrap;background:#f8f9fa;padding:15px;border:1px solid #e9ecef;border-radius:4px}
</style></head><body>
<div class="navbar"><a href="/">Home</a><a href="/wiki/list">Wiki List</a><a href="/wiki?name=""" & pageName & """">View</a><a href="/whistory?name=""" & pageName & """">History</a></div>
<div class="container">
<h1>📄 Wiki Content: """ & htmlEscape(pageName) & """</h1>
<div class="card">
<p><b>RID:</b> """ & htmlEscape(rid) & """ | <b>Date:</b> """ & dateStr & """ | <b>User:</b> """ & htmlEscape(user) & """</p>
<div class="content">""" & content.replace("<","&lt;").replace(">","&gt;") & """</div>
</div>
<p><a href="/wiki/edit?name=""" & pageName & """">Edit</a> | <a href="/whistory?name=""" & pageName & """">History</a></p>
</div></body></html>"""

proc renderLeavesPage*(leaves: seq[tuple[branch: string, rid: string, uuid: string, mtime: int64, user: string, comment: string]]): string =
  result = """
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Leaves - Fossil-Nim</title>
<style>
body{font-family:sans-serif;background:#f8f9fa;margin:0;padding:0}
.navbar{background:#343a40;color:#fff;padding:10px 20px;display:flex;gap:15px}
.navbar a{color:#fff;text-decoration:none}
.container{max-width:1000px;margin:20px auto;padding:0 20px}
.card{background:#fff;border:1px solid #dee2e6;border-radius:6px;padding:20px}
.leaf-table{width:100%;border-collapse:collapse}
.leaf-table th{background:#e9ecef;padding:10px;text-align:left}
.leaf-table td{padding:10px;border-top:1px solid #eee}
.badge{background:#28a745;color:#fff;padding:2px 6px;border-radius:10px;font-size:0.8em}
</style></head><body>
<div class="navbar"><a href="/">Home</a><a href="/timeline">Timeline</a><a href="/brlist">Branches</a><a href="/help">Help</a></div>
<div class="container">
<h1>🍃 Leaves (Branch Heads)</h1>
<div class="card">
<table class="leaf-table"><tr><th>Branch</th><th>Checkin</th><th>Date</th><th>User</th><th>Comment</th></tr>
"""
  for l in leaves:
    let dateStr = fromUnix(l.mtime).format("yyyy-MM-dd HH:mm")
    # SEC FIX XSS-01: Escape branch, user, comment
    result.add "<tr><td><span class='badge'>" & htmlEscape(l.branch) & "</span></td><td><a href='/info?id=" & htmlEscape(l.rid) & "'>" & htmlEscape(l.uuid[0..9]) & "</a></td><td>" & dateStr & "</td><td>" & htmlEscape(l.user) & "</td><td>" & htmlEscape(l.comment) & "</td></tr>\n"
  if leaves.len==0:
    result.add "<tr><td colspan='5' style='text-align:center;color:#6c757d'>No leaves found</td></tr>\n"
  result.add """
</table>
</div>
<div class="card" style="margin-top:20px">
<p>Leaves are the heads of branches - the most recent checkin on each branch. They represent the current state of each branch.</p>
</div>
</div></body></html>"""

proc getReportListSqlite*(backend: SqliteBackend): seq[tuple[id: int, name: string, title: string, count: int]] =
  # Predefined reports + dynamic counts from ticket table
  var reports: seq[tuple[id: int, name: string, title: string, count: int]] = @[]
  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_column_int64(pStmt: ptr sqlite3_stmt, iCol: cint): int64 {.importc.}
  {.pop.}
  const SQLITE_ROW = 100
  var stmt: ptr sqlite3_stmt
  var openCount = 0
  var closedCount = 0
  var totalCount = 0

  var sql = "SELECT COUNT(*) FROM ticket WHERE tkt_status='open'"
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) == 0:
    if sqlite3_step(stmt) == SQLITE_ROW:
      openCount = int(sqlite3_column_int64(stmt, 0))
    discard sqlite3_finalize(stmt)

  sql = "SELECT COUNT(*) FROM ticket WHERE tkt_status='closed'"
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) == 0:
    if sqlite3_step(stmt) == SQLITE_ROW:
      closedCount = int(sqlite3_column_int64(stmt, 0))
    discard sqlite3_finalize(stmt)

  sql = "SELECT COUNT(*) FROM ticket"
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) == 0:
    if sqlite3_step(stmt) == SQLITE_ROW:
      totalCount = int(sqlite3_column_int64(stmt, 0))
    discard sqlite3_finalize(stmt)

  reports.add (id: 1, name: "open", title: "Open Tickets", count: openCount)
  reports.add (id: 2, name: "closed", title: "Closed Tickets", count: closedCount)
  reports.add (id: 3, name: "all", title: "All Tickets", count: totalCount)
  reports.add (id: 4, name: "recent", title: "Recently Modified (7 days)", count: totalCount)
  reports.add (id: 5, name: "my", title: "My Tickets", count: 0)
  reports

proc getTicketsForReportSqlite*(backend: SqliteBackend, reportId: int, limit: int = 50): seq[tuple[id: string, title: string, status: string, typ: string, priority: int, mtime: int64]] =
  var tickets: seq[tuple[id: string, title: string, status: string, typ: string, priority: int, mtime: int64]] = @[]
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
  var stmt: ptr sqlite3_stmt
  var sql = ""
  case reportId
  of 1: sql = "SELECT tkt_uuid, tkt_title, tkt_status, tkt_type, tkt_priority, tkt_mtime FROM ticket WHERE tkt_status='open' ORDER BY tkt_priority DESC, tkt_mtime DESC LIMIT ?1"
  of 2: sql = "SELECT tkt_uuid, tkt_title, tkt_status, tkt_type, tkt_priority, tkt_mtime FROM ticket WHERE tkt_status='closed' ORDER BY tkt_mtime DESC LIMIT ?1"
  of 3: sql = "SELECT tkt_uuid, tkt_title, tkt_status, tkt_type, tkt_priority, tkt_mtime FROM ticket ORDER BY tkt_mtime DESC LIMIT ?1"
  of 4: sql = "SELECT tkt_uuid, tkt_title, tkt_status, tkt_type, tkt_priority, tkt_mtime FROM ticket WHERE tkt_mtime > strftime('%s','now','-7 days') ORDER BY tkt_mtime DESC LIMIT ?1"
  else: sql = "SELECT tkt_uuid, tkt_title, tkt_status, tkt_type, tkt_priority, tkt_mtime FROM ticket ORDER BY tkt_mtime DESC LIMIT ?1"

  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) != 0:
    return tickets
  discard sqlite3_bind_int(stmt, 1, cint(limit))
  while sqlite3_step(stmt) == SQLITE_ROW:
    let idPtr = sqlite3_column_text(stmt, 0)
    let titlePtr = sqlite3_column_text(stmt, 1)
    let statusPtr = sqlite3_column_text(stmt, 2)
    let typePtr = sqlite3_column_text(stmt, 3)
    let prio = sqlite3_column_int64(stmt, 4)
    let mtime = sqlite3_column_int64(stmt, 5)
    let id = if idPtr!=nil: $idPtr else: ""
    let title = if titlePtr!=nil: $titlePtr else: ""
    let status = if statusPtr!=nil: $statusPtr else: "open"
    let typ = if typePtr!=nil: $typePtr else: "bug"
    tickets.add (id: id, title: title, status: status, typ: typ, priority: int(prio), mtime: mtime)
  discard sqlite3_finalize(stmt)
  tickets

proc getWikiHistorySqlite*(backend: SqliteBackend, pageName: string, limit: int = 20): seq[tuple[rid: string, mtime: int64, user: string, comment: string]] =
  var history: seq[tuple[rid: string, mtime: int64, user: string, comment: string]] = @[]
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
  var stmt: ptr sqlite3_stmt
  let tagName = "wiki-" & pageName
  # Get history via tagxref + event
  let sql = """
    SELECT blob.uuid, event.mtime, event.user, event.comment
    FROM tagxref
    JOIN blob ON tagxref.rid = blob.rid
    JOIN event ON blob.rid = event.objid
    JOIN tag ON tagxref.tagid = tag.tagid
    WHERE tag.tagname = ?1
    ORDER BY event.mtime DESC LIMIT ?2
  """
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) != 0:
    return history
  discard sqlite3_bind_text(stmt, 1, tagName.cstring, -1, nil)
  discard sqlite3_bind_int(stmt, 2, cint(limit))
  while sqlite3_step(stmt) == SQLITE_ROW:
    let uuidPtr = sqlite3_column_text(stmt, 0)
    let mtime = sqlite3_column_int64(stmt, 1)
    let userPtr = sqlite3_column_text(stmt, 2)
    let commentPtr = sqlite3_column_text(stmt, 3)
    let uuid = if uuidPtr!=nil: $uuidPtr else: ""
    let user = if userPtr!=nil: $userPtr else: ""
    let comment = if commentPtr!=nil: $commentPtr else: ""
    history.add (rid: uuid, mtime: mtime, user: user, comment: comment)
  discard sqlite3_finalize(stmt)
  history

proc getLeavesSqlite*(backend: SqliteBackend, limit: int = 20): seq[tuple[branch: string, rid: string, uuid: string, mtime: int64, user: string, comment: string]] =
  var leaves: seq[tuple[branch: string, rid: string, uuid: string, mtime: int64, user: string, comment: string]] = @[]
  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_column_text(pStmt: ptr sqlite3_stmt, iCol: cint): cstring {.importc.}
  proc sqlite3_column_int64(pStmt: ptr sqlite3_stmt, iCol: cint): int64 {.importc.}
  {.pop.}
  const SQLITE_ROW = 100
  var stmt: ptr sqlite3_stmt
  # Leaves are checkins that are not parents of any other checkin (no plink where pid=rid)
  # Simplified: get latest checkin per branch
  let sql = """
    SELECT event.branch, event.objid, blob.uuid, event.mtime, event.user, event.comment
    FROM event
    JOIN blob ON event.objid = blob.rid
    WHERE event.type='ci'
    GROUP BY event.branch
    ORDER BY event.mtime DESC LIMIT 20
  """
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) != 0:
    return leaves
  while sqlite3_step(stmt) == SQLITE_ROW:
    let branchPtr = sqlite3_column_text(stmt, 0)
    let ridVal = sqlite3_column_int64(stmt, 1)
    let uuidPtr = sqlite3_column_text(stmt, 2)
    let mtime = sqlite3_column_int64(stmt, 3)
    let userPtr = sqlite3_column_text(stmt, 4)
    let commentPtr = sqlite3_column_text(stmt, 5)
    let branch = if branchPtr!=nil: $branchPtr else: "trunk"
    let uuid = if uuidPtr!=nil: $uuidPtr else: ""
    let user = if userPtr!=nil: $userPtr else: ""
    let comment = if commentPtr!=nil: $commentPtr else: ""
    leaves.add (branch: branch, rid: $ridVal, uuid: uuid, mtime: mtime, user: user, comment: comment)
  discard sqlite3_finalize(stmt)
  leaves

proc getAttachmentsSqlite*(backend: SqliteBackend, limit: int = 50): seq[tuple[id: string, filename: string, size: int, mtime: int64, user: string, ticketId: string]] =
  var atts: seq[tuple[id: string, filename: string, size: int, mtime: int64, user: string, ticketId: string]] = @[]
  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_column_text(pStmt: ptr sqlite3_stmt, iCol: cint): cstring {.importc.}
  proc sqlite3_column_int64(pStmt: ptr sqlite3_stmt, iCol: cint): int64 {.importc.}
  {.pop.}
  const SQLITE_ROW = 100
  var stmt: ptr sqlite3_stmt
  # Get chat attachments
  var sql = "SELECT msg_id, attachment, mtime, user, room FROM chat_message WHERE attachment!='' AND attachment IS NOT NULL ORDER BY mtime DESC LIMIT 50"
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) == 0:
    while sqlite3_step(stmt) == SQLITE_ROW:
      let idPtr = sqlite3_column_text(stmt, 0)
      let attPtr = sqlite3_column_text(stmt, 1)
      let mtime = sqlite3_column_int64(stmt, 2)
      let userPtr = sqlite3_column_text(stmt, 3)
      let roomPtr = sqlite3_column_text(stmt, 4)
      let id = if idPtr!=nil: $idPtr else: ""
      let att = if attPtr!=nil: $attPtr else: ""
      let user = if userPtr!=nil: $userPtr else: ""
      let room = if roomPtr!=nil: $roomPtr else: "main"
      if att.len>0:
        atts.add (id: id, filename: att, size: 0, mtime: mtime, user: user, ticketId: room)
    discard sqlite3_finalize(stmt)
  # Get forum post attachments
  sql = "SELECT post_id, attachment, mtime, user, thread_id FROM forum_post WHERE attachment!='' AND attachment IS NOT NULL ORDER BY mtime DESC LIMIT 50"
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) == 0:
    while sqlite3_step(stmt) == SQLITE_ROW:
      let idPtr = sqlite3_column_text(stmt, 0)
      let attPtr = sqlite3_column_text(stmt, 1)
      let mtime = sqlite3_column_int64(stmt, 2)
      let userPtr = sqlite3_column_text(stmt, 3)
      let threadPtr = sqlite3_column_text(stmt, 4)
      let id = if idPtr!=nil: $idPtr else: ""
      let att = if attPtr!=nil: $attPtr else: ""
      let user = if userPtr!=nil: $userPtr else: ""
      let threadId = if threadPtr!=nil: $threadPtr else: ""
      if att.len>0:
        atts.add (id: id, filename: att, size: 0, mtime: mtime, user: user, ticketId: threadId)
    discard sqlite3_finalize(stmt)
  atts

proc getTimelineForRssSqlite*(backend: SqliteBackend, limit: int = 20): seq[tuple[title: string, link: string, description: string, pubDate: string, author: string]] =
  var items: seq[tuple[title: string, link: string, description: string, pubDate: string, author: string]] = @[]
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
  var stmt: ptr sqlite3_stmt
  let sql = "SELECT user, comment, mtime, objid, branch FROM event ORDER BY mtime DESC LIMIT ?1"
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) != 0:
    return items
  discard sqlite3_bind_int(stmt, 1, cint(limit))
  while sqlite3_step(stmt) == SQLITE_ROW:
    let userPtr = sqlite3_column_text(stmt, 0)
    let commentPtr = sqlite3_column_text(stmt, 1)
    let mtime = sqlite3_column_int64(stmt, 2)
    let objid = sqlite3_column_int64(stmt, 3)
    let branchPtr = sqlite3_column_text(stmt, 4)
    let user = if userPtr!=nil: $userPtr else: "unknown"
    let comment = if commentPtr!=nil: $commentPtr else: ""
    let branch = if branchPtr!=nil: $branchPtr else: "trunk"
    let dateStr = fromUnix(mtime).format("ddd, dd MMM yyyy HH:mm:ss") & " GMT"
    let title = "[" & branch & "] " & comment.splitLines()[0]
    let link = "/info?id=" & $objid
    items.add (title: title, link: link, description: comment, pubDate: dateStr, author: user)
  discard sqlite3_finalize(stmt)
  items


proc getWikiPageInfoSqlite*(backend: SqliteBackend, pageName: string): tuple[found: bool, rid: string, uuid: string, mtime: int64, user: string, comment: string, size: int, content: string] =
  ## Full wiki page info for /winfo
  result = (found: false, rid: "", uuid: "", mtime: 0, user: "", comment: "", size: 0, content: "")
  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_column_text(pStmt: ptr sqlite3_stmt, iCol: cint): cstring {.importc.}
  proc sqlite3_column_int64(pStmt: ptr sqlite3_stmt, iCol: cint): int64 {.importc.}
  proc sqlite3_bind_text(pStmt: ptr sqlite3_stmt, i: cint, zData: cstring, n: cint, xDel: pointer): cint {.importc.}
  {.pop.}
  const SQLITE_ROW = 100
  var stmt: ptr sqlite3_stmt
  let tagName = "wiki-" & pageName
  let sql = """
    SELECT b.uuid, b.rid, e.mtime, e.user, e.comment, b.size
    FROM tag t
    JOIN tagxref x ON x.tagid=t.tagid
    JOIN blob b ON b.rid=x.rid
    JOIN event e ON e.objid=x.rid
    WHERE t.tagname=?1
    ORDER BY e.mtime DESC LIMIT 1
  """
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) != 0:
    return
  discard sqlite3_bind_text(stmt, 1, tagName.cstring, -1, nil)
  if sqlite3_step(stmt) == SQLITE_ROW:
    let uuidPtr = sqlite3_column_text(stmt, 0)
    let ridVal = sqlite3_column_int64(stmt, 1)
    let mtime = sqlite3_column_int64(stmt, 2)
    let userPtr = sqlite3_column_text(stmt, 3)
    let commentPtr = sqlite3_column_text(stmt, 4)
    let sizeVal = sqlite3_column_int64(stmt, 5)
    let uuid = if uuidPtr!=nil: $uuidPtr else: ""
    let user = if userPtr!=nil: $userPtr else: ""
    let comment = if commentPtr!=nil: $commentPtr else: ""
    discard sqlite3_finalize(stmt)
    # Get content
    var content = ""
    try:
      let blobRes = backend.getBlob(Rid(ridVal))
      if blobRes.isOk:
        content = blobRes.value.data
    except:
      discard
    result = (found: true, rid: $ridVal, uuid: uuid, mtime: mtime, user: user, comment: comment, size: int(sizeVal), content: content)
  else:
    discard sqlite3_finalize(stmt)

proc renderWinfoPage*(pageName: string, info: tuple[found: bool, rid: string, uuid: string, mtime: int64, user: string, comment: string, size: int, content: string], blame: seq[tuple[lineNum: int, content: string, user: string, mtime: int64, rid: string]] = @[]): string =
  let dateStr = if info.mtime>0: fromUnix(info.mtime).format("yyyy-MM-dd HH:mm:ss") else: "N/A"
  let escName = htmlEscape(pageName)
  result = """
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Wiki Info: """ & escName & """</title>
<style>
body{font-family:-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,sans-serif;background:#f8f9fa;margin:0;padding:0}
.navbar{background:#343a40;color:#fff;padding:10px 20px;display:flex;gap:15px}
.navbar a{color:#fff;text-decoration:none}
.container{max-width:1000px;margin:20px auto;padding:0 20px}
.card{background:#fff;border:1px solid #dee2e6;border-radius:6px;padding:20px;margin-bottom:20px}
.meta-table{width:100%;border-collapse:collapse}
.meta-table td{padding:8px;border-bottom:1px solid #eee}
.badge{background:#0d6efd;color:#fff;padding:2px 6px;border-radius:10px;font-size:0.8em}
</style></head><body>
<div class="navbar"><a href="/">Home</a><a href="/wiki/list">Wiki List</a><a href="/wiki?name=""" & escName & """">View</a><a href="/whistory?name=""" & escName & """">History</a><a href="/wdiff?name=""" & escName & """">Diff</a><a href="/help">Help</a></div>
<div class="container">
<h1>📄 Wiki Info: """ & escName & """</h1>
"""
  if not info.found:
    result.add "<div class='card'><p>Wiki page not found in DB. Showing placeholder info.</p><p>Name: " & escName & "</p></div></body></html>"
    return
  result.add """<div class="card">
<h2>Metadata</h2>
<table class="meta-table">
<tr><td><b>Name</b></td><td>""" & escName & """</td></tr>
<tr><td><b>RID</b></td><td><a href="/info?id=""" & info.rid & """">""" & info.rid & """</a></td></tr>
<tr><td><b>UUID</b></td><td><code>""" & htmlEscape(info.uuid) & """</code> <a href="/artifact?id=""" & info.uuid & """">artifact</a> | <a href="/raw?id=""" & info.uuid & """">raw</a></td></tr>
<tr><td><b>Date</b></td><td>""" & dateStr & """</td></tr>
<tr><td><b>User</b></td><td>""" & htmlEscape(info.user) & """</td></tr>
<tr><td><b>Comment</b></td><td>""" & htmlEscape(info.comment) & """</td></tr>
<tr><td><b>Size</b></td><td>""" & $info.size & """ bytes</td></tr>
<tr><td><b>Tag</b></td><td><span class='badge'>wiki-""" & escName & """</span></td></tr>
</table>
</div>
<div class="card">
<h2>Content Preview (first 2000 chars)</h2>
<pre style="white-space:pre-wrap;background:#f8f9fa;padding:15px;border:1px solid #e9ecef;border-radius:4px;max-height:400px;overflow:auto">""" & htmlEscape(info.content[0..min(info.content.len-1, 2000)]) & """</pre>
</div>
<div class="card">
<h2>Actions</h2>
<p>
<a href="/wiki?name=""" & escName & """">View</a> |
<a href="/wiki/edit?name=""" & escName & """">Edit</a> |
<a href="/whistory?name=""" & escName & """">History</a> |
<a href="/wdiff?name=""" & escName & """">Diff</a> |
<a href="/wdiff?name=""" & escName & """&side=1">Side-by-Side Diff</a> |
<a href="/wcontent?name=""" & escName & """&rid=""" & info.rid & """">Content by RID</a>
</p>
</div>
<div class="card">
<h2>Blame / Annotations (per-line)</h2>
<table style="width:100%;border-collapse:collapse;font-family:monospace;font-size:13px">
<tr><th style="background:#e9ecef;padding:6px;text-align:left">#</th><th style="background:#e9ecef;padding:6px;text-align:left">User</th><th style="background:#e9ecef;padding:6px;text-align:left">Date</th><th style="background:#e9ecef;padding:6px;text-align:left">Content</th></tr>
"""
  if blame.len>0:
    for b in blame:
      let bDate = if b.mtime>0: fromUnix(b.mtime).format("yyyy-MM-dd") else: "N/A"
      result.add "<tr><td style='padding:4px;border-top:1px solid #eee'>" & $b.lineNum & "</td><td style='padding:4px;border-top:1px solid #eee'>" & htmlEscape(b.user) & "</td><td style='padding:4px;border-top:1px solid #eee'>" & bDate & "</td><td style='padding:4px;border-top:1px solid #eee;white-space:pre-wrap'>" & htmlEscape(b.content) & "</td></tr>\n"
  else:
    let lines = info.content.splitLines()
    for i, line in lines:
      result.add "<tr><td style='padding:4px;border-top:1px solid #eee'>" & $(i+1) & "</td><td style='padding:4px;border-top:1px solid #eee'>" & htmlEscape(info.user) & "</td><td style='padding:4px;border-top:1px solid #eee'>" & dateStr & "</td><td style='padding:4px;border-top:1px solid #eee;white-space:pre-wrap'>" & htmlEscape(line) & "</td></tr>\n"
  result.add """</table>
<p style="font-size:12px;color:#6c757d">Blame shows who last edited each line (MVP: all lines attributed to latest version, full per-line history via /whistory)</p>
</div>
</div></body></html>"""

proc renderWdiffPage*(pageName: string, fromRid: string, toRid: string, fromContent: string, toContent: string, diffUnified: string): string =
  let escName = htmlEscape(pageName)
  result = """
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Wiki Diff: """ & escName & """</title>
<style>
body{font-family:monospace;background:#f8f9fa;margin:0;padding:0}
.navbar{background:#343a40;color:#fff;padding:10px 20px;display:flex;gap:15px;font-family:sans-serif}
.navbar a{color:#fff;text-decoration:none}
.container{max-width:1200px;margin:20px auto;padding:0 20px}
.diff-header{background:#fff;border:1px solid #dee2e6;padding:15px;margin-bottom:15px;border-radius:6px;font-family:sans-serif}
.diff-content{background:#fff;border:1px solid #dee2e6;padding:15px;border-radius:6px;overflow-x:auto;white-space:pre-wrap}
.diff-add{background:#d4edda;color:#155724}
.diff-del{background:#f8d7da;color:#721c24}
.diff-hunk{background:#cce5ff;color:#004085;font-weight:bold}
</style></head><body>
<div class="navbar"><a href="/">Home</a><a href="/wiki/list">Wiki List</a><a href="/wiki?name=""" & escName & """">View</a><a href="/winfo?name=""" & escName & """">Info</a><a href="/whistory?name=""" & escName & """">History</a><a href="/help">Help</a></div>
<div class="container">
<h1 style="font-family:sans-serif">📝 Wiki Diff: """ & escName & """</h1>
<div class="diff-header">
<p><b>Page:</b> """ & escName & """</p>
<p><b>From:</b> """ & htmlEscape(fromRid) & """ <b>To:</b> """ & htmlEscape(toRid) & """</p>
<p>From size: """ & $fromContent.len & """ bytes, To size: """ & $toContent.len & """ bytes</p>
</div>
<div class="diff-content">""" & htmlEscape(diffUnified) & """</div>
</div></body></html>"""

proc renderTinfoPage*(ticketId: string, ticketHtml: string, history: seq[tuple[mtime: int64, user: string, comment: string, field: string, oldVal: string, newVal: string]] = @[], extraInfo: string = ""): string =
  let escId = htmlEscape(ticketId)
  result = """
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Ticket Info: """ & escId & """</title>
<style>
body{font-family:-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,sans-serif;background:#f8f9fa;margin:0;padding:0;line-height:1.6}
.navbar{background:#343a40;color:#fff;padding:10px 20px;display:flex;gap:15px}
.navbar a{color:#fff;text-decoration:none}
.container{max-width:1000px;margin:20px auto;padding:0 20px}
.card{background:#fff;border:1px solid #dee2e6;border-radius:6px;padding:20px;margin-bottom:20px}
.history-table{width:100%;border-collapse:collapse}
.history-table th{background:#e9ecef;padding:8px;text-align:left}
.history-table td{padding:8px;border-top:1px solid #eee}
.badge{background:#0d6efd;color:#fff;padding:2px 6px;border-radius:10px;font-size:0.8em}
</style></head><body>
<div class="navbar"><a href="/">Home</a><a href="/ticket/list">Ticket List</a><a href="/tinfo?id=""" & escId & """">tinfo</a><a href="/ticket?id=""" & escId & """">ticket</a><a href="/reportlist">Reports</a><a href="/help">Help</a></div>
<div class="container">
<h1>🎫 Ticket Info: """ & escId & """ (alias /tinfo)</h1>
<div class="card">
""" & ticketHtml & """</div>
<div class="card">
<h2>📜 Change History (ticketchng)</h2>
<table class="history-table"><tr><th>Date</th><th>User</th><th>Field</th><th>Comment</th></tr>
"""
  if history.len>0:
    for h in history:
      let dateStr = fromUnix(h.mtime).format("yyyy-MM-dd HH:mm")
      result.add "<tr><td>" & dateStr & "</td><td>" & htmlEscape(h.user) & "</td><td><span class='badge'>" & htmlEscape(h.field) & "</span></td><td>" & htmlEscape(h.comment) & "</td></tr>\n"
  else:
    result.add "<tr><td colspan='4' style='text-align:center;color:#6c757d'>No change history found (ticketchng table empty or ticket is sample)</td></tr>\n"
  result.add """</table>
<p style="font-size:12px;color:#6c757d">History from ticketchng table, shows comments and field changes</p>
</div>
"""
  if extraInfo.len>0:
    result.add "<div class='card'><h2>Extra</h2><pre>" & htmlEscape(extraInfo) & "</pre></div>"
  result.add "</div></body></html>"


proc getTicketHistorySqlite*(backend: SqliteBackend, ticketId: string, limit: int = 50): seq[tuple[mtime: int64, user: string, comment: string, field: string, oldVal: string, newVal: string]] =
  ## Ticket change history for /tinfo timeline
  var history: seq[tuple[mtime: int64, user: string, comment: string, field: string, oldVal: string, newVal: string]] = @[]
  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_column_text(pStmt: ptr sqlite3_stmt, iCol: cint): cstring {.importc.}
  proc sqlite3_column_int64(pStmt: ptr sqlite3_stmt, iCol: cint): int64 {.importc.}
  proc sqlite3_bind_text(pStmt: ptr sqlite3_stmt, i: cint, zData: cstring, n: cint, xDel: pointer): cint {.importc.}
  {.pop.}
  const SQLITE_ROW = 100
  var stmt: ptr sqlite3_stmt
  let sql = "SELECT tkt_mtime, login, tkt_comment FROM ticketchng WHERE tkt_id=?1 ORDER BY tkt_mtime DESC LIMIT 50"
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) != 0:
    return history
  discard sqlite3_bind_text(stmt, 1, ticketId.cstring, -1, nil)
  while sqlite3_step(stmt) == SQLITE_ROW:
    let mtime = sqlite3_column_int64(stmt, 0)
    let userPtr = sqlite3_column_text(stmt, 1)
    let commentPtr = sqlite3_column_text(stmt, 2)
    let user = if userPtr!=nil: $userPtr else: ""
    let comment = if commentPtr!=nil: $commentPtr else: ""
    history.add (mtime: mtime, user: user, comment: comment, field: "comment", oldVal: "", newVal: comment)
  discard sqlite3_finalize(stmt)
  history

proc getWikiBlameSqlite*(backend: SqliteBackend, pageName: string): seq[tuple[lineNum: int, content: string, user: string, mtime: int64, rid: string]] =
  ## Simple blame for wiki: for each line of current content, find who last edited
  var blame: seq[tuple[lineNum: int, content: string, user: string, mtime: int64, rid: string]] = @[]
  let info = getWikiPageInfoSqlite(backend, pageName)
  if not info.found:
    return blame
  let lines = info.content.splitLines()
  # For MVP, all lines attributed to latest user
  for i, line in lines:
    blame.add (lineNum: i+1, content: line, user: info.user, mtime: info.mtime, rid: info.rid)
  blame

proc renderArtifactPage*(id: string, content: string, size: int, isBinary: bool, hexDump: string = "", meta: string = ""): string =
  let escId = htmlEscape(id)
  result = """
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Artifact """ & escId & """</title>
<style>
body{font-family:monospace;background:#f8f9fa;margin:0;padding:0}
.navbar{background:#343a40;color:#fff;padding:10px 20px;display:flex;gap:15px;font-family:sans-serif}
.navbar a{color:#fff;text-decoration:none}
.container{max-width:1200px;margin:20px auto;padding:0 20px}
.card{background:#fff;border:1px solid #dee2e6;border-radius:6px;padding:20px;margin-bottom:20px}
.meta-table{width:100%;border-collapse:collapse;font-family:sans-serif}
.meta-table td{padding:8px;border-bottom:1px solid #eee}
.hex{font-size:12px;line-height:1.4;white-space:pre;background:#f8f9fa;padding:15px;border:1px solid #e9ecef;border-radius:4px;overflow:auto;max-height:500px}
.content{white-space:pre-wrap;background:#f8f9fa;padding:15px;border:1px solid #e9ecef;border-radius:4px;overflow:auto;max-height:600px}
</style></head><body>
<div class="navbar"><a href="/">Home</a><a href="/timeline">Timeline</a><a href="/file">Files</a><a href="/raw?id=""" & escId & """">Raw</a><a href="/help">Help</a></div>
<div class="container">
<h1 style="font-family:sans-serif">📦 Artifact: """ & escId & """</h1>
<div class="card">
<h2>Metadata</h2>
<table class="meta-table">
<tr><td><b>ID</b></td><td><code>""" & escId & """</code></td></tr>
<tr><td><b>Size</b></td><td>""" & $size & """ bytes</td></tr>
<tr><td><b>Type</b></td><td>""" & (if isBinary: "Binary" else: "Text") & """</td></tr>
"""
  if meta.len>0:
    result.add "<tr><td><b>Meta</b></td><td>" & htmlEscape(meta) & "</td></tr>"
  result.add """</table>
<p>
<a href="/raw?id=""" & escId & """">Raw</a> |
<a href="/raw?id=""" & escId & """&mimetype=application/octet-stream">Download</a> |
<a href="/info?id=""" & escId & """">Info</a>
</p>
</div>
"""
  if isBinary:
    result.add """<div class="card"><h2>Hex Dump (first 4K)</h2><div class="hex">""" & htmlEscape(hexDump) & """</div></div>"""
  else:
    result.add """<div class="card"><h2>Content (first 10K)</h2><div class="content">""" & htmlEscape(content[0..min(content.len-1, 10000)]) & """</div></div>"""
  result.add "</div></body></html>"

proc hexDumpBlob*(data: string, limit: int = 4096): string =
  ## Generate hex dump like `hexdump -C`
  let n = min(data.len, limit)
  result = ""
  var offset = 0
  while offset < n:
    let chunkEnd = min(offset+16, n)
    var hexPart = ""
    var asciiPart = ""
    for i in offset..<chunkEnd:
      let b = data[i].uint8
      hexPart.add toHex(int(b), 2).toLowerAscii() & " "
      if b >= 32 and b < 127:
        asciiPart.add char(b)
      else:
        asciiPart.add "."
      if i-offset == 7:
        hexPart.add " "
    # Pad hexPart to 49 chars (16*3 + 1)
    while hexPart.len < 49:
      hexPart.add " "
    result.add toHex(offset, 8) & "  " & hexPart & " |" & asciiPart & "|\n"
    offset += 16
  if data.len > limit:
    result.add "... truncated, total " & $data.len & " bytes, showing " & $limit & "\n"

proc renderSitemapDynamicPage*(pages: seq[tuple[path: string, title: string, description: string]]): string =
  result = """
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Sitemap - Fossil-Nim</title>
<style>
body{font-family:sans-serif;background:#f8f9fa;margin:0;padding:0}
.navbar{background:#343a40;color:#fff;padding:10px 20px;display:flex;gap:15px}
.navbar a{color:#fff;text-decoration:none}
.container{max-width:1000px;margin:20px auto;padding:20px;background:#fff;border:1px solid #dee2e6;border-radius:6px}
h2{color:#343a40}
ul{line-height:1.8}
.badge{background:#0d6efd;color:#fff;padding:2px 6px;border-radius:10px;font-size:0.7em}
</style></head><body>
<div class="navbar"><a href="/">Home</a><a href="/timeline">Timeline</a><a href="/file">Files</a><a href="/help">Help</a></div>
<div class="container">
<h1>Sitemap - All Pages (Dynamic)</h1>
<p>Total pages: """ & $pages.len & """</p>
"""
  var currentGroup = ""
  for p in pages:
    let group = p.path.split("/")[1]
    if group != currentGroup:
      if currentGroup != "":
        result.add "</ul>\n"
      currentGroup = group
      result.add "<h2>" & htmlEscape(group) & " <span class='badge'>" & group & "</span></h2><ul>\n"
    result.add "<li><a href='" & htmlEscape(p.path) & "'>" & htmlEscape(p.path) & "</a> - " & htmlEscape(p.title) & " <span style='color:#6c757d'>" & htmlEscape(p.description) & "</span></li>\n"
  result.add "</ul></div></body></html>"

proc renderReportCustomPage*(reportName: string, sqlQuery: string, results: seq[Table[string, string]], error: string = ""): string =
  let escName = htmlEscape(reportName)
  result = """
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Custom Report: """ & escName & """</title>
<style>
body{font-family:sans-serif;background:#f8f9fa;margin:0;padding:0}
.navbar{background:#343a40;color:#fff;padding:10px 20px;display:flex;gap:15px}
.navbar a{color:#fff;text-decoration:none}
.container{max-width:1200px;margin:20px auto;padding:0 20px}
.card{background:#fff;border:1px solid #dee2e6;border-radius:6px;padding:20px;margin-bottom:20px}
.sql{font-family:monospace;background:#f8f9fa;padding:15px;border:1px solid #e9ecef;border-radius:4px;white-space:pre-wrap}
.result-table{width:100%;border-collapse:collapse}
.result-table th{background:#e9ecef;padding:8px;text-align:left}
.result-table td{padding:8px;border-top:1px solid #eee}
.error{background:#f8d7da;color:#721c24;padding:10px;border-radius:4px;border:1px solid #f5c6cb}
</style></head><body>
<div class="navbar"><a href="/">Home</a><a href="/reportlist">Reports</a><a href="/ticket/list">Tickets</a><a href="/help">Help</a></div>
<div class="container">
<h1>📊 Custom Report: """ & escName & """</h1>
<div class="card">
<h2>SQL Query</h2>
<div class="sql">""" & htmlEscape(sqlQuery) & """</div>
"""
  if error.len>0:
    result.add "<div class='error'>Error: " & htmlEscape(error) & "</div>"
  else:
    if results.len>0:
      result.add "<h2>Results (" & $results.len & " rows)</h2><table class='result-table'><tr>"
      for k in results[0].keys:
        result.add "<th>" & htmlEscape(k) & "</th>"
      result.add "</tr>\n"
      for row in results:
        result.add "<tr>"
        for k,v in row:
          result.add "<td>" & htmlEscape(v) & "</td>"
        result.add "</tr>\n"
      result.add "</table>"
    else:
      result.add "<p>No results</p>"
  result.add """</div>
<div class="card">
<h2>Predefined Reports</h2>
<ul>
<li><a href="/report?id=1">Open Tickets</a> - SELECT * WHERE status='open'</li>
<li><a href="/report?id=2">Closed Tickets</a></li>
<li><a href="/report?id=3">All Tickets</a></li>
<li><a href="/report?id=4">Recent (7 days)</a></li>
<li><a href="/report?id=5">My Tickets</a></li>
</ul>
<p>Custom SQL can be executed via <a href="/api/v1/sql?query=SELECT...">/api/v1/sql</a> (read-only) or MCP tool_sql.</p>
</div>
</div></body></html>"""


