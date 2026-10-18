## Fossil sync protocol - cards, xfer, clone bundle
import ../types
import ../storage/backend
import ../storage/sqlite_backend
import std/[strutils, tables, options, sequtils, os, times]

type
  XferCardKind* = enum
    ckFile, ckGimme, ckIgot, ckCookie, ckError, ckClone, ckPush

  XferCard* = object
    kind*: XferCardKind
    uuid*: Uuid
    data*: Blob
    errorMsg*: string
    rid*: Rid

proc parseCard*(line: string): FossilResult[XferCard] =
  let parts = line.splitWhitespace()
  if parts.len==0:
    return err[XferCard](feInvalidArg, "empty card")
  case parts[0]
  of "file":
    if parts.len<3: return err[XferCard](feInvalidArg, "invalid file card")
    let uuidRes = uuidFromHex(parts[1])
    if uuidRes.isErr: return err[XferCard](feInvalidArg, "invalid file uuid")
    let sizeRes = try: parseInt(parts[2]) except: -1
    if sizeRes < 0: return err[XferCard](feInvalidArg, "invalid file size")
    # Data will be filled by parseCards using size, here we keep empty or placeholder
    ok(XferCard(kind: ckFile, uuid: uuidRes.value, data: newBlob(""), rid: Rid(sizeRes)))
  of "gimme":
    if parts.len<2: return err[XferCard](feInvalidArg, "invalid gimme")
    let uuidRes = uuidFromHex(parts[1])
    if uuidRes.isErr: return err[XferCard](feInvalidArg, "invalid gimme uuid")
    ok(XferCard(kind: ckGimme, uuid: uuidRes.value))
  of "igot":
    if parts.len<2: return err[XferCard](feInvalidArg, "invalid igot")
    let uuidRes = uuidFromHex(parts[1])
    if uuidRes.isErr: return err[XferCard](feInvalidArg, "invalid igot uuid")
    ok(XferCard(kind: ckIgot, uuid: uuidRes.value))
  of "cookie":
    ok(XferCard(kind: ckCookie, data: newBlob(parts[1..^1].join(" "))))
  of "error":
    ok(XferCard(kind: ckError, errorMsg: parts[1..^1].join(" ")))
  else:
    err[XferCard](feInvalidArg, "unknown card", parts[0])

proc encodeCard*(card: XferCard): string {.gcsafe.} =
  case card.kind
  of ckFile:
    "file " & $card.uuid & " " & $card.data.len & "\n" & card.data.data & "\n"
  of ckGimme:
    "gimme " & $card.uuid & "\n"
  of ckIgot:
    "igot " & $card.uuid & "\n"
  of ckCookie:
    "cookie " & card.data.data & "\n"
  of ckError:
    "error " & card.errorMsg & "\n"
  else:
    $card.kind & " " & $card.uuid & "\n"

proc parseCards*(payload: string): seq[XferCard] {.gcsafe.} =
  ## Parse Fossil xfer cards, correctly handling file cards with size bytes including newlines
  var cards: seq[XferCard] = @[]
  var pos = 0
  while pos < payload.len:
    # Find end of line
    let nlPos = payload.find('\n', pos)
    if nlPos == -1:
      # Last line without newline
      let line = payload[pos..^1].strip()
      if line.len>0:
        let cardRes = parseCard(line)
        if cardRes.isOk:
          cards.add cardRes.value
      break
    let line = payload[pos..<nlPos].strip()
    if line.len==0:
      pos = nlPos+1
      continue
    let cardRes = parseCard(line)
    if cardRes.isOk:
      var card = cardRes.value
      if card.kind == ckFile:
        # Size is stored in rid field as parsed int
        let size = int(card.rid)
        let dataStart = nlPos+1
        if dataStart + size <= payload.len:
          let dataStr = payload[dataStart..<dataStart+size]
          card.data = newBlob(dataStr)
          card.rid = invalidRid() # clear size placeholder
          cards.add card
          # Advance pos past data and trailing newline if present
          pos = dataStart + size
          if pos < payload.len and payload[pos] == '\n':
            inc pos
        else:
          # Not enough data, treat as incomplete
          cards.add card
          pos = nlPos+1
      else:
        cards.add card
        pos = nlPos+1
    else:
      # Unknown card, skip line
      pos = nlPos+1
  cards

proc syncExchangeSqlite*(backend: SqliteBackend, localUuids: seq[Uuid], remoteCards: seq[XferCard]): FossilResult[seq[XferCard]] {.gcsafe.} =
  ## Two-way sync:
  ## - For local uuids not in remote (Ls \ Lc): send file cards (server -> client, pull)
  ## - For remote uuids (igot) not in local (Lc \ Ls): send gimme cards (server asks client to send, push)
  var resultCards: seq[XferCard] = @[]
  var remoteUuids = initTable[Uuid, bool]()
  var localSet = initTable[Uuid, bool]()
  for u in localUuids:
    localSet[u]=true
  for card in remoteCards:
    if card.kind == ckFile or card.kind == ckIgot:
      remoteUuids[card.uuid] = true
  # Ls \ Lc -> file cards (what server has but client doesn't)
  for uuid in localUuids:
    if not remoteUuids.hasKey(uuid):
      let blobRes = backend.getBlobByUuid(uuid)
      if blobRes.isOk:
        resultCards.add XferCard(kind: ckFile, uuid: uuid, data: blobRes.value)
  # Lc \ Ls -> gimme cards (what client has but server doesn't, server wants)
  for card in remoteCards:
    if card.kind == ckIgot:
      if not localSet.hasKey(card.uuid):
        resultCards.add XferCard(kind: ckGimme, uuid: card.uuid)
  ok(resultCards)

proc syncExchange*[T: StorageBackend](backend: T, localUuids: seq[Uuid], remoteCards: seq[XferCard]): FossilResult[seq[XferCard]] =
  var resultCards: seq[XferCard] = @[]
  var remoteUuids = initTable[Uuid, bool]()
  var localSet = initTable[Uuid, bool]()
  for u in localUuids:
    localSet[u]=true
  for card in remoteCards:
    if card.kind == ckFile or card.kind == ckIgot:
      remoteUuids[card.uuid] = true
  for uuid in localUuids:
    if not remoteUuids.hasKey(uuid):
      let blobRes = backend.getBlobByUuid(uuid)
      if blobRes.isOk:
        resultCards.add XferCard(kind: ckFile, uuid: uuid, data: blobRes.value)
  for card in remoteCards:
    if card.kind == ckIgot:
      if not localSet.hasKey(card.uuid):
        resultCards.add XferCard(kind: ckGimme, uuid: card.uuid)
  ok(resultCards)

proc importBundleSqlite*(backend: var SqliteBackend, bundle: string): FossilResult[int] =
  let cards = parseCards(bundle)
  var count=0
  for card in cards:
    if card.kind == ckFile:
      let putRes = backend.putBlob(card.uuid, card.data, false)
      if putRes.isOk: inc count
  # After importing blobs, try to rebuild events from manifest blobs (if any)
  # This ensures HTTP clone gets timeline entries - use high-level API to avoid C interop issues
  try:
    let allRidsRes = backend.getAllRids()
    if allRidsRes.isOk:
      for rid in allRidsRes.value:
        let blobRes = backend.getBlob(rid)
        if blobRes.isOk:
          let data = blobRes.value.data
          if data.len>10 and data.contains("\nD ") and data.contains("\nU ") and (data.startsWith("C ") or data.contains("\nC ")):
            # Check if event already exists via getEventByRid (returns err if not found)
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
                try:
                  mtime = getTime().toUnix()
                except:
                  mtime = 0
              # SEC-07 fix: use bind for event insert
              {.push header: "<sqlite3.h>".}
              type sqlite3_stmt_ev {.importc: "sqlite3_stmt", incompleteStruct.} = object
              proc sqlite3_prepare_v2_ev(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt_ev, pzTail: pointer): cint {.importc: "sqlite3_prepare_v2".}
              proc sqlite3_finalize_ev(pStmt: ptr sqlite3_stmt_ev): cint {.importc: "sqlite3_finalize".}
              proc sqlite3_step_ev(pStmt: ptr sqlite3_stmt_ev): cint {.importc: "sqlite3_step".}
              proc sqlite3_bind_text_ev(pStmt: ptr sqlite3_stmt_ev, i: cint, zData: cstring, n: cint, xDel: pointer): cint {.importc: "sqlite3_bind_text".}
              proc sqlite3_bind_int64_ev(pStmt: ptr sqlite3_stmt_ev, i: cint, v: int64): cint {.importc: "sqlite3_bind_int64".}
              {.pop.}
              var stmtEv: ptr sqlite3_stmt_ev
              let sqlEv = "INSERT OR IGNORE INTO event(type, mtime, objid, user, comment, branch) VALUES('ci', ?1, ?2, ?3, ?4, ?5)"
              if sqlite3_prepare_v2_ev(backend.db, sqlEv.cstring, -1, addr stmtEv, nil)==0:
                discard sqlite3_bind_int64_ev(stmtEv, 1, mtime)
                discard sqlite3_bind_int64_ev(stmtEv, 2, int64(rid))
                discard sqlite3_bind_text_ev(stmtEv, 3, user.cstring, -1, nil)
                discard sqlite3_bind_text_ev(stmtEv, 4, comment.cstring, -1, nil)
                discard sqlite3_bind_text_ev(stmtEv, 5, branch.cstring, -1, nil)
                discard sqlite3_step_ev(stmtEv)
                discard sqlite3_finalize_ev(stmtEv)
  except:
    discard
  ok(count)

proc buildCloneBundleSqlite*(backend: SqliteBackend): FossilResult[string] {.gcsafe.} =
  var bundle = ""
  let uuidsRes = backend.getAllUuids()
  if uuidsRes.isErr:
    return err[string](feIoError, "cannot get uuids")
  for uuid in uuidsRes.value:
    let blobRes = backend.getBlobByUuid(uuid)
    if blobRes.isOk:
      let card = XferCard(kind: ckFile, uuid: uuid, data: blobRes.value)
      bundle.add encodeCard(card)
  ok(bundle)

proc buildCloneBundle*[T: StorageBackend](backend: T): FossilResult[string] =
  var bundle = ""
  let uuidsRes = backend.getAllUuids()
  if uuidsRes.isErr:
    return err[string](feIoError, "cannot get uuids")
  for uuid in uuidsRes.value:
    let blobRes = backend.getBlobByUuid(uuid)
    if blobRes.isOk:
      let card = XferCard(kind: ckFile, uuid: uuid, data: blobRes.value)
      bundle.add encodeCard(card)
  ok(bundle)

proc cloneRepo*(srcPath, dstPath: string): FossilResult[int] =
  if not fileExists(srcPath):
    return err[int](feNotFound, "src not found", srcPath)
  var srcDb = SqliteBackend()
  if srcDb.open(srcPath).isErr:
    return err[int](feIoError, "cannot open src")
  defer: srcDb.close()
  var dstDb = SqliteBackend()
  if dstDb.open(dstPath).isErr:
    return err[int](feIoError, "cannot open dst")
  defer: dstDb.close()
  discard dstDb.initSchema()
  # Copy all tables via ATTACH for full fidelity (event, tag, mlink, ticket, forum, chat, search, etc)
  {.push header: "<sqlite3.h>".}
  type sqlite3_raw_clone {.importc: "sqlite3", incompleteStruct.} = object
  proc sqlite3_exec_clone(db: ptr sqlite3_raw_clone, sql: cstring, cb: pointer, arg: pointer, errmsg: ptr cstring): cint {.importc: "sqlite3_exec".}
  {.pop.}
  proc execClone(db: ptr sqlite3_raw_clone, sql: string): bool =
    var errMsg: cstring
    result = sqlite3_exec_clone(db, sql.cstring, nil, nil, addr errMsg)==0
  let safeSrc = srcPath.replace("'", "''")
  discard execClone(cast[ptr sqlite3_raw_clone](dstDb.db), "ATTACH DATABASE '" & safeSrc & "' AS srcDb")
  # Ensure columns for forum/chat migration
  discard execClone(cast[ptr sqlite3_raw_clone](dstDb.db), "ALTER TABLE main.forum_thread ADD COLUMN pinned INTEGER DEFAULT 0")
  discard execClone(cast[ptr sqlite3_raw_clone](dstDb.db), "ALTER TABLE main.forum_thread ADD COLUMN locked INTEGER DEFAULT 0")
  discard execClone(cast[ptr sqlite3_raw_clone](dstDb.db), "ALTER TABLE main.forum_thread ADD COLUMN deleted INTEGER DEFAULT 0")
  discard execClone(cast[ptr sqlite3_raw_clone](dstDb.db), "ALTER TABLE main.forum_post ADD COLUMN edited INTEGER DEFAULT 0")
  discard execClone(cast[ptr sqlite3_raw_clone](dstDb.db), "ALTER TABLE main.forum_post ADD COLUMN deleted INTEGER DEFAULT 0")
  discard execClone(cast[ptr sqlite3_raw_clone](dstDb.db), "ALTER TABLE main.forum_post ADD COLUMN attachment TEXT DEFAULT ''")
  discard execClone(cast[ptr sqlite3_raw_clone](dstDb.db), "ALTER TABLE main.chat_message ADD COLUMN attachment TEXT DEFAULT ''")
  discard execClone(cast[ptr sqlite3_raw_clone](dstDb.db), "ALTER TABLE main.chat_message ADD COLUMN edited INTEGER DEFAULT 0")
  discard execClone(cast[ptr sqlite3_raw_clone](dstDb.db), "CREATE TABLE IF NOT EXISTS main.forum_moderation(queue_id TEXT PRIMARY KEY, post_id TEXT, thread_id TEXT, user TEXT, mtime INTEGER, reason TEXT, status TEXT DEFAULT 'pending')")
  let tables = @["config","event","filename","mlink","tag","tagxref","user","private","shun","backlink","unclustered","audit","ticket","ticketchng","forum_thread","forum_post","chat_message","chat_room","chat_presence","forum_moderation","search_index","delta","blob"]
  var copied = 0
  for tbl in tables:
    if execClone(cast[ptr sqlite3_raw_clone](dstDb.db), "INSERT OR REPLACE INTO main.\"" & tbl & "\" SELECT * FROM srcDb.\"" & tbl & "\""):
      inc copied
    else:
      # fallback for schema evolution
      case tbl
      of "forum_thread":
        if execClone(cast[ptr sqlite3_raw_clone](dstDb.db), "INSERT OR REPLACE INTO main.forum_thread(thread_id, title, user, created, last_mtime, pinned, locked, deleted) SELECT thread_id, title, user, created, last_mtime, COALESCE(pinned,0), COALESCE(locked,0), COALESCE(deleted,0) FROM srcDb.forum_thread"):
          inc copied
        elif execClone(cast[ptr sqlite3_raw_clone](dstDb.db), "INSERT OR REPLACE INTO main.forum_thread(thread_id, title, user, created, last_mtime) SELECT thread_id, title, user, created, last_mtime FROM srcDb.forum_thread"):
          inc copied
      of "forum_post":
        if execClone(cast[ptr sqlite3_raw_clone](dstDb.db), "INSERT OR REPLACE INTO main.forum_post(post_id, thread_id, parent_id, user, mtime, title, content, uuid, rid, edited, deleted, attachment) SELECT post_id, thread_id, parent_id, user, mtime, title, content, uuid, rid, COALESCE(edited,0), COALESCE(deleted,0), COALESCE(attachment,'') FROM srcDb.forum_post"):
          inc copied
        elif execClone(cast[ptr sqlite3_raw_clone](dstDb.db), "INSERT OR REPLACE INTO main.forum_post(post_id, thread_id, parent_id, user, mtime, title, content, uuid, rid) SELECT post_id, thread_id, parent_id, user, mtime, title, content, uuid, rid FROM srcDb.forum_post"):
          inc copied
      of "chat_message":
        if execClone(cast[ptr sqlite3_raw_clone](dstDb.db), "INSERT OR REPLACE INTO main.chat_message(msg_id, room, user, mtime, content, uuid, rid, attachment, edited) SELECT msg_id, room, user, mtime, content, uuid, rid, COALESCE(attachment,''), COALESCE(edited,0) FROM srcDb.chat_message"):
          inc copied
        elif execClone(cast[ptr sqlite3_raw_clone](dstDb.db), "INSERT OR REPLACE INTO main.chat_message(msg_id, room, user, mtime, content, uuid, rid) SELECT msg_id, room, user, mtime, content, uuid, rid FROM srcDb.chat_message"):
          inc copied
      else:
        if execClone(cast[ptr sqlite3_raw_clone](dstDb.db), "INSERT OR IGNORE INTO main.\"" & tbl & "\" SELECT * FROM srcDb.\"" & tbl & "\""):
          inc copied
  discard execClone(cast[ptr sqlite3_raw_clone](dstDb.db), "DETACH DATABASE srcDb")
  discard execClone(cast[ptr sqlite3_raw_clone](dstDb.db), "INSERT OR REPLACE INTO main.search_fts(id, kind, title, content) SELECT id, kind, title, content FROM main.search_index WHERE NOT EXISTS (SELECT 1 FROM main.search_fts WHERE search_fts.id = search_index.id)")
  # Also ensure blob count via fallback putBlob loop for any missing due to ATTACH failure
  let uuidsRes = srcDb.getAllUuids()
  if uuidsRes.isErr:
    return err[int](feIoError, "cannot get uuids")
  var count=0
  for uuid in uuidsRes.value:
    let blobRes = srcDb.getBlobByUuid(uuid)
    if blobRes.isOk:
      # putBlob will dedup if already exists
      let putRes = dstDb.putBlob(uuid, blobRes.value, false)
      if putRes.isOk:
        inc count
  ok(count)
