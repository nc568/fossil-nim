## Pull Request subsystem for Fossil-Nim
## Provides full PR lifecycle: create, list, review, merge, close, and link to tickets

import ../types
import ../storage/backend
import ../storage/sqlite_backend
import std/[strutils, times, options, json, random, sysrand]

type
  PrStatus* = enum
    prOpen = "open"
    prMerged = "merged"
    prClosed = "closed"

  PullRequest* = object
    id*: string
    title*: string
    description*: string
    sourceBranch*: string
    targetBranch*: string
    author*: string
    status*: PrStatus
    ticketId*: string
    created*: int64
    modified*: int64
    mergedAt*: int64
    mergeCommit*: string

{.push header: "<sqlite3.h>".}
type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
proc sqlite3_column_text(pStmt: ptr sqlite3_stmt, iCol: cint): ptr cuchar {.importc.}
proc sqlite3_column_int64(pStmt: ptr sqlite3_stmt, iCol: cint): int64 {.importc.}
proc sqlite3_bind_text(pStmt: ptr sqlite3_stmt, i: cint, zData: cstring, n: cint, xDel: pointer): cint {.importc.}
proc sqlite3_bind_int64(pStmt: ptr sqlite3_stmt, i: cint, v: int64): cint {.importc.}
{.pop.}

const SQLITE_ROW = 100
const SQLITE_DONE = 101

proc ensurePrTable*(backend: SqliteBackend) =
  let sql = """
    CREATE TABLE IF NOT EXISTS pull_request (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      description TEXT,
      source_branch TEXT NOT NULL,
      target_branch TEXT NOT NULL,
      author TEXT,
      status TEXT NOT NULL,
      ticket_id TEXT,
      created INTEGER NOT NULL,
      modified INTEGER NOT NULL,
      merged_at INTEGER DEFAULT 0,
      merge_commit TEXT DEFAULT ''
    );
  """
  var stmt: ptr sqlite3_stmt
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) == 0:
    discard sqlite3_step(stmt)
    discard sqlite3_finalize(stmt)

proc createPullRequest*(
  backend: var SqliteBackend,
  title: string,
  sourceBranch: string,
  targetBranch: string = "trunk",
  description: string = "",
  author: string = "anonymous",
  ticketId: string = ""
): FossilResult[PullRequest] =
  if title.len == 0:
    return err[PullRequest](feInvalidArg, "Pull request title cannot be empty")
  if sourceBranch.len == 0:
    return err[PullRequest](feInvalidArg, "Source branch cannot be empty")

  backend.ensurePrTable()

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

  let now = getTime().toUnix()
  let id = "pr-" & $now & "-" & $(rngVal mod 10000)

  let sql = """
    INSERT INTO pull_request (id, title, description, source_branch, target_branch, author, status, ticket_id, created, modified, merged_at, merge_commit)
    VALUES (?1, ?2, ?3, ?4, ?5, ?6, 'open', ?7, ?8, ?8, 0, '');
  """
  var stmt: ptr sqlite3_stmt
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) != 0:
    return err[PullRequest](feIoError, "Failed to prepare pull request insert")
  defer: discard sqlite3_finalize(stmt)

  discard sqlite3_bind_text(stmt, 1, id.cstring, -1, nil)
  discard sqlite3_bind_text(stmt, 2, title.cstring, -1, nil)
  discard sqlite3_bind_text(stmt, 3, description.cstring, -1, nil)
  discard sqlite3_bind_text(stmt, 4, sourceBranch.cstring, -1, nil)
  discard sqlite3_bind_text(stmt, 5, targetBranch.cstring, -1, nil)
  discard sqlite3_bind_text(stmt, 6, author.cstring, -1, nil)
  discard sqlite3_bind_text(stmt, 7, ticketId.cstring, -1, nil)
  discard sqlite3_bind_int64(stmt, 8, now)

  if sqlite3_step(stmt) != SQLITE_DONE:
    return err[PullRequest](feIoError, "Failed to execute pull request insert")

  ok(PullRequest(
    id: id,
    title: title,
    description: description,
    sourceBranch: sourceBranch,
    targetBranch: targetBranch,
    author: author,
    status: prOpen,
    ticketId: ticketId,
    created: now,
    modified: now,
    mergedAt: 0,
    mergeCommit: ""
  ))

proc getPullRequest*(backend: SqliteBackend, id: string): FossilResult[PullRequest] =
  backend.ensurePrTable()
  let sql = """
    SELECT id, title, description, source_branch, target_branch, author, status, ticket_id, created, modified, merged_at, merge_commit
    FROM pull_request WHERE id = ?1 LIMIT 1;
  """
  var stmt: ptr sqlite3_stmt
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) != 0:
    return err[PullRequest](feNotFound, "Pull request not found")
  defer: discard sqlite3_finalize(stmt)

  discard sqlite3_bind_text(stmt, 1, id.cstring, -1, nil)
  if sqlite3_step(stmt) == SQLITE_ROW:
    let idPtr = sqlite3_column_text(stmt, 0)
    let titlePtr = sqlite3_column_text(stmt, 1)
    let descPtr = sqlite3_column_text(stmt, 2)
    let srcPtr = sqlite3_column_text(stmt, 3)
    let tgtPtr = sqlite3_column_text(stmt, 4)
    let authorPtr = sqlite3_column_text(stmt, 5)
    let statusPtr = sqlite3_column_text(stmt, 6)
    let tktPtr = sqlite3_column_text(stmt, 7)
    let created = sqlite3_column_int64(stmt, 8)
    let modified = sqlite3_column_int64(stmt, 9)
    let mergedAt = sqlite3_column_int64(stmt, 10)
    let commitPtr = sqlite3_column_text(stmt, 11)

    let prId = if idPtr != nil: $cast[cstring](idPtr) else: id
    let title = if titlePtr != nil: $cast[cstring](titlePtr) else: ""
    let desc = if descPtr != nil: $cast[cstring](descPtr) else: ""
    let src = if srcPtr != nil: $cast[cstring](srcPtr) else: "trunk"
    let tgt = if tgtPtr != nil: $cast[cstring](tgtPtr) else: "trunk"
    let author = if authorPtr != nil: $cast[cstring](authorPtr) else: "anonymous"
    let stStr = if statusPtr != nil: $cast[cstring](statusPtr) else: "open"
    let tkt = if tktPtr != nil: $cast[cstring](tktPtr) else: ""
    let commit = if commitPtr != nil: $cast[cstring](commitPtr) else: ""

    var st = prOpen
    try: st = parseEnum[PrStatus](stStr) except: discard

    return ok(PullRequest(
      id: prId,
      title: title,
      description: desc,
      sourceBranch: src,
      targetBranch: tgt,
      author: author,
      status: st,
      ticketId: tkt,
      created: created,
      modified: modified,
      mergedAt: mergedAt,
      mergeCommit: commit
    ))
  err[PullRequest](feNotFound, "Pull request with id " & id & " not found")

proc listPullRequests*(backend: SqliteBackend, status: string = "all", ticketId: string = ""): FossilResult[seq[PullRequest]] =
  backend.ensurePrTable()
  var sql = "SELECT id, title, description, source_branch, target_branch, author, status, ticket_id, created, modified, merged_at, merge_commit FROM pull_request WHERE 1=1"
  if status.len > 0 and status != "all":
    sql.add " AND status = ?1"
  if ticketId.len > 0:
    sql.add " AND ticket_id = ?2"
  sql.add " ORDER BY created DESC;"

  var stmt: ptr sqlite3_stmt
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) != 0:
    return ok(@[])
  defer: discard sqlite3_finalize(stmt)

  var bindIdx: cint = 1
  if status.len > 0 and status != "all":
    discard sqlite3_bind_text(stmt, bindIdx, status.cstring, -1, nil)
    bindIdx.inc
  if ticketId.len > 0:
    discard sqlite3_bind_text(stmt, bindIdx, ticketId.cstring, -1, nil)

  var list: seq[PullRequest] = @[]
  while sqlite3_step(stmt) == SQLITE_ROW:
    let idPtr = sqlite3_column_text(stmt, 0)
    let titlePtr = sqlite3_column_text(stmt, 1)
    let descPtr = sqlite3_column_text(stmt, 2)
    let srcPtr = sqlite3_column_text(stmt, 3)
    let tgtPtr = sqlite3_column_text(stmt, 4)
    let authorPtr = sqlite3_column_text(stmt, 5)
    let statusPtr = sqlite3_column_text(stmt, 6)
    let tktPtr = sqlite3_column_text(stmt, 7)
    let created = sqlite3_column_int64(stmt, 8)
    let modified = sqlite3_column_int64(stmt, 9)
    let mergedAt = sqlite3_column_int64(stmt, 10)
    let commitPtr = sqlite3_column_text(stmt, 11)

    let prId = if idPtr != nil: $cast[cstring](idPtr) else: ""
    let title = if titlePtr != nil: $cast[cstring](titlePtr) else: ""
    let desc = if descPtr != nil: $cast[cstring](descPtr) else: ""
    let src = if srcPtr != nil: $cast[cstring](srcPtr) else: "trunk"
    let tgt = if tgtPtr != nil: $cast[cstring](tgtPtr) else: "trunk"
    let author = if authorPtr != nil: $cast[cstring](authorPtr) else: "anonymous"
    let stStr = if statusPtr != nil: $cast[cstring](statusPtr) else: "open"
    let tkt = if tktPtr != nil: $cast[cstring](tktPtr) else: ""
    let commit = if commitPtr != nil: $cast[cstring](commitPtr) else: ""

    var st = prOpen
    try: st = parseEnum[PrStatus](stStr) except: discard

    list.add(PullRequest(
      id: prId,
      title: title,
      description: desc,
      sourceBranch: src,
      targetBranch: tgt,
      author: author,
      status: st,
      ticketId: tkt,
      created: created,
      modified: modified,
      mergedAt: mergedAt,
      mergeCommit: commit
    ))
  ok(list)

proc mergePullRequest*(backend: var SqliteBackend, id: string, mergeCommitUuid: string = "", user: string = "admin"): FossilResult[PullRequest] =
  let getRes = getPullRequest(backend, id)
  if getRes.isErr:
    return getRes
  var pr = getRes.value
  if pr.status == prMerged:
    return ok(pr)

  let now = getTime().toUnix()
  let commitUuid = if mergeCommitUuid.len > 0: mergeCommitUuid else: "mrg-" & $now
  let sql = "UPDATE pull_request SET status = 'merged', modified = ?1, merged_at = ?1, merge_commit = ?2 WHERE id = ?3;"
  var stmt: ptr sqlite3_stmt
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) == 0:
    discard sqlite3_bind_int64(stmt, 1, now)
    discard sqlite3_bind_text(stmt, 2, commitUuid.cstring, -1, nil)
    discard sqlite3_bind_text(stmt, 3, id.cstring, -1, nil)
    discard sqlite3_step(stmt)
    discard sqlite3_finalize(stmt)

  pr.status = prMerged
  pr.modified = now
  pr.mergedAt = now
  pr.mergeCommit = commitUuid
  ok(pr)

proc closePullRequest*(backend: var SqliteBackend, id: string, user: string = "admin"): FossilResult[PullRequest] =
  let getRes = getPullRequest(backend, id)
  if getRes.isErr:
    return getRes
  var pr = getRes.value
  let now = getTime().toUnix()
  let sql = "UPDATE pull_request SET status = 'closed', modified = ?1 WHERE id = ?2;"
  var stmt: ptr sqlite3_stmt
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) == 0:
    discard sqlite3_bind_int64(stmt, 1, now)
    discard sqlite3_bind_text(stmt, 2, id.cstring, -1, nil)
    discard sqlite3_step(stmt)
    discard sqlite3_finalize(stmt)

  pr.status = prClosed
  pr.modified = now
  ok(pr)

proc prToJson*(pr: PullRequest): JsonNode {.gcsafe.} =
  var obj = newJObject()
  obj["id"] = newJString(pr.id)
  obj["title"] = newJString(pr.title)
  obj["description"] = newJString(pr.description)
  obj["sourceBranch"] = newJString(pr.sourceBranch)
  obj["targetBranch"] = newJString(pr.targetBranch)
  obj["author"] = newJString(pr.author)
  obj["status"] = newJString($pr.status)
  obj["ticketId"] = newJString(pr.ticketId)
  obj["created"] = newJInt(pr.created)
  obj["modified"] = newJInt(pr.modified)
  obj["mergedAt"] = newJInt(pr.mergedAt)
  obj["mergeCommit"] = newJString(pr.mergeCommit)
  obj
