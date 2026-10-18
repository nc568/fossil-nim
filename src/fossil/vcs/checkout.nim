## Checkout logic - fixed implementation with proper vfile handling

import ../types
import ../config
import ../artifact/manifest
import ../storage/backend
import ../storage/sqlite_backend
import ../storage/schema
import std/[os, tables, options, strutils, times]

{.push header: "<sqlite3.h>".}
type
  sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
proc sqlite3_bind_text(pStmt: ptr sqlite3_stmt, i: cint, zData: cstring, n: cint, xDel: pointer): cint {.importc.}
proc sqlite3_bind_int64(pStmt: ptr sqlite3_stmt, i: cint, iValue: int64): cint {.importc.}
proc sqlite3_column_text(pStmt: ptr sqlite3_stmt, iCol: cint): ptr cuchar {.importc.}
proc sqlite3_column_int64(pStmt: ptr sqlite3_stmt, iCol: cint): int64 {.importc.}
const
  SQLITE_ROW = 100
  SQLITE_DONE = 101
  SQLITE_OK = 0
{.pop.}

type
  CheckoutStatus* = enum
    csUpToDate
    csModified
    csAdded
    csDeleted
    csConflict
    csUntracked
    csMissing
    csEdited

  FileStatus* = object
    path*: string
    status*: CheckoutStatus
    rid*: Option[Rid]
    manifestUuid*: Option[Uuid]
    fileSize*: int
    mtime*: int64

  Checkout* = object
    repoPath*: string
    rootPath*: string
    checkoutDbPath*: string
    manifestRid*: Rid
    manifestUuid*: Option[Uuid]
    branch*: string
    files*: Table[string, FileStatus]
    backendKind*: StorageKind
    isValid*: bool

  VFileEntry* = object
    id*: int
    pathname*: string
    deleted*: bool
    isExe*: bool
    isLink*: bool
    rid*: Rid
    mrid*: Rid
    chnged*: bool
    mtime*: int64
    origname*: string

proc findCheckoutRoot*(startDir: string = getCurrentDir()): FossilResult[string] =
  var dir = startDir
  while true:
    if fileExists(dir / "_FOSSIL_") or fileExists(dir / ".fslckout"):
      return ok(dir)
    let parent = parentDir(dir)
    if parent == dir: break
    dir = parent
  err[string](feNotRepo, "not a fossil checkout", startDir)

proc getCheckoutDbPath*(root: string): string =
  let p1 = root / "_FOSSIL_"
  if fileExists(p1): return p1
  let p2 = root / ".fslckout"
  if fileExists(p2): return p2
  root / "_FOSSIL_"

proc openCheckoutDb*(path: string): FossilResult[SqliteBackend] =
  var db = SqliteBackend()
  let r = db.open(path)
  if r.isErr: return err[SqliteBackend](r.error.code, r.error.msg, r.error.details)
  ok(db)

proc readVvar*(db: SqliteBackend, name: string): FossilResult[string] =
  let res = db.getMeta(name)
  if res.isOk: return res
  err[string](feNotFound, "vvar not found", name)

proc cstrToString(p: ptr cuchar): string =
  if p == nil: return ""
  var len = 0
  var q = cast[cstring](p)
  while q[len] != '\0': inc len
  result = newString(len)
  if len>0:
    copyMem(addr result[0], q, len)

proc listVFiles*(db: SqliteBackend): FossilResult[seq[VFileEntry]] =
  var entries: seq[VFileEntry] = @[]
  if not db.isOpen():
    return ok(entries)
  var stmt: ptr sqlite3_stmt
  let sql = "SELECT id, pathname, deleted, isexe, islink, rid, mrid, chnged, mtime, origname FROM vfile ORDER BY pathname"
  if sqlite3_prepare_v2(db.db, sql.cstring, -1, addr stmt, nil) != SQLITE_OK:
    # Table may not exist yet, return empty
    return ok(entries)
  defer: discard sqlite3_finalize(stmt)
  while sqlite3_step(stmt) == SQLITE_ROW:
    var e = VFileEntry()
    e.id = int(sqlite3_column_int64(stmt, 0))
    e.pathname = cstrToString(sqlite3_column_text(stmt, 1))
    e.deleted = sqlite3_column_int64(stmt, 2) != 0
    e.isExe = sqlite3_column_int64(stmt, 3) != 0
    e.isLink = sqlite3_column_int64(stmt, 4) != 0
    e.rid = Rid(sqlite3_column_int64(stmt, 5))
    e.mrid = Rid(sqlite3_column_int64(stmt, 6))
    e.chnged = sqlite3_column_int64(stmt, 7) != 0
    e.mtime = sqlite3_column_int64(stmt, 8)
    e.origname = cstrToString(sqlite3_column_text(stmt, 9))
    entries.add e
  ok(entries)

proc putVFile*(db: SqliteBackend, pathname: string, rid: Rid, mrid: Rid, mtime: int64, isExe: bool = false, isLink: bool = false): FossilResult[void] =
  if not db.isOpen():
    return errVoid(feDbError, "db not open")
  var stmt: ptr sqlite3_stmt
  let sql = "INSERT OR REPLACE INTO vfile(pathname, deleted, isexe, islink, rid, mrid, chnged, mtime) VALUES(?, 0, ?, ?, ?, ?, 0, ?)"
  if sqlite3_prepare_v2(db.db, sql.cstring, -1, addr stmt, nil) != SQLITE_OK:
    return errVoid(feDbError, "prepare vfile insert failed")
  defer: discard sqlite3_finalize(stmt)
  discard sqlite3_bind_text(stmt, 1, pathname.cstring, -1, nil)
  discard sqlite3_bind_int64(stmt, 2, if isExe: 1 else: 0)
  discard sqlite3_bind_int64(stmt, 3, if isLink: 1 else: 0)
  discard sqlite3_bind_int64(stmt, 4, int64(rid))
  discard sqlite3_bind_int64(stmt, 5, int64(mrid))
  discard sqlite3_bind_int64(stmt, 6, mtime)
  if sqlite3_step(stmt) != SQLITE_DONE:
    return errVoid(feDbError, "insert vfile failed")
  okVoid()

proc clearVFiles*(db: SqliteBackend): FossilResult[void] =
  if not db.isOpen():
    return errVoid(feDbError, "db not open")
  let r = db.execSql("DELETE FROM vfile")
  if r.isErr: return r
  okVoid()

proc status*[T: StorageBackend](backend: T, checkoutPath: string): FossilResult[seq[FileStatus]] =
  if not dirExists(checkoutPath):
    return err[seq[FileStatus]](feNotRepo, "checkout path not exists", checkoutPath)

  let checkoutDbPath = getCheckoutDbPath(checkoutPath)
  var statuses: seq[FileStatus] = @[]

  var vfiles: Table[string, VFileEntry] = initTable[string, VFileEntry]()
  if fileExists(checkoutDbPath):
    var db = SqliteBackend()
    if db.open(checkoutDbPath).isOk:
      let listRes = db.listVFiles()
      if listRes.isOk:
        for e in listRes.value:
          vfiles[e.pathname] = e
      db.close()

  # Walk working dir
  var seen: Table[string, bool] = initTable[string, bool]()
  for path in walkDirRec(checkoutPath):
    if not fileExists(path): continue
    let rel = relativePath(path, checkoutPath)
    if rel == "_FOSSIL_" or rel == ".fslckout": continue
    if rel.startsWith(".fossil"): continue
    if rel.startsWith(".git/") or rel == ".git": continue
    seen[rel] = true
    if vfiles.hasKey(rel):
      let ventry = vfiles[rel]
      try:
        let info = getFileInfo(path)
        let currentMtime = info.lastWriteTime.toUnix()
        let currentSize = int(info.size)
        # Added file: rid invalid
        if not ventry.rid.isValid or int64(ventry.rid) == 0:
          statuses.add FileStatus(path: rel, status: csAdded, rid: some(ventry.rid), fileSize: currentSize, mtime: currentMtime)
        else:
          # Try to compare content hash if backend is SqliteBackend
          var contentChanged = false
          when T is SqliteBackend:
            let oldBlobRes = backend.getBlob(ventry.rid)
            if oldBlobRes.isOk:
              let newData = readFile(path)
              if oldBlobRes.value.data != newData:
                contentChanged = true
          # Fallback to mtime check if we couldn't compare content or content same but mtime differs
          if contentChanged or ventry.chnged:
            statuses.add FileStatus(path: rel, status: csModified, rid: some(ventry.rid), fileSize: currentSize, mtime: currentMtime)
          elif currentMtime != ventry.mtime:
            # Even if mtime differs, double-check content if possible
            var changedByContent = false
            when T is SqliteBackend:
              let oldBlobRes2 = backend.getBlob(ventry.rid)
              if oldBlobRes2.isOk:
                let newData2 = readFile(path)
                if oldBlobRes2.value.data != newData2:
                  changedByContent = true
            if changedByContent or abs(currentMtime - ventry.mtime) > 2:
              # If content changed or mtime diff >2 sec, mark as edited
              # For simplicity, mark as modified if content changed, else edited
              if changedByContent:
                statuses.add FileStatus(path: rel, status: csModified, rid: some(ventry.rid), fileSize: currentSize, mtime: currentMtime)
              else:
                statuses.add FileStatus(path: rel, status: csEdited, rid: some(ventry.rid), fileSize: currentSize, mtime: currentMtime)
          else:
            discard
      except:
        if not ventry.rid.isValid or int64(ventry.rid) == 0:
          statuses.add FileStatus(path: rel, status: csAdded, rid: some(ventry.rid))
        else:
          statuses.add FileStatus(path: rel, status: csModified, rid: some(ventry.rid))
    else:
      var sz = 0
      try: sz = int(getFileSize(path))
      except: discard
      statuses.add FileStatus(path: rel, status: csUntracked, fileSize: sz)

  # Check for missing and deleted files
  for pathname, ventry in vfiles.pairs:
    if not seen.hasKey(pathname):
      let full = checkoutPath / pathname
      if not fileExists(full):
        if ventry.deleted:
          statuses.add FileStatus(path: pathname, status: csDeleted, rid: some(ventry.rid))
        else:
          statuses.add FileStatus(path: pathname, status: csMissing, rid: some(ventry.rid))

  ok(statuses)

proc openCheckout*(repoPath: string, checkoutPath: string): FossilResult[Checkout] =
  if not fileExists(repoPath):
    return err[Checkout](feNotFound, "repo not found", repoPath)
  if not dirExists(checkoutPath):
    return err[Checkout](feNotRepo, "checkout dir not exists", checkoutPath)
  let dbPath = getCheckoutDbPath(checkoutPath)
  var co = Checkout(repoPath: repoPath, rootPath: checkoutPath, checkoutDbPath: dbPath, isValid: true)
  if fileExists(dbPath):
    var db = SqliteBackend()
    if db.open(dbPath).isOk:
      let checkoutVal = db.getMeta("checkout")
      if checkoutVal.isOk:
        try:
          co.manifestRid = Rid(parseInt(checkoutVal.value))
        except:
          discard
      let branchVal = db.getMeta("branch")
      if branchVal.isOk:
        co.branch = branchVal.value
      db.close()
  ok(co)

proc materializeFile*(data: Blob, destPath: string, perm: string): FossilResult[void] =
  try:
    let parent = parentDir(destPath)
    if not dirExists(parent):
      createDir(parent)
    writeFile(destPath, data.data)
    if perm == "755" or perm == "x":
      when not defined(windows):
        try:
          setFilePermissions(destPath, {fpUserExec, fpUserRead, fpUserWrite, fpGroupRead, fpGroupExec, fpOthersRead, fpOthersExec})
        except:
          discard
    okVoid()
  except:
    errVoid(feIoError, "cannot write file", destPath & ": " & getCurrentExceptionMsg())

proc materializeCheckout*[T: StorageBackend](repoBackend: var T, checkout: Checkout, manifest: Manifest): FossilResult[void] =
  # Open checkout db and clear vfiles
  var checkoutDb = SqliteBackend()
  if not fileExists(checkout.checkoutDbPath):
    return errVoid(feNotFound, "checkout db not found", checkout.checkoutDbPath)
  if checkoutDb.open(checkout.checkoutDbPath).isErr:
    return errVoid(feDbError, "cannot open checkout db")
  defer: checkoutDb.close()
  discard checkoutDb.clearVFiles()

  let normRoot = normalizedPath(absolutePath(checkout.rootPath))

  for fe in manifest.files:
    if fe.name.len == 0 or fe.name.contains("..") or fe.name.startsWith("/") or fe.name.startsWith("\\"):
      return errVoid(feSecurityError, "unsafe file path in manifest: path traversal blocked", fe.name)
    let destPath = normalizedPath(absolutePath(checkout.rootPath / fe.name))
    if not destPath.startsWith(normRoot & DirSep) and destPath != normRoot:
      return errVoid(feSecurityError, "file path escapes checkout root", fe.name)
    let blobRes = repoBackend.getBlobByUuid(fe.uuid)
    if blobRes.isErr:
      continue
    let matRes = materializeFile(blobRes.value, destPath, fe.perm)
    if matRes.isErr:
      return errVoid(matRes.error.code, matRes.error.msg, matRes.error.details)
    # Insert into vfile
    var mtime: int64 = 0
    try:
      let info = getFileInfo(destPath)
      mtime = info.lastWriteTime.toUnix()
    except:
      mtime = getTime().toUnix()
    # Need rid of file content
    var fileRid: Rid = invalidRid()
    when T is SqliteBackend:
      let ridRes = repoBackend.getRidByUuid(fe.uuid)
      if ridRes.isOk:
        fileRid = ridRes.value
    discard checkoutDb.putVFile(fe.name, fileRid, checkout.manifestRid, mtime, fe.isExe, fe.isLink)

  # Update checkout meta
  discard checkoutDb.setMeta("checkout", $int64(checkout.manifestRid))
  if manifest.branch.len>0:
    discard checkoutDb.setMeta("branch", manifest.branch)

  okVoid()

proc createCheckoutDb*(checkoutPath: string, manifestRid: Rid, branch: string = "trunk", repoPath: string = ""): FossilResult[void] =
  let dbPath = checkoutPath / "_FOSSIL_"
  var db = SqliteBackend()
  let openRes = db.open(dbPath)
  if openRes.isErr: return errVoid(openRes.error.code, openRes.error.msg)
  defer: db.close()
  let schemaRes = db.initCheckoutSchema()
  if schemaRes.isErr: return schemaRes
  discard db.setMeta("checkout", $int64(manifestRid))
  discard db.setMeta("branch", branch)
  discard db.setMeta("repo", repoPath)
  discard db.setMeta("repository", repoPath)
  discard db.setMeta("project-code", "")
  # Clear vfile for fresh checkout
  discard db.clearVFiles()
  okVoid()
