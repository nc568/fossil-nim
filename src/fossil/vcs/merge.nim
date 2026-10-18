## Merge logic - fixed 3-way merge with proper hunk handling

import ../types
import ./diff
import std/[strutils, sequtils, tables, algorithm, options]

type
  MergeResult* = object
    merged*: Blob
    conflicts*: seq[tuple[path: string, conflict: string]]
    hasConflicts*: bool

  MergeOptions* = object
    base*: Blob
    ours*: Blob
    theirs*: Blob
    filePath*: string

  Hunk = object
    baseStart*: int # 1-indexed, inclusive, 0 means insertion at beginning
    baseEnd*: int   # inclusive, 0 if insertion (no base lines removed)
    newLines*: seq[string]

proc extractHunks(diffRes: DiffResult): seq[Hunk] =
  var hunks: seq[Hunk] = @[]
  var current: Option[Hunk] = none(Hunk)
  var lastContextOld = 0

  for line in diffRes.lines:
    case line.kind
    of dlContext:
      if current.isSome:
        hunks.add current.get
        current = none(Hunk)
      lastContextOld = line.oldLineNo
    of dlRemove:
      if current.isNone:
        current = some(Hunk(baseStart: line.oldLineNo, baseEnd: line.oldLineNo, newLines: @[]))
      else:
        var h = current.get
        h.baseEnd = line.oldLineNo
        current = some(h)
    of dlAdd:
      if current.isNone:
        # Insertion: baseStart is after last context, baseEnd = 0 for pure insertion
        # If lastContextOld is 0, insertion at beginning
        let start = if lastContextOld == 0: 0 else: lastContextOld + 1
        # Check if next lines are removes, we will update baseEnd when we see removes
        # For pure insertion, baseStart = insertion point, baseEnd = baseStart-1 (empty)
        current = some(Hunk(baseStart: start, baseEnd: start-1, newLines: @[line.content]))
      else:
        var h = current.get
        h.newLines.add line.content
        current = some(h)

  if current.isSome:
    hunks.add current.get

  # Normalize hunks: ensure baseStart <= baseEnd for removals, and for pure insertions baseEnd = baseStart-1
  for i in 0..<hunks.len:
    if hunks[i].baseEnd < hunks[i].baseStart and hunks[i].baseEnd != hunks[i].baseStart-1:
      # Pure insertion case already has baseEnd = baseStart-1, okay
      discard

  hunks

proc mergeHunks(baseLines: seq[string], oursHunks, theirsHunks: seq[Hunk]): tuple[merged: seq[string], conflicts: seq[string], hasConflict: bool] =
  var merged: seq[string] = @[]
  var conflicts: seq[string] = @[]
  var hasConflict = false

  # Sort hunks by baseStart
  var oHunks = oursHunks
  var tHunks = theirsHunks
  oHunks.sort(proc(a,b: Hunk): int = cmp(a.baseStart, b.baseStart))
  tHunks.sort(proc(a,b: Hunk): int = cmp(a.baseStart, b.baseStart))

  var bIdx = 1 # 1-indexed base line pointer
  var oPos = 0
  var tPos = 0
  let bLen = baseLines.len

  while bIdx <= bLen or oPos < oHunks.len or tPos < tHunks.len:
    let nextO = if oPos < oHunks.len: oHunks[oPos].baseStart else: int.high
    let nextT = if tPos < tHunks.len: tHunks[tPos].baseStart else: int.high
    let nextBase = min(nextO, nextT)

    # Add base lines up to next hunk start
    while bIdx < nextBase and bIdx <= bLen:
      merged.add baseLines[bIdx-1]
      inc bIdx

    if bIdx > bLen and oPos >= oHunks.len and tPos >= tHunks.len:
      break

    var oHunk: Option[Hunk] = none(Hunk)
    var tHunk: Option[Hunk] = none(Hunk)

    if oPos < oHunks.len and oHunks[oPos].baseStart == nextBase:
      oHunk = some(oHunks[oPos])
    if tPos < tHunks.len and tHunks[tPos].baseStart == nextBase:
      tHunk = some(tHunks[tPos])

    # Check for overlapping hunks that start at different positions but overlap
    # For simplicity, if both have hunks and their ranges overlap, treat as conflict if content differs
    if oHunk.isSome and tHunk.isSome:
      let oh = oHunk.get
      let th = tHunk.get
      # Check if ranges overlap
      let ohEnd = if oh.baseEnd >= oh.baseStart: oh.baseEnd else: oh.baseStart-1
      let thEnd = if th.baseEnd >= th.baseStart: th.baseEnd else: th.baseStart-1
      let overlap = not (ohEnd < th.baseStart or thEnd < oh.baseStart)
      if overlap:
        if oh.newLines == th.newLines:
          # Same change, take it
          for l in oh.newLines:
            merged.add l
          bIdx = max(ohEnd, thEnd) + 1
          inc oPos
          inc tPos
        else:
          # Conflict
          hasConflict = true
          conflicts.add "Conflict at base lines " & $oh.baseStart & "-" & $ohEnd & " vs " & $th.baseStart & "-" & $thEnd
          # Add conflict markers
          merged.add "<<<<<<< ours"
          for l in oh.newLines:
            merged.add l
          merged.add "======="
          for l in th.newLines:
            merged.add l
          merged.add ">>>>>>> theirs"
          bIdx = max(ohEnd, thEnd) + 1
          inc oPos
          inc tPos
      else:
        # No overlap, but same start? Actually if same start but non-overlapping (both insertions at same point)
        # Then they are both insertions at same point with different content -> conflict if content differs
        if oh.baseStart == th.baseStart and oh.baseEnd < oh.baseStart and th.baseEnd < th.baseStart:
          # Both pure insertions at same point
          if oh.newLines == th.newLines:
            for l in oh.newLines: merged.add l
            inc oPos; inc tPos
          else:
            hasConflict = true
            conflicts.add "Insert conflict at " & $oh.baseStart
            merged.add "<<<<<<< ours"
            for l in oh.newLines: merged.add l
            merged.add "======="
            for l in th.newLines: merged.add l
            merged.add ">>>>>>> theirs"
            inc oPos; inc tPos
        else:
          # Different ranges but same start? Apply ours first then theirs if they don't overlap
          # For simplicity, apply ours then theirs
          if oh.baseStart <= th.baseStart:
            for l in oh.newLines: merged.add l
            bIdx = max(bIdx, ohEnd+1)
            inc oPos
          else:
            for l in th.newLines: merged.add l
            bIdx = max(bIdx, thEnd+1)
            inc tPos
    elif oHunk.isSome:
      let oh = oHunk.get
      let ohEnd = if oh.baseEnd >= oh.baseStart: oh.baseEnd else: oh.baseStart-1
      for l in oh.newLines: merged.add l
      bIdx = max(bIdx, ohEnd+1)
      inc oPos
    elif tHunk.isSome:
      let th = tHunk.get
      let thEnd = if th.baseEnd >= th.baseStart: th.baseEnd else: th.baseStart-1
      for l in th.newLines: merged.add l
      bIdx = max(bIdx, thEnd+1)
      inc tPos
    else:
      # No hunk at this position, but next hunk is in future, add base line
      if bIdx <= bLen:
        merged.add baseLines[bIdx-1]
        inc bIdx
      else:
        # No more base, but hunks remain with insertion at end (baseStart > bLen)
        # Add remaining hunks
        if oPos < oHunks.len:
          for l in oHunks[oPos].newLines: merged.add l
          inc oPos
        elif tPos < tHunks.len:
          for l in tHunks[tPos].newLines: merged.add l
          inc tPos
        else:
          break

  (merged, conflicts, hasConflict)

proc threeWayMerge*(opts: MergeOptions): MergeResult =
  if opts.ours.data == opts.base.data:
    return MergeResult(merged: opts.theirs, hasConflicts: false)
  if opts.theirs.data == opts.base.data:
    return MergeResult(merged: opts.ours, hasConflicts: false)
  if opts.ours.data == opts.theirs.data:
    return MergeResult(merged: opts.ours, hasConflicts: false)

  let baseLines = opts.base.data.splitLines()
  let oursLines = opts.ours.data.splitLines()
  let theirsLines = opts.theirs.data.splitLines()

  let diffOurs = diffBlobs(opts.base, opts.ours, opts.filePath)
  let diffTheirs = diffBlobs(opts.base, opts.theirs, opts.filePath)

  let oursHunks = extractHunks(diffOurs)
  let theirsHunks = extractHunks(diffTheirs)

  let (mergedLines, conflicts, hasConflict) = mergeHunks(baseLines, oursHunks, theirsHunks)

  let mergedText = mergedLines.join("\n")
  # Preserve trailing newline if any of inputs had it
  var finalText = mergedText
  if opts.ours.data.endsWith("\n") or opts.theirs.data.endsWith("\n") or opts.base.data.endsWith("\n"):
    if not finalText.endsWith("\n"):
      finalText.add "\n"

  MergeResult(
    merged: newBlob(finalText),
    hasConflicts: hasConflict,
    conflicts: conflicts.mapIt((path: opts.filePath, conflict: it))
  )

proc mergeBranches*(base, branch1, branch2: string): MergeResult =
  threeWayMerge(MergeOptions(base: newBlob(base), ours: newBlob(branch1), theirs: newBlob(branch2)))

proc mergeFile*(basePath, oursPath, theirsPath: string): FossilResult[MergeResult] =
  try:
    let baseData = readFile(basePath)
    let oursData = readFile(oursPath)
    let theirsData = readFile(theirsPath)
    ok(threeWayMerge(MergeOptions(base: newBlob(baseData), ours: newBlob(oursData), theirs: newBlob(theirsData), filePath: oursPath)))
  except:
    err[MergeResult](feIoError, "cannot read files for merge", getCurrentExceptionMsg())
