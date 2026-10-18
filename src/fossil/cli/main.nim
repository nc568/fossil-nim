## Fossil CLI - real implementations for P0

import std/[os, strutils, sequtils, tables, times, options]
import ../types
import ../config
import ../storage/sqlite_backend
import ../storage/backend
when defined(useMdbx):
  import ../storage/libmdbx_backend
when defined(useLmdb):
  import ../storage/lmdb_backend
import ../storage/cdb_backend
import ../storage/hybrid_backend as hybridMod
import ../vcs/checkout as vcsCheckout
import ../vcs/commit as vcsCommit
import ../vcs/diff as vcsDiff
import ../vcs/timeline as vcsTimeline
import ../vcs/branch as vcsBranch
import ../artifact/manifest
when not defined(qbeCompat):
  import ../mcp/server as mcpServer
  import ../api/rest as apiRest
  import ../sync/http as syncHttp
  import std/asyncdispatch
import ../sync/protocol as syncProto
import ../wiki/wiki as wikiMod
import ../ticket/ticket as ticketMod
import ../markdown/parser as mdParser
import ../th1/interp as th1Interp
import ../search/search as searchMod
import ../forum/forum as forumMod
import ../chat/chat as chatMod
import ../vcs/git_export as gitExportMod
import ../vcs/archive as archiveMod
import std/json

const Version = "2.26.0-nim"

proc printVersion() =
  echo "Fossil-Nim version ", Version, " (ported from Fossil ", Version.split("-")[0], ")"
  echo "Storage backends: sqlite, libmdbx, lmdb, cdb"
  echo "Compiled with Nim ", NimVersion, " at ", CompileDate, " ", CompileTime
  when defined(qbeCompat):
    echo "QBE compat mode: ON"
  else:
    echo "QBE compat mode: OFF"
  echo "API: REST + MCP"

proc printHelp() =
  echo """
Usage: fossil <command> [options] [args]

Common commands:
  init        Create new repository
  clone       Clone repository (local or http)
  open        Open checkout from repository
  status      Show working tree status
  add         Add files to tracking
  commit      Commit changes
  diff        Show diff (Myers)
  timeline    Show timeline
  branch      Branch operations
  stash       Stash operations
  push        Push to remote
  pull        Pull from remote
  sync        Sync with remote (pull + push)
  wiki        Wiki operations
  ticket      Ticket operations
  search      Full-text search (FTS5)
  forum       Forum operations (list/get/create/post)
  chat        Chat operations (list/send)
  git-export  Export to git fast-export format
  git-import  Import from git fast-export
  zip         Create ZIP archive (real ZIP STORE)
  tarball     Create TAR archive (real USTAR)
  archive     Create archive (zip/tar)
  server      Start HTTP server (web UI + API + /xfer + /clone)
  mcp         MCP server operations
  rebuild     Rebuild repository with different backend
  sql         Run SQL (read-only)
  version     Show version

Storage:
  --backend sqlite|libmdbx|lmdb|cdb   Select backend (default sqlite)
  --repo <file>                       Repository file

MCP:
  fossil mcp serve [--stdio]          Start MCP server (89 tools: status, diff, commit, timeline, branch, wiki, ticket, search, forum, chat, sql...)

API:
  fossil server --api-enable -P 8080  Start server with API + Web UI (wiki new/edit, ticket new, forum, chat, search FTS5)

Run 'fossil help <command>' for command help.
"""

proc printHelpCommand(cmd: string) =
  case cmd
  of "init":
    echo """
fossil init [options] <repo.fossil>
  Create new repository.
Options:
  --backend <kind>   Storage backend (sqlite, libmdbx, lmdb, cdb)
"""
  of "open":
    echo """
fossil open <repo.fossil> [checkout-dir]
  Open checkout.
"""
  of "mcp":
    echo """
fossil mcp serve [options]
  Start MCP server for AI agents.
Options:
  --stdio            Use stdio transport (default)
  --sse --port 8081  Use SSE transport
  --repo <file>      Repo path
"""
  of "commit":
    echo """
fossil commit [options]
  Commit changes.
Options:
  -m <msg>           Commit message
  --branch <name>    Branch
  --baseline <uuid>  Baseline manifest
"""
  of "status":
    echo """
fossil status
  Show working tree status.
"""
  of "timeline":
    echo """
fossil timeline [limit] [options]
  Show timeline.
Options:
  --branch <name>    Filter by branch
  --user <name>      Filter by user
  --limit <n>        Limit entries
"""
  else:
    echo "No help for command: ", cmd

proc resolveRepoPath(cfg: FossilConfig, checkoutRoot: Option[string] = none(string)): string =
  if cfg.repoPath.len>0:
    if fileExists(cfg.repoPath):
      return cfg.repoPath
    # Try relative to cwd
    let absTry = getCurrentDir() / cfg.repoPath
    if fileExists(absTry):
      return absTry
    return cfg.repoPath

  proc tryReadRepoFromFossilFile(fossilPath: string, coRoot: string): string =
    if not fileExists(fossilPath):
      return ""
    var db = SqliteBackend()
    if db.open(fossilPath).isErr:
      return ""
    defer: db.close()
    var repoVal = ""
    let r1 = db.getMeta("repository")
    if r1.isOk and r1.value.len>0:
      repoVal = r1.value
    else:
      let r2 = db.getMeta("repo")
      if r2.isOk and r2.value.len>0:
        repoVal = r2.value
    if repoVal.len==0:
      return ""
    # Resolve relative paths - try multiple locations
    if fileExists(repoVal):
      return repoVal
    if isAbsolute(repoVal) and fileExists(repoVal):
      return repoVal
    if fileExists(coRoot / repoVal):
      return coRoot / repoVal
    if fileExists(parentDir(coRoot) / repoVal):
      return parentDir(coRoot) / repoVal
    if fileExists(getCurrentDir() / repoVal):
      return getCurrentDir() / repoVal
    if fileExists(parentDir(getCurrentDir()) / repoVal):
      return parentDir(getCurrentDir()) / repoVal
    # Try absolute path from coRoot parent
    try:
      let absFromParent = absolutePath(parentDir(coRoot) / repoVal)
      if fileExists(absFromParent):
        return absFromParent
    except:
      discard
    try:
      let absFromCoRoot = absolutePath(coRoot / repoVal)
      if fileExists(absFromCoRoot):
        return absFromCoRoot
    except:
      discard
    # Return as-is if non-empty (caller will try to open)
    return repoVal

  if checkoutRoot.isSome:
    let coRoot = checkoutRoot.get
    let fossilPath = coRoot / "_FOSSIL_"
    let res = tryReadRepoFromFossilFile(fossilPath, coRoot)
    if res.len>0:
      return res
    let fossilPath2 = coRoot / ".fslckout"
    let res2 = tryReadRepoFromFossilFile(fossilPath2, coRoot)
    if res2.len>0:
      return res2

  # Try to find _FOSSIL_ in cwd
  let rootRes = vcsCheckout.findCheckoutRoot()
  if rootRes.isOk:
    let coRoot = rootRes.value
    let fossilPath = coRoot / "_FOSSIL_"
    let res = tryReadRepoFromFossilFile(fossilPath, coRoot)
    if res.len>0:
      return res
    let fossilPath2 = coRoot / ".fslckout"
    let res2 = tryReadRepoFromFossilFile(fossilPath2, coRoot)
    if res2.len>0:
      return res2

  # Fallback: look for file in cwd
  if fileExists("repo.fossil"):
    return "repo.fossil"
  if fileExists(".fossil"):
    return ".fossil"
  if fileExists(getCurrentDir() / "repo.fossil"):
    return getCurrentDir() / "repo.fossil"
  ""

# --- Command implementations ---

proc cmdInit(args: seq[string], cfg: var FossilConfig): int =
  var backend = cfg.storageKind
  var repoPath = ""
  var i=0
  while i<args.len:
    if args[i]=="--backend" and i+1<args.len:
      case args[i+1].toLowerAscii()
      of "sqlite": backend=skSqlite
      of "libmdbx","mdbx": backend=skLibMdbx
      of "lmdb": backend=skLmdb
      of "cdb": backend=skCdb
      of "hybrid-cdb","hybrid": backend=skHybridCdb
      of "hybrid-lmdb": backend=skHybridLmdb
      of "hybrid-mdbx","hybrid-libmdbx": backend=skHybridMdbx
      else: echo "Unknown backend: ", args[i+1]; return 1
      i+=2
    elif args[i].startsWith("--backend="):
      let v = args[i].split("=")[1].toLowerAscii()
      case v
      of "sqlite": backend=skSqlite
      of "libmdbx","mdbx": backend=skLibMdbx
      of "lmdb": backend=skLmdb
      of "cdb": backend=skCdb
      of "hybrid-cdb","hybrid": backend=skHybridCdb
      of "hybrid-lmdb": backend=skHybridLmdb
      of "hybrid-mdbx","hybrid-libmdbx": backend=skHybridMdbx
      else: echo "Unknown backend: ", v; return 1
      i+=1
    else:
      if repoPath=="" and not args[i].startsWith("--"):
        repoPath=args[i]
      i+=1
  if repoPath=="" :
    echo "Usage: fossil init <repo.fossil>"
    return 1
  echo "Creating repository ", repoPath, " with backend ", $backend
  case backend
  of skSqlite:
    var b = SqliteBackend()
    let r = b.open(repoPath)
    if r.isErr:
      echo "Error: ", r.error.msg
      return 1
    let schemaRes = b.initSchema()
    if schemaRes.isErr:
      echo "Error creating schema: ", schemaRes.error.msg
      b.close()
      return 1
    # Init config
    discard b.setMeta("project-name", "Unnamed")
    discard b.setMeta("repository", repoPath)
    b.close()
  of skLibMdbx:
    when defined(useMdbx):
      var b = LibMdbxBackend()
      let r = b.open(repoPath)
      if r.isErr:
        echo "Error: ", r.error.msg
        return 1
      b.close()
    else:
      echo "libmdbx backend not compiled, rebuild with -d:useMdbx and install libmdbx"
      return 1
  of skLmdb:
    when defined(useLmdb):
      var b = LmdbBackend()
      let r = b.open(repoPath)
      if r.isErr:
        echo "Error: ", r.error.msg
        return 1
      b.close()
    else:
      echo "lmdb backend not compiled, rebuild with -d:useLmdb"
      return 1
  of skCdb:
    var b = CdbBackend()
    let r = b.open(repoPath)
    if r.isErr:
      echo "Error: ", r.error.msg
      return 1
    b.close()
  of skHybridCdb:
    var b = SqliteBackend()
    let r = b.open(repoPath)
    if r.isErr:
      echo "Error: ", r.error.msg
      return 1
    discard b.initSchema()
    b.close()
    # Also create CDB kv file
    var cdb = CdbBackend()
    discard cdb.open(repoPath & ".cdbkv")
    cdb.close()
    echo "Hybrid CDB: created ", repoPath, " + ", repoPath & ".cdbkv"
  of skHybridLmdb:
    when defined(useLmdb):
      var b = SqliteBackend()
      let r = b.open(repoPath)
      if r.isErr:
        echo "Error: ", r.error.msg
        return 1
      discard b.initSchema()
      b.close()
      let kvPath = repoPath & ".lmdb"
      if not dirExists(kvPath): createDir(kvPath)
      var kv = LmdbBackend()
      discard kv.open(kvPath)
      kv.close()
      echo "Hybrid LMDB: created ", repoPath, " + ", kvPath
    else:
      echo "lmdb backend not compiled, rebuild with -d:useLmdb --passL:-llmdb"
      return 1
  of skHybridMdbx:
    when defined(useMdbx):
      var b = SqliteBackend()
      let r = b.open(repoPath)
      if r.isErr:
        echo "Error: ", r.error.msg
        return 1
      discard b.initSchema()
      b.close()
      let kvPath = repoPath & ".mdbx"
      if not dirExists(kvPath): createDir(kvPath)
      var kv = LibMdbxBackend()
      discard kv.open(kvPath)
      kv.close()
      echo "Hybrid MDBX: created ", repoPath, " + ", kvPath
    else:
      echo "libmdbx backend not compiled, rebuild with -d:useMdbx"
      return 1
  echo "Repository created."
  0

proc cmdOpen(args: seq[string], cfg: FossilConfig): int =
  if args.len==0:
    echo "Usage: fossil open <repo.fossil> [checkout-dir]"
    return 1
  var repoPath = args[0]
  # Make repoPath absolute for saving
  if not isAbsolute(repoPath):
    repoPath = absolutePath(getCurrentDir() / repoPath)
  var checkoutDir = getCurrentDir()
  if args.len>=2:
    checkoutDir = args[1]
  if not isAbsolute(checkoutDir):
    checkoutDir = absolutePath(getCurrentDir() / checkoutDir)
  if not fileExists(repoPath):
    echo "Repository not found: ", repoPath
    return 1
  if not dirExists(checkoutDir):
    try: createDir(checkoutDir)
    except:
      echo "Cannot create checkout dir: ", checkoutDir
      return 1

  # Open repo
  var repoDb = SqliteBackend()
  let openRes = repoDb.open(repoPath)
  if openRes.isErr:
    echo "Cannot open repo: ", openRes.error.msg
    return 1
  defer: repoDb.close()

  # Find latest manifest
  let timelineFilter = vcsTimeline.TimelineFilter(limit: 1, offset: 0)
  let tlRes = vcsTimeline.getTimeline(repoDb, timelineFilter)
  var manifestRid = invalidRid()
  var manifestUuid: Option[Uuid] = none(Uuid)
  if tlRes.isOk and tlRes.value.len>0:
    manifestRid = tlRes.value[0].rid
    manifestUuid = some(tlRes.value[0].uuid)
  else:
    echo "Repository is empty, creating empty checkout"
    # Create empty checkout db with repo path saved
    let createRes = vcsCheckout.createCheckoutDb(checkoutDir, invalidRid(), "trunk", repoPath)
    if createRes.isErr:
      echo "Cannot create checkout db: ", createRes.error.msg
      return 1
    echo "Empty checkout created at ", checkoutDir
    return 0

  # Get manifest blob
  let blobRes = repoDb.getBlob(manifestRid)
  if blobRes.isErr:
    echo "Cannot get manifest blob: ", blobRes.error.msg
    return 1
  let manRes = parseManifest(blobRes.value.data)
  if manRes.isErr:
    echo "Cannot parse manifest: ", manRes.error.msg
    return 1
  let manifest = manRes.value

  # Create checkout db with repo path
  let createRes = vcsCheckout.createCheckoutDb(checkoutDir, manifestRid, manifest.branch, repoPath)
  if createRes.isErr:
    echo "Cannot create checkout db: ", createRes.error.msg
    return 1

  # Materialize files
  var coRes = vcsCheckout.openCheckout(repoPath, checkoutDir)
  if coRes.isErr:
    echo "Cannot open checkout: ", coRes.error.msg
    return 1
  let matRes = vcsCheckout.materializeCheckout(repoDb, coRes.value, manifest)
  if matRes.isErr:
    echo "Cannot materialize checkout: ", matRes.error.msg
    return 1

  echo "Checkout open at ", checkoutDir, " from ", $manifestUuid.get
  0

proc cmdStatus(args: seq[string], cfg: FossilConfig): int =
  let rootRes = vcsCheckout.findCheckoutRoot()
  if rootRes.isErr:
    echo "Not in a checkout: ", rootRes.error.msg
    return 1
  let root = rootRes.value
  echo "Checkout root: ", root

  # Try to get status via vcsCheckout.status
  var repoDb = SqliteBackend()
  let repoPath = resolveRepoPath(cfg, some(root))
  if repoPath.len>0 and fileExists(repoPath):
    if repoDb.open(repoPath).isOk:
      let stRes = vcsCheckout.status(repoDb, root)
      if stRes.isOk:
        for fs in stRes.value:
          case fs.status
          of csModified: echo "M ", fs.path
          of csAdded: echo "A ", fs.path
          of csDeleted: echo "D ", fs.path
          of csUntracked: echo "? ", fs.path
          of csMissing: echo "! ", fs.path
          of csConflict: echo "C ", fs.path
          else: discard
        repoDb.close()
        return 0
      repoDb.close()

  # Fallback simple scan
  echo "Scanning ", root
  for path in walkDirRec(root):
    if not fileExists(path): continue
    let rel = relativePath(path, root)
    if rel == "_FOSSIL_" or rel == ".fslckout": continue
    if rel.startsWith("."): continue
    echo "? ", rel
  0

proc cmdAdd(args: seq[string], cfg: FossilConfig): int =
  let rootRes = vcsCheckout.findCheckoutRoot()
  if rootRes.isErr:
    echo "Not in a checkout"
    return 1
  let root = rootRes.value
  if args.len==0:
    echo "Usage: fossil add <file>..."
    return 1
  let checkoutDbPath = vcsCheckout.getCheckoutDbPath(root)
  if not fileExists(checkoutDbPath):
    echo "Checkout db not found"
    return 1
  var db = SqliteBackend()
  if db.open(checkoutDbPath).isErr:
    echo "Cannot open checkout db"
    return 1
  defer: db.close()
  var fileTargets: seq[string] = @[]
  for f in args:
    let full = if isAbsolute(f): f else: root / f
    # SEC-03: path traversal check for add
    let normRoot = normalizedPath(absolutePath(root))
    let normFull = normalizedPath(absolutePath(full))
    if not normFull.startsWith(normRoot & DirSep) and normFull != normRoot:
      echo "Forbidden: path outside checkout: ", f
      continue
    if dirExists(full):
      for entry in walkDirRec(full):
        if not entry.contains(".git") and not entry.contains("_FOSSIL_") and not entry.endsWith(".fossil") and not entry.contains("build/cgen") and not entry.contains("nimcache"):
          fileTargets.add entry
    elif fileExists(full):
      fileTargets.add full
    else:
      echo "Not found: ", f

  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt_add {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2_add(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt_add, pzTail: pointer): cint {.importc: "sqlite3_prepare_v2".}
  proc sqlite3_finalize_add(pStmt: ptr sqlite3_stmt_add): cint {.importc: "sqlite3_finalize".}
  proc sqlite3_step_add(pStmt: ptr sqlite3_stmt_add): cint {.importc: "sqlite3_step".}
  proc sqlite3_bind_text_add(pStmt: ptr sqlite3_stmt_add, i: cint, zData: cstring, n: cint, xDel: pointer): cint {.importc: "sqlite3_bind_text".}
  {.pop.}

  for full in fileTargets:
    let rel = relativePath(full, root)
    let mtime = getFileInfo(full).lastWriteTime.toUnix()
    let putRes = db.putVFile(rel, invalidRid(), invalidRid(), mtime, false, false)
    if putRes.isOk:
      var stmtAdd: ptr sqlite3_stmt_add
      let sqlAdd = "UPDATE vfile SET chnged=1 WHERE pathname=?1"
      if sqlite3_prepare_v2_add(db.db, sqlAdd.cstring, -1, addr stmtAdd, nil)==0:
        discard sqlite3_bind_text_add(stmtAdd, 1, rel.cstring, -1, nil)
        discard sqlite3_step_add(stmtAdd)
        discard sqlite3_finalize_add(stmtAdd)
      echo "Added ", rel
    else:
      echo "Failed to add ", rel, ": ", putRes.error.msg
  0

proc cmdDiff(args: seq[string], cfg: FossilConfig): int =
  let rootRes = vcsCheckout.findCheckoutRoot()
  if rootRes.isErr:
    echo "Not in a checkout"
    return 1
  let root = rootRes.value
  var file = ""
  var unified = true
  var i=0
  while i<args.len:
    if args[i]=="--unified" or args[i]=="-u":
      unified=true; inc i
    elif args[i]=="--json":
      unified=false; inc i
    elif not args[i].startsWith("--") and file=="":
      file=args[i]; inc i
    else: inc i
  if file=="":
    echo "Usage: fossil diff <file> [--unified|--json]"
    return 1
  let full = root / file
  if not fileExists(full):
    echo "File not found: ", file
    return 1
  # Try to get baseline from repo if possible
  var oldContent=""
  var newContent=""
  try:
    newContent=readFile(full)
  except:
    echo "Cannot read file: ", file
    return 1
  let repoPath = resolveRepoPath(cfg, some(root))
  if repoPath!="" and fileExists(repoPath):
    var db = SqliteBackend()
    if db.open(repoPath).isOk:
      # Try to get baseline from checkout DB vfile
      let checkoutDbPath = root / "_FOSSIL_"
      if fileExists(checkoutDbPath):
        var coDb = SqliteBackend()
        if coDb.open(checkoutDbPath).isOk:
          let vfilesRes = vcsCheckout.listVFiles(coDb)
          if vfilesRes.isOk:
            for vf in vfilesRes.value:
              if vf.pathname == file:
                # vf.rid is file content rid, vf.mrid is manifest rid
                if vf.rid != invalidRid():
                  let blobRes = db.getBlob(vf.rid)
                  if blobRes.isOk:
                    oldContent = blobRes.value.data
                  else:
                    # Try via manifest
                    if vf.mrid != invalidRid():
                      let manBlobRes = db.getBlob(vf.mrid)
                      if manBlobRes.isOk:
                        let manRes = manifest.parseManifest(manBlobRes.value.data)
                        if manRes.isOk:
                          for fc in manRes.value.files:
                            if fc.name == file:
                              let fbRes = db.getBlobByUuid(fc.uuid)
                              if fbRes.isOk:
                                oldContent = fbRes.value.data
                              break
                break
          coDb.close()
      # Fallback: try latest manifest from event
      if oldContent.len == 0:
        try:
          # Get latest manifest rid
          var latestRid: Rid = invalidRid()
          let sql = "SELECT objid FROM event WHERE type='ci' ORDER BY mtime DESC, objid DESC LIMIT 1"
          # Use low-level query
          {.push header: "<sqlite3.h>".}
          type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
          proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
          proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
          proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
          proc sqlite3_column_int64(pStmt: ptr sqlite3_stmt, iCol: cint): int64 {.importc.}
          const SQLITE_ROW = 100
          {.pop.}
          var stmt: ptr sqlite3_stmt
          if sqlite3_prepare_v2(db.db, sql.cstring, -1, addr stmt, nil) == 0:
            if sqlite3_step(stmt) == SQLITE_ROW:
              latestRid = Rid(sqlite3_column_int64(stmt, 0))
            discard sqlite3_finalize(stmt)
          if latestRid != invalidRid():
            let manBlobRes = db.getBlob(latestRid)
            if manBlobRes.isOk:
              let manRes = manifest.parseManifest(manBlobRes.value.data)
              if manRes.isOk:
                for fc in manRes.value.files:
                  if fc.name == file:
                    let fbRes = db.getBlobByUuid(fc.uuid)
                    if fbRes.isOk:
                      oldContent = fbRes.value.data
                    break
        except:
          discard
      db.close()
  # If no baseline, diff empty vs new
  let oldBlob = Blob(data: oldContent)
  let newBlob = Blob(data: newContent)
  let d = vcsDiff.diffBlobs(oldBlob, newBlob, file)
  if unified:
    echo vcsDiff.diffToUnified(d, 3)
  else:
    echo vcsDiff.diffToJson(d)
  0

proc cmdCommit(args: seq[string], cfg: FossilConfig): int =
  var message=""
  var branch="trunk"
  var baseline: Option[Uuid] = none(Uuid)
  var files: seq[string] = @[]
  var userOpt = ""
  var i=0
  while i<args.len:
    if args[i]=="-m" and i+1<args.len:
      message=args[i+1]; i+=2
    elif args[i].startsWith("-m="):
      message=args[i].split("=",1)[1]; i+=1
    elif args[i]=="--message" and i+1<args.len:
      message=args[i+1]; i+=2
    elif args[i].startsWith("--message="):
      message=args[i].split("=",1)[1]; i+=1
    elif args[i]=="--branch" and i+1<args.len:
      branch=args[i+1]; i+=2
    elif args[i].startsWith("--branch="):
      branch=args[i].split("=",1)[1]; i+=1
    elif args[i]=="--baseline" and i+1<args.len:
      let bRes = uuidFromHex(args[i+1])
      if bRes.isOk: baseline=some(bRes.value)
      i+=2
    elif args[i]=="--user" and i+1<args.len:
      userOpt=args[i+1]; i+=2
    elif args[i].startsWith("--user="):
      userOpt=args[i].split("=",1)[1]; i+=1
    elif args[i]=="--user" or args[i]=="-u":
      # support -u admin as separate?
      if i+1<args.len:
        userOpt=args[i+1]; i+=2
      else: inc i
    elif not args[i].startsWith("-"):
      files.add args[i]
      inc i
    else: inc i
  if message=="" :
    echo "Commit message required (-m)"
    return 1

  let rootRes = vcsCheckout.findCheckoutRoot()
  if rootRes.isErr:
    echo "Not in a checkout: ", rootRes.error.msg
    return 1
  let root = rootRes.value
  let repoPath = resolveRepoPath(cfg, some(root))
  if repoPath=="" or not fileExists(repoPath):
    echo "Cannot find repository"
    return 1

  var repoDb = SqliteBackend()
  let openRes = repoDb.open(repoPath)
  if openRes.isErr:
    echo "Cannot open repo: ", openRes.error.msg
    return 1
  defer: repoDb.close()

  let finalUser = if userOpt.len>0: userOpt else: getEnv("USER", "unknown")
  var opts = vcsCommit.CommitOptions(message: message, branch: branch, user: finalUser, date: now().utc, baseline: baseline, files: files)
  let commitRes = vcsCommit.commit(repoDb, opts, root)
  if commitRes.isErr:
    echo "Commit failed: ", commitRes.error.msg, " ", commitRes.error.details
    return 1
  echo "Committed as [", ($commitRes.value.newManifestUuid)[0..9], "] rid=", commitRes.value.newRid, " files=", commitRes.value.fileCount, " delta=", commitRes.value.deltaCount, " full=", commitRes.value.fullCount
  0

proc cmdTimeline(args: seq[string], cfg: FossilConfig): int =
  var limit=20
  var branch: Option[string] = none(string)
  var user: Option[string] = none(string)
  var i=0
  while i<args.len:
    if args[i]=="--branch" and i+1<args.len:
      branch=some(args[i+1]); i+=2
    elif args[i].startsWith("--branch="):
      branch=some(args[i].split("=",1)[1]); i+=1
    elif args[i]=="--user" and i+1<args.len:
      user=some(args[i+1]); i+=2
    elif args[i].startsWith("--user="):
      user=some(args[i].split("=",1)[1]); i+=1
    elif args[i]=="--limit" and i+1<args.len:
      try: limit=parseInt(args[i+1])
      except: discard
      i+=2
    elif not args[i].startsWith("--"):
      try: limit=parseInt(args[i])
      except: discard
      i+=1
    else: inc i

  let repoPath = resolveRepoPath(cfg)
  if repoPath=="" or not fileExists(repoPath):
    echo "Cannot find repository"
    return 1

  var repoDb = SqliteBackend()
  if repoDb.open(repoPath).isErr:
    echo "Cannot open repo"
    return 1
  defer: repoDb.close()

  var filter = vcsTimeline.TimelineFilter(limit: limit, offset: 0, branch: branch, user: user)
  let tlRes = vcsTimeline.getTimeline(repoDb, filter)
  if tlRes.isErr:
    echo "Cannot get timeline: ", tlRes.error.msg
    return 1
  echo vcsTimeline.timelineToText(tlRes.value)
  0

proc cmdBranch(args: seq[string], cfg: FossilConfig): int =
  let repoPath = resolveRepoPath(cfg)
  if repoPath=="" or not fileExists(repoPath):
    echo "Cannot find repository"
    return 1
  var repoDb = SqliteBackend()
  if repoDb.open(repoPath).isErr:
    echo "Cannot open repo"
    return 1
  defer: repoDb.close()

  if args.len==0 or args[0]=="list":
    let listRes = vcsBranch.listBranches(repoDb)
    if listRes.isErr:
      echo "Error: ", listRes.error.msg
      return 1
    for b in listRes.value:
      echo b.name, " (", b.count, " commits) last=", b.lastMtime
    return 0
  elif args[0]=="new" and args.len>=2:
    let name = args[1]
    let crRes = vcsBranch.createBranch(repoDb, name)
    if crRes.isErr:
      echo "Error creating branch: ", crRes.error.msg
      return 1
    echo "Branch created: ", name
    return 0
  else:
    echo "Usage: fossil branch [list|new <name>]"
    return 1

proc cmdClone(args: seq[string], cfg: FossilConfig): int =
  if args.len < 2:
    echo "Usage: fossil clone <source> <dest.fossil> [--backend sqlite]"
    echo "  source can be local file or http:// URL"
    return 1
  let src = args[0]
  let dst = args[1]
  when defined(qbeCompat):
    if src.startsWith("http://") or src.startsWith("https://"):
      echo "HTTP clone not supported in QBE mode (offline only)"
      return 1
    echo "Cloning local repo ", src, " -> ", dst
    let res = syncProto.cloneRepo(src, dst)
    if res.isErr:
      echo "Clone failed: ", res.error.msg
      return 1
    echo "Cloned ", res.value, " artifacts"
  else:
    if src.startsWith("http://") or src.startsWith("https://"):
      echo "Cloning from URL ", src, " to ", dst
      let res = syncHttp.cloneFromUrl(src, dst)
      if res.isErr:
        echo "Clone failed: ", res.error.msg, " ", res.error.details
        return 1
      echo "Cloned ", res.value, " artifacts"
    else:
      echo "Cloning local repo ", src, " -> ", dst
      let res = syncProto.cloneRepo(src, dst)
      if res.isErr:
        echo "Clone failed: ", res.error.msg
        return 1
      echo "Cloned ", res.value, " artifacts"
  0

proc cmdPush(args: seq[string], cfg: FossilConfig): int =
  if args.len < 1:
    echo "Usage: fossil push <url> [--repo <file>]"
    return 1
  let url = args[0]
  let repoPath = resolveRepoPath(cfg)
  if repoPath=="" or not fileExists(repoPath):
    echo "Cannot find repository"
    return 1
  when defined(qbeCompat):
    echo "Push over HTTP not supported in QBE mode"
    return 1
  else:
    echo "Pushing to ", url, " from ", repoPath
    let res = syncHttp.pushToUrl(repoPath, url)
    if res.isErr:
      echo "Push failed: ", res.error.msg
      return 1
    echo "Pushed ", res.value, " artifacts"
    0

proc cmdPull(args: seq[string], cfg: FossilConfig): int =
  if args.len < 1:
    echo "Usage: fossil pull <url> [--repo <file>]"
    return 1
  let url = args[0]
  let repoPath = resolveRepoPath(cfg)
  if repoPath=="" or not fileExists(repoPath):
    echo "Cannot find repository"
    return 1
  when defined(qbeCompat):
    echo "Pull over HTTP not supported in QBE mode"
    return 1
  else:
    echo "Pulling from ", url, " to ", repoPath
    let res = syncHttp.pullFromUrl(repoPath, url)
    if res.isErr:
      echo "Pull failed: ", res.error.msg
      return 1
    echo "Pulled ", res.value, " artifacts"
    0

proc cmdSync(args: seq[string], cfg: FossilConfig): int =
  if args.len < 1:
    echo "Usage: fossil sync <url> [--repo <file>]"
    return 1
  let url = args[0]
  let repoPath = resolveRepoPath(cfg)
  if repoPath=="" or not fileExists(repoPath):
    echo "Cannot find repository"
    return 1
  when defined(qbeCompat):
    echo "Sync over HTTP not supported in QBE mode"
    return 1
  else:
    echo "Syncing with ", url
    let pullRes = syncHttp.pullFromUrl(repoPath, url)
    if pullRes.isErr:
      echo "Pull part failed: ", pullRes.error.msg
      return 1
    echo "Pulled ", pullRes.value
    let pushRes = syncHttp.pushToUrl(repoPath, url)
    if pushRes.isErr:
      echo "Push part failed: ", pushRes.error.msg
      return 1
    echo "Pushed ", pushRes.value
    echo "Sync done"
    0

proc cmdWiki(args: seq[string], cfg: FossilConfig): int =
  if args.len==0:
    echo "Usage: fossil wiki <list|get|create|render> [name] [--repo <file>]"
    return 1
  let sub = args[0].toLowerAscii()
  let repoPath = resolveRepoPath(cfg)
  var db = SqliteBackend()
  var useDb = false
  if repoPath!="" and fileExists(repoPath):
    if db.open(repoPath).isOk:
      useDb=true
  case sub
  of "list", "ls":
    if useDb:
      let pagesRes = wikiMod.listWikiPages(db)
      if pagesRes.isOk:
        for p in pagesRes.value: echo p
    else:
      echo "Home\nAbout\nRoadmap\nChangelog (no repo, showing defaults)"
  of "get", "show", "cat":
    if args.len<2:
      echo "Usage: fossil wiki get <page>"
      return 1
    let name = args[1]
    if useDb:
      let pageRes = wikiMod.getWikiPage(db, name)
      if pageRes.isOk:
        echo pageRes.value.content
      else:
        echo "Error: " & pageRes.error.msg
        return 1
    else:
      echo "# " & name & "\nSample content (no repo)"
  of "render":
    if args.len<2:
      echo "Usage: fossil wiki render <page|file>"
      return 1
    let nameOrFile = args[1]
    var content = ""
    if fileExists(nameOrFile):
      content = readFile(nameOrFile)
    else:
      if useDb:
        let pageRes = wikiMod.getWikiPage(db, nameOrFile)
        if pageRes.isOk: content = pageRes.value.content
        else: content = "# " & nameOrFile
      else:
        content = "# " & nameOrFile
    let page = wikiMod.WikiPage(name: nameOrFile, content: content, format: "markdown")
    echo wikiMod.renderWikiPage(page)
  of "create", "new", "add":
    if args.len<3:
      echo "Usage: fossil wiki create <page> <file|content>"
      return 1
    let name = args[1]
    let fileOrContent = args[2]
    var content = if fileExists(fileOrContent): readFile(fileOrContent) else: fileOrContent
    let page = wikiMod.WikiPage(name: name, content: content, format: "markdown", mtime: getTime().toUnix())
    if useDb:
      let res = wikiMod.saveWikiPage(db, page, "Create wiki page " & name)
      if res.isErr:
        echo "Error: " & res.error.msg
        return 1
      echo "Wiki page ", name, " saved as rid ", res.value
    else:
      echo "No repo, would save: ", name
  else:
    echo "Unknown wiki subcommand: ", sub
    return 1
  if useDb: db.close()
  0

proc cmdTicket(args: seq[string], cfg: FossilConfig): int =
  if args.len==0:
    echo "Usage: fossil ticket <list|get|create|comment> [args]"
    return 1
  let sub = args[0].toLowerAscii()
  let repoPath = resolveRepoPath(cfg)
  var db = SqliteBackend()
  var useDb = false
  if repoPath!="" and fileExists(repoPath):
    if db.open(repoPath).isOk: useDb=true
  case sub
  of "list", "ls":
    var status = ticketMod.tsOpen
    if args.len>=2:
      try: status = parseEnum[ticketMod.TicketStatus](args[1].toLowerAscii())
      except: discard
    if useDb:
      let ticketsRes = ticketMod.listTickets(db, status, 50)
      if ticketsRes.isOk:
        for t in ticketsRes.value:
          echo t.id & " [" & $t.status & "] " & t.title
    else:
      echo "No repo, showing sample tickets"
      for i in 0..2: echo $i & " [open] Sample ticket " & $i
  of "get", "show":
    if args.len<2:
      echo "Usage: fossil ticket get <id>"
      return 1
    let id = args[1]
    if useDb:
      let tRes = ticketMod.getTicket(db, id)
      if tRes.isOk:
        echo ticketMod.renderTicket(tRes.value)
        echo "\nJSON: ", $ticketMod.ticketToJson(tRes.value)
      else:
        echo "Error: " & tRes.error.msg; return 1
    else:
      echo "Ticket " & id & " (no repo)"
  of "create", "new", "add":
    if args.len<2:
      echo "Usage: fossil ticket create <title> [description]"
      return 1
    let title = args[1]
    let desc = if args.len>=3: args[2..^1].join(" ") else: ""
    if useDb:
      let res = ticketMod.createTicket(db, title, desc)
      if res.isOk:
        echo "Created ticket: " & res.value.id & " - " & res.value.title
      else:
        echo "Error: " & res.error.msg; return 1
    else:
      echo "Would create ticket: ", title
  of "comment", "add-comment":
    if args.len<3:
      echo "Usage: fossil ticket comment <id> <text>"
      return 1
    let id = args[1]
    let text = args[2..^1].join(" ")
    if useDb:
      let res = ticketMod.addComment(db, id, text)
      if res.isOk:
        echo "Added comment ", res.value.id
      else:
        echo "Error"; return 1
    else:
      echo "Would add comment to ", id
  else:
    echo "Unknown ticket subcommand: ", sub; return 1
  if useDb: db.close()
  0

proc cmdMarkdown(args: seq[string], cfg: FossilConfig): int =
  if args.len==0:
    echo "Usage: fossil markdown <file|-> [--html|--text]"
    echo "  Reads markdown and outputs HTML"
    return 1
  var toHtml = true
  var input = ""
  for a in args:
    if a=="--html": toHtml=true
    elif a=="--text": toHtml=false
    elif a=="-": input = stdin.readAll()
    elif fileExists(a): input = readFile(a)
    else:
      if input=="": input = a
      else: input.add " " & a
  if input=="":
    echo "No input"
    return 1
  if toHtml:
    echo mdParser.markdownToHtml(input)
  else:
    echo mdParser.markdownToText(input)
  0

proc cmdTh1(args: seq[string], cfg: FossilConfig): int =
  if args.len==0:
    echo "Usage: fossil th1 <script|file> [args] OR fossil th1 eval <code>"
    return 1
  var script = ""
  var vars = initTable[string, string]()
  var i=0
  if args[0]=="eval":
    if args.len<2:
      echo "Usage: fossil th1 eval <code>"
      return 1
    script = args[1..^1].join(" ")
  else:
    let first = args[0]
    if fileExists(first):
      script = readFile(first)
      # Remaining args as var assignments var=value
      for j in 1..<args.len:
        let parts = args[j].split("=",1)
        if parts.len==2: vars[parts[0]]=parts[1]
    else:
      script = args.join(" ")
  var interp = th1Interp.newInterp()
  for k,v in vars: interp.setVar(k, v)
  let res = interp.evalScript(script)
  if interp.output.len>0: echo interp.output
  if res.toStr.len>0: echo res.toStr
  if interp.error.len>0:
    echo "TH1 error: " & interp.error
    return 1
  0

proc cmdMcp(args: seq[string], cfg: FossilConfig): int =
  when defined(qbeCompat):
    echo "MCP not supported in QBE mode (requires async)"
    return 1
  else:
    if args.len==0 or args[0]=="serve":
      var useStdio=true
      var port=3000
      var bindAddr="127.0.0.1"
      var i=0
      while i<args.len:
        if args[i]=="--sse":
          useStdio=false; inc i
        elif args[i]=="--port" and i+1<args.len:
          try: port=parseInt(args[i+1])
          except: discard
          i+=2
        elif args[i].startsWith("--port="):
          try: port=parseInt(args[i].split("=")[1])
          except: discard
          inc i
        elif args[i]=="--bind" and i+1<args.len:
          bindAddr=args[i+1]; i+=2
        else: inc i
      if useStdio:
        mcpServer.runStdioLoop(cfg)
      else:
        echo "Starting MCP SSE server on ", bindAddr, ":", port
        mcpServer.runSseLoopSync(cfg, port, bindAddr)
    else:
      echo "Unknown mcp subcommand: ", args[0]
      return 1
    0

proc cmdServer(args: seq[string], cfg: FossilConfig): int =
  when defined(qbeCompat):
    echo "API server not supported in QBE mode (requires async)"
    return 1
  else:
    var port = cfg.apiPort
    var bindAddr = cfg.apiBind
    var i=0
    while i<args.len:
      if args[i]=="-P" and i+1<args.len:
        try: port=parseInt(args[i+1])
        except: discard
        i+=2
      elif args[i]=="--port" and i+1<args.len:
        try: port=parseInt(args[i+1])
        except: discard
        i+=2
      elif (args[i]=="--bind" or args[i]=="-b" or args[i]=="--host") and i+1<args.len:
        bindAddr = args[i+1]
        i+=2
      else: inc i
    echo "Starting server on ", bindAddr, ":", port
    var cfg2 = cfg
    cfg2.apiPort=port
    cfg2.apiBind=bindAddr
    waitFor apiRest.startApiServer(cfg2)
    0

proc migrateBatched*(src: SqliteBackend, dst: var SqliteBackend, batchSize: int = 10000): FossilResult[int] =
  ## Batched migration 10k txn: read batch, write in transaction (SQLite->SQLite)
  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_exec(db: pointer, sql: cstring, cb: pointer, arg: pointer, errmsg: ptr cstring): cint {.importc.}
  {.pop.}
  var total = 0
  # Begin transaction on dst
  discard sqlite3_exec(dst.db, "BEGIN TRANSACTION".cstring, nil, nil, nil)
  let allRidsRes = src.getAllRids()
  if allRidsRes.isErr:
    discard sqlite3_exec(dst.db, "ROLLBACK".cstring, nil, nil, nil)
    return err[int](allRidsRes.error.code, allRidsRes.error.msg)
  var batchCount = 0
  for rid in allRidsRes.value:
    let blobRes = src.getBlob(rid)
    let infoRes = src.getBlobInfo(rid)
    if blobRes.isOk and infoRes.isOk:
      let putRes = dst.putBlob(infoRes.value.uuid, blobRes.value, false)
      if putRes.isOk:
        inc total
        inc batchCount
        if batchCount >= batchSize:
          discard sqlite3_exec(dst.db, "COMMIT".cstring, nil, nil, nil)
          echo "Migrated batch: ", total, " blobs"
          discard sqlite3_exec(dst.db, "BEGIN TRANSACTION".cstring, nil, nil, nil)
          batchCount = 0
  discard sqlite3_exec(dst.db, "COMMIT".cstring, nil, nil, nil)
  ok(total)

proc migrateBatchedGeneric*[S, D](src: var S, dst: var D, batchSize: int = 10000): FossilResult[int] =
  ## Generic batched migration for any StorageBackend
  var total = 0
  var batchCount = 0
  let beginRes = dst.beginTxn()
  if beginRes.isErr:
    return err[int](beginRes.error.code, beginRes.error.msg)
  let allRidsRes = src.getAllRids()
  if allRidsRes.isErr:
    discard dst.rollbackTxn()
    return err[int](allRidsRes.error.code, allRidsRes.error.msg)
  for rid in allRidsRes.value:
    let blobRes = src.getBlob(rid)
    let infoRes = src.getBlobInfo(rid)
    if blobRes.isOk and infoRes.isOk:
      let putRes = dst.putBlob(infoRes.value.uuid, blobRes.value, false)
      if putRes.isOk:
        inc total
        inc batchCount
        if batchCount >= batchSize:
          let commitRes = dst.commitTxn()
          if commitRes.isErr:
            return err[int](commitRes.error.code, commitRes.error.msg)
          echo "Migrated batch: ", total, " blobs"
          let begin2 = dst.beginTxn()
          if begin2.isErr:
            return err[int](begin2.error.code, begin2.error.msg)
          batchCount = 0
  let finalCommit = dst.commitTxn()
  if finalCommit.isErr:
    return err[int](finalCommit.error.code, finalCommit.error.msg)
  ok(total)

proc cmdRebuild(args: seq[string], cfg: FossilConfig): int =
  echo "Rebuild: converting between backends (batched 10k txn) - now copies ALL tables (event, tag, mlink, ticket, forum, chat, search, etc)"
  echo "Usage: fossil rebuild --backend <new> [--batch-size 10000] <old.fossil> <new.fossil>"
  if args.len<2:
    return 1
  var newBackend = cfg.storageKind
  var batchSize = 10000
  var positional: seq[string] = @[]
  var i=0
  while i<args.len:
    if args[i]=="--backend" and i+1<args.len:
      case args[i+1].toLowerAscii()
      of "sqlite": newBackend=skSqlite
      of "libmdbx","mdbx": newBackend=skLibMdbx
      of "lmdb": newBackend=skLmdb
      of "cdb": newBackend=skCdb
      of "hybrid-cdb","hybrid": newBackend=skHybridCdb
      of "hybrid-lmdb": newBackend=skHybridLmdb
      of "hybrid-mdbx","hybrid-libmdbx": newBackend=skHybridMdbx
      else: echo "Unknown backend: ", args[i+1]; return 1
      i+=2
    elif args[i].startsWith("--backend="):
      let v = args[i].split("=",1)[1].toLowerAscii()
      case v
      of "sqlite": newBackend=skSqlite
      of "libmdbx","mdbx": newBackend=skLibMdbx
      of "lmdb": newBackend=skLmdb
      of "cdb": newBackend=skCdb
      of "hybrid-cdb","hybrid": newBackend=skHybridCdb
      of "hybrid-lmdb": newBackend=skHybridLmdb
      of "hybrid-mdbx","hybrid-libmdbx": newBackend=skHybridMdbx
      else: echo "Unknown backend: ", v; return 1
      inc i
    elif args[i]=="--batch-size" and i+1<args.len:
      try: batchSize = parseInt(args[i+1]) except: discard
      i+=2
    elif args[i].startsWith("--batch-size="):
      try: batchSize = parseInt(args[i].split("=",1)[1]) except: discard
      inc i
    elif not args[i].startsWith("--"):
      positional.add args[i]
      inc i
    else:
      inc i
  if positional.len<2:
    echo "Need old and new paths"
    return 1
  let oldPath = positional[^2]
  let newPath = positional[^1]
  echo "Rebuilding ", oldPath, " -> ", newPath, " as ", $newBackend, " batchSize=", batchSize
  var oldDb = SqliteBackend()
  if oldDb.open(oldPath).isErr:
    echo "Cannot open old repo"
    return 1
  defer: oldDb.close()
  case newBackend
  of skSqlite:
    var newDb = SqliteBackend()
    if newDb.open(newPath).isErr:
      echo "Cannot open new repo"
      return 1
    defer: newDb.close()
    discard newDb.initSchema()
    # Copy all tables via ATTACH (fast path for sqlite->sqlite)
    let copied = hybridMod.copyAllTablesViaAttach(newDb.db, oldPath)
    echo "Copied ", copied, " tables via ATTACH (including blob, event, tag, mlink, ticket, forum, chat, search)"
    # Also ensure blobs are migrated via putBlob for compression handling
    let migRes = migrateBatched(oldDb, newDb, batchSize)
    if migRes.isErr:
      echo "Migration failed: ", migRes.error.msg
      return 1
    echo "Rebuild done: migrated ", migRes.value, " blobs + ", copied, " tables in batches of ", batchSize
  of skLibMdbx:
    when defined(useMdbx):
      if not dirExists(newPath):
        try: createDir(newPath) except: discard
      var newDb = LibMdbxBackend()
      if newDb.open(newPath).isErr:
        echo "Cannot open new libmdbx repo at ", newPath
        return 1
      defer: newDb.close()
      let migRes = migrateBatchedGeneric(oldDb, newDb, batchSize)
      if migRes.isErr:
        echo "Migration failed: ", migRes.error.msg
        return 1
      echo "Rebuild done: migrated ", migRes.value, " blobs to libmdbx in batches of ", batchSize, " (note: pure KV backends only store blobs, relational data not copied)"
    else:
      echo "libmdbx backend not compiled. Build with -d:useMdbx and install libmdbx-dev"
      echo "  nim c -d:useMdbx -d:release --mm:refc --threads:off -o:fossil src/fossil/cli/main.nim"
      return 1
  of skLmdb:
    when defined(useLmdb):
      if not dirExists(newPath):
        try: createDir(newPath) except: discard
      var newDb = LmdbBackend()
      if newDb.open(newPath).isErr:
        echo "Cannot open new lmdb repo at ", newPath
        return 1
      defer: newDb.close()
      let migRes = migrateBatchedGeneric(oldDb, newDb, batchSize)
      if migRes.isErr:
        echo "Migration failed: ", migRes.error.msg
        return 1
      echo "Rebuild done: migrated ", migRes.value, " blobs to lmdb in batches of ", batchSize, " (pure KV, no relational tables)"
    else:
      echo "lmdb backend not compiled. Build with -d:useLmdb and install liblmdb-dev"
      return 1
  of skCdb:
    var newDb = CdbBackend()
    if newDb.open(newPath).isErr:
      echo "Cannot open new cdb repo at ", newPath
      return 1
    defer: newDb.close()
    let migRes = migrateBatchedGeneric(oldDb, newDb, batchSize)
    if migRes.isErr:
      echo "Migration failed: ", migRes.error.msg
      return 1
    echo "Rebuild done: migrated ", migRes.value, " blobs to cdb in batches of ", batchSize, " (pure KV, no relational tables)"
  of skHybridCdb:
    # Use new improved migrateToHybrid that copies ALL tables + blobs to KV
    let res = hybridMod.migrateToHybrid(oldPath, newPath, hybridMod.hkSqliteCdb, batchSize)
    if res.isErr:
      echo "Hybrid migration failed: ", res.error.msg
      return 1
    echo "Rebuild done: hybrid-cdb migrated ", res.value, " blobs + all relational tables (", newPath, " + ", newPath & ".cdbkv", ")"
  of skHybridLmdb:
    when defined(useLmdb):
      let res = hybridMod.migrateToHybrid(oldPath, newPath, hybridMod.hkSqliteLmdb, batchSize)
      if res.isErr:
        echo "Hybrid migration failed: ", res.error.msg
        return 1
      echo "Rebuild done: hybrid-lmdb migrated ", res.value, " blobs + all relational tables (", newPath, " + ", newPath & ".lmdb", ")"
    else:
      echo "lmdb backend not compiled. Build with -d:useLmdb --passL:-llmdb"
      return 1
  of skHybridMdbx:
    when defined(useMdbx):
      let res = hybridMod.migrateToHybrid(oldPath, newPath, hybridMod.hkSqliteMdbx, batchSize)
      if res.isErr:
        echo "Hybrid migration failed: ", res.error.msg
        return 1
      echo "Rebuild done: hybrid-mdbx migrated ", res.value, " blobs + all relational tables (", newPath, " + ", newPath & ".mdbx", ")"
    else:
      echo "libmdbx backend not compiled. Build with -d:useMdbx"
      return 1
  0

proc cmdGitExport(args: seq[string], cfg: FossilConfig): int =
  let repoPath = resolveRepoPath(cfg)
  if repoPath=="" or not fileExists(repoPath):
    echo "Cannot find repository"
    return 1
  var branch = "trunk"
  var limit = 1000
  var outPath = "export.gitfast"
  var allBranches = false
  var i=0
  while i<args.len:
    if args[i]=="--branch" and i+1<args.len:
      branch=args[i+1]
      i+=2
    elif args[i].startsWith("--branch="):
      branch=args[i].split("=",1)[1]
      inc i
    elif args[i]=="--limit" and i+1<args.len:
      try:
        limit=parseInt(args[i+1])
      except:
        discard
      i+=2
    elif args[i].startsWith("--limit="):
      try:
        limit=parseInt(args[i].split("=",1)[1])
      except:
        discard
      inc i
    elif args[i]=="--output" and i+1<args.len:
      outPath=args[i+1]
      i+=2
    elif args[i].startsWith("--output="):
      outPath=args[i].split("=",1)[1]
      inc i
    elif args[i]=="--all" or args[i]=="--all-branches":
      allBranches=true
      inc i
    else:
      inc i
  var db = SqliteBackend()
  if db.open(repoPath).isErr:
    echo "Cannot open repo"; return 1
  defer: db.close()
  var opts = gitExportMod.GitExportOptions(branch: branch, limit: limit, outputPath: outPath, allBranches: allBranches)
  let res = gitExportMod.exportToGitFast(db, opts)
  if res.isErr:
    echo "Export failed: ", res.error.msg; return 1
  echo "Exported ", res.value.splitLines().len, " lines to ", outPath
  0

proc cmdGitImport(args: seq[string], cfg: FossilConfig): int =
  let repoPath = resolveRepoPath(cfg)
  if repoPath=="" or not fileExists(repoPath):
    echo "Cannot find repository"; return 1
  if args.len==0:
    echo "Usage: fossil git-import <file.gitfast> [--repo <repo>]"; return 1
  let importPath = args[0]
  echo "Importing from ", importPath, " into ", repoPath
  var db = SqliteBackend()
  if db.open(repoPath).isErr:
    echo "Cannot open repo"; return 1
  defer: db.close()
  let res = gitExportMod.importFromGitFast(db, importPath)
  if res.isErr:
    echo "Import failed: ", res.error.msg; return 1
  echo "Imported ", res.value, " commits"
  0

proc cmdArchive(args: seq[string], cfg: FossilConfig): int =
  let repoPath = resolveRepoPath(cfg)
  if repoPath=="" or not fileExists(repoPath):
    echo "Cannot find repository"; return 1
  var branch = "trunk"
  var path = "/"
  var outPath = "archive.zip"
  var format = "zip"
  var i=0
  while i<args.len:
    if args[i]=="--branch" and i+1<args.len:
      branch=args[i+1]; i+=2
    elif args[i].startsWith("--branch="):
      branch=args[i].split("=",1)[1]; inc i
    elif args[i]=="--path" and i+1<args.len:
      path=args[i+1]; i+=2
    elif args[i].startsWith("--path="):
      path=args[i].split("=",1)[1]; inc i
    elif args[i]=="--output" and i+1<args.len:
      outPath=args[i+1]; i+=2
    elif args[i].startsWith("--output="):
      outPath=args[i].split("=",1)[1]; inc i
    elif args[i]=="--format" and i+1<args.len:
      format=args[i+1]; i+=2
    elif args[i].startsWith("--format="):
      format=args[i].split("=",1)[1]; inc i
    elif args[i]=="zip" or args[i]=="--zip":
      format="zip"; inc i
    elif args[i]=="tar" or args[i]=="tarball" or args[i]=="--tar":
      format="tar"; inc i
    elif not args[i].startsWith("-"):
      outPath=args[i]; inc i
    else: inc i
  # Detect format from output extension if not specified
  if outPath.endsWith(".zip"):
    format="zip"
  elif outPath.endsWith(".tar") or outPath.endsWith(".tar.gz") or outPath.endsWith(".tgz"):
    format="tar"
  echo "Creating archive: branch=", branch, " path=", path, " format=", format, " output=", outPath
  var db = SqliteBackend()
  if db.open(repoPath).isErr:
    echo "Cannot open repo"; return 1
  defer: db.close()
  let res = if format=="zip": archiveMod.createZipArchive(db, branch, path) else: archiveMod.createTarArchive(db, branch, path)
  if res.isErr:
    echo "Archive failed: ", res.error.msg; return 1
  try:
    writeFile(outPath, res.value)
    echo "Archive created: ", outPath, " (", res.value.len, " bytes, ", format, ")"
  except:
    echo "Cannot write archive: ", getCurrentExceptionMsg(); return 1
  0

proc cmdSearch(args: seq[string], cfg: FossilConfig): int =
  let repoPath = resolveRepoPath(cfg)
  if repoPath=="" or not fileExists(repoPath):
    echo "Cannot find repository"; return 1
  if args.len==0:
    echo "Usage: fossil search <query> [--limit 20] [--reindex]"; return 1
  if args[0]=="--reindex" or args[0]=="reindex":
    var db = SqliteBackend()
    if db.open(repoPath).isErr:
      echo "Cannot open repo"; return 1
    defer: db.close()
    echo "Reindexing search..."
    let res = searchMod.reindexAll(db, 500, 1000)
    if res.isErr:
      echo "Reindex failed: ", res.error.msg; return 1
    echo "Reindexed ", res.value, " documents (files+commits+branches+wiki)"
    return 0
  var query = args[0]
  var limit = 20
  var i=1
  while i<args.len:
    if args[i]=="--limit" and i+1<args.len:
      try:
        limit=parseInt(args[i+1])
      except:
        discard
      i+=2
    elif args[i]=="--reindex" or args[i]=="reindex":
      var db = SqliteBackend()
      if db.open(repoPath).isErr:
        echo "Cannot open repo"; return 1
      defer: db.close()
      echo "Reindexing search..."
      let res = searchMod.reindexAll(db, 500, 1000)
      if res.isErr:
        echo "Reindex failed: ", res.error.msg; return 1
      echo "Reindexed ", res.value, " documents"
      return 0
    else: inc i
  var db = SqliteBackend()
  if db.open(repoPath).isErr:
    echo "Cannot open repo"; return 1
  defer: db.close()
  discard searchMod.initSearchIndexSqlite(db)
  let opts = searchMod.SearchOptions(query: query, limit: limit, offset: 0, kinds: @[])
  let res = searchMod.search(db, opts)
  if res.isErr:
    echo "Search failed: ", res.error.msg; return 1
  for r in res.value:
    echo "[" & r.kind & "] " & r.title & " (" & r.id & "): " & r.snippet
  0

proc cmdForum(args: seq[string], cfg: FossilConfig): int =
  let repoPath = resolveRepoPath(cfg)
  if repoPath=="" or not fileExists(repoPath):
    echo "Cannot find repository"; return 1
  if args.len==0:
    echo "Usage: fossil forum <list|get|create|post> [args]"; return 1
  var db = SqliteBackend()
  if db.open(repoPath).isErr:
    echo "Cannot open repo"; return 1
  defer: db.close()
  discard forumMod.initForumSqlite(db)
  case args[0].toLowerAscii()
  of "list":
    let res = forumMod.listThreads(db, 20)
    if res.isOk:
      for t in res.value:
        echo t.id & " - " & t.title & " by " & t.user & " last " & $t.lastMtime
    else: echo "Error: ", res.error.msg
  of "get":
    if args.len<2: echo "Usage: fossil forum get <id>"; return 1
    let res = forumMod.getThread(db, args[1])
    if res.isOk:
      echo "Thread: ", res.value.title, " by ", res.value.user
      for p in res.value.posts:
        echo "- ", p.user, " at ", $p.mtime, ": ", p.content
    else: echo "Error: ", res.error.msg
  of "create":
    if args.len<3: echo "Usage: fossil forum create <title> <content> [--user <user>]"; return 1
    var user = getEnv("USER", "cli")
    var title = args[1]
    var content = args[2]
    var i=3
    while i<args.len:
      if args[i]=="--user" and i+1<args.len:
        user=args[i+1]; i+=2
      else: inc i
    let res = forumMod.createThread(db, title, content, user)
    if res.isOk: echo "Created thread: ", res.value.id
    else: echo "Error: ", res.error.msg
  else:
    echo "Unknown forum subcommand: ", args[0]
    return 1
  0

proc cmdChat(args: seq[string], cfg: FossilConfig): int =
  let repoPath = resolveRepoPath(cfg)
  if repoPath=="" or not fileExists(repoPath):
    echo "Cannot find repository"; return 1
  if args.len==0:
    echo "Usage: fossil chat <list|send> [args]"; return 1
  var db = SqliteBackend()
  if db.open(repoPath).isErr:
    echo "Cannot open repo"; return 1
  defer: db.close()
  discard chatMod.initChatSqlite(db)
  case args[0].toLowerAscii()
  of "list":
    var room = "main"
    if args.len>=2: room=args[1]
    let res = chatMod.listMessages(db, room, 50)
    if res.isOk:
      for m in res.value:
        echo m.user & " [" & $m.mtime & "] in " & m.room & ": " & m.content
    else: echo "Error: ", res.error.msg
  of "send":
    if args.len<2: echo "Usage: fossil chat send <message> [--room <room>] [--user <user>]"; return 1
    var room = "main"
    var user = getEnv("USER", "cli")
    var content = args[1]
    var i=2
    while i<args.len:
      if args[i]=="--room" and i+1<args.len:
        room=args[i+1]; i+=2
      elif args[i]=="--user" and i+1<args.len:
        user=args[i+1]; i+=2
      else: inc i
    let res = chatMod.sendMessage(db, room, content, user)
    if res.isOk: echo "Sent: ", res.value.id
    else: echo "Error: ", res.error.msg
  else:
    echo "Unknown chat subcommand"; return 1
  0

proc cmdSql(args: seq[string], cfg: FossilConfig): int =
  let repoPath = resolveRepoPath(cfg)
  if repoPath=="" or not fileExists(repoPath):
    echo "Cannot find repository"
    return 1
  var repoDb = SqliteBackend()
  # SEC-04 fix: open in READONLY mode — engine enforces read-only, whitelist is extra defense
  if repoDb.openReadOnly(repoPath).isErr:
    echo "Cannot open repo in read-only mode"
    return 1
  defer: repoDb.close()
  # Strip --repo args from query args (config already extracted repoPath)
  var filtered: seq[string] = @[]
  var i = 0
  while i < args.len:
    if args[i] == "--repo" and i+1 < args.len:
      i += 2
    elif args[i].startsWith("--repo="):
      inc i
    else:
      filtered.add(args[i])
      inc i
  if filtered.len==0:
    echo "Usage: fossil sql <query> [--repo <file>]"
    return 1
  let query = filtered.join(" ")
  # Only allow SELECT for safety, but also allow PRAGMA and other read-only
  let qlow = query.strip().toLowerAscii()
  if not (qlow.startsWith("select") or qlow.startsWith("pragma") or qlow.startsWith("show") or qlow.startsWith(".schema")):
    echo "Only SELECT/PRAGMA queries allowed in this mode"
    return 1

  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_column_count(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_column_name(pStmt: ptr sqlite3_stmt, iCol: cint): cstring {.importc.}
  proc sqlite3_column_text(pStmt: ptr sqlite3_stmt, iCol: cint): ptr cuchar {.importc.}
  const SQLITE_ROW = 100
  const SQLITE_DONE = 101
  {.pop.}

  proc cstrToStringLocal(p: ptr cuchar): string =
    if p == nil: return "NULL"
    var len = 0
    var q = cast[cstring](p)
    while q[len] != '\0': inc len
    result = newString(len)
    if len>0:
      copyMem(addr result[0], q, len)

  var stmt: ptr sqlite3_stmt
  if sqlite3_prepare_v2(repoDb.db, query.cstring, -1, addr stmt, nil) != 0:
    echo "SQL error: cannot prepare query"
    return 1
  defer: discard sqlite3_finalize(stmt)

  var first = true
  var rowCount = 0
  while sqlite3_step(stmt) == SQLITE_ROW:
    if first:
      # Print header
      let colCount = sqlite3_column_count(stmt)
      var headers: seq[string] = @[]
      for i in 0..<colCount:
        let name = sqlite3_column_name(stmt, i.cint)
        headers.add $name
      echo headers.join(" | ")
      echo "-".repeat(headers.join(" | ").len)
      first = false
    let colCount = sqlite3_column_count(stmt)
    var vals: seq[string] = @[]
    for i in 0..<colCount:
      let txt = sqlite3_column_text(stmt, i.cint)
      vals.add cstrToStringLocal(txt)
    echo vals.join(" | ")
    inc rowCount

  if first:
    # No rows, but query succeeded
    echo "OK (no rows)"
  else:
    echo "OK (", rowCount, " rows)"
  0

# --- Main dispatcher ---

proc main(): int =
  var cfg = loadConfigFromEnv()
  let args = commandLineParams()
  if args.len==0:
    printHelp()
    return 0
  let cmd = args[0].toLowerAscii()
  let rest = if args.len>1: args[1..^1] else: @[]

  # Global flags
  for a in rest:
    if a.startsWith("--backend="):
      let v = a.split("=")[1].toLowerAscii()
      case v
      of "sqlite": cfg.storageKind=skSqlite
      of "libmdbx","mdbx": cfg.storageKind=skLibMdbx
      of "lmdb": cfg.storageKind=skLmdb
      of "cdb": cfg.storageKind=skCdb
      of "hybrid-cdb","hybrid": cfg.storageKind=skHybridCdb
      of "hybrid-lmdb": cfg.storageKind=skHybridLmdb
      of "hybrid-mdbx","hybrid-libmdbx": cfg.storageKind=skHybridMdbx
      else: discard
    elif a.startsWith("--repo="):
      cfg.repoPath=a.split("=")[1]
    elif a=="--repo" and rest.len>0:
      # handled elsewhere
      discard

  # Also check --repo as separate arg
  var i=0
  while i<rest.len:
    if rest[i]=="--repo" and i+1<rest.len:
      cfg.repoPath=rest[i+1]
      i+=2
    elif rest[i]=="--backend" and i+1<rest.len:
      let v = rest[i+1].toLowerAscii()
      case v
      of "sqlite": cfg.storageKind=skSqlite
      of "libmdbx","mdbx": cfg.storageKind=skLibMdbx
      of "lmdb": cfg.storageKind=skLmdb
      of "cdb": cfg.storageKind=skCdb
      of "hybrid-cdb","hybrid": cfg.storageKind=skHybridCdb
      of "hybrid-lmdb": cfg.storageKind=skHybridLmdb
      of "hybrid-mdbx","hybrid-libmdbx": cfg.storageKind=skHybridMdbx
      else: discard
      i+=2
    else: inc i

  # Filter global flags from rest for command handlers
  var filteredRest: seq[string] = @[]
  i = 0
  while i<rest.len:
    if rest[i]=="--repo" and i+1<rest.len:
      i+=2
    elif rest[i].startsWith("--repo="):
      inc i
    elif rest[i]=="--backend" and i+1<rest.len:
      i+=2
    elif rest[i].startsWith("--backend="):
      inc i
    else:
      filteredRest.add(rest[i])
      inc i

  case cmd
  of "version", "--version", "-v":
    printVersion()
  of "help", "--help", "-h":
    if filteredRest.len>0: printHelpCommand(filteredRest[0])
    else: printHelp()
  of "init", "new":
    result = cmdInit(filteredRest, cfg)
  of "open":
    result = cmdOpen(filteredRest, cfg)
  of "status", "st":
    result = cmdStatus(filteredRest, cfg)
  of "add":
    result = cmdAdd(filteredRest, cfg)
  of "diff", "di":
    result = cmdDiff(filteredRest, cfg)
  of "commit", "ci":
    result = cmdCommit(filteredRest, cfg)
  of "timeline", "tim":
    result = cmdTimeline(filteredRest, cfg)
  of "clone":
    result = cmdClone(filteredRest, cfg)
  of "push":
    result = cmdPush(filteredRest, cfg)
  of "pull":
    result = cmdPull(filteredRest, cfg)
  of "sync":
    result = cmdSync(filteredRest, cfg)
  of "wiki":
    result = cmdWiki(filteredRest, cfg)
  of "ticket":
    result = cmdTicket(filteredRest, cfg)
  of "markdown", "md":
    result = cmdMarkdown(filteredRest, cfg)
  of "th1":
    result = cmdTh1(filteredRest, cfg)
  of "mcp":
    result = cmdMcp(filteredRest, cfg)
  of "server", "ui":
    result = cmdServer(filteredRest, cfg)
  of "rebuild":
    result = cmdRebuild(filteredRest, cfg)
  of "branch", "br":
    result = cmdBranch(filteredRest, cfg)
  of "sql":
    result = cmdSql(filteredRest, cfg)
  of "git-export", "export":
    result = cmdGitExport(filteredRest, cfg)
  of "git-import", "import":
    result = cmdGitImport(filteredRest, cfg)
  of "zip", "tarball", "archive", "tar":
    result = cmdArchive(filteredRest, cfg)
  of "search":
    result = cmdSearch(filteredRest, cfg)
  of "forum":
    result = cmdForum(filteredRest, cfg)
  of "chat":
    result = cmdChat(filteredRest, cfg)
  else:
    echo "Unknown command: ", cmd
    printHelp()
    result=1

when isMainModule:
  quit(main())
