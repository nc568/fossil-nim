## Forum subsystem - real SQLite implementation

import ../types
import ../storage/backend
import ../storage/sqlite_backend
import ../utils/hash
import std/[times, strutils, tables, json, random]

type
  ForumPost* = object
    id*: string
    threadId*: string
    parentId*: string
    user*: string
    mtime*: int64
    content*: string
    title*: string
    uuid*: Uuid
    rid*: Rid
    edited*: bool
    deleted*: bool
    attachment*: string

  ForumThread* = object
    id*: string
    title*: string
    posts*: seq[ForumPost]
    created*: int64
    lastMtime*: int64
    user*: string
    pinned*: bool
    locked*: bool
    deleted*: bool

proc initForumSqlite*(backend: var SqliteBackend): FossilResult[bool] =
  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  {.pop.}
  let sqls = @[
    "CREATE TABLE IF NOT EXISTS forum_thread(thread_id TEXT PRIMARY KEY, title TEXT, user TEXT, created INTEGER, last_mtime INTEGER, pinned INTEGER DEFAULT 0, locked INTEGER DEFAULT 0, deleted INTEGER DEFAULT 0)",
    "CREATE TABLE IF NOT EXISTS forum_post(post_id TEXT PRIMARY KEY, thread_id TEXT, parent_id TEXT, user TEXT, mtime INTEGER, title TEXT, content TEXT, uuid TEXT, rid INTEGER, edited INTEGER DEFAULT 0, deleted INTEGER DEFAULT 0, attachment TEXT DEFAULT '')",
    "CREATE TABLE IF NOT EXISTS forum_moderation(queue_id TEXT PRIMARY KEY, post_id TEXT, thread_id TEXT, user TEXT, mtime INTEGER, reason TEXT, status TEXT DEFAULT 'pending')"
  ]
  for sql in sqls:
    var stmt: ptr sqlite3_stmt
    if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) == 0:
      discard sqlite3_step(stmt)
      discard sqlite3_finalize(stmt)
  # Try to add columns if table existed before without them
  let alters = @[
    "ALTER TABLE forum_thread ADD COLUMN pinned INTEGER DEFAULT 0",
    "ALTER TABLE forum_thread ADD COLUMN locked INTEGER DEFAULT 0",
    "ALTER TABLE forum_thread ADD COLUMN deleted INTEGER DEFAULT 0",
    "ALTER TABLE forum_post ADD COLUMN edited INTEGER DEFAULT 0",
    "ALTER TABLE forum_post ADD COLUMN deleted INTEGER DEFAULT 0",
    "ALTER TABLE forum_post ADD COLUMN attachment TEXT DEFAULT ''"
  ]
  for sql in alters:
    var stmt: ptr sqlite3_stmt
    if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) == 0:
      discard sqlite3_step(stmt)
      discard sqlite3_finalize(stmt)
  ok(true)

proc listThreadsSqlite*(backend: SqliteBackend, limit: int = 20): FossilResult[seq[ForumThread]] =
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
  var threads: seq[ForumThread] = @[]
  let sql = "SELECT thread_id, title, user, created, last_mtime, pinned, locked, deleted FROM forum_thread WHERE deleted=0 ORDER BY pinned DESC, last_mtime DESC LIMIT ?1"
  var stmt: ptr sqlite3_stmt
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) != 0:
    # Fallback without new columns
    let sqlFallback = "SELECT thread_id, title, user, created, last_mtime FROM forum_thread ORDER BY last_mtime DESC LIMIT ?1"
    if sqlite3_prepare_v2(backend.db, sqlFallback.cstring, -1, addr stmt, nil) != 0:
      return ok(threads)
    discard sqlite3_bind_int(stmt, 1, cint(limit))
    while sqlite3_step(stmt) == SQLITE_ROW:
      let idPtr = sqlite3_column_text(stmt, 0)
      let titlePtr = sqlite3_column_text(stmt, 1)
      let userPtr = sqlite3_column_text(stmt, 2)
      let created = sqlite3_column_int64(stmt, 3)
      let last = sqlite3_column_int64(stmt, 4)
      let id = if idPtr!=nil: $idPtr else: ""
      let title = if titlePtr!=nil: $titlePtr else: ""
      let user = if userPtr!=nil: $userPtr else: ""
      threads.add ForumThread(id: id, title: title, user: user, created: created, lastMtime: last)
    discard sqlite3_finalize(stmt)
    return ok(threads)
  discard sqlite3_bind_int(stmt, 1, cint(limit))
  while sqlite3_step(stmt) == SQLITE_ROW:
    let idPtr = sqlite3_column_text(stmt, 0)
    let titlePtr = sqlite3_column_text(stmt, 1)
    let userPtr = sqlite3_column_text(stmt, 2)
    let created = sqlite3_column_int64(stmt, 3)
    let last = sqlite3_column_int64(stmt, 4)
    let pinned = sqlite3_column_int64(stmt, 5)
    let locked = sqlite3_column_int64(stmt, 6)
    let deleted = sqlite3_column_int64(stmt, 7)
    let id = if idPtr!=nil: $idPtr else: ""
    let title = if titlePtr!=nil: $titlePtr else: ""
    let user = if userPtr!=nil: $userPtr else: ""
    threads.add ForumThread(id: id, title: title, user: user, created: created, lastMtime: last, pinned: pinned!=0, locked: locked!=0, deleted: deleted!=0)
  discard sqlite3_finalize(stmt)
  ok(threads)

proc getThreadSqlite*(backend: SqliteBackend, id: string): FossilResult[ForumThread] =
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
  var thread = ForumThread(id: id)
  let sqlThreadFull = "SELECT title, user, created, last_mtime, pinned, locked, deleted FROM forum_thread WHERE thread_id=?1"
  let sqlThreadSimple = "SELECT title, user, created, last_mtime FROM forum_thread WHERE thread_id=?1"
  var stmt: ptr sqlite3_stmt
  var useFullThread = true
  if sqlite3_prepare_v2(backend.db, sqlThreadFull.cstring, -1, addr stmt, nil) != 0:
    useFullThread = false
    if sqlite3_prepare_v2(backend.db, sqlThreadSimple.cstring, -1, addr stmt, nil) != 0:
      return err[ForumThread](feNotFound, "thread not found", id)
  discard sqlite3_bind_text(stmt, 1, id.cstring, -1, nil)
  if sqlite3_step(stmt) == SQLITE_ROW:
    let titlePtr = sqlite3_column_text(stmt, 0)
    let userPtr = sqlite3_column_text(stmt, 1)
    thread.created = sqlite3_column_int64(stmt, 2)
    thread.lastMtime = sqlite3_column_int64(stmt, 3)
    thread.title = if titlePtr!=nil: $titlePtr else: id
    thread.user = if userPtr!=nil: $userPtr else: ""
    thread.id = id
    if useFullThread:
      thread.pinned = sqlite3_column_int64(stmt, 4)!=0
      thread.locked = sqlite3_column_int64(stmt, 5)!=0
      thread.deleted = sqlite3_column_int64(stmt, 6)!=0
  discard sqlite3_finalize(stmt)

  # Get posts - try full with attachment/edited/deleted, fallback simple
  let sqlPostsFull = "SELECT post_id, thread_id, parent_id, user, mtime, title, content, attachment, edited, deleted FROM forum_post WHERE thread_id=?1 ORDER BY mtime ASC"
  let sqlPostsSimple = "SELECT post_id, thread_id, parent_id, user, mtime, title, content FROM forum_post WHERE thread_id=?1 ORDER BY mtime ASC"
  var useFullPosts = true
  var stmtPosts: ptr sqlite3_stmt
  if sqlite3_prepare_v2(backend.db, sqlPostsFull.cstring, -1, addr stmtPosts, nil) != 0:
    useFullPosts = false
    if sqlite3_prepare_v2(backend.db, sqlPostsSimple.cstring, -1, addr stmtPosts, nil) != 0:
      return ok(thread)
  discard sqlite3_bind_text(stmtPosts, 1, id.cstring, -1, nil)
  while sqlite3_step(stmtPosts) == SQLITE_ROW:
    let pidPtr = sqlite3_column_text(stmtPosts, 0)
    let tidPtr = sqlite3_column_text(stmtPosts, 1)
    let parentPtr = sqlite3_column_text(stmtPosts, 2)
    let userPtr = sqlite3_column_text(stmtPosts, 3)
    let mtime = sqlite3_column_int64(stmtPosts, 4)
    let titlePtr = sqlite3_column_text(stmtPosts, 5)
    let contentPtr = sqlite3_column_text(stmtPosts, 6)
    let pid = if pidPtr!=nil: $pidPtr else: ""
    let tid = if tidPtr!=nil: $tidPtr else: id
    let parent = if parentPtr!=nil: $parentPtr else: ""
    let user = if userPtr!=nil: $userPtr else: ""
    let title = if titlePtr!=nil: $titlePtr else: ""
    let content = if contentPtr!=nil: $contentPtr else: ""
    var attachment = ""
    var edited = false
    var deleted = false
    if useFullPosts:
      let attPtr = sqlite3_column_text(stmtPosts, 7)
      let editVal = sqlite3_column_int64(stmtPosts, 8)
      let delVal = sqlite3_column_int64(stmtPosts, 9)
      attachment = if attPtr!=nil: $attPtr else: ""
      edited = editVal!=0
      deleted = delVal!=0
    thread.posts.add ForumPost(id: pid, threadId: tid, parentId: parent, user: user, mtime: mtime, title: title, content: content, attachment: attachment, edited: edited, deleted: deleted)
  discard sqlite3_finalize(stmtPosts)
  ok(thread)

proc createThreadSqlite*(backend: var SqliteBackend, title: string, content: string, user: string): FossilResult[ForumThread] =
  if title.len==0 or content.len==0:
    return err[ForumThread](feInvalidArg, "title and content required")
  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_bind_text(pStmt: ptr sqlite3_stmt, i: cint, zData: cstring, n: cint, xDel: pointer): cint {.importc.}
  proc sqlite3_bind_int64(pStmt: ptr sqlite3_stmt, i: cint, v: int64): cint {.importc.}
  {.pop.}
  let threadId = $getTime().toUnix() & "_" & $rand(100000)
  let now = getTime().toUnix()
  var stmt: ptr sqlite3_stmt
  let sqlThread = "INSERT INTO forum_thread(thread_id, title, user, created, last_mtime) VALUES(?1, ?2, ?3, ?4, ?4)"
  if sqlite3_prepare_v2(backend.db, sqlThread.cstring, -1, addr stmt, nil) != 0:
    return err[ForumThread](feIoError, "cannot prepare thread insert")
  discard sqlite3_bind_text(stmt, 1, threadId.cstring, -1, nil)
  discard sqlite3_bind_text(stmt, 2, title.cstring, -1, nil)
  discard sqlite3_bind_text(stmt, 3, user.cstring, -1, nil)
  discard sqlite3_bind_int64(stmt, 4, now)
  discard sqlite3_step(stmt)
  discard sqlite3_finalize(stmt)

  let postId = threadId & "_1"
  let sqlPost = "INSERT INTO forum_post(post_id, thread_id, parent_id, user, mtime, title, content, uuid, rid) VALUES(?1, ?2, '', ?3, ?4, ?5, ?6, '', 0)"
  if sqlite3_prepare_v2(backend.db, sqlPost.cstring, -1, addr stmt, nil) == 0:
    discard sqlite3_bind_text(stmt, 1, postId.cstring, -1, nil)
    discard sqlite3_bind_text(stmt, 2, threadId.cstring, -1, nil)
    discard sqlite3_bind_text(stmt, 3, user.cstring, -1, nil)
    discard sqlite3_bind_int64(stmt, 4, now)
    discard sqlite3_bind_text(stmt, 5, title.cstring, -1, nil)
    discard sqlite3_bind_text(stmt, 6, content.cstring, -1, nil)
    discard sqlite3_step(stmt)
    discard sqlite3_finalize(stmt)

  # Auto-index forum thread for FTS5
  try:
    var stmtIdx: ptr sqlite3_stmt
    let sqlCreateFts = "CREATE VIRTUAL TABLE IF NOT EXISTS search_fts USING fts5(id, kind, title, content, tokenize='porter unicode61')"
    if sqlite3_prepare_v2(backend.db, sqlCreateFts.cstring, -1, addr stmtIdx, nil) == 0:
      discard sqlite3_step(stmtIdx)
      discard sqlite3_finalize(stmtIdx)
    let sqlCreateIdx = "CREATE TABLE IF NOT EXISTS search_index(id TEXT PRIMARY KEY, kind TEXT, title TEXT, content TEXT, mtime INTEGER)"
    if sqlite3_prepare_v2(backend.db, sqlCreateIdx.cstring, -1, addr stmtIdx, nil) == 0:
      discard sqlite3_step(stmtIdx)
      discard sqlite3_finalize(stmtIdx)
    let sqlIdx = "INSERT OR REPLACE INTO search_index(id, kind, title, content, mtime) VALUES(?1, 'forum', ?2, ?3, ?4)"
    if sqlite3_prepare_v2(backend.db, sqlIdx.cstring, -1, addr stmtIdx, nil) == 0:
      discard sqlite3_bind_text(stmtIdx, 1, threadId.cstring, -1, nil)
      discard sqlite3_bind_text(stmtIdx, 2, title.cstring, -1, nil)
      discard sqlite3_bind_text(stmtIdx, 3, content.cstring, -1, nil)
      discard sqlite3_bind_int64(stmtIdx, 4, now)
      discard sqlite3_step(stmtIdx)
      discard sqlite3_finalize(stmtIdx)
    let sqlDelFts = "DELETE FROM search_fts WHERE id=?1"
    if sqlite3_prepare_v2(backend.db, sqlDelFts.cstring, -1, addr stmtIdx, nil) == 0:
      discard sqlite3_bind_text(stmtIdx, 1, threadId.cstring, -1, nil)
      discard sqlite3_step(stmtIdx)
      discard sqlite3_finalize(stmtIdx)
    let sqlFts = "INSERT OR REPLACE INTO search_fts(id, kind, title, content) VALUES(?1, 'forum', ?2, ?3)"
    if sqlite3_prepare_v2(backend.db, sqlFts.cstring, -1, addr stmtIdx, nil) == 0:
      discard sqlite3_bind_text(stmtIdx, 1, threadId.cstring, -1, nil)
      discard sqlite3_bind_text(stmtIdx, 2, title.cstring, -1, nil)
      discard sqlite3_bind_text(stmtIdx, 3, content.cstring, -1, nil)
      discard sqlite3_step(stmtIdx)
      discard sqlite3_finalize(stmtIdx)
  except:
    discard

  ok(ForumThread(id: threadId, title: title, user: user, created: now, lastMtime: now, posts: @[ForumPost(id: postId, threadId: threadId, user: user, mtime: now, title: title, content: content)]))

proc createPostSqlite*(backend: var SqliteBackend, threadId: string, content: string, user: string, parentId: string = "", title: string = ""): FossilResult[ForumPost] =
  if content.len==0:
    return err[ForumPost](feInvalidArg, "empty content")
  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_bind_text(pStmt: ptr sqlite3_stmt, i: cint, zData: cstring, n: cint, xDel: pointer): cint {.importc.}
  proc sqlite3_bind_int64(pStmt: ptr sqlite3_stmt, i: cint, v: int64): cint {.importc.}
  {.pop.}
  let postId = $getTime().toUnix() & "_" & $rand(100000)
  let now = getTime().toUnix()
  var stmt: ptr sqlite3_stmt
  let sqlPost = "INSERT INTO forum_post(post_id, thread_id, parent_id, user, mtime, title, content, uuid, rid) VALUES(?1, ?2, ?3, ?4, ?5, ?6, ?7, '', 0)"
  if sqlite3_prepare_v2(backend.db, sqlPost.cstring, -1, addr stmt, nil) != 0:
    return err[ForumPost](feIoError, "cannot prepare post insert")
  discard sqlite3_bind_text(stmt, 1, postId.cstring, -1, nil)
  discard sqlite3_bind_text(stmt, 2, threadId.cstring, -1, nil)
  discard sqlite3_bind_text(stmt, 3, parentId.cstring, -1, nil)
  discard sqlite3_bind_text(stmt, 4, user.cstring, -1, nil)
  discard sqlite3_bind_int64(stmt, 5, now)
  discard sqlite3_bind_text(stmt, 6, title.cstring, -1, nil)
  discard sqlite3_bind_text(stmt, 7, content.cstring, -1, nil)
  discard sqlite3_step(stmt)
  discard sqlite3_finalize(stmt)

  # Update thread last_mtime
  let sqlUpd = "UPDATE forum_thread SET last_mtime=?1 WHERE thread_id=?2"
  if sqlite3_prepare_v2(backend.db, sqlUpd.cstring, -1, addr stmt, nil) == 0:
    discard sqlite3_bind_int64(stmt, 1, now)
    discard sqlite3_bind_text(stmt, 2, threadId.cstring, -1, nil)
    discard sqlite3_step(stmt)
    discard sqlite3_finalize(stmt)

  # Auto-index forum post for FTS5
  try:
    var stmtIdx: ptr sqlite3_stmt
    let sqlCreateFts = "CREATE VIRTUAL TABLE IF NOT EXISTS search_fts USING fts5(id, kind, title, content, tokenize='porter unicode61')"
    if sqlite3_prepare_v2(backend.db, sqlCreateFts.cstring, -1, addr stmtIdx, nil) == 0:
      discard sqlite3_step(stmtIdx)
      discard sqlite3_finalize(stmtIdx)
    let sqlCreateIdx = "CREATE TABLE IF NOT EXISTS search_index(id TEXT PRIMARY KEY, kind TEXT, title TEXT, content TEXT, mtime INTEGER)"
    if sqlite3_prepare_v2(backend.db, sqlCreateIdx.cstring, -1, addr stmtIdx, nil) == 0:
      discard sqlite3_step(stmtIdx)
      discard sqlite3_finalize(stmtIdx)
    let sqlIdx = "INSERT OR REPLACE INTO search_index(id, kind, title, content, mtime) VALUES(?1, 'forum', ?2, ?3, ?4)"
    if sqlite3_prepare_v2(backend.db, sqlIdx.cstring, -1, addr stmtIdx, nil) == 0:
      discard sqlite3_bind_text(stmtIdx, 1, postId.cstring, -1, nil)
      discard sqlite3_bind_text(stmtIdx, 2, title.cstring, -1, nil)
      discard sqlite3_bind_text(stmtIdx, 3, content.cstring, -1, nil)
      discard sqlite3_bind_int64(stmtIdx, 4, now)
      discard sqlite3_step(stmtIdx)
      discard sqlite3_finalize(stmtIdx)
    let sqlDelFts = "DELETE FROM search_fts WHERE id=?1"
    if sqlite3_prepare_v2(backend.db, sqlDelFts.cstring, -1, addr stmtIdx, nil) == 0:
      discard sqlite3_bind_text(stmtIdx, 1, postId.cstring, -1, nil)
      discard sqlite3_step(stmtIdx)
      discard sqlite3_finalize(stmtIdx)
    let sqlFts = "INSERT OR REPLACE INTO search_fts(id, kind, title, content) VALUES(?1, 'forum', ?2, ?3)"
    if sqlite3_prepare_v2(backend.db, sqlFts.cstring, -1, addr stmtIdx, nil) == 0:
      discard sqlite3_bind_text(stmtIdx, 1, postId.cstring, -1, nil)
      discard sqlite3_bind_text(stmtIdx, 2, title.cstring, -1, nil)
      discard sqlite3_bind_text(stmtIdx, 3, content.cstring, -1, nil)
      discard sqlite3_step(stmtIdx)
      discard sqlite3_finalize(stmtIdx)
  except:
    discard

  ok(ForumPost(id: postId, threadId: threadId, parentId: parentId, user: user, mtime: now, title: title, content: content))

# Generic wrappers
proc listThreads*[T: StorageBackend](backend: T, limit: int = 20): FossilResult[seq[ForumThread]] =
  when T is SqliteBackend:
    listThreadsSqlite(backend, limit)
  else:
    ok(@[])

proc getThread*[T: StorageBackend](backend: T, id: string): FossilResult[ForumThread] =
  when T is SqliteBackend:
    getThreadSqlite(backend, id)
  else:
    err[ForumThread](feNotFound, "thread not found", id)

proc createThread*[T: StorageBackend](backend: var T, title: string, content: string, user: string): FossilResult[ForumThread] =
  when T is SqliteBackend:
    createThreadSqlite(backend, title, content, user)
  else:
    if content.len==0: return err[ForumThread](feInvalidArg, "empty content")
    ok(ForumThread(id: "new", title: title, posts: @[ForumPost(id: "1", threadId: "new", content: content, user: user)]))

proc createPost*[T: StorageBackend](backend: var T, threadId: string, content: string, user: string, parentId: string = "", title: string = ""): FossilResult[ForumPost] =
  when T is SqliteBackend:
    createPostSqlite(backend, threadId, content, user, parentId, title)
  else:
    if content.len==0: return err[ForumPost](feInvalidArg, "empty content")
    ok(ForumPost(id: "new", threadId: threadId, content: content, user: user))

proc threadToJson*(thread: ForumThread): JsonNode =
  var postsArr = newJArray()
  for p in thread.posts:
    var obj = newJObject()
    obj["id"] = newJString(p.id)
    obj["threadId"] = newJString(p.threadId)
    obj["parentId"] = newJString(p.parentId)
    obj["user"] = newJString(p.user)
    obj["mtime"] = newJInt(p.mtime)
    obj["title"] = newJString(p.title)
    obj["content"] = newJString(p.content)
    obj["edited"] = newJBool(p.edited)
    obj["deleted"] = newJBool(p.deleted)
    obj["attachment"] = newJString(p.attachment)
    postsArr.add obj
  var res = newJObject()
  res["id"] = newJString(thread.id)
  res["title"] = newJString(thread.title)
  res["user"] = newJString(thread.user)
  res["created"] = newJInt(thread.created)
  res["lastMtime"] = newJInt(thread.lastMtime)
  res["pinned"] = newJBool(thread.pinned)
  res["locked"] = newJBool(thread.locked)
  res["deleted"] = newJBool(thread.deleted)
  res["posts"] = postsArr
  res

# --- Moderation, pinning, search within forum ---

proc pinThreadSqlite*(backend: var SqliteBackend, threadId: string, pinned: bool = true): FossilResult[bool] =
  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_bind_text(pStmt: ptr sqlite3_stmt, i: cint, zData: cstring, n: cint, xDel: pointer): cint {.importc.}
  proc sqlite3_bind_int(pStmt: ptr sqlite3_stmt, i: cint, v: cint): cint {.importc.}
  {.pop.}
  var stmt: ptr sqlite3_stmt
  let sql = "UPDATE forum_thread SET pinned=?1 WHERE thread_id=?2"
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) != 0:
    return err[bool](feIoError, "cannot prepare pin")
  discard sqlite3_bind_int(stmt, 1, cint(if pinned: 1 else: 0))
  discard sqlite3_bind_text(stmt, 2, threadId.cstring, -1, nil)
  discard sqlite3_step(stmt)
  discard sqlite3_finalize(stmt)
  ok(true)

proc lockThreadSqlite*(backend: var SqliteBackend, threadId: string, locked: bool = true): FossilResult[bool] =
  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_bind_text(pStmt: ptr sqlite3_stmt, i: cint, zData: cstring, n: cint, xDel: pointer): cint {.importc.}
  proc sqlite3_bind_int(pStmt: ptr sqlite3_stmt, i: cint, v: cint): cint {.importc.}
  {.pop.}
  var stmt: ptr sqlite3_stmt
  let sql = "UPDATE forum_thread SET locked=?1 WHERE thread_id=?2"
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) != 0:
    return err[bool](feIoError, "cannot prepare lock")
  discard sqlite3_bind_int(stmt, 1, cint(if locked: 1 else: 0))
  discard sqlite3_bind_text(stmt, 2, threadId.cstring, -1, nil)
  discard sqlite3_step(stmt)
  discard sqlite3_finalize(stmt)
  ok(true)

proc deleteThreadSqlite*(backend: var SqliteBackend, threadId: string): FossilResult[bool] =
  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_bind_text(pStmt: ptr sqlite3_stmt, i: cint, zData: cstring, n: cint, xDel: pointer): cint {.importc.}
  {.pop.}
  var stmt: ptr sqlite3_stmt
  let sql = "UPDATE forum_thread SET deleted=1 WHERE thread_id=?1"
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) != 0:
    return err[bool](feIoError, "cannot prepare delete")
  discard sqlite3_bind_text(stmt, 1, threadId.cstring, -1, nil)
  discard sqlite3_step(stmt)
  discard sqlite3_finalize(stmt)
  ok(true)

proc editPostSqlite*(backend: var SqliteBackend, postId: string, newContent: string): FossilResult[bool] =
  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_bind_text(pStmt: ptr sqlite3_stmt, i: cint, zData: cstring, n: cint, xDel: pointer): cint {.importc.}
  {.pop.}
  var stmt: ptr sqlite3_stmt
  let sql = "UPDATE forum_post SET content=?1, edited=1 WHERE post_id=?2"
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) != 0:
    return err[bool](feIoError, "cannot prepare edit")
  discard sqlite3_bind_text(stmt, 1, newContent.cstring, -1, nil)
  discard sqlite3_bind_text(stmt, 2, postId.cstring, -1, nil)
  discard sqlite3_step(stmt)
  discard sqlite3_finalize(stmt)
  ok(true)

proc listPinnedThreadsSqlite*(backend: SqliteBackend, limit: int = 20): FossilResult[seq[ForumThread]] =
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
  var threads: seq[ForumThread] = @[]
  var stmt: ptr sqlite3_stmt
  let sql = "SELECT thread_id, title, user, created, last_mtime, pinned, locked FROM forum_thread WHERE pinned=1 AND deleted=0 ORDER BY last_mtime DESC LIMIT ?1"
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) != 0:
    return ok(threads)
  discard sqlite3_bind_int(stmt, 1, cint(limit))
  while sqlite3_step(stmt) == SQLITE_ROW:
    let idPtr = sqlite3_column_text(stmt, 0)
    let titlePtr = sqlite3_column_text(stmt, 1)
    let userPtr = sqlite3_column_text(stmt, 2)
    let created = sqlite3_column_int64(stmt, 3)
    let last = sqlite3_column_int64(stmt, 4)
    let pinned = sqlite3_column_int64(stmt, 5)
    let locked = sqlite3_column_int64(stmt, 6)
    let id = if idPtr!=nil: $idPtr else: ""
    let title = if titlePtr!=nil: $titlePtr else: ""
    let user = if userPtr!=nil: $userPtr else: ""
    threads.add ForumThread(id: id, title: title, user: user, created: created, lastMtime: last, pinned: pinned!=0, locked: locked!=0)
  discard sqlite3_finalize(stmt)
  ok(threads)

proc searchForumSqlite*(backend: SqliteBackend, query: string, limit: int = 20): FossilResult[seq[ForumPost]] =
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
  var posts: seq[ForumPost] = @[]
  var stmt: ptr sqlite3_stmt
  # Use FTS5 if available, fallback to LIKE
  let sqlFts = "SELECT p.post_id, p.thread_id, p.parent_id, p.user, p.mtime, p.title, p.content FROM forum_post p JOIN search_fts f ON f.id=p.post_id WHERE search_fts MATCH ?1 AND f.kind='forum' LIMIT ?2"
  let sqlLike = "SELECT post_id, thread_id, parent_id, user, mtime, title, content FROM forum_post WHERE content LIKE ?1 OR title LIKE ?1 LIMIT ?2"
  var sql = sqlLike
  # Try FTS first
  if sqlite3_prepare_v2(backend.db, sqlFts.cstring, -1, addr stmt, nil) == 0:
    sql = sqlFts
    discard sqlite3_finalize(stmt)
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) != 0:
    return ok(posts)
  if sql==sqlFts:
    discard sqlite3_bind_text(stmt, 1, query.cstring, -1, nil)
    discard sqlite3_bind_int(stmt, 2, cint(limit))
  else:
    discard sqlite3_bind_text(stmt, 1, ("%" & query & "%").cstring, -1, nil)
    discard sqlite3_bind_int(stmt, 2, cint(limit))
  while sqlite3_step(stmt) == SQLITE_ROW:
    let pidPtr = sqlite3_column_text(stmt, 0)
    let tidPtr = sqlite3_column_text(stmt, 1)
    let parentPtr = sqlite3_column_text(stmt, 2)
    let userPtr = sqlite3_column_text(stmt, 3)
    let mtime = sqlite3_column_int64(stmt, 4)
    let titlePtr = sqlite3_column_text(stmt, 5)
    let contentPtr = sqlite3_column_text(stmt, 6)
    let pid = if pidPtr!=nil: $pidPtr else: ""
    let tid = if tidPtr!=nil: $tidPtr else: ""
    let parent = if parentPtr!=nil: $parentPtr else: ""
    let user = if userPtr!=nil: $userPtr else: ""
    let title = if titlePtr!=nil: $titlePtr else: ""
    let content = if contentPtr!=nil: $contentPtr else: ""
    posts.add ForumPost(id: pid, threadId: tid, parentId: parent, user: user, mtime: mtime, title: title, content: content)
  discard sqlite3_finalize(stmt)
  ok(posts)

# Generic wrappers for new procs
proc pinThread*[T: StorageBackend](backend: var T, threadId: string, pinned: bool = true): FossilResult[bool] =
  when T is SqliteBackend:
    pinThreadSqlite(backend, threadId, pinned)
  else:
    ok(true)

proc lockThread*[T: StorageBackend](backend: var T, threadId: string, locked: bool = true): FossilResult[bool] =
  when T is SqliteBackend:
    lockThreadSqlite(backend, threadId, locked)
  else:
    ok(true)

proc deleteThread*[T: StorageBackend](backend: var T, threadId: string): FossilResult[bool] =
  when T is SqliteBackend:
    deleteThreadSqlite(backend, threadId)
  else:
    ok(true)

proc editPost*[T: StorageBackend](backend: var T, postId: string, newContent: string): FossilResult[bool] =
  when T is SqliteBackend:
    editPostSqlite(backend, postId, newContent)
  else:
    ok(true)

proc listPinnedThreads*[T: StorageBackend](backend: T, limit: int = 20): FossilResult[seq[ForumThread]] =
  when T is SqliteBackend:
    listPinnedThreadsSqlite(backend, limit)
  else:
    ok(@[])

proc searchForum*[T: StorageBackend](backend: T, query: string, limit: int = 20): FossilResult[seq[ForumPost]] =
  when T is SqliteBackend:
    searchForumSqlite(backend, query, limit)
  else:
    ok(@[])

