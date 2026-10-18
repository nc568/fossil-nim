## Login page - port of login.c, session management

import ../../types
import ../../storage/sqlite_backend
import std/[strutils, tables, times, random, base64, sha1, json, sysrand]

type
  User* = object
    login*: string
    name*: string
    email*: string
    capabilities*: string
    pwHash*: string
    mtime*: int64
    isAdmin*: bool

  Session* = object
    id*: string
    user*: string
    loginTime*: int64
    expireTime*: int64
    ip*: string

proc hashPassword*(password: string): string =
  # Simple SHA1 for MVP, original Fossil uses SHA1 + salt
  $secureHash(password)

proc verifyPassword*(password: string, hash: string): bool =
  hashPassword(password) == hash

proc generateSessionId*(): string =
  # SEC FIX CRY-01: Use CSPRNG sysrand.urandom instead of std/random Mersenne Twister
  var byteSeq = newSeq[byte](32)
  var ok = urandom(byteSeq)
  var bytes = newString(32)
  if ok:
    for i in 0..<32:
      bytes[i] = char(byteSeq[i])
  else:
    # Fallback to randomize + rand if sysrand fails (should not happen on Linux)
    randomize()
    for i in 0..<32:
      bytes[i] = char(rand(255))
  encode(bytes).replace("+", "-").replace("/", "_").replace("=", "")

proc getUserSqlite*(backend: SqliteBackend, login: string): FossilResult[User] =
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
  let sql = "SELECT login, pw, cap, mtime, info FROM user WHERE login=?1"
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) != 0:
    return err[User](feNotFound, "user not found", login)
  discard sqlite3_bind_text(stmt, 1, login.cstring, -1, nil)
  if sqlite3_step(stmt) != SQLITE_ROW:
    discard sqlite3_finalize(stmt)
    return err[User](feNotFound, "user not found", login)
  let loginPtr = sqlite3_column_text(stmt, 0)
  let pwPtr = sqlite3_column_text(stmt, 1)
  let capPtr = sqlite3_column_text(stmt, 2)
  let mtime = sqlite3_column_int64(stmt, 3)
  let infoPtr = sqlite3_column_text(stmt, 4)
  let loginStr = if loginPtr!=nil: $loginPtr else: login
  let pwHash = if pwPtr!=nil: $pwPtr else: ""
  let cap = if capPtr!=nil: $capPtr else: ""
  let info = if infoPtr!=nil: $infoPtr else: ""
  discard sqlite3_finalize(stmt)
  var user = User(login: loginStr, capabilities: cap, pwHash: pwHash, mtime: mtime, isAdmin: cap.contains("a") or cap.contains("s"))
  # Parse info JSON or simple format for name/email
  if info.len>0:
    try:
      let j = parseJson(info)
      if j.hasKey("name"): user.name = j["name"].getStr()
      if j.hasKey("email"): user.email = j["email"].getStr()
    except:
      user.name = info
  ok(user)

proc listUsersSqlite*(backend: SqliteBackend): FossilResult[seq[User]] =
  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_column_text(pStmt: ptr sqlite3_stmt, iCol: cint): cstring {.importc.}
  proc sqlite3_column_int64(pStmt: ptr sqlite3_stmt, iCol: cint): int64 {.importc.}
  {.pop.}
  const SQLITE_ROW = 100
  var users: seq[User] = @[]
  var stmt: ptr sqlite3_stmt
  let sql = "SELECT login, cap, mtime, info FROM user ORDER BY login"
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) != 0:
    return ok(users)
  while sqlite3_step(stmt) == SQLITE_ROW:
    let loginPtr = sqlite3_column_text(stmt, 0)
    let capPtr = sqlite3_column_text(stmt, 1)
    let mtime = sqlite3_column_int64(stmt, 2)
    let infoPtr = sqlite3_column_text(stmt, 3)
    let login = if loginPtr!=nil: $loginPtr else: ""
    let cap = if capPtr!=nil: $capPtr else: ""
    let info = if infoPtr!=nil: $infoPtr else: ""
    var u = User(login: login, capabilities: cap, mtime: mtime, isAdmin: cap.contains("a") or cap.contains("s"))
    if info.len>0:
      try:
        let j = parseJson(info)
        if j.hasKey("name"): u.name = j["name"].getStr()
        if j.hasKey("email"): u.email = j["email"].getStr()
      except:
        u.name = info
    users.add u
  discard sqlite3_finalize(stmt)
  ok(users)

proc createSessionSqlite*(backend: var SqliteBackend, user: string, ip: string = ""): FossilResult[Session] =
  let sid = generateSessionId()
  let now = getTime().toUnix()
  let expire = now + 86400*7 # 7 days
  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_bind_text(pStmt: ptr sqlite3_stmt, i: cint, zData: cstring, n: cint, xDel: pointer): cint {.importc.}
  proc sqlite3_bind_int64(pStmt: ptr sqlite3_stmt, i: cint, v: int64): cint {.importc.}
  {.pop.}
  # Ensure session table exists
  var stmt: ptr sqlite3_stmt
  let sqlCreate = "CREATE TABLE IF NOT EXISTS session(sid TEXT PRIMARY KEY, user TEXT, mtime INTEGER, expire INTEGER, ip TEXT)"
  if sqlite3_prepare_v2(backend.db, sqlCreate.cstring, -1, addr stmt, nil) == 0:
    discard sqlite3_step(stmt)
    discard sqlite3_finalize(stmt)
  let sql = "INSERT INTO session(sid, user, mtime, expire, ip) VALUES(?1, ?2, ?3, ?4, ?5)"
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) != 0:
    return err[Session](feIoError, "cannot create session")
  discard sqlite3_bind_text(stmt, 1, sid.cstring, -1, nil)
  discard sqlite3_bind_text(stmt, 2, user.cstring, -1, nil)
  discard sqlite3_bind_int64(stmt, 3, now)
  discard sqlite3_bind_int64(stmt, 4, expire)
  discard sqlite3_bind_text(stmt, 5, ip.cstring, -1, nil)
  discard sqlite3_step(stmt)
  discard sqlite3_finalize(stmt)
  ok(Session(id: sid, user: user, loginTime: now, expireTime: expire, ip: ip))

proc validateSessionSqlite*(backend: SqliteBackend, sid: string): FossilResult[Session] =
  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_column_text(pStmt: ptr sqlite3_stmt, iCol: cint): cstring {.importc.}
  proc sqlite3_column_int64(pStmt: ptr sqlite3_stmt, iCol: cint): int64 {.importc.}
  proc sqlite3_bind_text(pStmt: ptr sqlite3_stmt, i: cint, zData: cstring, n: cint, xDel: pointer): cint {.importc.}
  proc sqlite3_bind_int64(pStmt: ptr sqlite3_stmt, i: cint, v: int64): cint {.importc.}
  {.pop.}
  const SQLITE_ROW = 100
  var stmt: ptr sqlite3_stmt
  let sql = "SELECT sid, user, mtime, expire, ip FROM session WHERE sid=?1 AND expire>?2"
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) != 0:
    return err[Session](feNotFound, "session not found")
  discard sqlite3_bind_text(stmt, 1, sid.cstring, -1, nil)
  discard sqlite3_bind_int64(stmt, 2, getTime().toUnix())
  if sqlite3_step(stmt) != SQLITE_ROW:
    discard sqlite3_finalize(stmt)
    return err[Session](feNotFound, "session expired")
  let sidPtr = sqlite3_column_text(stmt, 0)
  let userPtr = sqlite3_column_text(stmt, 1)
  let mtime = sqlite3_column_int64(stmt, 2)
  let expire = sqlite3_column_int64(stmt, 3)
  let ipPtr = sqlite3_column_text(stmt, 4)
  let sidStr = if sidPtr!=nil: $sidPtr else: sid
  let user = if userPtr!=nil: $userPtr else: ""
  let ip = if ipPtr!=nil: $ipPtr else: ""
  discard sqlite3_finalize(stmt)
  ok(Session(id: sidStr, user: user, loginTime: mtime, expireTime: expire, ip: ip))

var gCsrfTokens* {.global.} = initTable[string, int64]()

proc generateCsrfToken*(): string =
  # SEC FIX CRY-01: Use CSPRNG for CSRF tokens as well
  var byteSeq = newSeq[byte](32)
  var ok = urandom(byteSeq)
  var bytes = newString(32)
  if ok:
    for i in 0..<32:
      bytes[i] = char(byteSeq[i])
  else:
    randomize()
    for i in 0..<32:
      bytes[i] = char(rand(255))
  var b64 = encode(bytes)
  # Pure URL-safe token: remove =, +, / so no percent encoding happens in forms
  b64 = b64.replace("+", "-").replace("/", "_").replace("=", "")
  let token = b64 & "_" & $getTime().toUnix()
  gCsrfTokens[token] = getTime().toUnix() + 3600
  token

proc validateCsrfToken*(token: string): bool =
  if token.len==0:
    return false
  let cleanToken = token.replace("%3D", "=").replace("%3d", "=").strip()
  let unpaddedToken = cleanToken.replace("=", "")
  let now = getTime().toUnix()
  for cand in [token, cleanToken, unpaddedToken]:
    if cand.len > 0 and gCsrfTokens.hasKey(cand):
      let exp = gCsrfTokens[cand]
      if exp > now:
        return true
      else:
        gCsrfTokens.del(cand)
  false

proc cleanupCsrfTokens*() =
  let now = getTime().toUnix()
  var toDel: seq[string] = @[]
  for k,v in gCsrfTokens:
    if v < now:
      toDel.add k
  for k in toDel:
    gCsrfTokens.del(k)

proc renderLoginPage*(error: string = "", redirect: string = ""): string =
  let csrf = generateCsrfToken()
  var html = """<html><head><meta charset="UTF-8"><title>Login - Fossil</title>
<link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>🦖</text></svg>">
<style>
body{font-family:sans-serif;background:#f8f9fa;display:flex;justify-content:center;align-items:center;min-height:100vh;margin:0}
.card{background:white;padding:40px;border-radius:8px;box-shadow:0 2px 10px rgba(0,0,0,0.1);width:100%;max-width:400px}
h1{text-align:center;margin-bottom:30px;color:#343a40}
input{width:100%;padding:12px;margin:8px 0;border:1px solid #ced4da;border-radius:4px;box-sizing:border-box}
button{width:100%;padding:12px;background:#007bff;color:white;border:none;border-radius:4px;cursor:pointer;font-size:16px;margin-top:10px}
button:hover{background:#0056b3}
.error{background:#f8d7da;color:#721c24;padding:10px;border-radius:4px;margin-bottom:15px;border:1px solid #f5c6cb}
a{color:#007bff;text-decoration:none}
a:hover{text-decoration:underline}
.footer{text-align:center;margin-top:20px;font-size:14px;color:#6c757d}
.csrf-note{font-size:11px;color:#6c757d;margin-top:8px;text-align:center}
</style></head><body>"""
  html.add "<div class='card'><h1>🔐 Login</h1>"
  if error.len>0:
    html.add "<div class='error'>" & error & "</div>"
  html.add "<form method='post' action='/login'>"
  html.add "<input type='hidden' name='csrf' value='" & csrf & "'>"
  if redirect.len>0:
    html.add "<input type='hidden' name='redirect' value='" & redirect & "'>"
  html.add "<input name='user' id='login-user' placeholder='Username' required autofocus>"
  html.add "<input name='password' id='login-pass' type='password' placeholder='Password' required>"
  html.add "<button type='submit'>Login</button>"
  html.add "</form><div class='csrf-note'>CSRF protection enabled • Token expires in 1h</div><div class='footer'><a href='/'>← Back to Home</a></div></div></body></html>"
  html

proc renderLoginSuccess*(session: Session, redirect: string = "/"): string =
  var html = """<html><head><meta charset="UTF-8"><title>Login Success - Fossil</title>
<link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>🦖</text></svg>">
<meta http-equiv='refresh' content='1;url=""" & redirect & """'>
<script>
  try {
    localStorage.setItem('fossil_user', '""" & session.user & """');
    localStorage.setItem('fossil_token', 'session-active');
  } catch(e) {}
  setTimeout(function() {
    window.location.href = '""" & redirect & """';
  }, 600);
</script>
<style>body{font-family:sans-serif;background:#f8f9fa;display:flex;justify-content:center;align-items:center;min-height:100vh;margin:0}
.card{background:white;padding:40px;border-radius:8px;box-shadow:0 2px 10px rgba(0,0,0,0.1);text-align:center}
.success{color:#28a745;font-size:48px;margin-bottom:20px}
</style></head><body>
<div class='card'><div class='success'>✓</div><h2>Welcome, """ & session.user & """!</h2><p>Redirecting to <a href='""" & redirect & """'>""" & redirect & """</a>...</p></div></body></html>"""
  html

proc renderLogoutPage*(): string =
  """<html><head><meta charset="UTF-8"><title>Logged Out - Fossil</title>
<link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>🦖</text></svg>">
<meta http-equiv='refresh' content='1;url=/'>
<script>
  try {
    localStorage.removeItem('fossil_user');
    localStorage.removeItem('fossil_token');
  } catch(e) {}
  setTimeout(function() {
    window.location.href = '/';
  }, 600);
</script>
<style>body{font-family:sans-serif;background:#f8f9fa;display:flex;justify-content:center;align-items:center;min-height:100vh;margin:0}
.card{background:white;padding:40px;border-radius:8px;box-shadow:0 2px 10px rgba(0,0,0,0.1);text-align:center}
</style></head><body><div class='card'><h2>Logged out</h2><p>Redirecting to <a href='/'>home</a>...</p></div></body></html>"""
