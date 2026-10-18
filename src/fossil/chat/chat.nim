## Chat subsystem - real SQLite implementation

import ../types
import ../storage/backend
import ../storage/sqlite_backend
import std/[times, json, strutils, random]

type
  ChatMessage* = object
    id*: string
    room*: string
    user*: string
    mtime*: int64
    content*: string
    uuid*: Uuid
    rid*: Rid
    attachment*: string
    edited*: bool

  ChatRoom* = object
    room*: string
    owner*: string
    privateRoom*: bool
    created*: int64
    userCount*: int

  ChatPresence* = object
    user*: string
    room*: string
    lastSeen*: int64
    typing*: bool
    status*: string

proc initChatSqlite*(backend: var SqliteBackend): FossilResult[bool] =
  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  {.pop.}
  let sqls = @[
    "DROP INDEX IF EXISTS chat_room",
    "CREATE TABLE IF NOT EXISTS chat_message(msg_id TEXT PRIMARY KEY, room TEXT, user TEXT, mtime INTEGER, content TEXT, uuid TEXT, rid INTEGER, attachment TEXT DEFAULT '', edited INTEGER DEFAULT 0)",
    "CREATE INDEX IF NOT EXISTS idx_chat_message_room ON chat_message(room)",
    "CREATE TABLE IF NOT EXISTS chat_room(room TEXT PRIMARY KEY, owner TEXT, is_private INTEGER DEFAULT 0, created INTEGER)",
    "CREATE TABLE IF NOT EXISTS chat_presence(user TEXT, room TEXT, last_seen INTEGER, typing INTEGER DEFAULT 0, status TEXT DEFAULT 'online', PRIMARY KEY(user, room))",
    "INSERT OR IGNORE INTO chat_room(room, owner, is_private, created) VALUES('main', 'system', 0, strftime('%s','now'))"
  ]
  for sql in sqls:
    var stmt: ptr sqlite3_stmt
    if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) == 0:
      discard sqlite3_step(stmt)
      discard sqlite3_finalize(stmt)
  # Alter for existing tables
  let alters = @[
    "ALTER TABLE chat_message ADD COLUMN attachment TEXT DEFAULT ''",
    "ALTER TABLE chat_message ADD COLUMN edited INTEGER DEFAULT 0"
  ]
  for sql in alters:
    var stmt: ptr sqlite3_stmt
    if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) == 0:
      discard sqlite3_step(stmt)
      discard sqlite3_finalize(stmt)
  ok(true)

proc listMessagesSqlite*(backend: SqliteBackend, room: string = "main", limit: int = 50): FossilResult[seq[ChatMessage]] =
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
  var msgs: seq[ChatMessage] = @[]
  # Try with attachment and edited columns, fallback without
  let sqlFull = "SELECT msg_id, room, user, mtime, content, attachment, edited FROM chat_message WHERE room=?1 ORDER BY mtime DESC LIMIT ?2"
  let sqlSimple = "SELECT msg_id, room, user, mtime, content FROM chat_message WHERE room=?1 ORDER BY mtime DESC LIMIT ?2"
  var stmt: ptr sqlite3_stmt
  var useFull = true
  if sqlite3_prepare_v2(backend.db, sqlFull.cstring, -1, addr stmt, nil) != 0:
    useFull = false
    if sqlite3_prepare_v2(backend.db, sqlSimple.cstring, -1, addr stmt, nil) != 0:
      return ok(msgs)
  discard sqlite3_bind_text(stmt, 1, room.cstring, -1, nil)
  discard sqlite3_bind_int(stmt, 2, cint(limit))
  while sqlite3_step(stmt) == SQLITE_ROW:
    let idPtr = sqlite3_column_text(stmt, 0)
    let roomPtr = sqlite3_column_text(stmt, 1)
    let userPtr = sqlite3_column_text(stmt, 2)
    let mtime = sqlite3_column_int64(stmt, 3)
    let contentPtr = sqlite3_column_text(stmt, 4)
    let id = if idPtr!=nil: $idPtr else: ""
    let rm = if roomPtr!=nil: $roomPtr else: room
    let user = if userPtr!=nil: $userPtr else: ""
    let content = if contentPtr!=nil: $contentPtr else: ""
    var attachment = ""
    var edited = false
    if useFull:
      let attPtr = sqlite3_column_text(stmt, 5)
      let editVal = sqlite3_column_int64(stmt, 6)
      attachment = if attPtr!=nil: $attPtr else: ""
      edited = editVal!=0
    msgs.add ChatMessage(id: id, room: rm, user: user, mtime: mtime, content: content, attachment: attachment, edited: edited)
  discard sqlite3_finalize(stmt)
  ok(msgs)

proc sendMessageSqlite*(backend: var SqliteBackend, room: string, content: string, user: string): FossilResult[ChatMessage] =
  if content.len==0:
    return err[ChatMessage](feInvalidArg, "empty content")
  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_bind_text(pStmt: ptr sqlite3_stmt, i: cint, zData: cstring, n: cint, xDel: pointer): cint {.importc.}
  proc sqlite3_bind_int64(pStmt: ptr sqlite3_stmt, i: cint, v: int64): cint {.importc.}
  {.pop.}
  let msgId = $getTime().toUnix() & "_" & $rand(100000)
  let now = getTime().toUnix()
  var stmt: ptr sqlite3_stmt
  let sql = "INSERT INTO chat_message(msg_id, room, user, mtime, content, uuid, rid) VALUES(?1, ?2, ?3, ?4, ?5, '', 0)"
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) != 0:
    return err[ChatMessage](feIoError, "cannot prepare chat insert")
  discard sqlite3_bind_text(stmt, 1, msgId.cstring, -1, nil)
  discard sqlite3_bind_text(stmt, 2, room.cstring, -1, nil)
  discard sqlite3_bind_text(stmt, 3, user.cstring, -1, nil)
  discard sqlite3_bind_int64(stmt, 4, now)
  discard sqlite3_bind_text(stmt, 5, content.cstring, -1, nil)
  discard sqlite3_step(stmt)
  discard sqlite3_finalize(stmt)
  # Auto-index chat for FTS5
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
    let sqlIdx = "INSERT OR REPLACE INTO search_index(id, kind, title, content, mtime) VALUES(?1, 'chat', ?2, ?3, ?4)"
    if sqlite3_prepare_v2(backend.db, sqlIdx.cstring, -1, addr stmtIdx, nil) == 0:
      discard sqlite3_bind_text(stmtIdx, 1, msgId.cstring, -1, nil)
      discard sqlite3_bind_text(stmtIdx, 2, room.cstring, -1, nil)
      discard sqlite3_bind_text(stmtIdx, 3, content.cstring, -1, nil)
      discard sqlite3_bind_int64(stmtIdx, 4, now)
      discard sqlite3_step(stmtIdx)
      discard sqlite3_finalize(stmtIdx)
    let sqlDelFts = "DELETE FROM search_fts WHERE id=?1"
    if sqlite3_prepare_v2(backend.db, sqlDelFts.cstring, -1, addr stmtIdx, nil) == 0:
      discard sqlite3_bind_text(stmtIdx, 1, msgId.cstring, -1, nil)
      discard sqlite3_step(stmtIdx)
      discard sqlite3_finalize(stmtIdx)
    let sqlFts = "INSERT OR REPLACE INTO search_fts(id, kind, title, content) VALUES(?1, 'chat', ?2, ?3)"
    if sqlite3_prepare_v2(backend.db, sqlFts.cstring, -1, addr stmtIdx, nil) == 0:
      discard sqlite3_bind_text(stmtIdx, 1, msgId.cstring, -1, nil)
      discard sqlite3_bind_text(stmtIdx, 2, room.cstring, -1, nil)
      discard sqlite3_bind_text(stmtIdx, 3, content.cstring, -1, nil)
      discard sqlite3_step(stmtIdx)
      discard sqlite3_finalize(stmtIdx)
  except:
    discard
  ok(ChatMessage(id: msgId, room: room, user: user, mtime: now, content: content))

proc listMessages*[T: StorageBackend](backend: T, room: string = "main", limit: int = 50): FossilResult[seq[ChatMessage]] =
  when T is SqliteBackend:
    listMessagesSqlite(backend, room, limit)
  else:
    ok(@[])

proc sendMessage*[T: StorageBackend](backend: var T, room: string, content: string, user: string): FossilResult[ChatMessage] =
  when T is SqliteBackend:
    sendMessageSqlite(backend, room, content, user)
  else:
    if content.len==0: return err[ChatMessage](feInvalidArg, "empty content")
    ok(ChatMessage(id: "new", room: room, user: user, mtime: getTime().toUnix(), content: content))

proc chatToJson*(msg: ChatMessage): JsonNode =
  %* {"id": msg.id, "room": msg.room, "user": msg.user, "mtime": msg.mtime, "content": msg.content, "attachment": msg.attachment, "edited": msg.edited}

proc createRoomSqlite*(backend: var SqliteBackend, room: string, owner: string, privateRoom: bool = false): FossilResult[ChatRoom] =
  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_bind_text(pStmt: ptr sqlite3_stmt, i: cint, zData: cstring, n: cint, xDel: pointer): cint {.importc.}
  proc sqlite3_bind_int(pStmt: ptr sqlite3_stmt, i: cint, v: cint): cint {.importc.}
  proc sqlite3_bind_int64(pStmt: ptr sqlite3_stmt, i: cint, v: int64): cint {.importc.}
  {.pop.}
  if room.len==0: return err[ChatRoom](feInvalidArg, "room name required")
  let now = getTime().toUnix()
  var stmt: ptr sqlite3_stmt
  let sql = "INSERT OR REPLACE INTO chat_room(room, owner, is_private, created) VALUES(?1, ?2, ?3, ?4)"
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) != 0:
    return err[ChatRoom](feIoError, "cannot prepare room insert")
  discard sqlite3_bind_text(stmt, 1, room.cstring, -1, nil)
  discard sqlite3_bind_text(stmt, 2, owner.cstring, -1, nil)
  discard sqlite3_bind_int(stmt, 3, cint(if privateRoom: 1 else: 0))
  discard sqlite3_bind_int64(stmt, 4, now)
  discard sqlite3_step(stmt)
  discard sqlite3_finalize(stmt)
  ok(ChatRoom(room: room, owner: owner, privateRoom: privateRoom, created: now))

proc listRoomsSqlite*(backend: SqliteBackend): FossilResult[seq[ChatRoom]] =
  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_column_text(pStmt: ptr sqlite3_stmt, iCol: cint): cstring {.importc.}
  proc sqlite3_column_int64(pStmt: ptr sqlite3_stmt, iCol: cint): int64 {.importc.}
  {.pop.}
  const SQLITE_ROW = 100
  var rooms: seq[ChatRoom] = @[]
  var stmt: ptr sqlite3_stmt
  let sql = "SELECT room, owner, is_private, created FROM chat_room ORDER BY room"
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) != 0:
    return ok(rooms)
  while sqlite3_step(stmt) == SQLITE_ROW:
    let roomPtr = sqlite3_column_text(stmt, 0)
    let ownerPtr = sqlite3_column_text(stmt, 1)
    let priv = sqlite3_column_int64(stmt, 2)
    let created = sqlite3_column_int64(stmt, 3)
    let room = if roomPtr!=nil: $roomPtr else: ""
    let owner = if ownerPtr!=nil: $ownerPtr else: ""
    rooms.add ChatRoom(room: room, owner: owner, privateRoom: priv!=0, created: created)
  discard sqlite3_finalize(stmt)
  ok(rooms)

proc updatePresenceSqlite*(backend: var SqliteBackend, user: string, room: string, typing: bool = false, status: string = "online"): FossilResult[ChatPresence] =
  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_bind_text(pStmt: ptr sqlite3_stmt, i: cint, zData: cstring, n: cint, xDel: pointer): cint {.importc.}
  proc sqlite3_bind_int(pStmt: ptr sqlite3_stmt, i: cint, v: cint): cint {.importc.}
  proc sqlite3_bind_int64(pStmt: ptr sqlite3_stmt, i: cint, v: int64): cint {.importc.}
  {.pop.}
  let now = getTime().toUnix()
  var stmt: ptr sqlite3_stmt
  let sql = "INSERT OR REPLACE INTO chat_presence(user, room, last_seen, typing, status) VALUES(?1, ?2, ?3, ?4, ?5)"
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) != 0:
    return err[ChatPresence](feIoError, "cannot prepare presence")
  discard sqlite3_bind_text(stmt, 1, user.cstring, -1, nil)
  discard sqlite3_bind_text(stmt, 2, room.cstring, -1, nil)
  discard sqlite3_bind_int64(stmt, 3, now)
  discard sqlite3_bind_int(stmt, 4, cint(if typing: 1 else: 0))
  discard sqlite3_bind_text(stmt, 5, status.cstring, -1, nil)
  discard sqlite3_step(stmt)
  discard sqlite3_finalize(stmt)
  ok(ChatPresence(user: user, room: room, lastSeen: now, typing: typing, status: status))

proc listPresenceSqlite*(backend: SqliteBackend, room: string = "main"): FossilResult[seq[ChatPresence]] =
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
  var pres: seq[ChatPresence] = @[]
  var stmt: ptr sqlite3_stmt
  let sql = "SELECT user, room, last_seen, typing, status FROM chat_presence WHERE room=?1 AND last_seen>?2 ORDER BY last_seen DESC"
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) != 0:
    return ok(pres)
  discard sqlite3_bind_text(stmt, 1, room.cstring, -1, nil)
  {.push header: "<sqlite3.h>".}
  proc sqlite3_bind_int64(pStmt: ptr sqlite3_stmt, i: cint, v: int64): cint {.importc.}
  {.pop.}
  discard sqlite3_bind_int64(stmt, 2, getTime().toUnix() - 300) # last 5 min
  while sqlite3_step(stmt) == SQLITE_ROW:
    let userPtr = sqlite3_column_text(stmt, 0)
    let roomPtr = sqlite3_column_text(stmt, 1)
    let last = sqlite3_column_int64(stmt, 2)
    let typing = sqlite3_column_int64(stmt, 3)
    let statusPtr = sqlite3_column_text(stmt, 4)
    let user = if userPtr!=nil: $userPtr else: ""
    let rm = if roomPtr!=nil: $roomPtr else: room
    let status = if statusPtr!=nil: $statusPtr else: "online"
    pres.add ChatPresence(user: user, room: rm, lastSeen: last, typing: typing!=0, status: status)
  discard sqlite3_finalize(stmt)
  ok(pres)

# Generic wrappers
proc createRoom*[T: StorageBackend](backend: var T, room: string, owner: string, privateRoom: bool = false): FossilResult[ChatRoom] =
  when T is SqliteBackend:
    createRoomSqlite(backend, room, owner, privateRoom)
  else:
    ok(ChatRoom(room: room, owner: owner))

proc listRooms*[T: StorageBackend](backend: T): FossilResult[seq[ChatRoom]] =
  when T is SqliteBackend:
    listRoomsSqlite(backend)
  else:
    ok(@[ChatRoom(room: "main", owner: "system")])

proc updatePresence*[T: StorageBackend](backend: var T, user: string, room: string, typing: bool = false, status: string = "online"): FossilResult[ChatPresence] =
  when T is SqliteBackend:
    updatePresenceSqlite(backend, user, room, typing, status)
  else:
    ok(ChatPresence(user: user, room: room, lastSeen: getTime().toUnix(), typing: typing, status: status))

proc listPresence*[T: StorageBackend](backend: T, room: string = "main"): FossilResult[seq[ChatPresence]] =
  when T is SqliteBackend:
    listPresenceSqlite(backend, room)
  else:
    ok(@[])

# --- Enhanced chat: edit, delete, attachments, reactions ---

proc editMessageSqlite*(backend: var SqliteBackend, msgId: string, newContent: string): FossilResult[bool] =
  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_bind_text(pStmt: ptr sqlite3_stmt, i: cint, zData: cstring, n: cint, xDel: pointer): cint {.importc.}
  {.pop.}
  var stmt: ptr sqlite3_stmt
  let sql = "UPDATE chat_message SET content=?1, edited=1 WHERE msg_id=?2"
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) != 0:
    return err[bool](feIoError, "cannot prepare edit")
  discard sqlite3_bind_text(stmt, 1, newContent.cstring, -1, nil)
  discard sqlite3_bind_text(stmt, 2, msgId.cstring, -1, nil)
  discard sqlite3_step(stmt)
  discard sqlite3_finalize(stmt)
  ok(true)

proc deleteMessageSqlite*(backend: var SqliteBackend, msgId: string): FossilResult[bool] =
  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_bind_text(pStmt: ptr sqlite3_stmt, i: cint, zData: cstring, n: cint, xDel: pointer): cint {.importc.}
  {.pop.}
  var stmt: ptr sqlite3_stmt
  let sql = "DELETE FROM chat_message WHERE msg_id=?1"
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) != 0:
    return err[bool](feIoError, "cannot prepare delete")
  discard sqlite3_bind_text(stmt, 1, msgId.cstring, -1, nil)
  discard sqlite3_step(stmt)
  discard sqlite3_finalize(stmt)
  ok(true)

proc addAttachmentSqlite*(backend: var SqliteBackend, msgId: string, attachmentUrl: string): FossilResult[bool] =
  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_bind_text(pStmt: ptr sqlite3_stmt, i: cint, zData: cstring, n: cint, xDel: pointer): cint {.importc.}
  {.pop.}
  var stmt: ptr sqlite3_stmt
  let sql = "UPDATE chat_message SET attachment=?1 WHERE msg_id=?2"
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) != 0:
    return err[bool](feIoError, "cannot prepare attachment")
  discard sqlite3_bind_text(stmt, 1, attachmentUrl.cstring, -1, nil)
  discard sqlite3_bind_text(stmt, 2, msgId.cstring, -1, nil)
  discard sqlite3_step(stmt)
  discard sqlite3_finalize(stmt)
  ok(true)

proc sendMessageWithAttachmentSqlite*(backend: var SqliteBackend, room: string, content: string, user: string, attachment: string = ""): FossilResult[ChatMessage] =
  if content.len==0 and attachment.len==0:
    return err[ChatMessage](feInvalidArg, "empty content and attachment")
  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_bind_text(pStmt: ptr sqlite3_stmt, i: cint, zData: cstring, n: cint, xDel: pointer): cint {.importc.}
  proc sqlite3_bind_int64(pStmt: ptr sqlite3_stmt, i: cint, v: int64): cint {.importc.}
  {.pop.}
  let msgId = $getTime().toUnix() & "_" & $rand(100000)
  let now = getTime().toUnix()
  var stmt: ptr sqlite3_stmt
  let sql = "INSERT INTO chat_message(msg_id, room, user, mtime, content, uuid, rid, attachment) VALUES(?1, ?2, ?3, ?4, ?5, '', 0, ?6)"
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) != 0:
    return err[ChatMessage](feIoError, "cannot prepare chat insert")
  discard sqlite3_bind_text(stmt, 1, msgId.cstring, -1, nil)
  discard sqlite3_bind_text(stmt, 2, room.cstring, -1, nil)
  discard sqlite3_bind_text(stmt, 3, user.cstring, -1, nil)
  discard sqlite3_bind_int64(stmt, 4, now)
  discard sqlite3_bind_text(stmt, 5, content.cstring, -1, nil)
  discard sqlite3_bind_text(stmt, 6, attachment.cstring, -1, nil)
  discard sqlite3_step(stmt)
  discard sqlite3_finalize(stmt)
  # Auto-index chat for FTS5
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
    let sqlIdx = "INSERT OR REPLACE INTO search_index(id, kind, title, content, mtime) VALUES(?1, 'chat', ?2, ?3, ?4)"
    if sqlite3_prepare_v2(backend.db, sqlIdx.cstring, -1, addr stmtIdx, nil) == 0:
      discard sqlite3_bind_text(stmtIdx, 1, msgId.cstring, -1, nil)
      discard sqlite3_bind_text(stmtIdx, 2, room.cstring, -1, nil)
      discard sqlite3_bind_text(stmtIdx, 3, content.cstring, -1, nil)
      discard sqlite3_bind_int64(stmtIdx, 4, now)
      discard sqlite3_step(stmtIdx)
      discard sqlite3_finalize(stmtIdx)
    let sqlDelFts = "DELETE FROM search_fts WHERE id=?1"
    if sqlite3_prepare_v2(backend.db, sqlDelFts.cstring, -1, addr stmtIdx, nil) == 0:
      discard sqlite3_bind_text(stmtIdx, 1, msgId.cstring, -1, nil)
      discard sqlite3_step(stmtIdx)
      discard sqlite3_finalize(stmtIdx)
    let sqlFts = "INSERT OR REPLACE INTO search_fts(id, kind, title, content) VALUES(?1, 'chat', ?2, ?3)"
    if sqlite3_prepare_v2(backend.db, sqlFts.cstring, -1, addr stmtIdx, nil) == 0:
      discard sqlite3_bind_text(stmtIdx, 1, msgId.cstring, -1, nil)
      discard sqlite3_bind_text(stmtIdx, 2, room.cstring, -1, nil)
      discard sqlite3_bind_text(stmtIdx, 3, content.cstring, -1, nil)
      discard sqlite3_step(stmtIdx)
      discard sqlite3_finalize(stmtIdx)
  except:
    discard
  ok(ChatMessage(id: msgId, room: room, user: user, mtime: now, content: content, attachment: attachment))

proc deleteRoomSqlite*(backend: var SqliteBackend, room: string): FossilResult[bool] =
  if room=="main":
    return err[bool](feInvalidArg, "cannot delete main room")
  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_bind_text(pStmt: ptr sqlite3_stmt, i: cint, zData: cstring, n: cint, xDel: pointer): cint {.importc.}
  {.pop.}
  var stmt: ptr sqlite3_stmt
  let sql = "DELETE FROM chat_room WHERE room=?1"
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) != 0:
    return err[bool](feIoError, "cannot prepare delete room")
  discard sqlite3_bind_text(stmt, 1, room.cstring, -1, nil)
  discard sqlite3_step(stmt)
  discard sqlite3_finalize(stmt)
  ok(true)

# Generic wrappers for enhanced chat
proc editMessage*[T: StorageBackend](backend: var T, msgId: string, newContent: string): FossilResult[bool] =
  when T is SqliteBackend:
    editMessageSqlite(backend, msgId, newContent)
  else:
    ok(true)

proc deleteMessage*[T: StorageBackend](backend: var T, msgId: string): FossilResult[bool] =
  when T is SqliteBackend:
    deleteMessageSqlite(backend, msgId)
  else:
    ok(true)

proc addAttachment*[T: StorageBackend](backend: var T, msgId: string, attachmentUrl: string): FossilResult[bool] =
  when T is SqliteBackend:
    addAttachmentSqlite(backend, msgId, attachmentUrl)
  else:
    ok(true)

proc sendMessageWithAttachment*[T: StorageBackend](backend: var T, room: string, content: string, user: string, attachment: string = ""): FossilResult[ChatMessage] =
  when T is SqliteBackend:
    sendMessageWithAttachmentSqlite(backend, room, content, user, attachment)
  else:
    ok(ChatMessage(id: "new", room: room, user: user, mtime: getTime().toUnix(), content: content, attachment: attachment))

proc deleteRoom*[T: StorageBackend](backend: var T, room: string): FossilResult[bool] =
  when T is SqliteBackend:
    deleteRoomSqlite(backend, room)
  else:
    ok(true)
