## Full parity web pages - missing pages for complete Fossil UI
## Implements: /diff, /blame, /annotate, /tree, /dir, /brlist, /taglist, /zip, /raw, /help, /sitemap, /timeline with graph, /file with raw/hex

import ../../types
import ../../storage/sqlite_backend
import ../../vcs/diff as diffMod
import ../../vcs/blame as blameMod
import ../../vcs/timeline as timelineMod
import ../../vcs/branch as branchMod
import std/[strutils, tables, sequtils, times, os, json]

proc htmlEscape*(s: string): string =
  result = s
  result = result.replace("&", "&amp;")
  result = result.replace("<", "&lt;")
  result = result.replace(">", "&gt;")
  result = result.replace("\"", "&quot;")
  result = result.replace("'", "&#39;")
  result = result.replace("`", "&#96;")

  ## SEC-05 fix: escape HTML to prevent XSS
  result = s
  result = result.replace("&", "&amp;")
  result = result.replace("<", "&lt;")
  result = result.replace(">", "&gt;")
  result = result.replace("\"", "&quot;")
  result = result.replace("'", "&#39;")
  result = result.replace("`", "&#96;")

type
  DiffInfo* = object
    fromRid*: Rid
    toRid*: Rid
    fromName*: string
    toName*: string
    content*: string

proc renderDiffPage*(fileName: string, fromRid: string, toRid: string, diffContent: string, unified: bool = true): string =
  ## Render diff page HTML
  let escFile = htmlEscape(fileName)
  let title = if fileName.len>0: "Diff: " & escFile else: "Diff"
  result = """
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>""" & title & """</title>
<style>
body{font-family:monospace;background:#f8f9fa;color:#212529;margin:0;padding:0}
.navbar{background:#343a40;color:#fff;padding:10px 20px;display:flex;gap:15px}
.navbar a{color:#fff;text-decoration:none}
.navbar a:hover{text-decoration:underline}
.container{max-width:1200px;margin:20px auto;padding:0 20px}
.diff-header{background:#fff;border:1px solid #dee2e6;padding:15px;margin-bottom:15px;border-radius:6px}
.diff-content{background:#fff;border:1px solid #dee2e6;padding:15px;border-radius:6px;overflow-x:auto;white-space:pre-wrap}
.diff-add{background:#d4edda;color:#155724}
.diff-del{background:#f8d7da;color:#721c24}
.diff-hunk{background:#cce5ff;color:#004085;font-weight:bold}
.btn{padding:6px 12px;border-radius:4px;border:1px solid #ccc;background:#fff;cursor:pointer;text-decoration:none;display:inline-block}
.btn-primary{background:#0d6efd;color:#fff;border-color:#0d6efd}
</style></head><body>
<div class="navbar"><a href="/">Home</a><a href="/timeline">Timeline</a><a href="/file">Files</a><a href="/brlist">Branches</a><a href="/help">Help</a></div>
<div class="container">
<h1>""" & title & """</h1>
<div class="diff-header">
<p><b>File:</b> """ & htmlEscape(fileName) & """</p>
<p><b>From:</b> """ & htmlEscape(fromRid) & """ <b>To:</b> """ & htmlEscape(toRid) & """</p>
<p>
<a class="btn btn-primary" href="/finfo?name=""" & htmlEscape(fileName) & """">History</a>
<a class="btn" href="/blame?name=""" & htmlEscape(fileName) & """">Blame</a>
<a class="btn" href="/file?name=""" & htmlEscape(fileName) & """">View File</a>
<a class="btn" href="/raw?name=""" & htmlEscape(fileName) & """">Raw</a>
</p>
</div>
<div class="diff-content">""" & diffContent.replace("<", "&lt;").replace(">", "&gt;") & """</div>
</div></body></html>"""

proc renderBlamePage*(fileName: string, blameLines: seq[tuple[lineNum: int, author: string, date: string, content: string, rid: string]]): string =
  let escFileBlame = htmlEscape(fileName)
  result = """
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Blame: """ & escFileBlame & """</title>
<style>
body{font-family:monospace;background:#f8f9fa;margin:0;padding:0}
.navbar{background:#343a40;color:#fff;padding:10px 20px;display:flex;gap:15px}
.navbar a{color:#fff;text-decoration:none}
.container{max-width:1200px;margin:20px auto;padding:0 20px}
.blame-table{width:100%;border-collapse:collapse;background:#fff;border:1px solid #dee2e6}
.blame-table th{background:#e9ecef;padding:8px;text-align:left}
.blame-table td{padding:4px 8px;border-top:1px solid #eee;vertical-align:top}
.blame-author{color:#6c757d;font-size:0.9em}
.blame-date{color:#6c757d;font-size:0.8em}
.blame-line{white-space:pre}
</style></head><body>
<div class="navbar"><a href="/">Home</a><a href="/timeline">Timeline</a><a href="/file">Files</a><a href="/finfo?name=""" & htmlEscape(fileName) & """">History</a><a href="/diff?name=""" & htmlEscape(fileName) & """">Diff</a></div>
<div class="container">
<h1>Blame: """ & htmlEscape(fileName) & """</h1>
<table class="blame-table"><tr><th>#</th><th>Author</th><th>Date</th><th>Content</th></tr>
"""
  for bl in blameLines:
    # SEC FIX XSS-01: Escape author, date, content
    result.add "<tr><td>" & $bl.lineNum & "</td><td class='blame-author'>" & htmlEscape(bl.author) & "<br><span class='blame-date'>" & htmlEscape(bl.date) & "</span></td><td class='blame-line'>" & htmlEscape(bl.content) & "</td></tr>\n"
  result.add "</table></div></body></html>"

proc renderTreePage*(path: string, files: seq[string], dirs: seq[string], branch: string = "trunk"): string =
  let escPath = htmlEscape(path)
  let escBranch = htmlEscape(branch)
  result = """
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Tree: """ & escPath & """</title>
<style>
body{font-family:-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,sans-serif;background:#f8f9fa;margin:0;padding:0}
.navbar{background:#343a40;color:#fff;padding:10px 20px;display:flex;gap:15px}
.navbar a{color:#fff;text-decoration:none}
.container{max-width:1000px;margin:20px auto;padding:0 20px}
.file-list{background:#fff;border:1px solid #dee2e6;border-radius:6px;padding:15px}
.file-list ul{list-style:none;padding:0}
.file-list li{padding:6px 0;border-bottom:1px solid #f0f0f0}
.file-list li:last-child{border-bottom:none}
.dir{font-weight:bold;color:#0d6efd}
.file{color:#212529}
.breadcrumb{margin-bottom:15px;color:#6c757d}
.breadcrumb a{color:#0d6efd;text-decoration:none}
</style></head><body>
<div class="navbar"><a href="/">Home</a><a href="/timeline">Timeline</a><a href="/brlist">Branches</a><a href="/help">Help</a></div>
<div class="container">
<div class="breadcrumb"><a href="/tree">/</a> """ & escPath & """ <span style="float:right">Branch: """ & escBranch & """</span></div>
<h1>Directory: /""" & escPath & """</h1>
<div class="file-list">
<h3>Directories</h3><ul>
"""
  for d in dirs:
    result.add "<li><span class='dir'>📁</span> <a class='dir' href='/tree?path=" & path & "/" & d & "'>" & d & "</a></li>\n"
  result.add "</ul><h3>Files</h3><ul>\n"
  for f in files:
    result.add "<li><span class='file'>📄</span> <a class='file' href='/file?name=" & path & "/" & f & "'>" & f & "</a> <a href='/finfo?name=" & path & "/" & f & "' style='font-size:0.8em;color:#6c757d'>(history)</a></li>\n"
  result.add """
</ul></div>
<p><a href="/zip?path=""" & path & """">Download ZIP</a> | <a href="/tarball?path=""" & path & """">Tarball</a></p>
</div></body></html>"""

proc renderBrlistPage*(branches: seq[tuple[name: string, count: int, lastMtime: int64, tip: string]]): string =
  result = """
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Branches</title>
<style>
body{font-family:sans-serif;background:#f8f9fa;margin:0;padding:0}
.navbar{background:#343a40;color:#fff;padding:10px 20px;display:flex;gap:15px}
.navbar a{color:#fff;text-decoration:none}
.container{max-width:1000px;margin:20px auto;padding:0 20px}
.branch-table{width:100%;border-collapse:collapse;background:#fff;border:1px solid #dee2e6;border-radius:6px;overflow:hidden}
.branch-table th{background:#e9ecef;padding:10px;text-align:left}
.branch-table td{padding:10px;border-top:1px solid #eee}
.badge{background:#0d6efd;color:#fff;padding:2px 6px;border-radius:10px;font-size:0.8em}
</style></head><body>
<div class="navbar"><a href="/">Home</a><a href="/timeline">Timeline</a><a href="/taglist">Tags</a><a href="/help">Help</a></div>
<div class="container">
<h1>Branches</h1>
<table class="branch-table"><tr><th>Branch</th><th>Commits</th><th>Last Modified</th><th>Tip</th><th>Actions</th></tr>
"""
  for b in branches:
    let dateStr = fromUnix(b.lastMtime).format("yyyy-MM-dd HH:mm")
    # SEC FIX XSS-01: Escape branch name and tip
    let escBName = htmlEscape(b.name)
    let escTip = htmlEscape(b.tip)
    result.add "<tr><td><span class='badge'>branch</span> <a href='/timeline?branch=" & escBName & "'>" & escBName & "</a></td><td>" & $b.count & "</td><td>" & dateStr & "</td><td><a href='/info?id=" & escTip & "'>" & escTip[0..min(9, escTip.high)] & "</a></td><td><a href='/timeline?branch=" & escBName & "'>Timeline</a> | <a href='/tree?branch=" & escBName & "'>Files</a> | <a href='/zip?branch=" & escBName & "'>ZIP</a></td></tr>\n"
  result.add "</table></div></body></html>"

proc renderTaglistPage*(tags: seq[tuple[name: string, typeName: string, count: int]]): string =
  result = """
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Tags</title>
<style>
body{font-family:sans-serif;background:#f8f9fa;margin:0;padding:0}
.navbar{background:#343a40;color:#fff;padding:10px 20px;display:flex;gap:15px}
.navbar a{color:#fff;text-decoration:none}
.container{max-width:1000px;margin:20px auto;padding:0 20px}
.tag-table{width:100%;border-collapse:collapse;background:#fff;border:1px solid #dee2e6}
.tag-table th{background:#e9ecef;padding:10px;text-align:left}
.tag-table td{padding:10px;border-top:1px solid #eee}
</style></head><body>
<div class="navbar"><a href="/">Home</a><a href="/timeline">Timeline</a><a href="/brlist">Branches</a><a href="/help">Help</a></div>
<div class="container">
<h1>Tags</h1>
<table class="tag-table"><tr><th>Tag</th><th>Type</th><th>Count</th></tr>
"""
  for t in tags:
    # SEC FIX XSS-01: Escape tag names
    result.add "<tr><td>" & htmlEscape(t.name) & "</td><td>" & htmlEscape(t.typeName) & "</td><td>" & $t.count & "</td></tr>\n"
  result.add "</table></div></body></html>"

proc renderRawPage*(fileName: string, content: string, isBinary: bool): string =
  if isBinary:
    result = "Binary file: " & fileName & " (" & $content.len & " bytes)"
  else:
    result = content

proc renderHelpPage*(): string =
  result = """
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Help - Fossil-Nim</title>
<style>
body{font-family:sans-serif;background:#f8f9fa;margin:0;padding:0;line-height:1.6}
.navbar{background:#343a40;color:#fff;padding:10px 20px;display:flex;gap:15px}
.navbar a{color:#fff;text-decoration:none}
.container{max-width:1000px;margin:20px auto;padding:20px;background:#fff;border:1px solid #dee2e6;border-radius:6px}
h2{color:#343a40;border-bottom:2px solid #0d6efd;padding-bottom:5px}
code{background:#f0f0f0;padding:2px 4px;border-radius:3px}
pre{background:#f8f9fa;padding:15px;border:1px solid #dee2e6;border-radius:4px;overflow-x:auto}
a{color:#0d6efd;text-decoration:none}
a:hover{text-decoration:underline}
</style></head><body>
<div class="navbar"><a href="/">Home</a><a href="/timeline">Timeline</a><a href="/file">Files</a><a href="/brlist">Branches</a><a href="/help">Help</a><a href="/sitemap">Sitemap</a></div>
<div class="container">
<h1>🦖 Fossil-Nim Help</h1>
<p>Complete rewrite of Fossil SCM in Nim. Version 2.26.0-nim</p>

<h2>Web UI Pages (Full Parity)</h2>
<ul>
<li><a href="/timeline">/timeline</a> - Show timeline of checkins, with filters ?branch=trunk&limit=20</li>
<li><a href="/file">/file</a> - File browser, ?name=path or ?pattern=*.nim</li>
<li><a href="/finfo?name=README.md">/finfo</a> - File history, ?name=path</li>
<li><a href="/diff?name=README.md">/diff</a> - Diff view, ?name=path&from=rid&to=rid</li>
<li><a href="/blame?name=README.md">/blame</a> - Blame/annotate, ?name=path</li>
<li><a href="/tree">/tree</a> - Directory tree, ?path=/&branch=trunk</li>
<li><a href="/dir">/dir</a> - Alias for /tree</li>
<li><a href="/info">/info</a> - Checkin info, ?id=rid or ?rid=rid</li>
<li><a href="/graph">/graph</a> - Commit graph visualization</li>
<li><a href="/brlist">/brlist</a> - Branch list</li>
<li><a href="/taglist">/taglist</a> - Tag list</li>
<li><a href="/wiki">/wiki</a> - Wiki page view, ?name=Home</li>
<li><a href="/wiki/list">/wiki/list</a> - Wiki page list</li>
<li><a href="/wiki/new">/wiki/new</a> - New wiki page form</li>
<li><a href="/wiki/edit?name=Home">/wiki/edit</a> - Edit wiki page</li>
<li><a href="/ticket">/ticket</a> - Ticket view, ?id=0</li>
<li><a href="/ticket/list">/ticket/list</a> - Ticket list</li>
<li><a href="/ticket/new">/ticket/new</a> - New ticket form</li>
<li><a href="/forum">/forum</a> - Forum thread, ?id=thread_id</li>
<li><a href="/forum/list">/forum/list</a> - Forum list</li>
<li><a href="/forum/new">/forum/new</a> - New forum thread</li>
<li><a href="/chat">/chat</a> - Chat room, ?room=main</li>
<li><a href="/chat/rooms">/chat/rooms</a> - Chat rooms list</li>
<li><a href="/search">/search</a> - Search, ?q=query (FTS5)</li>
<li><a href="/zip">/zip</a> - Download ZIP, ?branch=trunk&path=/</li>
<li><a href="/tarball">/tarball</a> - Download tarball</li>
<li><a href="/raw?name=README.md">/raw</a> - Raw file content</li>
<li><a href="/stat">/stat</a> - Repository statistics (commits, files, wiki, tickets, etc)</li>
<li><a href="/reportlist">/reportlist</a> - Ticket reports list</li>
<li><a href="/report?id=1">/report</a> - Ticket report view, ?id=1</li>
<li><a href="/attach">/attach</a> - Attachments list</li>
<li><a href="/attachlist">/attachlist</a> - Alias for /attach</li>
<li><a href="/rss">/rss</a> - RSS feed (timeline)</li>
<li><a href="/timeline.rss">/timeline.rss</a> - Alias for /rss</li>
<li><a href="/wcontent?name=Home">/wcontent</a> - Wiki content history, ?name=Home&rid=xxx</li>
<li><a href="/whistory?name=Home">/whistory</a> - Wiki history, ?name=Home</li>
<li><a href="/leaves">/leaves</a> - Leaves (branch heads)</li>
<li><a href="/login">/login</a> - Login page</li>
<li><a href="/setup">/setup</a> - Setup/admin page</li>
<li><a href="/help">/help</a> - This help page</li>
<li><a href="/sitemap">/sitemap</a> - Sitemap of all pages</li>
</ul>

<h2>API Endpoints</h2>
<ul>
<li><code>GET /api/v1/timeline?limit=20&branch=trunk</code> - Timeline JSON</li>
<li><code>GET /api/v1/file?name=README.md</code> - File content</li>
<li><code>GET /api/v1/branches</code> - Branch list</li>
<li><code>GET /api/v1/wiki/list</code> - Wiki list</li>
<li><code>GET /api/v1/wiki/get?name=Home</code> - Wiki page</li>
<li><code>POST /api/v1/wiki/save</code> - Save wiki (auth)</li>
<li><code>GET /api/v1/ticket/list</code> - Ticket list</li>
<li><code>POST /api/v1/ticket/create</code> - Create ticket</li>
<li><code>GET /api/v1/search?q=bug</code> - Search FTS5</li>
<li><code>GET /api/v1/forum/list</code> - Forum list</li>
<li><code>POST /api/v1/forum/create</code> - Create thread</li>
<li><code>GET /api/v1/chat/list?room=main</code> - Chat messages</li>
<li><code>POST /api/v1/chat/send</code> - Send chat</li>
<li><code>GET /api/v1/info?rid=1</code> - Checkin info</li>
<li><code>GET /api/v1/diff?name=file.txt&from=1&to=2</code> - Diff</li>
<li><code>GET /api/v1/blame?name=file.txt</code> - Blame</li>
</ul>

<h2>CLI Commands</h2>
<pre>
fossil init repo.fossil
fossil open repo.fossil
fossil add file.txt
fossil commit -m "message" file.txt
fossil timeline --limit 20
fossil diff file.txt
fossil status
fossil branch list
fossil git-export --output export.gitfast --limit 100
fossil git-import export.gitfast
fossil server --port 8080 --repo repo.fossil
fossil mcp serve --stdio
</pre>

<h2>Storage Backends</h2>
<ul>
<li><b>SQLite</b> (default) - 100% compatible, WAL mode, delta chain</li>
<li><b>libmdbx</b> - Recommended, fast, ACID, small</li>
<li><b>LMDB</b> - Fast read, writer bottleneck</li>
<li><b>CDB</b> - Read-only archival, ultra-fast</li>
</ul>
<pre>fossil rebuild --backend libmdbx --repo repo.fossil</pre>

<h2>QBE / cproc</h2>
<pre>
make qbe          # Dynamic QBE build 573K
make qbe-static   # Static with gcc fallback
nim c -d:qbeCompat --mm:refc --threads:off src/fossil/cli/main_qbe.nim
</pre>

<h2>MCP (89 tools)</h2>
<p>Model Context Protocol server for AI agents: status, diff, commit, timeline, branch_list, wiki_list, wiki_get, wiki_create, ticket_list, ticket_get, ticket_create, search, forum_list, forum_get, forum_create, forum_post, chat_list, chat_send, blame, stash, tag, user management, and all VCS operations.</p>
<pre>fossil mcp serve --stdio</pre>

<h2>Documentation</h2>
<ul>
<li><a href="/assets/docs/ARCHITECTURE.md">ARCHITECTURE.md</a></li>
<li><a href="/assets/docs/API.md">API.md</a></li>
<li><a href="/assets/docs/MCP_API.md">MCP_API.md</a></li>
<li><a href="/assets/docs/STORAGE_BACKENDS.md">STORAGE_BACKENDS.md</a></li>
<li><a href="/assets/docs/CPROC_QBE.md">CPROC_QBE.md</a></li>
</ul>
</div></body></html>"""

proc renderSitemapPage*(): string =
  result = """
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Sitemap - Fossil-Nim</title>
<style>
body{font-family:sans-serif;background:#f8f9fa;margin:0;padding:0}
.navbar{background:#343a40;color:#fff;padding:10px 20px;display:flex;gap:15px}
.navbar a{color:#fff;text-decoration:none}
.container{max-width:1000px;margin:20px auto;padding:20px;background:#fff;border:1px solid #dee2e6;border-radius:6px}
h2{color:#343a40}
ul{line-height:1.8}
</style></head><body>
<div class="navbar"><a href="/">Home</a><a href="/timeline">Timeline</a><a href="/file">Files</a><a href="/help">Help</a></div>
<div class="container">
<h1>Sitemap - All Pages</h1>

<h2>Core VCS</h2>
<ul>
<li><a href="/timeline">/timeline</a> - Timeline</li>
<li><a href="/timeline?graph=1">/timeline?graph=1</a> - Timeline with graph</li>
<li><a href="/file">/file</a> - File browser</li>
<li><a href="/tree">/tree</a> - Tree view</li>
<li><a href="/dir">/dir</a> - Directory listing (alias)</li>
<li><a href="/finfo">/finfo</a> - File info/history</li>
<li><a href="/diff">/diff</a> - Diff</li>
<li><a href="/blame">/blame</a> - Blame</li>
<li><a href="/annotate">/annotate</a> - Annotate (alias)</li>
<li><a href="/info">/info</a> - Checkin info</li>
<li><a href="/graph">/graph</a> - Graph</li>
<li><a href="/brlist">/brlist</a> - Branch list</li>
<li><a href="/taglist">/taglist</a> - Tag list</li>
<li><a href="/zip">/zip</a> - ZIP download</li>
<li><a href="/tarball">/tarball</a> - Tarball download</li>
<li><a href="/raw">/raw</a> - Raw file</li>
</ul>

<h2>Wiki</h2>
<ul>
<li><a href="/wiki">/wiki</a> - Wiki page</li>
<li><a href="/wiki/list">/wiki/list</a> - List</li>
<li><a href="/wiki/new">/wiki/new</a> - New</li>
<li><a href="/wiki/edit">/wiki/edit</a> - Edit</li>
<li><a href="/wcontent">/wcontent</a> - Wiki content history</li>
<li><a href="/whistory">/whistory</a> - Wiki history</li>
</ul>

<h2>Tickets</h2>
<ul>
<li><a href="/ticket">/ticket</a> - Ticket view</li>
<li><a href="/ticket/list">/ticket/list</a> - List</li>
<li><a href="/ticket/new">/ticket/new</a> - New</li>
<li><a href="/reportlist">/reportlist</a> - Reports</li>
<li><a href="/report?id=1">/report</a> - Report view</li>
<li><a href="/attach">/attach</a> - Attachments</li>
<li><a href="/attachlist">/attachlist</a> - Attachments list</li>
</ul>

<h2>Statistics & Feeds</h2>
<ul>
<li><a href="/stat">/stat</a> - Repository statistics</li>
<li><a href="/leaves">/leaves</a> - Leaves (branch heads)</li>
<li><a href="/rss">/rss</a> - RSS feed</li>
<li><a href="/timeline.rss">/timeline.rss</a> - RSS alias</li>
</ul>

<h2>Forum & Chat</h2>
<ul>
<li><a href="/forum">/forum</a> - Forum thread</li>
<li><a href="/forum/list">/forum/list</a> - List</li>
<li><a href="/forum/new">/forum/new</a> - New thread</li>
<li><a href="/chat">/chat</a> - Chat</li>
<li><a href="/chat/rooms">/chat/rooms</a> - Rooms</li>
<li><a href="/chat/presence">/chat/presence</a> - Presence</li>
</ul>

<h2>Search & Help</h2>
<ul>
<li><a href="/search">/search</a> - Search FTS5</li>
<li><a href="/help">/help</a> - Help</li>
<li><a href="/sitemap">/sitemap</a> - Sitemap</li>
<li><a href="/login">/login</a> - Login</li>
<li><a href="/setup">/setup</a> - Setup</li>
</ul>

<h2>API</h2>
<ul>
<li><a href="/api/v1/timeline">/api/v1/timeline</a></li>
<li><a href="/api/v1/file">/api/v1/file</a></li>
<li><a href="/api/v1/branches">/api/v1/branches</a></li>
<li><a href="/api/v1/wiki/list">/api/v1/wiki/list</a></li>
<li><a href="/api/v1/ticket/list">/api/v1/ticket/list</a></li>
<li><a href="/api/v1/search">/api/v1/search</a></li>
<li><a href="/api/v1/forum/list">/api/v1/forum/list</a></li>
<li><a href="/api/v1/chat/list">/api/v1/chat/list</a></li>
<li><a href="/api/v1/info">/api/v1/info</a></li>
<li><a href="/api/v1/diff">/api/v1/diff</a></li>
<li><a href="/api/v1/blame">/api/v1/blame</a></li>
<li><a href="/api/v1/openapi.json">/api/v1/openapi.json</a></li>
</ul>
</div></body></html>"""

# Helpers for DB queries
proc getBranchesForBrlist*(backend: SqliteBackend): seq[tuple[name: string, count: int, lastMtime: int64, tip: string]] =
  var branches: seq[tuple[name: string, count: int, lastMtime: int64, tip: string]] = @[]
  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_column_text(pStmt: ptr sqlite3_stmt, iCol: cint): cstring {.importc.}
  proc sqlite3_column_int64(pStmt: ptr sqlite3_stmt, iCol: cint): int64 {.importc.}
  {.pop.}
  const SQLITE_ROW = 100
  let sql = "SELECT branch, COUNT(*), MAX(mtime), MAX(objid) FROM event WHERE type='ci' GROUP BY branch ORDER BY MAX(mtime) DESC"
  var stmt: ptr sqlite3_stmt
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) != 0:
    return branches
  while sqlite3_step(stmt) == SQLITE_ROW:
    let branchPtr = sqlite3_column_text(stmt, 0)
    let cnt = sqlite3_column_int64(stmt, 1)
    let mtime = sqlite3_column_int64(stmt, 2)
    let tipPtr = sqlite3_column_text(stmt, 3)
    let branchName = if branchPtr!=nil: $branchPtr else: "trunk"
    let tip = if tipPtr!=nil: $tipPtr else: ""
    branches.add (name: branchName, count: int(cnt), lastMtime: mtime, tip: tip)
  discard sqlite3_finalize(stmt)
  branches

proc getTagsForTaglist*(backend: SqliteBackend): seq[tuple[name: string, typeName: string, count: int]] =
  var tags: seq[tuple[name: string, typeName: string, count: int]] = @[]
  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_column_text(pStmt: ptr sqlite3_stmt, iCol: cint): cstring {.importc.}
  proc sqlite3_column_int64(pStmt: ptr sqlite3_stmt, iCol: cint): int64 {.importc.}
  {.pop.}
  const SQLITE_ROW = 100
  let sql = "SELECT tagname, COUNT(*) FROM tagxref GROUP BY tagname ORDER BY tagname LIMIT 100"
  var stmt: ptr sqlite3_stmt
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) != 0:
    # Fallback: try tag table
    let sql2 = "SELECT tagname FROM tag ORDER BY tagname LIMIT 100"
    if sqlite3_prepare_v2(backend.db, sql2.cstring, -1, addr stmt, nil) != 0:
      return tags
    while sqlite3_step(stmt) == SQLITE_ROW:
      let namePtr = sqlite3_column_text(stmt, 0)
      let name = if namePtr!=nil: $namePtr else: ""
      tags.add (name: name, typeName: "sym", count: 1)
    discard sqlite3_finalize(stmt)
    return tags
  while sqlite3_step(stmt) == SQLITE_ROW:
    let namePtr = sqlite3_column_text(stmt, 0)
    let cnt = sqlite3_column_int64(stmt, 1)
    let name = if namePtr!=nil: $namePtr else: ""
    tags.add (name: name, typeName: "tag", count: int(cnt))
  discard sqlite3_finalize(stmt)
  tags


proc renderDiffSideBySide*(fileName: string, fromRid: string, toRid: string, diffResult: diffMod.DiffResult): string =
  let escFile = htmlEscape(fileName)
  result = """
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Diff Side-by-Side: """ & escFile & """</title>
<style>
body{font-family:monospace;background:#f8f9fa;margin:0;padding:0}
.navbar{background:#343a40;color:#fff;padding:10px 20px;display:flex;gap:15px;font-family:sans-serif}
.navbar a{color:#fff;text-decoration:none}
.container{max-width:1400px;margin:20px auto;padding:0 20px}
.diff-header{background:#fff;border:1px solid #dee2e6;padding:15px;margin-bottom:15px;border-radius:6px;font-family:sans-serif}
.side-by-side{display:flex;gap:10px}
.side{flex:1;background:#fff;border:1px solid #dee2e6;border-radius:6px;padding:10px;overflow:auto;max-height:80vh}
.line{white-space:pre-wrap;padding:2px 4px}
.line-add{background:#d4edda}
.line-del{background:#f8d7da}
.line-context{background:#fff}
.lineno{color:#6c757d;font-size:0.8em;margin-right:8px;user-select:none}
.btn{padding:6px 12px;border-radius:4px;border:1px solid #ccc;background:#fff;cursor:pointer;text-decoration:none;display:inline-block;font-family:sans-serif}
.btn-primary{background:#0d6efd;color:#fff;border-color:#0d6efd}
</style></head><body>
<div class="navbar"><a href="/">Home</a><a href="/timeline">Timeline</a><a href="/file">Files</a><a href="/brlist">Branches</a><a href="/help">Help</a></div>
<div class="container">
<h1 style="font-family:sans-serif">Diff Side-by-Side: """ & escFile & """</h1>
<div class="diff-header">
<p><b>File:</b> """ & escFile & """</p>
<p><b>From:</b> """ & htmlEscape(fromRid) & """ <b>To:</b> """ & htmlEscape(toRid) & """</p>
<p><a class="btn" href="/diff?name=""" & escFile & """&from=""" & htmlEscape(fromRid) & """&to=""" & htmlEscape(toRid) & """">Unified</a> <a class="btn btn-primary" href="/wdiff?name=""" & escFile & """&v1=""" & htmlEscape(fromRid) & """&v2=""" & htmlEscape(toRid) & """&side=1">Side-by-Side</a></p>
</div>
<div class="side-by-side">
<div class="side"><h3 style="font-family:sans-serif">Old (""" & htmlEscape(fromRid) & """)</h3>
"""
  for line in diffResult.lines:
    if line.kind == diffMod.dlRemove or line.kind == diffMod.dlContext:
      let cls = if line.kind == diffMod.dlRemove: "line-del" else: "line-context"
      result.add "<div class='line " & cls & "'><span class='lineno'>" & $line.oldLineNo & "</span>" & htmlEscape(line.content) & "</div>\n"
  result.add "</div><div class='side'><h3 style='font-family:sans-serif'>New (" & htmlEscape(toRid) & ")</h3>\n"
  for line in diffResult.lines:
    if line.kind == diffMod.dlAdd or line.kind == diffMod.dlContext:
      let cls = if line.kind == diffMod.dlAdd: "line-add" else: "line-context"
      result.add "<div class='line " & cls & "'><span class='lineno'>" & $line.newLineNo & "</span>" & htmlEscape(line.content) & "</div>\n"
  result.add "</div></div></div></body></html>"


