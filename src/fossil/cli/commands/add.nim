## Add command - adds files to checkout tracking

import ../../types
import ../../vcs/checkout as vcsCheckout
import ../../storage/sqlite_backend
import std/[os, strutils, options, times]

proc cmdAdd*(args: seq[string], checkoutRoot: string = ""): FossilResult[seq[string]] =
  var root = checkoutRoot
  if root.len == 0:
    let rootRes = vcsCheckout.findCheckoutRoot()
    if rootRes.isErr:
      return err[seq[string]](feNotRepo, "not in a checkout")
    root = rootRes.value

  if args.len == 0:
    return err[seq[string]](feInvalidArg, "no files specified")

  let checkoutDbPath = vcsCheckout.getCheckoutDbPath(root)
  if not fileExists(checkoutDbPath):
    return err[seq[string]](feNotFound, "checkout db not found")

  var db = SqliteBackend()
  if db.open(checkoutDbPath).isErr:
    return err[seq[string]](feDbError, "cannot open checkout db")

  defer: db.close()

  var added: seq[string] = @[]
  var fileTargets: seq[string] = @[]
  for f in args:
    let full = if isAbsolute(f): f else: root / f
    if dirExists(full):
      for entry in walkDirRec(full):
        if not entry.contains(".git") and not entry.contains("_FOSSIL_") and not entry.endsWith(".fossil") and not entry.contains("build/cgen") and not entry.contains("nimcache"):
          fileTargets.add entry
    elif fileExists(full):
      fileTargets.add full

  for full in fileTargets:
    let rel = relativePath(full, root)
    # Insert into vfile as added (rid 0, mrid 0, chnged true)
    let mtime = getFileInfo(full).lastWriteTime.toUnix()
    let putRes = db.putVFile(rel, invalidRid(), invalidRid(), mtime, false, false)
    if putRes.isOk:
      # SEC-07 fix: use bind
      {.push header: "<sqlite3.h>".}
      type sqlite3_stmt_a {.importc: "sqlite3_stmt", incompleteStruct.} = object
      proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt_a, pzTail: pointer): cint {.importc.}
      proc sqlite3_finalize(pStmt: ptr sqlite3_stmt_a): cint {.importc.}
      proc sqlite3_step(pStmt: ptr sqlite3_stmt_a): cint {.importc.}
      proc sqlite3_bind_text(pStmt: ptr sqlite3_stmt_a, i: cint, zData: cstring, n: cint, xDel: pointer): cint {.importc.}
      {.pop.}
      var stmt: ptr sqlite3_stmt_a
      let sql = "UPDATE vfile SET chnged=1 WHERE pathname=?1"
      if sqlite3_prepare_v2(db.db, sql.cstring, -1, addr stmt, nil)==0:
        discard sqlite3_bind_text(stmt, 1, rel.cstring, -1, nil)
        discard sqlite3_step(stmt)
        discard sqlite3_finalize(stmt)
      added.add rel

  ok(added)
