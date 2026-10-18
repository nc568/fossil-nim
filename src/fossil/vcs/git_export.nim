## Git fast-export / fast-import - Enhanced with file changes, branches, full manifest

import ../types
import ../storage/sqlite_backend
import ./timeline as vcsTimeline
import ./checkout as vcsCheckout
import ../artifact/manifest as manifestMod
import ../utils/hash
import std/[strutils, times, os, tables, sequtils, json, options, algorithm]

type
  GitExportOptions* = object
    branch*: string
    limit*: int
    outputPath*: string
    allBranches*: bool

  GitFileOp* = object
    op*: string # "M" or "D"
    mode*: string # e.g. "100644"
    path*: string
    blobMark*: int
    blobUuid*: string

  GitCommit* = object
    mark*: int
    branch*: string
    author*: string
    committer*: string
    authorEmail*: string
    committerEmail*: string
    timestamp*: int64
    message*: string
    fromMark*: int # parent mark, 0 if none
    fileOps*: seq[GitFileOp]

proc getFilesForManifestSqlite*(backend: SqliteBackend, mid: Rid): FossilResult[seq[tuple[name: string, rid: Rid, uuid: string]]] =
  {.push header: "<sqlite3.h>".}
  type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
  proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
  proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
  proc sqlite3_column_text(pStmt: ptr sqlite3_stmt, iCol: cint): cstring {.importc.}
  proc sqlite3_column_int64(pStmt: ptr sqlite3_stmt, iCol: cint): int64 {.importc.}
  proc sqlite3_bind_int64(pStmt: ptr sqlite3_stmt, i: cint, v: int64): cint {.importc.}
  {.pop.}
  const SQLITE_ROW = 100
  var files: seq[tuple[name: string, rid: Rid, uuid: string]] = @[]
  var stmt: ptr sqlite3_stmt
  let sql = "SELECT filename.name, blob.rid, blob.uuid FROM mlink JOIN filename ON mlink.fnid=filename.fnid JOIN blob ON mlink.fid=blob.rid WHERE mlink.mid=?1 ORDER BY filename.name"
  if sqlite3_prepare_v2(backend.db, sql.cstring, -1, addr stmt, nil) != 0:
    # Fallback try without uuid
    let sql2 = "SELECT filename.name, mlink.fid FROM mlink JOIN filename ON mlink.fnid=filename.fnid WHERE mlink.mid=?1 ORDER BY filename.name"
    if sqlite3_prepare_v2(backend.db, sql2.cstring, -1, addr stmt, nil) != 0:
      return ok(files)
    discard sqlite3_bind_int64(stmt, 1, int64(mid))
    while sqlite3_step(stmt) == SQLITE_ROW:
      let namePtr = sqlite3_column_text(stmt, 0)
      let fid = sqlite3_column_int64(stmt, 1)
      if namePtr!=nil:
        files.add (name: $namePtr, rid: Rid(fid), uuid: "")
    discard sqlite3_finalize(stmt)
    return ok(files)
  discard sqlite3_bind_int64(stmt, 1, int64(mid))
  while sqlite3_step(stmt) == SQLITE_ROW:
    let namePtr = sqlite3_column_text(stmt, 0)
    let rid = sqlite3_column_int64(stmt, 1)
    let uuidPtr = sqlite3_column_text(stmt, 2)
    if namePtr!=nil:
      let uuid = if uuidPtr!=nil: $uuidPtr else: ""
      files.add (name: $namePtr, rid: Rid(rid), uuid: uuid)
  discard sqlite3_finalize(stmt)
  ok(files)

proc exportToGitFastEnhanced*(backend: SqliteBackend, opts: GitExportOptions): FossilResult[string] =
  ## Enhanced export with file changes
  var filter = vcsTimeline.defaultFilter()
  filter.limit = opts.limit
  if not opts.allBranches and opts.branch.len>0:
    filter.branch = some(opts.branch)
  let tlRes = vcsTimeline.getTimelineSqlite(backend, filter)
  if tlRes.isErr:
    return err[string](tlRes.error.code, tlRes.error.msg)
  
  # Sort by mtime ASC for git fast-export (oldest first)
  var entries = tlRes.value
  entries.sort(proc(a,b: auto): int = cmp(a.mtime, b.mtime))
  
  var output = ""
  var mark = 1
  var markMap = initTable[Rid, int]()
  var blobMark = 10000 # start blob marks from 10000 to avoid collision with commit marks
  var blobMarkMap = initTable[Rid, int]() # rid -> blob mark
  
  output.add "# Fossil-Nim git fast-export\n"
  output.add "# Generated: " & $getTime() & "\n"
  output.add "# Branch: " & opts.branch & " Limit: " & $opts.limit & "\n"
  output.add "# Commits: " & $entries.len & "\n\n"
  
  var prevMarkByBranch = initTable[string, int]()
  
  # Git fast-export expects oldest first so parents exist before children.
  # getTimeline returns newest first, so reverse to chronological order.
  var ordered = entries
  ordered.reverse()
  
  for entry in ordered:
    let commitMark = mark
    markMap[entry.rid] = commitMark
    inc mark
    
    # Get files for this manifest
    let filesRes = getFilesForManifestSqlite(backend, entry.rid)
    var files: seq[tuple[name: string, rid: Rid, uuid: string]] = @[]
    if filesRes.isOk:
      files = filesRes.value
    
    # For each file, output blob if not already output
    var fileOps: seq[GitFileOp] = @[]
    for f in files:
      if f.rid == invalidRid(): continue
      var bMark = 0
      if blobMarkMap.hasKey(f.rid):
        bMark = blobMarkMap[f.rid]
      else:
        # Get blob content
        let blobRes = backend.getBlob(f.rid)
        if blobRes.isErr: continue
        let content = blobRes.value.data
        # Output blob
        output.add "blob\n"
        output.add "mark :" & $blobMark & "\n"
        output.add "data " & $content.len & "\n"
        output.add content & "\n"
        bMark = blobMark
        blobMarkMap[f.rid] = bMark
        inc blobMark
      
      fileOps.add GitFileOp(op: "M", mode: "100644", path: f.name, blobMark: bMark, blobUuid: f.uuid)
    
    # Output commit
    let branchRef = if entry.branch.len>0: entry.branch else: "trunk"
    output.add "commit refs/heads/" & branchRef & "\n"
    output.add "mark :" & $commitMark & "\n"
    let author = entry.user
    let email = entry.user & "@fossil-nim"
    output.add "author " & author & " <" & email & "> " & $entry.mtime & " +0000\n"
    output.add "committer " & author & " <" & email & "> " & $entry.mtime & " +0000\n"
    output.add "data " & $entry.comment.len & "\n"
    output.add entry.comment & "\n"
    
    # Parent
    if prevMarkByBranch.hasKey(branchRef):
      output.add "from :" & $prevMarkByBranch[branchRef] & "\n"
    elif branchRef != "trunk" and prevMarkByBranch.hasKey("trunk"):
      # Branch from trunk?
      output.add "from :" & $prevMarkByBranch["trunk"] & "\n"
    
    # File ops
    for op in fileOps:
      output.add "M " & op.mode & " :" & $op.blobMark & " " & op.path & "\n"
    
    output.add "\n"
    prevMarkByBranch[branchRef] = commitMark
  
  if opts.outputPath.len>0:
    try:
      writeFile(opts.outputPath, output)
    except:
      return err[string](feIoError, "cannot write export file: " & getCurrentExceptionMsg())
  ok(output)

proc parseGitFastImport*(content: string): seq[GitCommit] =
  ## Parse git fast-export content into commits
  var commits: seq[GitCommit] = @[]
  var lines = content.splitLines()
  var i = 0
  var blobMarks = initTable[int, string]() # mark -> content
  var currentCommit: Option[GitCommit] = none(GitCommit)
  var currentBlobMark = 0
  var currentBlobContent = ""
  var inBlobData = false
  var blobDataLen = 0
  
  while i < lines.len:
    let line = lines[i]
    if line.startsWith("blob"):
      # If we were in a commit, save it before starting blob
      if currentCommit.isSome:
        commits.add currentCommit.get()
        currentCommit = none(GitCommit)
      # Next lines: mark, data
      currentBlobMark = 0
      currentBlobContent = ""
      inBlobData = false
    elif line.startsWith("mark :") and not currentCommit.isSome:
      # Could be blob mark
      try:
        let markStr = line[6..^1].strip()
        currentBlobMark = parseInt(markStr)
      except: discard
    elif line.startsWith("data ") and currentBlobMark!=0 and not currentCommit.isSome:
      try:
        let lenStr = line[5..^1].strip()
        blobDataLen = parseInt(lenStr)
        inBlobData = true
        inc i
        if i < lines.len:
          # Data may be multi-line? For simplicity, take next line(s) until len
          var data = ""
          var remaining = blobDataLen
          while remaining>0 and i < lines.len:
            let l = lines[i]
            if l.len <= remaining:
              data.add l & "\n"
              remaining -= l.len + 1
            else:
              data.add l[0..<remaining]
              remaining = 0
            inc i
            if remaining>0 and i < lines.len:
              # Continue
              discard
          # Store blob
          blobMarks[currentBlobMark] = data.strip(chars={'\n'})
          currentBlobMark = 0
          inBlobData = false
          continue
      except: discard
    elif line.startsWith("commit refs/heads/"):
      # Save previous commit if any
      if currentCommit.isSome:
        commits.add currentCommit.get()
      let branch = line["commit refs/heads/".len..^1].strip()
      currentCommit = some(GitCommit(branch: branch, fileOps: @[]))
    elif line.startsWith("mark :") and currentCommit.isSome:
      try:
        let markStr = line[6..^1].strip()
        currentCommit.get().mark = parseInt(markStr)
      except: discard
    elif line.startsWith("author ") and currentCommit.isSome:
      # author Name <email> timestamp tz
      var rest = line["author ".len..^1]
      # Parse name until <
      let lt = rest.find('<')
      if lt!= -1:
        currentCommit.get().author = rest[0..<lt].strip()
        let gt = rest.find('>', lt)
        if gt!= -1:
          currentCommit.get().authorEmail = rest[lt+1..<gt].strip()
          let after = rest[gt+1..^1].strip()
          let parts = after.split(' ')
          if parts.len>=1:
            try: currentCommit.get().timestamp = parseInt(parts[0])
            except: discard
    elif line.startsWith("committer ") and currentCommit.isSome:
      var rest = line["committer ".len..^1]
      let lt = rest.find('<')
      if lt!= -1:
        currentCommit.get().committer = rest[0..<lt].strip()
        let gt = rest.find('>', lt)
        if gt!= -1:
          currentCommit.get().committerEmail = rest[lt+1..<gt].strip()
    elif line.startsWith("data ") and currentCommit.isSome:
      try:
        let lenStr = line[5..^1].strip()
        let dataLen = parseInt(lenStr)
        inc i
        if i < lines.len:
          var msg = ""
          var remaining = dataLen
          # Message may be on next line(s)
          while remaining>0 and i < lines.len:
            let l = lines[i]
            if l.len < remaining:
              msg.add l & "\n"
              remaining -= l.len + 1
              inc i
            else:
              msg.add l[0..<remaining]
              remaining = 0
              # Don't inc i yet, leave for next iteration? Actually message consumes one line typically
              inc i
              break
          currentCommit.get().message = msg.strip()
          continue
      except: discard
    elif line.startsWith("from :") and currentCommit.isSome:
      try:
        let markStr = line[6..^1].strip()
        currentCommit.get().fromMark = parseInt(markStr)
      except: discard
    elif line.startsWith("M ") and currentCommit.isSome:
      # M mode :mark path
      let parts = line.split(' ', 3)
      if parts.len>=4:
        # parts[0]=M, parts[1]=mode, parts[2]=:mark, parts[3]=path
        let mode = parts[1]
        let markPart = parts[2]
        let path = parts[3]
        var bMark = 0
        try:
          if markPart.startsWith(":"):
            bMark = parseInt(markPart[1..^1])
        except: discard
        currentCommit.get().fileOps.add GitFileOp(op: "M", mode: mode, path: path, blobMark: bMark)
      elif parts.len==3:
        # M mode path without mark? Try parse
        let mode = parts[1]
        let path = parts[2]
        currentCommit.get().fileOps.add GitFileOp(op: "M", mode: mode, path: path, blobMark: 0)
    elif line.startsWith("D ") and currentCommit.isSome:
      let path = line[2..^1].strip()
      currentCommit.get().fileOps.add GitFileOp(op: "D", path: path)
    inc i
  
  if currentCommit.isSome:
    commits.add currentCommit.get()
  commits

proc importFromGitFastEnhanced*(backend: var SqliteBackend, inputPath: string): FossilResult[int] =
  if not fileExists(inputPath):
    return err[int](feNotFound, "import file not found: " & inputPath)
  var content: string
  try:
    content = readFile(inputPath)
  except:
    return err[int](feIoError, "cannot read import file: " & getCurrentExceptionMsg())
  
  # Parse content for blobs and commits
  var blobContents = initTable[int, string]() # mark -> content
  var blobRids = initTable[int, Rid]() # mark -> rid
  var commitMarks = initTable[int, Rid]() # mark -> rid (manifest rid)
  
  var lines = content.splitLines()
  var i = 0
  var currentBlobMark = 0
  
  # First pass: extract blobs
  while i < lines.len:
    let line = lines[i]
    if line == "blob":
      inc i
      if i < lines.len and lines[i].startsWith("mark :"):
        try:
          currentBlobMark = parseInt(lines[i][6..^1].strip())
        except: currentBlobMark = 0
        inc i
      if i < lines.len and lines[i].startsWith("data "):
        try:
          let dataLen = parseInt(lines[i][5..^1].strip())
          inc i
          var data = ""
          var remaining = dataLen
          while remaining>0 and i < lines.len:
            let l = lines[i]
            # Handle case where data contains newlines - for simplicity assume data is on next lines
            if dataLen <= 1000000: # reasonable
              # If next line is exactly dataLen chars, take it
              if l.len >= remaining:
                data.add l[0..<remaining]
                remaining = 0
                inc i
                break
              else:
                data.add l & "\n"
                remaining -= l.len + 1
                inc i
            else:
              inc i
              break
          if currentBlobMark!=0:
            blobContents[currentBlobMark] = data
            # Create blob in Fossil
            let blob = newBlob(data)
            let uuid = hashBlob(blob)
            let putRes = backend.putBlob(uuid, blob, false)
            if putRes.isOk:
              blobRids[currentBlobMark] = putRes.value
        except:
          discard
        currentBlobMark = 0
        continue
    inc i
  
  # Second pass: parse commits and create Fossil manifests
  var commits = parseGitFastImport(content)
  var count = 0
  var prevRidByBranch = initTable[string, Rid]()
  
  for commit in commits:
    # Build manifest content
    var manifest = "C " & commit.message.replace("\n", "\\n") & "\n"
    manifest.add "D " & $fromUnix(commit.timestamp).utc().format("yyyy-MM-dd'T'HH:mm:ss") & "\n"
    manifest.add "U " & commit.author & "\n"
    manifest.add "E " & $commit.timestamp & "\n"
    
    # Parent
    if commit.fromMark!=0 and commitMarks.hasKey(commit.fromMark):
      let parentRid = commitMarks[commit.fromMark]
      let parentInfo = backend.getBlobInfo(parentRid)
      if parentInfo.isOk:
        manifest.add "P " & $parentInfo.value.uuid & "\n"
    elif prevRidByBranch.hasKey(commit.branch):
      let parentRid = prevRidByBranch[commit.branch]
      let parentInfo = backend.getBlobInfo(parentRid)
      if parentInfo.isOk:
        manifest.add "P " & $parentInfo.value.uuid & "\n"
    
    # Files
    for op in commit.fileOps:
      if op.op == "M":
        var fileRid: Rid = invalidRid()
        var fileUuid = ""
        if op.blobMark!=0 and blobRids.hasKey(op.blobMark):
          fileRid = blobRids[op.blobMark]
          let info = backend.getBlobInfo(fileRid)
          if info.isOk:
            fileUuid = $info.value.uuid
        elif op.blobUuid.len>0:
          fileUuid = op.blobUuid
        else:
          continue
        # F card: F <name> <uuid> <perm>
        let perm = if op.mode=="100755": "x" else: ""
        manifest.add "F " & op.path & " " & fileUuid & (if perm.len>0: " " & perm else: "") & "\n"
      # D operation: in Fossil, file deletion is just not including F card, so skip
    
    manifest.add "R " & commit.branch & "\n"
    
    # Create manifest blob
    let blob = newBlob(manifest)
    let uuid = hashBlob(blob)
    let putRes = backend.putBlob(uuid, blob, false)
    if putRes.isOk:
      let rid = putRes.value
      commitMarks[commit.mark] = rid
      prevRidByBranch[commit.branch] = rid
      
      # Create event
      {.push header: "<sqlite3.h>".}
      type sqlite3_stmt {.importc: "sqlite3_stmt", incompleteStruct.} = object
      proc sqlite3_prepare_v2(db: pointer, zSql: cstring, nByte: cint, ppStmt: ptr ptr sqlite3_stmt, pzTail: pointer): cint {.importc.}
      proc sqlite3_finalize(pStmt: ptr sqlite3_stmt): cint {.importc.}
      proc sqlite3_step(pStmt: ptr sqlite3_stmt): cint {.importc.}
      proc sqlite3_bind_text(pStmt: ptr sqlite3_stmt, i: cint, zData: cstring, n: cint, xDel: pointer): cint {.importc.}
      proc sqlite3_bind_int64(pStmt: ptr sqlite3_stmt, i: cint, v: int64): cint {.importc.}
      {.pop.}
      var stmt: ptr sqlite3_stmt
      let sqlEvent = "INSERT OR IGNORE INTO event(type, mtime, objid, user, comment, branch) VALUES('ci', ?1, ?2, ?3, ?4, ?5)"
      if sqlite3_prepare_v2(backend.db, sqlEvent.cstring, -1, addr stmt, nil) == 0:
        discard sqlite3_bind_int64(stmt, 1, commit.timestamp)
        discard sqlite3_bind_int64(stmt, 2, int64(rid))
        discard sqlite3_bind_text(stmt, 3, commit.author.cstring, -1, nil)
        discard sqlite3_bind_text(stmt, 4, commit.message.cstring, -1, nil)
        discard sqlite3_bind_text(stmt, 5, commit.branch.cstring, -1, nil)
        discard sqlite3_step(stmt)
        discard sqlite3_finalize(stmt)
      
      # Create mlink entries for files
      for op in commit.fileOps:
        if op.op=="M" and op.blobMark!=0 and blobRids.hasKey(op.blobMark):
          let fileRid = blobRids[op.blobMark]
          # Get or create filename fnid
          var fnid: int64 = 0
          let sqlFn = "INSERT OR IGNORE INTO filename(name) VALUES(?1)"
          if sqlite3_prepare_v2(backend.db, sqlFn.cstring, -1, addr stmt, nil) == 0:
            discard sqlite3_bind_text(stmt, 1, op.path.cstring, -1, nil)
            discard sqlite3_step(stmt)
            discard sqlite3_finalize(stmt)
          let sqlFnId = "SELECT fnid FROM filename WHERE name=?1"
          if sqlite3_prepare_v2(backend.db, sqlFnId.cstring, -1, addr stmt, nil) == 0:
            discard sqlite3_bind_text(stmt, 1, op.path.cstring, -1, nil)
            if sqlite3_step(stmt)==100:
              {.push header: "<sqlite3.h>".}
              proc sqlite3_column_int64(pStmt: ptr sqlite3_stmt, iCol: cint): int64 {.importc.}
              {.pop.}
              fnid = sqlite3_column_int64(stmt, 0)
            discard sqlite3_finalize(stmt)
          if fnid!=0:
            let sqlMlink = "INSERT OR IGNORE INTO mlink(mid, fid, fnid) VALUES(?1, ?2, ?3)"
            if sqlite3_prepare_v2(backend.db, sqlMlink.cstring, -1, addr stmt, nil) == 0:
              discard sqlite3_bind_int64(stmt, 1, int64(rid))
              discard sqlite3_bind_int64(stmt, 2, int64(fileRid))
              discard sqlite3_bind_int64(stmt, 3, fnid)
              discard sqlite3_step(stmt)
              discard sqlite3_finalize(stmt)
      
      # --- Search auto-index for imported commit ---
      try:
        # Ensure FTS tables exist
        let sqlCreateFts = "CREATE VIRTUAL TABLE IF NOT EXISTS search_fts USING fts5(id, kind, title, content, tokenize='porter unicode61')"
        if sqlite3_prepare_v2(backend.db, sqlCreateFts.cstring, -1, addr stmt, nil) == 0:
          discard sqlite3_step(stmt)
          discard sqlite3_finalize(stmt)
        let sqlCreateIdx = "CREATE TABLE IF NOT EXISTS search_index(id TEXT PRIMARY KEY, kind TEXT, title TEXT, content TEXT, mtime INTEGER)"
        if sqlite3_prepare_v2(backend.db, sqlCreateIdx.cstring, -1, addr stmt, nil) == 0:
          discard sqlite3_step(stmt)
          discard sqlite3_finalize(stmt)
        # Index commit
        let commitTitle = "[" & commit.branch & "] " & commit.message.splitLines()[0]
        let commitContent = commit.branch & " " & commit.author & " " & commit.message
        let sqlIdxCommit = "INSERT OR REPLACE INTO search_index(id, kind, title, content, mtime) VALUES(?1, 'commit', ?2, ?3, ?4)"
        if sqlite3_prepare_v2(backend.db, sqlIdxCommit.cstring, -1, addr stmt, nil) == 0:
          discard sqlite3_bind_text(stmt, 1, ("commit-" & $uuid).cstring, -1, nil)
          discard sqlite3_bind_text(stmt, 2, commitTitle.cstring, -1, nil)
          discard sqlite3_bind_text(stmt, 3, commitContent.cstring, -1, nil)
          discard sqlite3_bind_int64(stmt, 4, commit.timestamp)
          discard sqlite3_step(stmt)
          discard sqlite3_finalize(stmt)
        let sqlDelFtsCommit = "DELETE FROM search_fts WHERE id=?1"
        if sqlite3_prepare_v2(backend.db, sqlDelFtsCommit.cstring, -1, addr stmt, nil) == 0:
          discard sqlite3_bind_text(stmt, 1, ("commit-" & $uuid).cstring, -1, nil)
          discard sqlite3_step(stmt)
          discard sqlite3_finalize(stmt)
        let sqlFtsCommit = "INSERT OR REPLACE INTO search_fts(id, kind, title, content) VALUES(?1, 'commit', ?2, ?3)"
        if sqlite3_prepare_v2(backend.db, sqlFtsCommit.cstring, -1, addr stmt, nil) == 0:
          discard sqlite3_bind_text(stmt, 1, ("commit-" & $uuid).cstring, -1, nil)
          discard sqlite3_bind_text(stmt, 2, commitTitle.cstring, -1, nil)
          discard sqlite3_bind_text(stmt, 3, commitContent.cstring, -1, nil)
          discard sqlite3_step(stmt)
          discard sqlite3_finalize(stmt)
        # Index files from this commit
        for op in commit.fileOps:
          if op.op=="M" and op.blobMark!=0 and blobRids.hasKey(op.blobMark) and blobContents.hasKey(op.blobMark):
            let content = blobContents[op.blobMark]
            if content.len==0 or content.len>200000: continue
            if content.contains("\0"): continue
            let ext = op.path.split(".")[^1].toLowerAscii()
            if ext in ["png","jpg","jpeg","gif","bmp","ico","zip","gz","bz2","xz","pdf","exe","dll","so","o","a","bin"]:
              continue
            let toIndex = if content.len>50000: content[0..49999] else: content
            let sqlIdxFile = "INSERT OR REPLACE INTO search_index(id, kind, title, content, mtime) VALUES(?1, 'file', ?2, ?3, ?4)"
            if sqlite3_prepare_v2(backend.db, sqlIdxFile.cstring, -1, addr stmt, nil) == 0:
              discard sqlite3_bind_text(stmt, 1, ("file-" & op.path).cstring, -1, nil)
              discard sqlite3_bind_text(stmt, 2, op.path.cstring, -1, nil)
              discard sqlite3_bind_text(stmt, 3, toIndex.cstring, -1, nil)
              discard sqlite3_bind_int64(stmt, 4, commit.timestamp)
              discard sqlite3_step(stmt)
              discard sqlite3_finalize(stmt)
            let sqlDelFtsFile = "DELETE FROM search_fts WHERE id=?1"
            if sqlite3_prepare_v2(backend.db, sqlDelFtsFile.cstring, -1, addr stmt, nil) == 0:
              discard sqlite3_bind_text(stmt, 1, ("file-" & op.path).cstring, -1, nil)
              discard sqlite3_step(stmt)
              discard sqlite3_finalize(stmt)
            let sqlFtsFile = "INSERT OR REPLACE INTO search_fts(id, kind, title, content) VALUES(?1, 'file', ?2, ?3)"
            if sqlite3_prepare_v2(backend.db, sqlFtsFile.cstring, -1, addr stmt, nil) == 0:
              discard sqlite3_bind_text(stmt, 1, ("file-" & op.path).cstring, -1, nil)
              discard sqlite3_bind_text(stmt, 2, op.path.cstring, -1, nil)
              discard sqlite3_bind_text(stmt, 3, toIndex.cstring, -1, nil)
              discard sqlite3_step(stmt)
              discard sqlite3_finalize(stmt)
      except:
        discard
      
      inc count
  
  ok(count)

proc gitExportCommandEnhanced*(repoPath: string, opts: GitExportOptions): FossilResult[string] =
  var db = SqliteBackend()
  if db.open(repoPath).isErr:
    return err[string](feIoError, "cannot open repo")
  defer: db.close()
  exportToGitFastEnhanced(db, opts)

proc gitImportCommandEnhanced*(repoPath: string, inputPath: string): FossilResult[int] =
  var db = SqliteBackend()
  if db.open(repoPath).isErr:
    return err[int](feIoError, "cannot open repo")
  defer: db.close()
  importFromGitFastEnhanced(db, inputPath)

# Compatibility wrappers for old API
proc exportToGitFast*(backend: SqliteBackend, opts: GitExportOptions): FossilResult[string] =
  exportToGitFastEnhanced(backend, opts)

proc importFromGitFast*(backend: var SqliteBackend, inputPath: string): FossilResult[int] =
  importFromGitFastEnhanced(backend, inputPath)
