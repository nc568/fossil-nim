## Commit logic - fixed with mlink, filename, tag, tagxref and checkout vfile update

import ../types
import ../artifact/manifest
import ../storage/backend
import ../storage/sqlite_backend
import ../storage/schema
import ../utils/hash
import ../delta/delta as fossilDelta
import ../search/search as searchMod
import std/[os, times, tables, options, strutils]

{.push header: "<sqlite3.h>".}
type
  sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
proc sqlite3_reset(pStmt: ptr sqlite3_stmt): cint {.importc.}
proc sqlite3_clear_bindings(pStmt: ptr sqlite3_stmt): cint {.importc.}
proc sqlite3_bind_text(pStmt: ptr sqlite3_stmt, i: cint, zData: cstring, n: cint, xDel: pointer): cint {.importc.}
proc sqlite3_bind_int64(pStmt: ptr sqlite3_stmt, i: cint, iValue: int64): cint {.importc.}
proc sqlite3_column_text(pStmt: ptr sqlite3_stmt, iCol: cint): ptr cuchar {.importc.}
proc sqlite3_column_int64(pStmt: ptr sqlite3_stmt, iCol: cint): int64 {.importc.}
const
  SQLITE_ROW = 100
  SQLITE_DONE = 101
  SQLITE_OK = 0
{.pop.}

proc cstrToString(p: ptr cuchar): string =
  if p == nil: return ""
  var len = 0
  var q = cast[cstring](p)
  while q[len] != '\0': inc len
  result = newString(len)
  if len>0:
    copyMem(addr result[0], q, len)

type
  CommitOptions* = object
    message*: string
    branch*: string
    user*: string
    date*: DateTime
    allowEmpty*: bool
    isPrivate*: bool
    files*: seq[string]
    baseline*: Option[Uuid]
    force*: bool
    keepMtime*: bool

  CommitResult* = object
    newManifestUuid*: Uuid
    newRid*: Rid
    fileCount*: int
    deltaCount*: int
    fullCount*: int

proc buildManifestFromWorkingTree*(opts: CommitOptions, checkoutPath: string, baselineManifest: Option[Manifest] = none(Manifest), fileCache: var Table[string, Blob]): FossilResult[Manifest] =
  var m = Manifest()
  m.comment = opts.message
  m.user = if opts.user.len>0: opts.user else: getEnv("USER", "unknown")
  m.branch = if opts.branch.len>0: opts.branch else: "trunk"
  m.date = if opts.date != DateTime(): opts.date else: now().utc
  m.files = @[]
  m.tags = initTable[string, string]()

  if baselineManifest.isSome:
    m.parent = baselineManifest.get.parent
    if opts.baseline.isSome:
      m.parent = @[opts.baseline.get]
    else:
      if baselineManifest.get.uuid.isSome:
        m.parent = @[baselineManifest.get.uuid.get]

  var filesToScan = opts.files
  if filesToScan.len==0:
    for path in walkDirRec(checkoutPath):
      if not fileExists(path): continue
      let rel = relativePath(path, checkoutPath)
      if rel.startsWith("_FOSSIL_") or rel.startsWith(".fslckout"): continue
      if rel.startsWith(".fsl"): continue
      if rel.startsWith(".git"): continue
      if rel.endsWith(".fossil") or rel.endsWith(".fossil-shm") or rel.endsWith(".fossil-wal"): continue
      if ".fossil" in rel and (rel.endsWith("-shm") or rel.endsWith("-wal")): continue
      if rel.endsWith(".db") and fileExists(checkoutPath / "_FOSSIL_"): 
        # Skip any db files in checkout root that look like repo
        continue
      filesToScan.add rel

  for rel in filesToScan:
    let full = checkoutPath / rel
    if not fileExists(full): continue
    try:
      let data = readFile(full)
      let blob = newBlob(data)
      let uuid = hashBlob(blob)
      var perm = "644"
      m.files.add FileEntry(name: rel, uuid: uuid, perm: perm)
      fileCache[rel] = blob
    except:
      return err[Manifest](feIoError, "cannot read file", rel)

  ok(m)

proc buildManifestFromWorkingTree*(opts: CommitOptions, checkoutPath: string, baselineManifest: Option[Manifest] = none(Manifest)): FossilResult[Manifest] =
  var dummy = initTable[string, Blob]()
  buildManifestFromWorkingTree(opts, checkoutPath, baselineManifest, dummy)

proc getOrCreateFilename(db: SqliteBackend, name: string, cache: var Table[string, int64]): FossilResult[int64] =
  if cache.hasKey(name):
    return ok(cache[name])

  # Try select
  var stmt: ptr sqlite3_stmt
  let sel = "SELECT fnid FROM filename WHERE name=?"
  if sqlite3_prepare_v2(db.db, sel.cstring, -1, addr stmt, nil) == SQLITE_OK:
    discard sqlite3_bind_text(stmt, 1, name.cstring, -1, nil)
    if sqlite3_step(stmt) == SQLITE_ROW:
      let fnid = sqlite3_column_int64(stmt, 0)
      discard sqlite3_finalize(stmt)
      cache[name] = fnid
      return ok(fnid)
    discard sqlite3_finalize(stmt)

  # Insert
  var insStmt: ptr sqlite3_stmt
  let ins = "INSERT OR IGNORE INTO filename(name) VALUES(?)"
  if sqlite3_prepare_v2(db.db, ins.cstring, -1, addr insStmt, nil) == SQLITE_OK:
    discard sqlite3_bind_text(insStmt, 1, name.cstring, -1, nil)
    discard sqlite3_step(insStmt)
    discard sqlite3_finalize(insStmt)

  # Select again
  var stmt2: ptr sqlite3_stmt
  if sqlite3_prepare_v2(db.db, sel.cstring, -1, addr stmt2, nil) == SQLITE_OK:
    discard sqlite3_bind_text(stmt2, 1, name.cstring, -1, nil)
    if sqlite3_step(stmt2) == SQLITE_ROW:
      let fnid = sqlite3_column_int64(stmt2, 0)
      discard sqlite3_finalize(stmt2)
      cache[name] = fnid
      return ok(fnid)
    discard sqlite3_finalize(stmt2)

  err[int64](feDbError, "cannot get fnid", name)

proc getOrCreateFilename(db: SqliteBackend, name: string): FossilResult[int64] =
  var dummy = initTable[string, int64]()
  getOrCreateFilename(db, name, dummy)

proc getOrCreateTag(db: SqliteBackend, tagname: string, cache: var Table[string, int64]): FossilResult[int64] =
  if cache.hasKey(tagname):
    return ok(cache[tagname])

  var stmt: ptr sqlite3_stmt
  let sel = "SELECT tagid FROM tag WHERE tagname=?"
  if sqlite3_prepare_v2(db.db, sel.cstring, -1, addr stmt, nil) == SQLITE_OK:
    discard sqlite3_bind_text(stmt, 1, tagname.cstring, -1, nil)
    if sqlite3_step(stmt) == SQLITE_ROW:
      let tagid = sqlite3_column_int64(stmt, 0)
      discard sqlite3_finalize(stmt)
      cache[tagname] = tagid
      return ok(tagid)
    discard sqlite3_finalize(stmt)

  var insStmt: ptr sqlite3_stmt
  let ins = "INSERT OR IGNORE INTO tag(tagname) VALUES(?)"
  if sqlite3_prepare_v2(db.db, ins.cstring, -1, addr insStmt, nil) == SQLITE_OK:
    discard sqlite3_bind_text(insStmt, 1, tagname.cstring, -1, nil)
    discard sqlite3_step(insStmt)
    discard sqlite3_finalize(insStmt)

  var stmt2: ptr sqlite3_stmt
  if sqlite3_prepare_v2(db.db, sel.cstring, -1, addr stmt2, nil) == SQLITE_OK:
    discard sqlite3_bind_text(stmt2, 1, tagname.cstring, -1, nil)
    if sqlite3_step(stmt2) == SQLITE_ROW:
      let tagid = sqlite3_column_int64(stmt2, 0)
      discard sqlite3_finalize(stmt2)
      cache[tagname] = tagid
      return ok(tagid)
    discard sqlite3_finalize(stmt2)

  err[int64](feDbError, "cannot get tagid", tagname)

proc getOrCreateTag(db: SqliteBackend, tagname: string): FossilResult[int64] =
  var dummy = initTable[string, int64]()
  getOrCreateTag(db, tagname, dummy)

proc toJulianDate(dt: DateTime): float =
  # Convert DateTime to Julian date: JD = Unix time / 86400 + 2440587.5
  let unix = dt.toTime().toUnixFloat()
  unix / 86400.0 + 2440587.5

proc commit*[T: StorageBackend](backend: var T, opts: CommitOptions, checkoutPath: string): FossilResult[CommitResult] =
  if opts.message.strip().len==0 and not opts.allowEmpty:
    return err[CommitResult](feInvalidArg, "empty commit message")

  var baselineManifest: Option[Manifest] = none(Manifest)
  when T is SqliteBackend:
    if opts.baseline.isSome:
      let blobRes = backend.getBlobByUuid(opts.baseline.get)
      if blobRes.isOk:
        let manRes = parseManifest(blobRes.value.data)
        if manRes.isOk:
          baselineManifest = some(manRes.value)
    else:
      let sql = "SELECT objid FROM event WHERE type='ci' ORDER BY mtime DESC, objid DESC LIMIT 1"
      var stmt: ptr sqlite3_stmt
      if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) == 0:
        defer: discard sqlite3_finalize(stmt)
        if sqlite3_step(stmt) == SQLITE_ROW:
          let rid = Rid(sqlite3_column_int64(stmt, 0))
          let blobRes = backend.getBlob(rid)
          if blobRes.isOk:
            let manRes = parseManifest(blobRes.value.data)
            if manRes.isOk:
              baselineManifest = some(manRes.value)
  else:
    if opts.baseline.isSome:
      let blobRes = backend.getBlobByUuid(opts.baseline.get)
      if blobRes.isOk:
        let manRes = parseManifest(blobRes.value.data)
        if manRes.isOk:
          baselineManifest = some(manRes.value)

  var fileCache = initTable[string, Blob]()
  let manifestRes = buildManifestFromWorkingTree(opts, checkoutPath, baselineManifest, fileCache)
  if manifestRes.isErr:
    return err[CommitResult](manifestRes.error.code, manifestRes.error.msg, manifestRes.error.details)

  var manifest = manifestRes.value
  let validation = validateManifest(manifest)
  if validation.isErr:
    return err[CommitResult](validation.error.code, validation.error.msg)

  let manifestText = manifestToString(manifest)
  let blob = newBlob(manifestText)
  let uuid = hashBlob(blob)

  when T is SqliteBackend:
    discard backend.execSql("BEGIN IMMEDIATE TRANSACTION")

  var deltaCount = 0
  var fullCount = 0
  var fileRidMap = initTable[string, Rid]()
  var changedFiles: seq[FileEntry] = @[]

  var deltaStmt: ptr sqlite3_stmt
  var deltaPrep = false
  when T is SqliteBackend:
    let deltaSql = "INSERT OR REPLACE INTO delta(rid, srcid, size) VALUES(?1, ?2, ?3)"
    deltaPrep = sqlite3_prepare_v2(backend.db, deltaSql.cstring, -1, addr deltaStmt, nil) == SQLITE_OK

  for fe in manifest.files:
    let fileBlob = if fileCache.hasKey(fe.name):
                     fileCache[fe.name]
                   else:
                     let full = checkoutPath / fe.name
                     if not fileExists(full): continue
                     newBlob(readFile(full))

    var baselineUuid: Option[Uuid] = none(Uuid)
    if baselineManifest.isSome:
      for bfe in baselineManifest.get.files:
        if bfe.name == fe.name:
          baselineUuid = some(bfe.uuid)
          break

    if baselineUuid.isSome and baselineUuid.get == fe.uuid:
      # Unchanged, get existing rid
      when T is SqliteBackend:
        let ridRes = backend.getRidByUuid(fe.uuid)
        if ridRes.isOk:
          fileRidMap[fe.name] = ridRes.value
      inc fullCount
      continue

    changedFiles.add(fe)

    var srcRid: Option[Rid] = none(Rid)
    var srcBlob: Option[Blob] = none(Blob)
    if baselineUuid.isSome:
      when T is SqliteBackend:
        let baseBlobRes = backend.getBlobByUuid(baselineUuid.get)
        if baseBlobRes.isOk:
          srcBlob = some(baseBlobRes.value)
          let ridRes = backend.getRidByUuid(baselineUuid.get)
          if ridRes.isOk:
            srcRid = some(ridRes.value)

    var storedRid: Rid = invalidRid()
    if srcBlob.isSome and srcRid.isSome:
      let deltaRes = fossilDelta.deltaCreate(srcBlob.get, fileBlob)
      if deltaRes.isOk:
        let enc = fossilDelta.deltaEncode(deltaRes.value)
        if enc.len < (fileBlob.len * 70 div 100) and enc.len > 0:
          when T is SqliteBackend:
            let putRes = backend.putBlob(fe.uuid, enc, true)
            if putRes.isOk:
              if deltaPrep:
                discard sqlite3_reset(deltaStmt)
                discard sqlite3_bind_int64(deltaStmt, 1, int64(putRes.value))
                discard sqlite3_bind_int64(deltaStmt, 2, int64(srcRid.get))
                discard sqlite3_bind_int64(deltaStmt, 3, int64(enc.len))
                discard sqlite3_step(deltaStmt)
              else:
                discard backend.execSql("INSERT OR REPLACE INTO delta(rid, srcid, size) VALUES(" & $int64(putRes.value) & ", " & $int64(srcRid.get) & ", " & $enc.len & ")")
              storedRid = putRes.value
              inc deltaCount
            else:
              let putRes2 = backend.putBlob(fe.uuid, fileBlob, false)
              if putRes2.isOk:
                storedRid = putRes2.value
              inc fullCount
          else:
            let putRes = backend.putBlob(fe.uuid, fileBlob, false)
            if putRes.isOk:
              storedRid = putRes.value
            inc deltaCount
        else:
          let putRes = backend.putBlob(fe.uuid, fileBlob, false)
          if putRes.isOk:
            storedRid = putRes.value
          inc fullCount
      else:
        let putRes = backend.putBlob(fe.uuid, fileBlob, false)
        if putRes.isOk:
          storedRid = putRes.value
        inc fullCount
    else:
      let putRes = backend.putBlob(fe.uuid, fileBlob, false)
      if putRes.isOk:
        storedRid = putRes.value
      inc fullCount

    if storedRid != invalidRid():
      fileRidMap[fe.name] = storedRid
    else:
      when T is SqliteBackend:
        let ridRes = backend.getRidByUuid(fe.uuid)
        if ridRes.isOk:
          fileRidMap[fe.name] = ridRes.value

  if deltaPrep:
    discard sqlite3_finalize(deltaStmt)

  let putRes = backend.putBlob(uuid, blob, false)
  if putRes.isErr:
    when T is SqliteBackend:
      discard backend.execSql("ROLLBACK")
    return err[CommitResult](putRes.error.code, putRes.error.msg, putRes.error.details)

  let newRid = putRes.value

  when T is SqliteBackend:
    # SEC-07 fix: use parameterized query instead of replace("'", "''")
    let jd = toJulianDate(manifest.date)
    var stmt: ptr sqlite3_stmt
    let sql = "INSERT OR IGNORE INTO event(objid, type, mtime, user, comment, branch) VALUES(?1, 'ci', ?2, ?3, ?4, ?5)"
    if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil)==SQLITE_OK:
      discard sqlite3_bind_int64(stmt, 1, int64(newRid))
      discard sqlite3_bind_int64(stmt, 2, int64(jd))
      discard sqlite3_bind_text(stmt, 3, manifest.user.cstring, -1, nil)
      discard sqlite3_bind_text(stmt, 4, manifest.comment.cstring, -1, nil)
      discard sqlite3_bind_text(stmt, 5, manifest.branch.cstring, -1, nil)
      discard sqlite3_step(stmt)
      discard sqlite3_finalize(stmt)

    # Pre-populate fnidCache with all existing filenames in one fast query
    var fnidCache = initTable[string, int64]()
    var tagCache = initTable[string, int64]()
    var fnStmt: ptr sqlite3_stmt
    let fnSql = "SELECT fnid, name FROM filename"
    if sqlite3_prepare_v2(backend.db, fnSql.cstring, -1, addr fnStmt, nil) == SQLITE_OK:
      while sqlite3_step(fnStmt) == SQLITE_ROW:
        let fnid = sqlite3_column_int64(fnStmt, 0)
        let n = cstrToString(sqlite3_column_text(fnStmt, 1))
        fnidCache[n] = fnid
      discard sqlite3_finalize(fnStmt)

    # Fill filename and mlink with single prepared statement
    var mlinkStmt: ptr sqlite3_stmt
    let mlinkSql = "INSERT OR REPLACE INTO mlink(mid, fid, fnid, pid, mperm) VALUES(?1, ?2, ?3, 0, ?4)"
    let mlinkPrepOk = sqlite3_prepare_v2(backend.db, mlinkSql.cstring, -1, addr mlinkStmt, nil) == SQLITE_OK

    for fe in manifest.files:
      if not fileRidMap.hasKey(fe.name):
        continue
      let fid = fileRidMap[fe.name]
      let fnidRes = getOrCreateFilename(backend, fe.name, fnidCache)
      if fnidRes.isErr:
        continue
      let fnid = fnidRes.value
      let mperm = if fe.isExe: 1 else: 0
      if mlinkPrepOk:
        discard sqlite3_reset(mlinkStmt)
        discard sqlite3_bind_int64(mlinkStmt, 1, int64(newRid))
        discard sqlite3_bind_int64(mlinkStmt, 2, int64(fid))
        discard sqlite3_bind_int64(mlinkStmt, 3, fnid)
        discard sqlite3_bind_int64(mlinkStmt, 4, int64(mperm))
        discard sqlite3_step(mlinkStmt)
      else:
        discard backend.execSql("INSERT OR REPLACE INTO mlink(mid, fid, fnid, pid, mperm) VALUES(" & $int64(newRid) & ", " & $int64(fid) & ", " & $fnid & ", 0, " & $mperm & ")")

    if mlinkPrepOk:
      discard sqlite3_finalize(mlinkStmt)

    # Tags: branch
    let branchTag = manifest.branch
    if branchTag.len>0:
      let tagRes = getOrCreateTag(backend, "sym-" & branchTag, tagCache)
      if tagRes.isOk:
        let tagid = tagRes.value
        # SEC-07 fix: bind branch value
        var stmtTag: ptr sqlite3_stmt
        let sqlTag = "INSERT OR REPLACE INTO tagxref(tagid, tagtype, srcid, origid, value, mtime, rid) VALUES(?1, 2, 0, ?2, ?3, ?4, ?5)"
        if sqlite3_prepare_v2(backend.db, sqlTag.cstring, -1, addr stmtTag, nil)==SQLITE_OK:
          discard sqlite3_bind_int64(stmtTag, 1, int64(tagid))
          discard sqlite3_bind_int64(stmtTag, 2, int64(newRid))
          discard sqlite3_bind_text(stmtTag, 3, branchTag.cstring, -1, nil)
          discard sqlite3_bind_int64(stmtTag, 4, int64(jd))
          discard sqlite3_bind_int64(stmtTag, 5, int64(newRid))
          discard sqlite3_step(stmtTag)
          discard sqlite3_finalize(stmtTag)
      # Also create tag for branch itself
      let branchTagRes = getOrCreateTag(backend, branchTag, tagCache)
      if branchTagRes.isOk:
        let tagid2 = branchTagRes.value
        var stmtTag2: ptr sqlite3_stmt
        let sqlTag2 = "INSERT OR REPLACE INTO tagxref(tagid, tagtype, srcid, origid, value, mtime, rid) VALUES(?1, 2, 0, ?2, NULL, ?3, ?4)"
        if sqlite3_prepare_v2(backend.db, sqlTag2.cstring, -1, addr stmtTag2, nil)==SQLITE_OK:
          discard sqlite3_bind_int64(stmtTag2, 1, int64(tagid2))
          discard sqlite3_bind_int64(stmtTag2, 2, int64(newRid))
          discard sqlite3_bind_int64(stmtTag2, 3, int64(jd))
          discard sqlite3_bind_int64(stmtTag2, 4, int64(newRid))
          discard sqlite3_step(stmtTag2)
          discard sqlite3_finalize(stmtTag2)

    # --- Search auto-index ---
    # Auto-index commit and changed files (using in-memory fileCache)
    try:
      discard searchMod.initSearchIndexSqlite(backend)
      let commitTitle = "[" & manifest.branch & "] " & manifest.comment.splitLines()[0]
      let commitContent = manifest.branch & " " & manifest.user & " " & manifest.comment
      discard searchMod.indexDocumentSqlite(backend, "commit", "commit-" & $uuid, commitTitle, commitContent, int64(manifest.date.toTime().toUnix()))
      # Index changed files only (up to 50k each, skip binary)
      for fe in changedFiles:
        let ext = fe.name.split(".")[^1].toLowerAscii()
        if ext in ["png","jpg","jpeg","gif","bmp","ico","zip","gz","bz2","xz","pdf","exe","dll","so","o","a","bin"]:
          continue
        try:
          let data = if fileCache.hasKey(fe.name):
                       fileCache[fe.name].data
                     else:
                       let fullPath = checkoutPath / fe.name
                       if not fileExists(fullPath): continue
                       readFile(fullPath)
          if data.len==0 or data.len>200000: continue
          if data.contains("\0"): continue
          let toIndex = if data.len>50000: data[0..49999] else: data
          discard searchMod.indexDocumentSqlite(backend, "file", "file-" & fe.name, fe.name, toIndex, int64(manifest.date.toTime().toUnix()))
        except:
          discard
    except:
      discard

    # Commit main repository transaction
    discard backend.execSql("COMMIT")

    # Update checkout DB vfile inside single transaction with prepared statement
    let checkoutDbPath = checkoutPath / "_FOSSIL_"
    if fileExists(checkoutDbPath):
      var coDb = SqliteBackend()
      if coDb.open(checkoutDbPath).isOk:
        discard coDb.execSql("BEGIN TRANSACTION")
        discard coDb.execSql("DELETE FROM vfile")
        var stmt: ptr sqlite3_stmt
        let sql = "INSERT OR REPLACE INTO vfile(pathname, deleted, isexe, islink, rid, mrid, chnged, mtime) VALUES(?, 0, ?, ?, ?, ?, 0, ?)"
        let vfilePrepOk = sqlite3_prepare_v2(coDb.db, sql.cstring, -1, addr stmt, nil) == SQLITE_OK
        for fe in manifest.files:
          var fid = invalidRid()
          if fileRidMap.hasKey(fe.name):
            fid = fileRidMap[fe.name]
          else:
            let ridRes = backend.getRidByUuid(fe.uuid)
            if ridRes.isOk:
              fid = ridRes.value
          var mtime: int64 = getTime().toUnix()
          try:
            let info = getFileInfo(checkoutPath / fe.name)
            mtime = info.lastWriteTime.toUnix()
          except:
            discard
          if vfilePrepOk:
            discard sqlite3_reset(stmt)
            discard sqlite3_bind_text(stmt, 1, fe.name.cstring, -1, nil)
            discard sqlite3_bind_int64(stmt, 2, if fe.isExe: 1 else: 0)
            discard sqlite3_bind_int64(stmt, 3, if fe.isLink: 1 else: 0)
            discard sqlite3_bind_int64(stmt, 4, int64(fid))
            discard sqlite3_bind_int64(stmt, 5, int64(newRid))
            discard sqlite3_bind_int64(stmt, 6, mtime)
            discard sqlite3_step(stmt)
          else:
            var fallbackStmt: ptr sqlite3_stmt
            if sqlite3_prepare_v2(coDb.db, sql.cstring, -1, addr fallbackStmt, nil) == SQLITE_OK:
              discard sqlite3_bind_text(fallbackStmt, 1, fe.name.cstring, -1, nil)
              discard sqlite3_bind_int64(fallbackStmt, 2, if fe.isExe: 1 else: 0)
              discard sqlite3_bind_int64(fallbackStmt, 3, if fe.isLink: 1 else: 0)
              discard sqlite3_bind_int64(fallbackStmt, 4, int64(fid))
              discard sqlite3_bind_int64(fallbackStmt, 5, int64(newRid))
              discard sqlite3_bind_int64(fallbackStmt, 6, mtime)
              discard sqlite3_step(fallbackStmt)
              discard sqlite3_finalize(fallbackStmt)
        if vfilePrepOk:
          discard sqlite3_finalize(stmt)
        discard coDb.setMeta("checkout", $int64(newRid))
        discard coDb.setMeta("branch", manifest.branch)
        discard coDb.execSql("COMMIT")
        coDb.close()

  ok(CommitResult(newManifestUuid: uuid, newRid: newRid, fileCount: manifest.files.len, deltaCount: deltaCount, fullCount: fullCount))
