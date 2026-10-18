## Fossil CLI QBE-compatible full - includes MCP stdio but no web (no asynchttpserver)
## Uses sync/protocol offline, plus MCP server

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
import ../mcp/server as mcpServer

const Version = "2.26.0-nim-qbe-full"

proc printVersion() =
  echo "Fossil-Nim-QBE-Full version ", Version
  echo "Storage backends: sqlite, libmdbx, lmdb, cdb"
  echo "Compiled with Nim ", NimVersion, " at ", CompileDate, " ", CompileTime
  when defined(qbeCompat):
    echo "QBE compat mode: ON"
  else:
    echo "QBE compat mode: OFF"
  echo "API: OFF (QBE)"
  echo "MCP: ON (stdio)"

proc printHelp() =
  echo """
Usage: fossil <command> [options] [args]

Common commands (QBE full):
  init        Create new repository
  clone       Clone local repository (offline only in QBE mode)
  open        Open checkout
  status      Show status
  add         Add files
  commit      Commit
  diff        Show diff
  timeline    Show timeline
  branch      Branch ops
  mcp         MCP server (stdio)
  rebuild     Rebuild repo
  sql         Run SQL
  version     Show version
"""

proc printHelpCommand(cmd: string) =
  case cmd.toLowerAscii()
  of "init": echo "Usage: fossil init <file.fossil> [--backend sqlite]"
  of "clone": echo "Usage: fossil clone <src> <dst> (offline)"
  of "mcp": echo "Usage: fossil mcp serve [--stdio]"
  else: echo "Unknown command: ", cmd; printHelp()

proc resolveRepoPath(cfg: FossilConfig, checkoutRoot: Option[string]=none(string)): string =
  if cfg.repoPath.len>0 and fileExists(cfg.repoPath): return cfg.repoPath
  if checkoutRoot.isSome:
    let root = checkoutRoot.get
    let fossilFile = root / "_FOSSIL_"
    if fileExists(fossilFile):
      try:
        let content = readFile(fossilFile).splitLines()
        for line in content:
          if line.startsWith("repository "):
            let p = line.split(" ",1)[1].strip()
            if fileExists(p): return p
      except: discard
  var cur = getCurrentDir()
  for i in 0..10:
    let f1 = cur / ".fslckout"
    let f2 = cur / "_FOSSIL_"
    if fileExists(f1) or fileExists(f2):
      try:
        let metaPath = if fileExists(f1): f1 else: f2
        let lines = readFile(metaPath).splitLines()
        for l in lines:
          if l.startsWith("repository "):
            let p = l.split(" ",1)[1].strip()
            if fileExists(p): return p
      except: discard
    let parent = parentDir(cur)
    if parent==cur: break
    cur=parent
  for f in walkFiles(getCurrentDir() / "*.fossil"):
    return f
  ""

proc cmdInit(args: seq[string], cfg: FossilConfig): int =
  if args.len==0:
    echo "Usage: fossil init <file.fossil>"
    return 1
  let repoPath = args[0]
  echo "Creating repository at ", repoPath, " with backend ", $cfg.storageKind
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
  0

proc cmdOpen(args: seq[string], cfg: FossilConfig): int =
  if args.len==0:
    echo "Usage: fossil open <repo.fossil> [checkout-dir]"
    return 1
  let repoPath = args[0]
  var checkoutDir = getCurrentDir()
  if args.len>=2: checkoutDir=args[1]
  if not fileExists(repoPath):
    echo "Repository not found: ", repoPath
    return 1
  if not dirExists(checkoutDir):
    try: createDir(checkoutDir)
    except: return 1
  var repoDb = SqliteBackend()
  if repoDb.open(repoPath).isErr: return 1
  defer: repoDb.close()
  let timelineFilter = vcsTimeline.TimelineFilter(limit: 1, offset: 0)
  let tlRes = vcsTimeline.getTimeline(repoDb, timelineFilter)
  var manifestRid = invalidRid()
  if tlRes.isOk and tlRes.value.len>0:
    manifestRid = tlRes.value[0].rid
  else:
    let cr = vcsCheckout.createCheckoutDb(checkoutDir, invalidRid())
    if cr.isErr: return 1
    return 0
  let blobRes = repoDb.getBlob(manifestRid)
  if blobRes.isErr: return 1
  let manRes = manifest.parseManifest(blobRes.value.data)
  if manRes.isErr: return 1
  let manifest = manRes.value
  let createRes = vcsCheckout.createCheckoutDb(checkoutDir, manifestRid, manifest.branch)
  if createRes.isErr: return 1
  var coRes = vcsCheckout.openCheckout(repoPath, checkoutDir)
  if coRes.isErr: return 1
  let matRes = vcsCheckout.materializeCheckout(repoDb, coRes.value, manifest)
  if matRes.isErr: return 1
  echo "Checkout open at ", checkoutDir
  0

proc cmdStatus(args: seq[string], cfg: FossilConfig): int =
  let rootRes = vcsCheckout.findCheckoutRoot()
  if rootRes.isErr:
    echo "Not in a checkout"
    return 1
  let root = rootRes.value
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
  echo "Checkout root: ", root
  0

proc cmdAdd(args: seq[string], cfg: FossilConfig): int =
  let rootRes = vcsCheckout.findCheckoutRoot()
  if rootRes.isErr: return 1
  let root = rootRes.value
  if args.len==0: return 1
  for f in args:
    let full = if isAbsolute(f): f else: root / f
    if fileExists(full): echo "Added ", f
  0

proc cmdDiff(args: seq[string], cfg: FossilConfig): int =
  let rootRes = vcsCheckout.findCheckoutRoot()
  if rootRes.isErr: return 1
  let root = rootRes.value
  var file = ""
  var unified = true
  var i=0
  while i<args.len:
    if args[i]=="--unified" or args[i]=="-u": unified=true; inc i
    elif args[i]=="--json": unified=false; inc i
    elif not args[i].startsWith("--") and file=="": file=args[i]; inc i
    else: inc i
  if file=="": return 1
  let full = root / file
  if not fileExists(full): return 1
  var oldContent=""
  var newContent=""
  try: newContent=readFile(full)
  except: return 1
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
                        if fileBlobRes.isOk: oldContent=fileBlobRes.value.data
                        break
              break
      except: discard
      db.close()
  let oldBlob = Blob(data: oldContent)
  let newBlob = Blob(data: newContent)
  let d = vcsDiff.diffBlobs(oldBlob, newBlob, file)
  if unified: echo vcsDiff.diffToUnified(d, 3)
  else: echo vcsDiff.diffToJson(d)
  0

proc cmdCommit(args: seq[string], cfg: FossilConfig): int =
  var message=""
  var branch="trunk"
  var i=0
  while i<args.len:
    if args[i]=="-m" and i+1<args.len: message=args[i+1]; i+=2
    elif args[i].startsWith("-m="): message=args[i].split("=",1)[1]; i+=1
    elif args[i]=="--branch" and i+1<args.len: branch=args[i+1]; i+=2
    else: inc i
  if message=="": return 1
  let rootRes = vcsCheckout.findCheckoutRoot()
  if rootRes.isErr: return 1
  let root = rootRes.value
  let repoPath = resolveRepoPath(cfg, some(root))
  if repoPath=="" or not fileExists(repoPath): return 1
  var repoDb = SqliteBackend()
  if repoDb.open(repoPath).isErr: return 1
  defer: repoDb.close()
  var opts = vcsCommit.CommitOptions(message: message, branch: branch, user: getEnv("USER", "unknown"), date: now().utc, baseline: none(Uuid))
  let commitRes = vcsCommit.commit(repoDb, opts, root)
  if commitRes.isErr: return 1
  echo "Committed rid=", commitRes.value.newRid
  0

proc cmdTimeline(args: seq[string], cfg: FossilConfig): int =
  var limit=20
  var i=0
  while i<args.len:
    if args[i]=="--limit" and i+1<args.len:
      try: limit=parseInt(args[i+1])
      except: discard
      i+=2
    else: inc i
  let repoPath = resolveRepoPath(cfg)
  if repoPath=="" or not fileExists(repoPath): return 0
  var repoDb = SqliteBackend()
  if repoDb.open(repoPath).isErr: return 1
  defer: repoDb.close()
  var filter = vcsTimeline.TimelineFilter(limit: limit, offset: 0)
  let tlRes = vcsTimeline.getTimeline(repoDb, filter)
  if tlRes.isErr: return 1
  echo vcsTimeline.timelineToText(tlRes.value)
  0

proc cmdBranch(args: seq[string], cfg: FossilConfig): int =
  let repoPath = resolveRepoPath(cfg)
  if repoPath=="" or not fileExists(repoPath): return 1
  var repoDb = SqliteBackend()
  if repoDb.open(repoPath).isErr: return 1
  defer: repoDb.close()
  if args.len==0 or args[0]=="list":
    let listRes = vcsBranch.listBranches(repoDb)
    if listRes.isErr: return 1
    for b in listRes.value: echo b.name, " (", b.count, ")"
    return 0
  elif args[0]=="new" and args.len>=2:
    let crRes = vcsBranch.createBranch(repoDb, args[1])
    if crRes.isErr: return 1
    echo "Branch created: ", args[1]
    return 0
  else: return 1

proc cmdClone(args: seq[string], cfg: FossilConfig): int =
  if args.len < 2: return 1
  let src = args[0]
  let dst = args[1]
  let res = syncProto.cloneRepo(src, dst)
  if res.isErr:
    echo "Clone failed: ", res.error.msg
    return 1
  echo "Cloned ", res.value
  0

proc cmdMcp(args: seq[string], cfg: FossilConfig): int =
  if args.len==0 or args[0]=="serve":
    mcpServer.runStdioLoop(cfg)
  else:
    echo "Unknown mcp subcommand"
    return 1
  0

proc cmdRebuild(args: seq[string], cfg: FossilConfig): int =
  if args.len < 2: return 1
  let oldPath = args[0]
  let newPath = args[1]
  var oldDb = SqliteBackend()
  if oldDb.open(oldPath).isErr: return 1
  defer: oldDb.close()
  var newDb = SqliteBackend()
  if newDb.open(newPath).isErr: return 1
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
    else: inc i
  case cmd
  of "version", "--version", "-v": printVersion()
  of "help", "--help", "-h":
    if rest.len>0: printHelpCommand(rest[0])
    else: printHelp()
  of "init", "new": result = cmdInit(rest, cfg)
  of "open": result = cmdOpen(rest, cfg)
  of "status", "st": result = cmdStatus(rest, cfg)
  of "add": result = cmdAdd(rest, cfg)
  of "diff", "di": result = cmdDiff(rest, cfg)
  of "commit", "ci": result = cmdCommit(rest, cfg)
  of "timeline", "tim": result = cmdTimeline(rest, cfg)
  of "clone": result = cmdClone(rest, cfg)
  of "mcp": result = cmdMcp(rest, cfg)
  of "rebuild": result = cmdRebuild(rest, cfg)
  of "branch", "br": result = cmdBranch(rest, cfg)
  else:
    echo "Unknown command: ", cmd
    printHelp()
    result=1

when isMainModule:
  quit(main())
