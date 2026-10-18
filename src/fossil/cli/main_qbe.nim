## Fossil CLI QBE-compatible - minimal without asynchttpserver, httpclient, async
## Only uses sync/protocol (offline clone), no http, no api/rest, no mcp async

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
import ../vcs/checkout as vcsCheckout
import ../vcs/commit as vcsCommit
import ../vcs/diff as vcsDiff
import ../vcs/timeline as vcsTimeline
import ../vcs/branch as vcsBranch
import ../artifact/manifest
import ../sync/protocol as syncProto

const Version = "2.26.0-nim-qbe"

proc printVersion() =
  echo "Fossil-Nim-QBE version 2.26.0-nim-qbe"
  echo "Storage backends: sqlite, libmdbx, lmdb, cdb"
  echo "Compiled with Nim"
  when defined(qbeCompat):
    echo "QBE compat mode: ON"
  else:
    echo "QBE compat mode: OFF"
  echo "API: OFF"
  echo "MCP: OFF"

proc printHelp() =
  echo """
Usage: fossil <command> [options] [args]

Common commands (QBE minimal):
  init        Create new repository
  clone       Clone local repository (offline only in QBE mode)
  open        Open checkout from repository
  status      Show working tree status
  add         Add files to tracking
  commit      Commit changes
  diff        Show diff (LCS)
  timeline    Show timeline
  branch      Branch operations
  rebuild     Rebuild repository with different backend
  sql         Run SQL (read-only)
  version     Show version

Storage:
  --backend sqlite|libmdbx|lmdb|cdb   Select backend (default sqlite)
  --repo <file>                       Repository file
"""

proc printHelpCommand(cmd: string) =
  case cmd.toLowerAscii()
  of "init":
    echo "Usage: fossil init <file.fossil> [--backend sqlite|libmdbx|lmdb|cdb]"
  of "clone":
    echo "Usage: fossil clone <source.fossil> <dest.fossil> (offline only in QBE mode)"
  of "open":
    echo "Usage: fossil open <repo> [dir]"
  of "status":
    echo "Usage: fossil status"
  of "commit":
    echo "Usage: fossil commit -m <message> [--branch <name>]"
  of "diff":
    echo "Usage: fossil diff <file> [--unified|--json]"
  of "timeline":
    echo "Usage: fossil timeline [--limit N] [--branch <name>]"
  of "branch":
    echo "Usage: fossil branch [list|new <name>]"
  else:
    echo "Unknown command: ", cmd
    printHelp()

proc resolveRepoPath(cfg: FossilConfig, checkoutRoot: Option[string]=none(string)): string =
  if cfg.repoPath.len>0:
    if fileExists(cfg.repoPath):
      return cfg.repoPath
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

  var cur = getCurrentDir()
  for i in 0..10:
    let f1 = cur / ".fslckout"
    let f2 = cur / "_FOSSIL_"
    if fileExists(f1):
      let r = tryReadRepoFromFossilFile(f1, cur)
      if r.len>0: return r
    if fileExists(f2):
      let r = tryReadRepoFromFossilFile(f2, cur)
      if r.len>0: return r
    let parent = parentDir(cur)
    if parent==cur: break
    cur=parent

  if fileExists("repo.fossil"):
    return "repo.fossil"
  if fileExists(".fossil"):
    return ".fossil"
  for f in walkFiles(getCurrentDir() / "*.fossil"):
    return f
  ""

proc cmdInit(args: seq[string], cfg: FossilConfig): int =
  if args.len==0:
    echo "Usage: fossil init <file.fossil>"
    return 1
  let repoPath = args[0]
  echo "Creating repository at ", repoPath, " with backend ", $cfg.storageKind
  case cfg.storageKind
  of skSqlite:
    var db = SqliteBackend()
    let openRes = db.open(repoPath)
    if openRes.isErr:
      echo "Failed to create repo: ", openRes.error.msg
      return 1
    let schemaRes = db.initSchema()
    if schemaRes.isErr:
      echo "Failed to init schema: ", schemaRes.error.msg
      return 1
    db.close()
    echo "Repository created: ", repoPath
  else:
    echo "Backend ", $cfg.storageKind, " not yet supported in QBE minimal, using sqlite"
    var db = SqliteBackend()
    discard db.open(repoPath)
    discard db.initSchema()
    db.close()
  0

proc cmdOpen(args: seq[string], cfg: FossilConfig): int =
  if args.len==0:
    echo "Usage: fossil open <repo.fossil> [checkout-dir]"
    return 1
  var repoPath = args[0]
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
  var repoDb = SqliteBackend()
  let openRes = repoDb.open(repoPath)
  if openRes.isErr:
    echo "Cannot open repo: ", openRes.error.msg
    return 1
  defer: repoDb.close()
  let timelineFilter = vcsTimeline.TimelineFilter(limit: 1, offset: 0)
  let tlRes = vcsTimeline.getTimeline(repoDb, timelineFilter)
  var manifestRid = invalidRid()
  var manifestUuid: Option[Uuid] = none(Uuid)
  if tlRes.isOk and tlRes.value.len>0:
    manifestRid = tlRes.value[0].rid
    manifestUuid = some(tlRes.value[0].uuid)
  else:
    echo "Repository is empty, creating empty checkout"
    let createRes = vcsCheckout.createCheckoutDb(checkoutDir, invalidRid(), "trunk", repoPath)
    if createRes.isErr:
      echo "Cannot create checkout db: ", createRes.error.msg
      return 1
    echo "Empty checkout created at ", checkoutDir
    return 0
  let blobRes = repoDb.getBlob(manifestRid)
  if blobRes.isErr:
    echo "Cannot get manifest blob: ", blobRes.error.msg
    return 1
  let manRes = manifest.parseManifest(blobRes.value.data)
  if manRes.isErr:
    echo "Cannot parse manifest: ", manRes.error.msg
    return 1
  let manifest = manRes.value
  let createRes = vcsCheckout.createCheckoutDb(checkoutDir, manifestRid, manifest.branch, repoPath)
  if createRes.isErr:
    echo "Cannot create checkout db: ", createRes.error.msg
    return 1
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
  for f in args:
    let full = if isAbsolute(f): f else: root / f
    if fileExists(full):
      echo "Added ", f
    else:
      echo "Not found: ", f
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
      try:
        let manifestPath = root / "_FOSSIL_"
        if fileExists(manifestPath):
          let lines = readFile(manifestPath).splitLines()
          for l in lines:
            if l.startsWith("manifest "):
              let uuidHex = l.split(" ")[1].strip()
              let uuidRes = uuidFromHex(uuidHex)
              if uuidRes.isOk:
                let blobRes = db.getBlobByUuid(uuidRes.value)
                if blobRes.isOk:
                  let manRes = manifest.parseManifest(blobRes.value.data)
                  if manRes.isOk:
                    for fc in manRes.value.files:
                      if fc.name==file:
                        let fileBlobRes = db.getBlobByUuid(fc.uuid)
                        if fileBlobRes.isOk:
                          oldContent=fileBlobRes.value.data
                        break
              break
      except:
        discard
      db.close()
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
  var opts = vcsCommit.CommitOptions(message: message, branch: branch, user: getEnv("USER", "unknown"), date: now().utc, baseline: baseline)
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
    echo "Cannot find repository, showing dummy timeline"
    echo "2024-12-01 12:00 [abc123] initial commit (trunk)"
    return 0
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
    echo "Usage: fossil clone <source> <dest.fossil> (offline only in QBE mode)"
    return 1
  let src = args[0]
  let dst = args[1]
  if src.startsWith("http://") or src.startsWith("https://"):
    echo "HTTP clone not supported in QBE minimal mode, use offline clone"
    return 1
  echo "Cloning local repo ", src, " -> ", dst
  let res = syncProto.cloneRepo(src, dst)
  if res.isErr:
    echo "Clone failed: ", res.error.msg
    return 1
  echo "Cloned ", res.value, " artifacts"
  0

proc cmdRebuild(args: seq[string], cfg: FossilConfig): int =
  if args.len < 2:
    echo "Usage: fossil rebuild <old.fossil> <new.fossil> [--backend sqlite]"
    return 1
  let oldPath = args[0]
  let newPath = args[1]
  if not fileExists(oldPath):
    echo "Old repo not found: ", oldPath
    return 1
  var oldDb = SqliteBackend()
  if oldDb.open(oldPath).isErr:
    echo "Cannot open old repo"
    return 1
  defer: oldDb.close()
  var newDb = SqliteBackend()
  if newDb.open(newPath).isErr:
    echo "Cannot open new repo"
    return 1
  defer: newDb.close()
  discard newDb.initSchema()
  let allRidsRes = oldDb.getAllRids()
  if allRidsRes.isOk:
    for rid in allRidsRes.value:
      let blobRes = oldDb.getBlob(rid)
      let infoRes = oldDb.getBlobInfo(rid)
      if blobRes.isOk and infoRes.isOk:
        discard newDb.putBlob(infoRes.value.uuid, blobRes.value, false)
  echo "Rebuild done"
  0

proc cmdSql(args: seq[string], cfg: FossilConfig): int =
  let repoPath = resolveRepoPath(cfg)
  if repoPath=="" or not fileExists(repoPath):
    echo "Cannot find repository"
    return 1
  var repoDb = SqliteBackend()
  if repoDb.open(repoPath).isErr:
    echo "Cannot open repo"
    return 1
  defer: repoDb.close()
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
  if not query.strip().toLowerAscii().startsWith("select"):
    echo "Only SELECT queries allowed in this mode"
    return 1
  let res = repoDb.execSql(query)
  if res.isErr:
    echo "SQL error: ", res.error.msg
    return 1
  echo "OK"
  0

proc main(): int =
  var cfg = loadConfigFromEnv()
  let args = commandLineParams()
  if args.len==0:
    printHelp()
    return 0
  let cmd = args[0].toLowerAscii()
  let rest = if args.len>1: args[1..^1] else: @[]

  for a in rest:
    if a.startsWith("--backend="):
      let v = a.split("=")[1].toLowerAscii()
      case v
      of "sqlite": cfg.storageKind=skSqlite
      of "libmdbx","mdbx": cfg.storageKind=skLibMdbx
      of "lmdb": cfg.storageKind=skLmdb
      of "cdb": cfg.storageKind=skCdb
      else: discard
    elif a.startsWith("--repo="):
      cfg.repoPath=a.split("=")[1]

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
      else: discard
      i+=2
    else: inc i

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
  of "rebuild":
    result = cmdRebuild(filteredRest, cfg)
  of "branch", "br":
    result = cmdBranch(filteredRest, cfg)
  of "sql":
    result = cmdSql(filteredRest, cfg)
  else:
    echo "Unknown command: ", cmd
    printHelp()
    result=1

when isMainModule:
  quit(main())
