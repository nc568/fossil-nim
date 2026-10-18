## Setup page - port of setup.c, admin.c, user management

import ../../types
import ../../storage/sqlite_backend
import ./login_page
import std/[strutils, tables, times, json]

type
  RepoConfig* = object
    name*: string
    value*: string
    mtime*: int64

proc getConfigSqlite*(backend: SqliteBackend, name: string): FossilResult[string] =
  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_column_text(pStmt: ptr sqlite3_stmt, iCol: cint): cstring {.importc.}
  proc sqlite3_bind_text(pStmt: ptr sqlite3_stmt, i: cint, zData: cstring, n: cint, xDel: pointer): cint {.importc.}
  {.pop.}
  const SQLITE_ROW = 100
  var stmt: ptr sqlite3_stmt
  let sql = "SELECT value FROM config WHERE name=?1"
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) != 0:
    return err[string](feNotFound, "config not found", name)
  discard sqlite3_bind_text(stmt, 1, name.cstring, -1, nil)
  if sqlite3_step(stmt) != SQLITE_ROW:
    discard sqlite3_finalize(stmt)
    return err[string](feNotFound, "config not found", name)
  let valPtr = sqlite3_column_text(stmt, 0)
  let val = if valPtr!=nil: $valPtr else: ""
  discard sqlite3_finalize(stmt)
  ok(val)

proc listConfigsSqlite*(backend: SqliteBackend): FossilResult[seq[RepoConfig]] =
  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_column_text(pStmt: ptr sqlite3_stmt, iCol: cint): cstring {.importc.}
  proc sqlite3_column_int64(pStmt: ptr sqlite3_stmt, iCol: cint): int64 {.importc.}
  {.pop.}
  const SQLITE_ROW = 100
  var configs: seq[RepoConfig] = @[]
  var stmt: ptr sqlite3_stmt
  let sql = "SELECT name, value, mtime FROM config ORDER BY name"
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) != 0:
    return ok(configs)
  while sqlite3_step(stmt) == SQLITE_ROW:
    let namePtr = sqlite3_column_text(stmt, 0)
    let valPtr = sqlite3_column_text(stmt, 1)
    let mtime = sqlite3_column_int64(stmt, 2)
    let name = if namePtr!=nil: $namePtr else: ""
    let val = if valPtr!=nil: $valPtr else: ""
    configs.add RepoConfig(name: name, value: val, mtime: mtime)
  discard sqlite3_finalize(stmt)
  ok(configs)

proc setConfigSqlite*(backend: var SqliteBackend, name: string, value: string): FossilResult[bool] =
  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_bind_text(pStmt: ptr sqlite3_stmt, i: cint, zData: cstring, n: cint, xDel: pointer): cint {.importc.}
  proc sqlite3_bind_int64(pStmt: ptr sqlite3_stmt, i: cint, v: int64): cint {.importc.}
  {.pop.}
  var stmt: ptr sqlite3_stmt
  let sql = "INSERT OR REPLACE INTO config(name, value, mtime) VALUES(?1, ?2, ?3)"
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) != 0:
    return err[bool](feIoError, "cannot prepare config insert")
  discard sqlite3_bind_text(stmt, 1, name.cstring, -1, nil)
  discard sqlite3_bind_text(stmt, 2, value.cstring, -1, nil)
  discard sqlite3_bind_int64(stmt, 3, getTime().toUnix())
  discard sqlite3_step(stmt)
  discard sqlite3_finalize(stmt)
  ok(true)

proc renderSetupPage*(users: seq[User], configs: seq[RepoConfig], currentUser: string = ""): string =
  let csrf = generateCsrfToken()
  var html = """<html><head><title>Setup - Fossil</title>
<style>
body{font-family:sans-serif;max-width:1200px;margin:20px auto;padding:0 20px;background:#f8f9fa}
h1{border-bottom:2px solid #343a40;padding-bottom:10px}
h2{color:#495057;border-bottom:1px solid #dee2e6;padding-bottom:5px;margin-top:30px}
.card{background:white;border:1px solid #dee2e6;border-radius:6px;padding:20px;margin:15px 0}
table{width:100%;border-collapse:collapse;background:white}
th,td{padding:10px 12px;border:1px solid #dee2e6;text-align:left}
th{background:#343a40;color:white}
tr:hover{background:#f8f9fa}
input,select{padding:6px 10px;border:1px solid #ced4da;border-radius:4px;margin:2px}
button{padding:6px 12px;background:#007bff;color:white;border:none;border-radius:4px;cursor:pointer}
button:hover{background:#0056b3}
button.danger{background:#dc3545}
button.danger:hover{background:#c82333}
.badge{display:inline-block;padding:2px 8px;border-radius:10px;font-size:12px;color:white;background:#28a745}
.badge-admin{background:#dc3545}
a{color:#007bff;text-decoration:none}
a:hover{text-decoration:underline}
.grid{display:grid;grid-template-columns:1fr 1fr;gap:20px}
@media(max-width:768px){.grid{grid-template-columns:1fr}}
</style></head><body>"""
  html.add "<h1>⚙️ Setup & Administration</h1>"
  html.add "<div class='card'><p>Logged in as <strong>" & currentUser & "</strong> | <a href='/'>Home</a> | <a href='/timeline'>Timeline</a> | <a href='/logout'>Logout</a></p></div>"

  html.add "<div class='grid'>"
  # Users
  html.add "<div class='card'><h2>👥 Users (" & $users.len & ")</h2>"
  html.add "<table><tr><th>Login</th><th>Name</th><th>Capabilities</th><th>Admin</th><th>Actions</th></tr>"
  for u in users:
    let adminBadge = if u.isAdmin: "<span class='badge badge-admin'>admin</span>" else: ""
    html.add "<tr><td>" & u.login & "</td><td>" & u.name & "</td><td><code>" & u.capabilities & "</code></td><td>" & adminBadge & "</td><td><a href='/setup/user?login=" & u.login & "'>edit</a></td></tr>"
  html.add "</table>"
  html.add "<h3>Add User</h3><form method='post' action='/setup/user/new'><input type='hidden' name='csrf' value='" & csrf & "'><input name='login' placeholder='Login' required><input name='name' placeholder='Full name'><input name='email' placeholder='Email'><input name='cap' placeholder='Capabilities (e.g., a b c d)' value='v'><input name='password' type='password' placeholder='Password' required><button type='submit'>Add User</button></form>"
  html.add "</div>"

  # Config
  html.add "<div class='card'><h2>🔧 Configuration (" & $configs.len & ")</h2>"
  html.add "<table><tr><th>Name</th><th>Value</th><th>Modified</th><th>Actions</th></tr>"
  for c in configs:
    let valDisplay = if c.value.len>100: c.value[0..100] & "..." else: c.value
    html.add "<tr><td><code>" & c.name & "</code></td><td>" & valDisplay.replace("<","&lt;") & "</td><td>" & fromUnix(c.mtime).format("yyyy-MM-dd HH:mm") & "</td><td><a href='/setup/config?name=" & c.name & "'>edit</a></td></tr>"
  html.add "</table>"
  html.add "<h3>Set Config</h3><form method='post' action='/setup/config'><input type='hidden' name='csrf' value='" & csrf & "'><input name='name' placeholder='Config name' required style='width:200px'><input name='value' placeholder='Value' style='width:300px'><button type='submit'>Set</button></form>"
  html.add "</div></div>"

  html.add "<div class='card'><h2>📊 Repository Stats</h2>"
  html.add "<p><a href='/stat'>Statistics</a> | <a href='/bloblist'>Blobs</a> | <a href='/file'>Files</a> | <a href='/taglist'>Tags</a> | <a href='/branch?list'>Branches</a></p>"
  html.add "<p><a href='/rebuild'>Rebuild</a> | <a href='/test_env'>Test Environment</a> | <a href='/test_timewarp'>Timewarp</a></p>"
  html.add "</div>"

  html.add "</body></html>"
  html

proc renderUserEditPage*(user: User): string =
  let csrf = generateCsrfToken()
  var html = """<html><head><title>Edit User - Fossil</title>
<style>
body{font-family:sans-serif;max-width:600px;margin:40px auto;padding:0 20px;background:#f8f9fa}
.card{background:white;padding:30px;border-radius:8px;box-shadow:0 2px 10px rgba(0,0,0,0.1)}
input{width:100%;padding:10px;margin:8px 0;border:1px solid #ced4da;border-radius:4px;box-sizing:border-box}
button{padding:10px 20px;background:#007bff;color:white;border:none;border-radius:4px;cursor:pointer}
button:hover{background:#0056b3}
a{color:#007bff;text-decoration:none}
</style></head><body>"""
  html.add "<div class='card'><h1>Edit User: " & user.login & "</h1>"
  html.add "<form method='post' action='/setup/user/edit'>"
  html.add "<input type='hidden' name='csrf' value='" & csrf & "'>"
  html.add "<input type='hidden' name='login' value='" & user.login & "'>"
  html.add "<label>Login: <input name='login_display' value='" & user.login & "' disabled></label>"
  html.add "<label>Full Name: <input name='name' value='" & user.name & "'></label>"
  html.add "<label>Email: <input name='email' value='" & user.email & "'></label>"
  html.add "<label>Capabilities: <input name='cap' value='" & user.capabilities & "'></label>"
  html.add "<label>New Password (leave blank to keep): <input name='password' type='password'></label>"
  html.add "<button type='submit'>Save</button> <a href='/setup'>Cancel</a>"
  html.add "</form></div></body></html>"
  html
