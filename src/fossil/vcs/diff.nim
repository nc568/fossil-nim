## Diff implementation - Myers O(ND) + heuristic fallback for huge files

import ../types
import std/[strutils]

type
  DiffLineKind* = enum
    dlContext
    dlAdd
    dlRemove

  DiffLine* = object
    kind*: DiffLineKind
    content*: string
    oldLineNo*: int
    newLineNo*: int

  DiffResult* = object
    file*: string
    lines*: seq[DiffLine]
    isBinary*: bool

proc isBinary*(b: Blob): bool =
  let checkLen = min(b.len, 8000)
  for i in 0..<checkLen:
    if b.data[i] == '\0': return true
  false

type TmpEdit = tuple[kind: DiffLineKind, content: string, aIdx: int, bIdx: int]

proc myersDiff(aLines, bLines: seq[string]): seq[TmpEdit] =
  let n = aLines.len
  let m = bLines.len
  if n==0 and m==0:
    return @[]
  if n==0:
    var res: seq[TmpEdit] = @[]
    for j in 0..<m:
      res.add (dlAdd, bLines[j], -1, j)
    return res
  if m==0:
    var res: seq[TmpEdit] = @[]
    for i in 0..<n:
      res.add (dlRemove, aLines[i], i, -1)
    return res

  let maxD = n + m
  let offset = maxD
  let size = 2*maxD + 1
  var V = newSeq[int](size)
  for i in 0..<size: V[i] = -1
  V[offset+1] = 0

  var trace: seq[seq[int]] = @[]
  var reachedD = -1

  for d in 0..maxD:
    # iterate k
    var k = -d
    while k <= d:
      var x: int
      if k == -d or (k != d and V[k-1+offset] < V[k+1+offset]):
        x = V[k+1+offset]
      else:
        x = V[k-1+offset] + 1
      var y = x - k
      # snake
      while x < n and y < m and aLines[x] == bLines[y]:
        inc x; inc y
      V[k+offset] = x
      if x >= n and y >= m:
        # store trace for this d and break
        var copyV = newSeq[int](size)
        for i in 0..<size: copyV[i] = V[i]
        trace.add(copyV)
        reachedD = d
        break
      k += 2
    if reachedD != -1:
      break
    # save copy for this d
    var copyV = newSeq[int](size)
    for i in 0..<size: copyV[i] = V[i]
    trace.add(copyV)

  if reachedD == -1:
    # fallback - should not happen
    reachedD = maxD
    if trace.len == 0:
      var copyV = newSeq[int](size)
      for i in 0..<size: copyV[i] = V[i]
      trace.add(copyV)

  # backtrack
  var rev: seq[TmpEdit] = @[]
  var curX = n
  var curY = m
  for d in countdown(reachedD, 0):
    let curK = curX - curY
    if d == 0:
      # only diagonal moves remain
      while curX > 0 and curY > 0:
        dec curX; dec curY
        rev.add (dlContext, aLines[curX], curX, curY)
      break
    # Vprev is trace[d-1]
    let Vprev = trace[d-1]
    var prevK: int
    if curK == -d or (curK != d and Vprev[curK-1+offset] < Vprev[curK+1+offset]):
      prevK = curK + 1
    else:
      prevK = curK - 1
    let prevX = Vprev[prevK+offset]
    let prevY = prevX - prevK

    # snake backwards: from (curX,curY) to (prevX, prevY) after edit
    while curX > prevX and curY > prevY:
      dec curX; dec curY
      rev.add (dlContext, aLines[curX], curX, curY)

    # edit step
    if curX == prevX:
      # insertion (down) - b[prevY] added
      # after snake, curX==prevX, curY==prevY+1
      dec curY
      rev.add (dlAdd, bLines[curY], -1, curY)
    else:
      # deletion (right) - a[prevX] removed
      dec curX
      rev.add (dlRemove, aLines[curX], curX, -1)

    curX = prevX
    curY = prevY

  # rev currently from end to start, reverse
  var fwd: seq[TmpEdit] = @[]
  for i in countdown(rev.len-1, 0):
    fwd.add rev[i]
  fwd

proc heuristicDiff(aLines, bLines: seq[string]): seq[TmpEdit] =
  var res: seq[TmpEdit] = @[]
  var i=0; var j=0
  let n=aLines.len; let m=bLines.len
  while i<n or j<m:
    if i<n and j<m and aLines[i]==bLines[j]:
      res.add (dlContext, aLines[i], i, j)
      inc i; inc j
    elif i<n and j<m:
      var found=false
      for k in 1..10:
        if i+k < n and aLines[i+k]==bLines[j]:
          for d in 0..<k:
            res.add (dlRemove, aLines[i+d], i+d, -1)
          i+=k; found=true; break
        if j+k < m and aLines[i]==bLines[j+k]:
          for ins in 0..<k:
            res.add (dlAdd, bLines[j+ins], -1, j+ins)
          j+=k; found=true; break
      if not found:
        res.add (dlRemove, aLines[i], i, -1)
        inc i
        if j<m:
          res.add (dlAdd, bLines[j], -1, j)
          inc j
    elif i<n:
      res.add (dlRemove, aLines[i], i, -1)
      inc i
    else:
      res.add (dlAdd, bLines[j], -1, j)
      inc j
  res

proc diffBlobs*(a, b: Blob, fileName: string = ""): DiffResult =
  if a.isBinary or b.isBinary:
    return DiffResult(file: fileName, isBinary: true)
  let aLines = a.data.splitLines()
  let bLines = b.data.splitLines()
  let n = aLines.len
  let m = bLines.len

  var res: seq[DiffLine] = @[]

  if n==0 and m==0:
    return DiffResult(file: fileName, lines: res, isBinary: false)
  if n==0:
    var newNo=1
    for j in 0..<m:
      res.add DiffLine(kind: dlAdd, content: bLines[j], oldLineNo: 0, newLineNo: newNo)
      inc newNo
    return DiffResult(file: fileName, lines: res, isBinary: false)
  if m==0:
    var oldNo=1
    for i in 0..<n:
      res.add DiffLine(kind: dlRemove, content: aLines[i], oldLineNo: oldNo, newLineNo: 0)
      inc oldNo
    return DiffResult(file: fileName, lines: res, isBinary: false)

  # For huge files, use heuristic to avoid O(N*D) blow-up when D large
  var tmp: seq[TmpEdit]
  if int64(n) * int64(m) > 20_000_000 or (n + m) > 30000:
    tmp = heuristicDiff(aLines, bLines)
  else:
    tmp = myersDiff(aLines, bLines)

  var oNo=1; var nNo=1
  for e in tmp:
    case e.kind
    of dlContext:
      res.add DiffLine(kind: dlContext, content: e.content, oldLineNo: oNo, newLineNo: nNo)
      inc oNo; inc nNo
    of dlRemove:
      res.add DiffLine(kind: dlRemove, content: e.content, oldLineNo: oNo, newLineNo: 0)
      inc oNo
    of dlAdd:
      res.add DiffLine(kind: dlAdd, content: e.content, oldLineNo: 0, newLineNo: nNo)
      inc nNo

  DiffResult(file: fileName, lines: res, isBinary: false)

proc diffToUnified*(d: DiffResult, context: int = 3): string =
  if d.isBinary:
    return "Binary files differ\n"
  var sb = ""
  sb.add "--- a/" & d.file & "\n"
  sb.add "+++ b/" & d.file & "\n"
  if d.lines.len == 0:
    return sb
  var oldCount=0; var newCount=0
  for line in d.lines:
    case line.kind
    of dlContext: inc oldCount; inc newCount
    of dlRemove: inc oldCount
    of dlAdd: inc newCount
  var oldStart=1; var newStart=1
  for line in d.lines:
    if line.kind != dlContext:
      oldStart = if line.oldLineNo!=0: line.oldLineNo else: oldStart
      newStart = if line.newLineNo!=0: line.newLineNo else: newStart
      break
  sb.add "@@ -" & $oldStart & "," & $oldCount & " +" & $newStart & "," & $newCount & " @@\n"
  for line in d.lines:
    case line.kind
    of dlContext: sb.add " " & line.content & "\n"
    of dlAdd: sb.add "+" & line.content & "\n"
    of dlRemove: sb.add "-" & line.content & "\n"
  sb

proc diffToJson*(d: DiffResult): string =
  var sb = "{\"file\":\"" & d.file & "\",\"binary\":" & $d.isBinary & ",\"lines\":["
  var first=true
  for line in d.lines:
    if not first: sb.add ","
    first=false
    sb.add "{\"kind\":\"" & $line.kind & "\",\"content\":\"" & line.content.replace("\"", "\\\"") & "\"}"
  sb.add "]}"
  sb

proc diffStats*(d: DiffResult): tuple[added: int, removed: int, context: int] =
  var a=0; var r=0; var c=0
  for line in d.lines:
    case line.kind
    of dlAdd: inc a
    of dlRemove: inc r
    of dlContext: inc c
  (a,r,c)
