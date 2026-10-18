## Fossil Delta Format - improved with rolling hash
## 100% compatible with original delta.c

import ../types
import std/[strutils, tables, hashes]

type
  DeltaOpKind* = enum
    dopCopy = 0
    dopInsert = 1

  DeltaOp* = object
    case kind*: DeltaOpKind
    of dopCopy:
      copyLen*: int
      copyOff*: int
    of dopInsert:
      insertData*: string

  Delta* = object
    targetSize*: int
    ops*: seq[DeltaOp]
    checksum*: uint32

proc deltaOutputSize*(d: Delta): int = d.targetSize

const b64Alphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz~"

proc encodeInt*(n: int): string =
  if n == 0: return "0"
  var uv = uint64(n)
  if n < 0:
    uv = uint64(uint32(n))
  var res = ""
  while uv > 0:
    let idx = int(uv mod 64)
    res = b64Alphabet[idx] & res
    uv = uv div 64
  if res.len == 0: res = "0"
  res

proc encodeIntU32*(n: uint32): string =
  if n == 0: return "0"
  var uv = uint64(n)
  var res = ""
  while uv > 0:
    let idx = int(uv mod 64)
    res = b64Alphabet[idx] & res
    uv = uv div 64
  res

proc decodeInt*(s: string): int =
  var v: uint64 = 0
  for c in s:
    let idx = b64Alphabet.find(c)
    if idx < 0:
      raise newException(ValueError, "invalid base64 char: " & $c)
    v = v * 64 + uint64(idx)
  int(v)

proc decodeIntU32*(s: string): uint32 =
  var v: uint64 = 0
  for c in s:
    let idx = b64Alphabet.find(c)
    if idx < 0:
      raise newException(ValueError, "invalid base64 char")
    v = v * 64 + uint64(idx)
  uint32(v and 0xFFFFFFFF'u64)

proc isB64Char(c: char): bool =
  b64Alphabet.find(c) >= 0

proc computeChecksum*(data: string): uint32 =
  var sum: uint64 = 0
  var i = 0
  let n = data.len
  while i < n:
    var word: uint32 = 0
    for j in 0..3:
      word = word shl 8
      if i + j < n:
        word = word or uint32(uint8(data[i+j]))
    sum += uint64(word)
    i += 4
  uint32(sum and 0xFFFFFFFF'u64)

proc hash4(s: string, pos: int): int =
  if pos+4 > s.len: return 0
  var h = 0
  h = (h * 31 + ord(s[pos])) and 0xFFFFFF
  h = (h * 31 + ord(s[pos+1])) and 0xFFFFFF
  h = (h * 31 + ord(s[pos+2])) and 0xFFFFFF
  h = (h * 31 + ord(s[pos+3])) and 0xFFFFFF
  h

proc deltaCreate*(source, target: Blob, useChecksum: bool = true): FossilResult[Delta] =
  if target.len == 0:
    return ok(Delta(targetSize: 0, ops: @[], checksum: 0))

  let s = source.data
  let t = target.data

  var hashTable = initTable[int, seq[int]]()
  if s.len >= 4:
    for i in 0..s.len-4:
      let h = hash4(s, i)
      if not hashTable.hasKey(h):
        hashTable[h] = @[]
      if hashTable[h].len < 8:
        hashTable[h].add i

  var ops: seq[DeltaOp] = @[]
  var i = 0

  while i < t.len:
    var bestLen = 0
    var bestOff = 0

    if s.len >= 4 and i+4 <= t.len:
      let h = hash4(t, i)
      if hashTable.hasKey(h):
        for srcPos in hashTable[h]:
          if s[srcPos] != t[i] or s[srcPos+1] != t[i+1] or s[srcPos+2] != t[i+2] or s[srcPos+3] != t[i+3]:
            continue
          var l = 4
          while i+l < t.len and srcPos+l < s.len and t[i+l] == s[srcPos+l] and l < 65535:
            inc l
          if l > bestLen:
            bestLen = l
            bestOff = srcPos
            if bestLen > 1000:
              break

    if bestLen >= 4:
      ops.add DeltaOp(kind: dopCopy, copyLen: bestLen, copyOff: bestOff)
      i += bestLen
    else:
      var litStart = i
      inc i
      while i < t.len and i - litStart < 64:
        if s.len >= 4 and i+4 <= t.len:
          let h2 = hash4(t, i)
          if hashTable.hasKey(h2):
            var hasMatch = false
            for srcPos in hashTable[h2]:
              if s[srcPos] == t[i] and s[srcPos+1] == t[i+1] and s[srcPos+2] == t[i+2] and s[srcPos+3] == t[i+3]:
                hasMatch = true
                break
            if hasMatch:
              break
        inc i
      let lit = t[litStart..<i]
      ops.add DeltaOp(kind: dopInsert, insertData: lit)

  let cs = computeChecksum(t)
  ok(Delta(targetSize: t.len, ops: ops, checksum: cs))

proc deltaEncode*(d: Delta): Blob =
  var outStr = newStringOfCap(d.targetSize + 100)
  outStr.add encodeInt(d.targetSize) & "\n"
  for op in d.ops:
    case op.kind
    of dopCopy:
      outStr.add encodeInt(op.copyLen) & "@" & encodeInt(op.copyOff) & ","
    of dopInsert:
      outStr.add encodeInt(op.insertData.len) & ":" & op.insertData
  let cs = if d.checksum != 0: d.checksum else: 0'u32
  outStr.add encodeIntU32(cs) & ";\n"
  Blob(data: outStr)

proc deltaEncodeWithTarget*(d: Delta, targetData: string): Blob =
  var outStr = newStringOfCap(d.targetSize + 100)
  outStr.add encodeInt(d.targetSize) & "\n"
  for op in d.ops:
    case op.kind
    of dopCopy:
      outStr.add encodeInt(op.copyLen) & "@" & encodeInt(op.copyOff) & ","
    of dopInsert:
      outStr.add encodeInt(op.insertData.len) & ":" & op.insertData
  let cs = computeChecksum(targetData)
  outStr.add encodeIntU32(cs) & ";\n"
  Blob(data: outStr)

proc deltaDecode*(b: Blob): FossilResult[Delta] =
  let s = b.data
  if s.len == 0:
    return err[Delta](feDeltaError, "empty delta")
  var lineEnd = s.find('\n')
  if lineEnd == -1:
    return err[Delta](feDeltaError, "delta missing newline")
  var targetSize: int
  try:
    let sizeStr = s[0..<lineEnd].strip()
    targetSize = decodeInt(sizeStr)
  except:
    return err[Delta](feDeltaError, "invalid target size")
  var pos = lineEnd+1
  var ops: seq[DeltaOp] = @[]
  var checksum: uint32 = 0
  while pos < s.len:
    if s[pos] == ';':
      break
    var lenStart = pos
    while pos < s.len and isB64Char(s[pos]): inc pos
    if pos >= s.len: break
    if lenStart == pos:
      var csStart = pos
      while pos < s.len and isB64Char(s[pos]): inc pos
      if pos < s.len and s[pos] == ';':
        let csStr = s[csStart..<pos]
        try:
          checksum = decodeIntU32(csStr)
        except:
          discard
        break
      else:
        return err[Delta](feDeltaError, "invalid op len")
    let lenStr = s[lenStart..<pos]
    var l: int
    try: l = decodeInt(lenStr)
    except: return err[Delta](feDeltaError, "invalid op len")
    if pos >= s.len: return err[Delta](feDeltaError, "truncated delta")
    let sep = s[pos]
    inc pos
    if sep == '@':
      var offStart = pos
      while pos < s.len and isB64Char(s[pos]): inc pos
      let offStr = s[offStart..<pos]
      var off: int
      try: off = decodeInt(offStr)
      except: return err[Delta](feDeltaError, "invalid copy off")
      if pos < s.len and s[pos] == ',': inc pos
      ops.add DeltaOp(kind: dopCopy, copyLen: l, copyOff: off)
    elif sep == ':':
      if pos+l > s.len:
        return err[Delta](feDeltaError, "literal out of bounds")
      let lit = s[pos..<pos+l]
      pos += l
      ops.add DeltaOp(kind: dopInsert, insertData: lit)
    elif sep == ';':
      try:
        checksum = decodeIntU32(lenStr)
      except:
        discard
      break
    else:
      if sep in {'0'..'9', 'A'..'Z', 'a'..'z', '_', '~'}:
        var semi = s.find(';', pos-1)
        if semi != -1:
          let csStr = s[lenStart..<semi]
          try:
            checksum = decodeIntU32(csStr)
          except:
            discard
          break
        return err[Delta](feDeltaError, "invalid sep", $sep)
      return err[Delta](feDeltaError, "invalid sep", $sep)

  if checksum == 0:
    var remaining = s[pos..^1]
    var semiPos = remaining.find(';')
    if semiPos != -1:
      let csStr = remaining[0..<semiPos].strip()
      if csStr.len>0:
        try:
          checksum = decodeIntU32(csStr)
        except:
          discard

  ok(Delta(targetSize: targetSize, ops: ops, checksum: checksum))

proc deltaApply*(source: Blob, delta: Delta): FossilResult[Blob] =
  var outStr = newStringOfCap(delta.targetSize)
  for op in delta.ops:
    case op.kind
    of dopCopy:
      if op.copyOff + op.copyLen > source.len:
        return err[Blob](feDeltaError, "copy out of bounds", $op)
      outStr.add source.data[op.copyOff..<op.copyOff+op.copyLen]
    of dopInsert:
      outStr.add op.insertData
  if delta.checksum != 0:
    let cs = computeChecksum(outStr)
    if cs != delta.checksum:
      return err[Blob](feDeltaError, "checksum mismatch", "expected " & $delta.checksum & " got " & $cs)
  ok(Blob(data: outStr))

proc deltaApply*(source: Blob, deltaBlob: Blob): FossilResult[Blob] =
  let dRes = deltaDecode(deltaBlob)
  if dRes.isErr: return err[Blob](dRes.error.code, dRes.error.msg, dRes.error.details)
  deltaApply(source, dRes.value)

proc deltaRoundtripTest*(source, target: Blob): bool =
  let cr = deltaCreate(source, target)
  if cr.isErr: return false
  let enc = deltaEncode(cr.value)
  let ap = deltaApply(source, enc)
  if ap.isErr: return false
  ap.value.data == target.data

proc deltaSize*(d: Delta): int =
  deltaEncode(d).len

proc deltaCompressionRatio*(source, target: Blob): float =
  let cr = deltaCreate(source, target)
  if cr.isErr: return 1.0
  let encSize = cr.value.deltaSize()
  if target.len == 0: return 0.0
  float(encSize) / float(target.len)
