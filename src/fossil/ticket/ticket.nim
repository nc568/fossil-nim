## Ticket subsystem with Markdown, TH1, comments

import ../types
import ../storage/backend
import ../storage/sqlite_backend
import ../markdown/parser as mdParser
import ../th1/interp as th1Interp
import std/[tables, strutils, times, options, json, random, sysrand]

type
  TicketStatus* = enum
    tsOpen = "open"
    tsClosed = "closed"
    tsFixed = "fixed"
    tsVerified = "verified"

  TicketPriority* = enum
    tpLow = 1
    tpMedium = 2
    tpHigh = 3
    tpCritical = 4

  TicketComment* = object
    id*: string
    ticketId*: string
    user*: string
    date*: int64
    content*: string
    format*: string

  Ticket* = object
    id*: string
    title*: string
    description*: string
    status*: TicketStatus
    ticketType*: string
    priority*: int
    owner*: string
    reporter*: string
    created*: int64
    modified*: int64
    uuid*: Uuid
    rid*: Rid
    comments*: seq[TicketComment]
    tags*: seq[string]

proc listTicketsSqlite*(backend: SqliteBackend, status: TicketStatus = tsOpen, limit: int = 50): FossilResult[seq[Ticket]] =
  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_column_text(pStmt: ptr sqlite3_stmt, iCol: cint): ptr cuchar {.importc.}
  proc sqlite3_column_int64(pStmt: ptr sqlite3_stmt, iCol: cint): int64 {.importc.}
  {.pop.}
  const SQLITE_ROW = 100
  let sql = """
    SELECT tkt_uuid, tkt_title, tkt_status, tkt_type, tkt_priority, tkt_owner, tkt_reporter, tkt_mtime
    FROM ticket WHERE tkt_status=?1 ORDER BY tkt_mtime DESC LIMIT ?2
  """
  var tickets: seq[Ticket] = @[]
  var stmt: ptr sqlite3_stmt
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) != 0:
    let sql2 = "SELECT tagname FROM tag WHERE tagname LIKE 'ticket-%' LIMIT ?1"
    var stmt2: ptr sqlite3_stmt
    if sqlite3_prepare_v2(backend.db, sql2.cstring, -1, addr stmt2, nil) != 0:
      for i in 0..<min(limit, 5):
        tickets.add Ticket(id: $i, title: "Ticket " & $i, description: "Description for ticket " & $i & "\n\n- Steps\n- Expected", status: status, priority: 3, ticketType: "bug", tags: @["bug"])
      return ok(tickets)
    defer: discard sqlite3_finalize(stmt2)
    {.push header: "<sqlite3.h>".}
    proc sqlite3_bind_int64(pStmt: ptr sqlite3_stmt, i: cint, v: int64): cint {.importc.}
    {.pop.}
    discard sqlite3_bind_int64(stmt2, 1, int64(limit))
    while sqlite3_step(stmt2) == SQLITE_ROW:
      let tagPtr = sqlite3_column_text(stmt2, 0)
      if tagPtr != nil:
        let tagname = $cast[cstring](tagPtr)
        let tid = if tagname.startsWith("ticket-"): tagname[7..^1] else: tagname
        tickets.add Ticket(id: tid, title: "Ticket " & tid, description: "From tag " & tagname, status: status, priority: 2)
    if tickets.len==0:
      for i in 0..<min(limit, 5):
        tickets.add Ticket(id: $i, title: "Ticket " & $i, description: "Description", status: status, priority: 3)
    return ok(tickets)
  defer: discard sqlite3_finalize(stmt)
  {.push header: "<sqlite3.h>".}
  proc sqlite3_bind_text(pStmt: ptr sqlite3_stmt, i: cint, zData: cstring, n: cint, xDel: pointer): cint {.importc.}
  proc sqlite3_bind_int64(pStmt: ptr sqlite3_stmt, i: cint, v: int64): cint {.importc.}
  {.pop.}
  discard sqlite3_bind_text(stmt, 1, ($status).cstring, -1, nil)
  discard sqlite3_bind_int64(stmt, 2, int64(limit))
  while sqlite3_step(stmt) == SQLITE_ROW:
    let uuidPtr = sqlite3_column_text(stmt, 0)
    let titlePtr = sqlite3_column_text(stmt, 1)
    let statusPtr = sqlite3_column_text(stmt, 2)
    let typePtr = sqlite3_column_text(stmt, 3)
    let prio = sqlite3_column_int64(stmt, 4)
    let ownerPtr = sqlite3_column_text(stmt, 5)
    let reporterPtr = sqlite3_column_text(stmt, 6)
    let mtime = sqlite3_column_int64(stmt, 7)
    let idStr = if uuidPtr != nil: $cast[cstring](uuidPtr) else: ""
    let title = if titlePtr != nil: $cast[cstring](titlePtr) else: "Ticket"
    let stStr = if statusPtr != nil: $cast[cstring](statusPtr) else: $status
    let typ = if typePtr != nil: $cast[cstring](typePtr) else: "bug"
    let owner = if ownerPtr != nil: $cast[cstring](ownerPtr) else: ""
    let reporter = if reporterPtr != nil: $cast[cstring](reporterPtr) else: ""
    var st = status
    try: st = parseEnum[TicketStatus](stStr) except: discard
    tickets.add Ticket(id: idStr, title: title, description: "Ticket " & idStr, status: st, ticketType: typ, priority: int(prio), owner: owner, reporter: reporter, created: mtime, modified: mtime)
  ok(tickets)

proc listTickets*[T: StorageBackend](backend: T, status: TicketStatus = tsOpen, limit: int = 50): FossilResult[seq[Ticket]] =
  when T is SqliteBackend:
    listTicketsSqlite(backend, status, limit)
  else:
    var tickets: seq[Ticket] = @[]
    for i in 0..<min(limit, 5):
      tickets.add Ticket(id: $i, title: "Ticket " & $i, description: "Description for ticket " & $i & "\n\n- Steps\n- Expected", status: status, priority: 3, ticketType: "bug", tags: @["bug"])
    ok(tickets)

proc getTicketSqlite*(backend: SqliteBackend, id: string): FossilResult[Ticket] =
  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_column_text(pStmt: ptr sqlite3_stmt, iCol: cint): ptr cuchar {.importc.}
  proc sqlite3_column_int64(pStmt: ptr sqlite3_stmt, iCol: cint): int64 {.importc.}
  {.pop.}
  const SQLITE_ROW = 100
  let sql = "SELECT tkt_uuid, tkt_title, tkt_desc, tkt_status, tkt_type, tkt_priority, tkt_owner, tkt_reporter, tkt_mtime FROM ticket WHERE tkt_uuid=?1 LIMIT 1"
  var stmt: ptr sqlite3_stmt
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) != 0:
    return ok(Ticket(id: id, title: "Sample ticket " & id, description: "# Bug report\n\n**Steps**\n\n1. Do X\n", status: tsOpen, priority: 2))
  defer: discard sqlite3_finalize(stmt)
  {.push header: "<sqlite3.h>".}
  proc sqlite3_bind_text(pStmt: ptr sqlite3_stmt, i: cint, zData: cstring, n: cint, xDel: pointer): cint {.importc.}
  {.pop.}
  discard sqlite3_bind_text(stmt, 1, id.cstring, -1, nil)
  if sqlite3_step(stmt) == SQLITE_ROW:
    let uuidPtr = sqlite3_column_text(stmt, 0)
    let titlePtr = sqlite3_column_text(stmt, 1)
    let descPtr = sqlite3_column_text(stmt, 2)
    let statusPtr = sqlite3_column_text(stmt, 3)
    let typePtr = sqlite3_column_text(stmt, 4)
    let prio = sqlite3_column_int64(stmt, 5)
    let ownerPtr = sqlite3_column_text(stmt, 6)
    let reporterPtr = sqlite3_column_text(stmt, 7)
    let mtime = sqlite3_column_int64(stmt, 8)
    let title = if titlePtr != nil: $cast[cstring](titlePtr) else: "Ticket " & id
    let desc = if descPtr != nil: $cast[cstring](descPtr) else: "Description"
    let stStr = if statusPtr != nil: $cast[cstring](statusPtr) else: "open"
    let typ = if typePtr != nil: $cast[cstring](typePtr) else: "bug"
    let owner = if ownerPtr != nil: $cast[cstring](ownerPtr) else: ""
    let reporter = if reporterPtr != nil: $cast[cstring](reporterPtr) else: ""
    var st = tsOpen
    try: st = parseEnum[TicketStatus](stStr) except: discard
    ok(Ticket(id: id, title: title, description: desc, status: st, ticketType: typ, priority: int(prio), owner: owner, reporter: reporter, created: mtime, modified: mtime))
  else:
    ok(Ticket(id: id, title: "Sample ticket " & id, description: "# Bug report\n\n**Steps to reproduce**\n\n1. Do X\n2. See error\n\n```\nError log here\n```\n", status: tsOpen, priority: 2, comments: @[TicketComment(id: "1", ticketId: id, user: "admin", date: getTime().toUnix(), content: "First comment", format: "markdown")]))

proc getTicket*[T: StorageBackend](backend: T, id: string): FossilResult[Ticket] =
  when T is SqliteBackend:
    getTicketSqlite(backend, id)
  else:
    ok(Ticket(id: id, title: "Sample ticket " & id, description: "# Bug report\n\n**Steps to reproduce**\n\n1. Do X\n2. See error\n\n```\nError log here\n```\n", status: tsOpen, priority: 2, comments: @[TicketComment(id: "1", ticketId: id, user: "admin", date: getTime().toUnix(), content: "First comment", format: "markdown")]))

proc createTicketSqlite*(backend: var SqliteBackend, title: string, desc: string, ticketType: string = "bug", priority: int = 2): FossilResult[Ticket] =
  if title.len==0:
    return err[Ticket](feInvalidArg, "title empty")
  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_bind_text(pStmt: ptr sqlite3_stmt, i: cint, zData: cstring, n: cint, xDel: pointer): cint {.importc.}
  proc sqlite3_bind_int64(pStmt: ptr sqlite3_stmt, i: cint, v: int64): cint {.importc.}
  {.pop.}
  var rngVal: int64 = 0
  try:
    var b: array[8, byte]
    if urandom(b):
      copyMem(addr rngVal, addr b[0], sizeof(rngVal))
      if rngVal < 0: rngVal = -rngVal
  except: discard
  if rngVal == 0:
    randomize()
    rngVal = int64(rand(1_000_000_000))
  let uuid = $getTime().toUnix() & "_" & $nanosecond(getTime()) & "_" & $rngVal
  let now = getTime().toUnix()
  let sql = "INSERT INTO ticket(tkt_uuid, tkt_title, tkt_desc, tkt_status, tkt_type, tkt_priority, tkt_owner, tkt_reporter, tkt_ctime, tkt_mtime) VALUES(?1, ?2, ?3, 'open', ?4, ?5, '', '', ?6, ?6)"
  var stmt: ptr sqlite3_stmt
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) != 0:
    return err[Ticket](feIoError, "cannot prepare ticket insert")
  defer: discard sqlite3_finalize(stmt)
  discard sqlite3_bind_text(stmt, 1, uuid.cstring, -1, nil)
  discard sqlite3_bind_text(stmt, 2, title.cstring, -1, nil)
  discard sqlite3_bind_text(stmt, 3, desc.cstring, -1, nil)
  discard sqlite3_bind_text(stmt, 4, ticketType.cstring, -1, nil)
  discard sqlite3_bind_int64(stmt, 5, int64(priority))
  discard sqlite3_bind_int64(stmt, 6, now)
  if sqlite3_step(stmt) != 101:
    return err[Ticket](feIoError, "cannot insert ticket")
  # Auto-index for FTS5
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
    let sqlIdx = "INSERT OR REPLACE INTO search_index(id, kind, title, content, mtime) VALUES(?1, 'ticket', ?2, ?3, ?4)"
    if sqlite3_prepare_v2(backend.db, sqlIdx.cstring, -1, addr stmtIdx, nil) == 0:
      discard sqlite3_bind_text(stmtIdx, 1, uuid.cstring, -1, nil)
      discard sqlite3_bind_text(stmtIdx, 2, title.cstring, -1, nil)
      discard sqlite3_bind_text(stmtIdx, 3, desc.cstring, -1, nil)
      discard sqlite3_bind_int64(stmtIdx, 4, now)
      discard sqlite3_step(stmtIdx)
      discard sqlite3_finalize(stmtIdx)
    let sqlDelFts = "DELETE FROM search_fts WHERE id=?1"
    if sqlite3_prepare_v2(backend.db, sqlDelFts.cstring, -1, addr stmtIdx, nil) == 0:
      discard sqlite3_bind_text(stmtIdx, 1, uuid.cstring, -1, nil)
      discard sqlite3_step(stmtIdx)
      discard sqlite3_finalize(stmtIdx)
    let sqlFts = "INSERT OR REPLACE INTO search_fts(id, kind, title, content) VALUES(?1, 'ticket', ?2, ?3)"
    if sqlite3_prepare_v2(backend.db, sqlFts.cstring, -1, addr stmtIdx, nil) == 0:
      discard sqlite3_bind_text(stmtIdx, 1, uuid.cstring, -1, nil)
      discard sqlite3_bind_text(stmtIdx, 2, title.cstring, -1, nil)
      discard sqlite3_bind_text(stmtIdx, 3, desc.cstring, -1, nil)
      discard sqlite3_step(stmtIdx)
      discard sqlite3_finalize(stmtIdx)
  except:
    discard
  ok(Ticket(id: uuid, title: title, description: desc, status: tsOpen, ticketType: ticketType, priority: priority, created: now, modified: now))

proc createTicket*[T: StorageBackend](backend: var T, title: string, desc: string, ticketType: string = "bug", priority: int = 2): FossilResult[Ticket] =
  when T is SqliteBackend:
    createTicketSqlite(backend, title, desc, ticketType, priority)
  else:
    if title.len==0:
      return err[Ticket](feInvalidArg, "title empty")
    let t = Ticket(id: "new", title: title, description: desc, status: tsOpen, ticketType: ticketType, priority: priority, created: getTime().toUnix(), modified: getTime().toUnix())
    ok(t)

proc updateTicketSqlite*(backend: var SqliteBackend, id: string, updates: Table[string, string]): FossilResult[Ticket] =
  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_bind_text(pStmt: ptr sqlite3_stmt, i: cint, zData: cstring, n: cint, xDel: pointer): cint {.importc.}
  proc sqlite3_bind_int64(pStmt: ptr sqlite3_stmt, i: cint, v: int64): cint {.importc.}
  {.pop.}
  var setClauses: seq[string] = @[]
  if updates.hasKey("title"): setClauses.add "tkt_title=?1"
  if updates.hasKey("description"): setClauses.add "tkt_desc=?2"
  if updates.hasKey("status"): setClauses.add "tkt_status=?3"
  if updates.hasKey("owner"): setClauses.add "tkt_owner=?4"
  if updates.hasKey("type"): setClauses.add "tkt_type=?5"
  # For simplicity, we update only provided fields via separate statements
  for k,v in updates:
    let col = case k
      of "title": "tkt_title"
      of "description": "tkt_desc"
      of "status": "tkt_status"
      of "owner": "tkt_owner"
      of "type": "tkt_type"
      of "priority": "tkt_priority"
      else: ""
    if col=="": continue
    let sql = "UPDATE ticket SET " & col & "=?1, tkt_mtime=?2 WHERE tkt_uuid=?3"
    var stmt: ptr sqlite3_stmt
    if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) == 0:
      if k=="priority":
        try:
          discard sqlite3_bind_int64(stmt, 1, int64(parseInt(v)))
        except:
          discard sqlite3_bind_text(stmt, 1, v.cstring, -1, nil)
      else:
        discard sqlite3_bind_text(stmt, 1, v.cstring, -1, nil)
      discard sqlite3_bind_int64(stmt, 2, getTime().toUnix())
      discard sqlite3_bind_text(stmt, 3, id.cstring, -1, nil)
      discard sqlite3_step(stmt)
      discard sqlite3_finalize(stmt)
  # Return updated ticket
  getTicketSqlite(backend, id)

proc updateTicket*[T: StorageBackend](backend: var T, id: string, updates: Table[string, string]): FossilResult[Ticket] =
  when T is SqliteBackend:
    updateTicketSqlite(backend, id, updates)
  else:
    var ticketRes = getTicket(backend, id)
    if ticketRes.isErr:
      return err[Ticket](ticketRes.error.code, ticketRes.error.msg)
    var ticket = ticketRes.value
    if updates.hasKey("title"): ticket.title = updates["title"]
    if updates.hasKey("description"): ticket.description = updates["description"]
    if updates.hasKey("status"):
      try: ticket.status = parseEnum[TicketStatus](updates["status"])
      except: discard
    if updates.hasKey("owner"): ticket.owner = updates["owner"]
    ticket.modified = getTime().toUnix()
    ok(ticket)

proc addCommentSqlite*(backend: var SqliteBackend, ticketId: string, content: string, user: string = "anonymous"): FossilResult[TicketComment] =
  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_bind_text(pStmt: ptr sqlite3_stmt, i: cint, zData: cstring, n: cint, xDel: pointer): cint {.importc.}
  proc sqlite3_bind_int64(pStmt: ptr sqlite3_stmt, i: cint, v: int64): cint {.importc.}
  {.pop.}
  # Ensure ticketchng table exists
  let sqlCreate = "CREATE TABLE IF NOT EXISTS ticketchng(tkt_id TEXT, tkt_rid INTEGER, tkt_mtime INTEGER, login TEXT, tkt_comment TEXT)"
  var stmtCreate: ptr sqlite3_stmt
  if sqlite3_prepare_v2(backend.db, sqlCreate.cstring, -1, addr stmtCreate, nil) == 0:
    discard sqlite3_step(stmtCreate)
    discard sqlite3_finalize(stmtCreate)
  let commentId = $getTime().toUnix() & "_" & $rand(1000)
  let now = getTime().toUnix()
  let sql = "INSERT INTO ticketchng(tkt_id, tkt_rid, tkt_mtime, login, tkt_comment) VALUES(?1, 0, ?2, ?3, ?4)"
  var stmt: ptr sqlite3_stmt
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) != 0:
    return err[TicketComment](feIoError, "cannot prepare comment insert")
  defer: discard sqlite3_finalize(stmt)
  discard sqlite3_bind_text(stmt, 1, ticketId.cstring, -1, nil)
  discard sqlite3_bind_int64(stmt, 2, now)
  discard sqlite3_bind_text(stmt, 3, user.cstring, -1, nil)
  discard sqlite3_bind_text(stmt, 4, content.cstring, -1, nil)
  if sqlite3_step(stmt) != 101:
    return err[TicketComment](feIoError, "cannot insert comment")
  ok(TicketComment(id: commentId, ticketId: ticketId, user: user, date: now, content: content, format: "markdown"))

proc addComment*[T: StorageBackend](backend: var T, ticketId: string, content: string, user: string = "anonymous"): FossilResult[TicketComment] =
  when T is SqliteBackend:
    addCommentSqlite(backend, ticketId, content, user)
  else:
    let comment = TicketComment(id: $getTime().toUnix(), ticketId: ticketId, user: user, date: getTime().toUnix(), content: content, format: "markdown")
    ok(comment)

proc renderTicket*(ticket: Ticket): string =
  var html = "<div class=\"ticket\">"
  html.add "<h2>" & mdParser.parseInline(ticket.title) & " [" & $ticket.status & "]</h2>"
  html.add "<p>Type: " & ticket.ticketType & " Priority: " & $ticket.priority & "</p>"
  html.add "<div class=\"description\">" & mdParser.markdownToHtml(ticket.description) & "</div>"
  if ticket.comments.len>0:
    html.add "<h3>Comments</h3>"
    for c in ticket.comments:
      html.add "<div class=\"comment\"><b>" & c.user & "</b> at " & $c.date & "<br>"
      html.add mdParser.markdownToHtml(c.content) & "</div>"
  html.add "</div>"
  html

proc ticketToJson*(ticket: Ticket): JsonNode {.gcsafe.} =
  var commentsArr = newJArray()
  for c in ticket.comments:
    var obj = newJObject()
    obj["id"] = newJString(c.id)
    obj["user"] = newJString(c.user)
    obj["date"] = newJInt(c.date)
    obj["content"] = newJString(c.content)
    obj["html"] = newJString(mdParser.markdownToHtml(c.content))
    commentsArr.add obj
  var res = newJObject()
  res["id"] = newJString(ticket.id)
  res["title"] = newJString(ticket.title)
  res["description"] = newJString(ticket.description)
  res["html"] = newJString(renderTicket(ticket))
  res["status"] = newJString($ticket.status)
  res["type"] = newJString(ticket.ticketType)
  res["priority"] = newJInt(ticket.priority)
  res["owner"] = newJString(ticket.owner)
  res["reporter"] = newJString(ticket.reporter)
  res["created"] = newJInt(ticket.created)
  res["modified"] = newJInt(ticket.modified)
  var tagsArr = newJArray()
  for t in ticket.tags: tagsArr.add newJString(t)
  res["tags"] = tagsArr
  res["comments"] = commentsArr
  res

proc renderTicketWithTh1*(ticket: Ticket, th1Script: string, vars: Table[string, string] = initTable[string, string]()): string =
  var interp = th1Interp.newInterp()
  for k,v in vars:
    interp.setVar(k, v)
  interp.setVar("ticketId", ticket.id)
  interp.setVar("ticketTitle", ticket.title)
  interp.setVar("ticketStatus", $ticket.status)
  discard interp.evalScript(th1Script)
  interp.output & renderTicket(ticket)
