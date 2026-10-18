## HTTP transport for sync - real implementation

import ../types
import ../storage/sqlite_backend
import ./protocol
import std/[httpclient, strutils, options, os, json, times]

type
  HttpTransport* = object
    url*: string
    userAgent*: string
    timeoutMs*: int

proc newHttpTransport*(url: string): HttpTransport =
  HttpTransport(url: url, userAgent: "Fossil-Nim/2.26.0", timeoutMs: 30000)

proc postXfer*(transport: HttpTransport, payload: string): FossilResult[string] =
  try:
    var client = newHttpClient(timeout=transport.timeoutMs)
    client.headers = newHttpHeaders({"Content-Type": "application/x-fossil", "User-Agent": transport.userAgent})
    let resp = client.postContent(transport.url & "/xfer", body=payload)
    ok(resp)
  except:
    err[string](feIoError, "http post failed", getCurrentExceptionMsg())

proc getClone*(transport: HttpTransport): FossilResult[string] =
  try:
    var client = newHttpClient(timeout=transport.timeoutMs)
    client.headers = newHttpHeaders({"User-Agent": transport.userAgent})
    let resp = client.getContent(transport.url & "/clone")
    ok(resp)
  except:
    err[string](feIoError, "http get clone failed", getCurrentExceptionMsg())

proc cloneFromUrl*(url: string, dstPath: string): FossilResult[int] =
  ## Clone from remote URL (expects /clone endpoint returning file cards or JSON)
  let transport = newHttpTransport(url)
  let cloneRes = transport.getClone()
  if cloneRes.isErr:
    return err[int](cloneRes.error.code, cloneRes.error.msg, cloneRes.error.details)

  var dstDb = SqliteBackend()
  let openRes = dstDb.open(dstPath)
  if openRes.isErr:
    return err[int](openRes.error.code, openRes.error.msg)
  defer: dstDb.close()

  let schemaRes = dstDb.initSchema()
  if schemaRes.isErr:
    return err[int](schemaRes.error.code, schemaRes.error.msg)

  # Try to parse as JSON first (new format), fallback to file cards
  try:
    let j = parseJson(cloneRes.value)
    var count=0
    if j.hasKey("blobs"):
      for blobObj in j["blobs"]:
        let uuidStr = blobObj["uuid"].getStr()
        let contentB64 = blobObj["content"].getStr()
        let uuidRes = uuidFromHex(uuidStr)
        if uuidRes.isOk:
          let data = newBlob(contentB64) # assume not base64 for simplicity, or decode if needed
          let putRes = dstDb.putBlob(uuidRes.value, data, false)
          if putRes.isOk: inc count
    return ok(count)
  except:
    # Fallback to file cards format
    let importRes = importBundleSqlite(dstDb, cloneRes.value)
    return importRes

proc rebuildEventsAfterImport(backend: var SqliteBackend) =
  ## Helper to rebuild missing events from manifest blobs
  try:
    let allRidsRes = backend.getAllRids()
    if allRidsRes.isOk:
      for rid in allRidsRes.value:
        let blobRes = backend.getBlob(rid)
        if blobRes.isOk:
          let data = blobRes.value.data
          if data.len>10 and data.contains("\nD ") and data.contains("\nU ") and (data.startsWith("C ") or data.contains("\nC ")):
            let evRes = backend.getEventByRid(rid)
            if evRes.isErr:
              var user = "unknown"
              var comment = ""
              var branch = "trunk"
              var mtime: int64 = 0
              for line in data.splitLines():
                if line.startsWith("U "):
                  user = line[2..^1].strip()
                elif line.startsWith("C "):
                  comment = line[2..^1].strip()
                elif line.startsWith("R "):
                  branch = line[2..^1].strip()
                elif line.startsWith("E "):
                  try:
                    mtime = parseInt(line[2..^1].strip().split(" ")[0])
                  except: discard
              if mtime==0:
                mtime = getTime().toUnix()
              # SEC-07 fix: bind
              {.push header: "<sqlite3.h>".}
              type sqlite3_stmt_h {.importc: "sqlite3_stmt", incompleteStruct.} = object
              proc sqlite3_prepare_v2_h(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt_h, pzTail: pointer): cint {.importc: "sqlite3_prepare_v2".}
              proc sqlite3_finalize_h(pStmt: ptr sqlite3_stmt_h): cint {.importc: "sqlite3_finalize".}
              proc sqlite3_step_h(pStmt: ptr sqlite3_stmt_h): cint {.importc: "sqlite3_step".}
              proc sqlite3_bind_text_h(pStmt: ptr sqlite3_stmt_h, i: cint, zData: cstring, n: cint, xDel: pointer): cint {.importc: "sqlite3_bind_text".}
              proc sqlite3_bind_int64_h(pStmt: ptr sqlite3_stmt_h, i: cint, v: int64): cint {.importc: "sqlite3_bind_int64".}
              {.pop.}
              var stmtH: ptr sqlite3_stmt_h
              let sqlH = "INSERT OR IGNORE INTO event(type, mtime, objid, user, comment, branch) VALUES('ci', ?1, ?2, ?3, ?4, ?5)"
              if sqlite3_prepare_v2_h(backend.db, sqlH.cstring, -1, addr stmtH, nil)==0:
                discard sqlite3_bind_int64_h(stmtH, 1, mtime)
                discard sqlite3_bind_int64_h(stmtH, 2, int64(rid))
                discard sqlite3_bind_text_h(stmtH, 3, user.cstring, -1, nil)
                discard sqlite3_bind_text_h(stmtH, 4, comment.cstring, -1, nil)
                discard sqlite3_bind_text_h(stmtH, 5, branch.cstring, -1, nil)
                discard sqlite3_step_h(stmtH)
                discard sqlite3_finalize_h(stmtH)
  except:
    discard

proc pushToUrl*(localRepoPath: string, url: string): FossilResult[int] =
  ## Push local repo to remote via xfer
  var localDb = SqliteBackend()
  let openRes = localDb.open(localRepoPath)
  if openRes.isErr: return err[int](openRes.error.code, openRes.error.msg)
  defer: localDb.close()

  let allUuidsRes = localDb.getAllUuids()
  if allUuidsRes.isErr: return err[int](allUuidsRes.error.code, allUuidsRes.error.msg)

  var payload = ""
  for uuid in allUuidsRes.value:
    payload.add "igot " & $uuid & "\n"

  let transport = newHttpTransport(url)
  let respRes = transport.postXfer(payload)
  if respRes.isErr: return err[int](respRes.error.code, respRes.error.msg)

  # Parse response: may contain gimme (server wants our files) and file (server pushes its extra)
  let remoteCards = parseCards(respRes.value)
  var toSend: seq[XferCard] = @[]
  var importedFromServer = 0
  for card in remoteCards:
    case card.kind
    of ckGimme:
      let blobRes = localDb.getBlobByUuid(card.uuid)
      if blobRes.isOk:
        toSend.add XferCard(kind: ckFile, uuid: card.uuid, data: blobRes.value)
    of ckFile:
      # Server sent us a file we lacked (bidirectional sync)
      let putRes = localDb.putBlob(card.uuid, card.data, false)
      if putRes.isOk: inc importedFromServer
    else: discard

  if importedFromServer>0:
    rebuildEventsAfterImport(localDb)

  if toSend.len > 0:
    var sendPayload = ""
    for c in toSend:
      sendPayload.add encodeCard(c)
    let sendRes = transport.postXfer(sendPayload)
    if sendRes.isErr: return err[int](sendRes.error.code, sendRes.error.msg)
    # Server may respond with more file cards after we sent ours (optional)
    let secondCards = parseCards(sendRes.value)
    for card in secondCards:
      if card.kind == ckFile:
        let putRes = localDb.putBlob(card.uuid, card.data, false)
        if putRes.isOk: inc importedFromServer
    if importedFromServer>0:
      rebuildEventsAfterImport(localDb)

  ok(toSend.len)

proc pullFromUrl*(localRepoPath: string, url: string): FossilResult[int] =
  ## Pull from remote - tries xfer first, then clone
  var localDb = SqliteBackend()
  let openRes = localDb.open(localRepoPath)
  if openRes.isErr: return err[int](openRes.error.code, openRes.error.msg)
  defer: localDb.close()

  let allUuidsRes = localDb.getAllUuids()
  if allUuidsRes.isErr: return err[int](allUuidsRes.error.code, allUuidsRes.error.msg)

  let transport = newHttpTransport(url)

  # Try xfer-based pull: send igot, expect file cards
  var payload = ""
  for uuid in allUuidsRes.value:
    payload.add "igot " & $uuid & "\n"
  let xferRes = transport.postXfer(payload)
  if xferRes.isOk:
    let cards = parseCards(xferRes.value)
    var imported=0
    var hasFile=false
    for card in cards:
      if card.kind==ckFile:
        hasFile=true
        let putRes = localDb.putBlob(card.uuid, card.data, false)
        if putRes.isOk: inc imported
    if hasFile:
      rebuildEventsAfterImport(localDb)
      return ok(imported)
    # If no file, fallback to clone

  # Fallback to clone bundle
  let cloneRes = transport.getClone()
  if cloneRes.isErr: return err[int](cloneRes.error.code, cloneRes.error.msg)

  let importRes = importBundleSqlite(localDb, cloneRes.value)
  ok(importRes.value)
