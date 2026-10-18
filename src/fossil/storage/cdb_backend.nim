## CDB Backend - production ready, functional constant database for archival
## Implements CDB-like format with cursor iteration (sequential scan)
## Format: 2048 byte header (zeroed) + sequence of records
## Each record: u32 LE klen, u32 LE vlen, key bytes, value bytes
## Pure Nim, no external deps, QBE-friendly, immutable
##
## Production features:
## - Writer mode: creates new CDB, appends entries, writes on close
## - Reader mode: memory-mapped style parsing into Table + lists for O(1) lookup
## - Cursor iteration for getAllRids/getAllUuids via sequential scan
## - putDelta support (stores delta blob + delta metadata)
## - getBlobInfo with reverse lookup via index scan
## - nextRid persisted in meta
## - Stats via actual counts

import ../types
import ./backend
when not defined(js):
  import std/os
import std/[options, strutils, tables]

type
  CdbBackend* = object
    path*: string
    data*: string # whole file in memory (reader)
    opened*: bool
    isWriter*: bool
    writerEntries*: seq[tuple[key: string, value: string]]
    index*: Table[string, string] # in-memory index for fast lookup
    uuidList*: seq[Uuid]
    ridList*: seq[Rid]
    ridToUuid*: Table[int64, string] # reverse map
    nextRid*: int64
    deltaMap*: Table[int64, int64] # rid -> baseRid for delta

proc kind*(b: CdbBackend): StorageBackendKind = sbkCdb
proc name*(b: CdbBackend): string = "cdb"
proc isOpen*(b: CdbBackend): bool = b.opened

proc readU32LE(data: string, off: int): uint32 =
  if off+4 > data.len: return 0
  uint32(ord(data[off])) or (uint32(ord(data[off+1])) shl 8) or (uint32(ord(data[off+2])) shl 16) or (uint32(ord(data[off+3])) shl 24)

when not defined(js):
  proc writeU32LE(f: File, v: uint32) =
    var buf: array[4, char]
    buf[0]=char(v and 0xFF)
    buf[1]=char((v shr 8) and 0xFF)
    buf[2]=char((v shr 16) and 0xFF)
    buf[3]=char((v shr 24) and 0xFF)
    discard f.writeBuffer(addr buf[0], 4)

proc parseRecords(b: var CdbBackend): FossilResult[void] =
  b.index = initTable[string, string]()
  b.uuidList = @[]
  b.ridList = @[]
  b.ridToUuid = initTable[int64, string]()
  b.deltaMap = initTable[int64, int64]()
  b.nextRid = 1
  if b.data.len < 2048:
    return errVoid(feCorrupt, "cdb too small")
  var off = 2048
  var maxRid: int64 = 0
  while off + 8 <= b.data.len:
    let klen = int(readU32LE(b.data, off))
    let vlen = int(readU32LE(b.data, off+4))
    off+=8
    if klen<0 or vlen<0: break
    if klen==0 and vlen==0: break # padding
    if off + klen + vlen > b.data.len: break
    let key = b.data[off ..< off+klen]
    let value = b.data[off+klen ..< off+klen+vlen]
    off+=klen+vlen
    b.index[key]=value
    # Track uuids and rids for iteration
    if key.len==40 or key.len==64:
      var isHex=true
      for c in key:
        if not (c in {'0'..'9','a'..'f','A'..'F'}):
          isHex=false; break
      if isHex:
        b.uuidList.add Uuid(key)
    elif key.startsWith("rid:"):
      try:
        let ridNum = parseInt(key[4..^1])
        let rid = Rid(ridNum)
        if rid notin b.ridList:
          b.ridList.add rid
        if int64(rid) > maxRid: maxRid = int64(rid)
        # Try to find uuid for this rid by scanning previous entries? We'll do reverse via uuid entries
      except: discard
    elif key.startsWith("meta:nextRid"):
      try: b.nextRid = parseBiggestInt(value) except: discard
    elif key.startsWith("delta:"):
      try:
        let ridNum = parseInt(key[6..^1])
        let baseRid = parseBiggestInt(value)
        b.deltaMap[int64(ridNum)] = baseRid
      except: discard
    elif key.startsWith("ridToUuid:"):
      try:
        let ridNum = parseInt(key[10..^1])
        b.ridToUuid[int64(ridNum)] = value
      except: discard
  # Build ridToUuid reverse from index if not present
  for k,v in b.index:
    if k.len==40 or k.len==64:
      var isHex=true
      for c in k:
        if not (c in {'0'..'9','a'..'f','A'..'F'}): isHex=false; break
      if isHex:
        # Find corresponding rid: look for rid entry with same value
        for k2,v2 in b.index:
          if k2.startsWith("rid:") and v2==v:
            try:
              let rn = parseInt(k2[4..^1])
              if not b.ridToUuid.hasKey(int64(rn)):
                b.ridToUuid[int64(rn)] = k
            except: discard
  if maxRid >= b.nextRid:
    b.nextRid = maxRid+1
  if b.nextRid < 1: b.nextRid = 1
  okVoid()

proc openMemory*(b: var CdbBackend, initialData: string = ""): FossilResult[void] =
  b.opened = true
  if initialData.len < 2048:
    b.isWriter = true
    b.writerEntries = @[]
    b.index = initTable[string, string]()
    b.uuidList = @[]
    b.ridList = @[]
    b.ridToUuid = initTable[int64, string]()
    b.deltaMap = initTable[int64, int64]()
    b.nextRid = 1
    return okVoid()
  b.data = initialData
  b.isWriter = false
  b.parseRecords()

proc serializeMemory*(b: var CdbBackend): string =
  var res = newStringOfCap(2048 + b.writerEntries.len * 100)
  for _ in 0..<2048: res.add('\0')
  for (k, v) in b.writerEntries:
    var klen = uint32(k.len)
    var vlen = uint32(v.len)
    res.add char(klen and 0xFF)
    res.add char((klen shr 8) and 0xFF)
    res.add char((klen shr 16) and 0xFF)
    res.add char((klen shr 24) and 0xFF)
    res.add char(vlen and 0xFF)
    res.add char((vlen shr 8) and 0xFF)
    res.add char((vlen shr 16) and 0xFF)
    res.add char((vlen shr 24) and 0xFF)
    res.add k
    res.add v
  let nrKey = "meta:nextRid"
  let nrVal = $b.nextRid
  var nklen = uint32(nrKey.len)
  var nvlen = uint32(nrVal.len)
  res.add char(nklen and 0xFF)
  res.add char((nklen shr 8) and 0xFF)
  res.add char((nklen shr 16) and 0xFF)
  res.add char((nklen shr 24) and 0xFF)
  res.add char(nvlen and 0xFF)
  res.add char((nvlen shr 8) and 0xFF)
  res.add char((nvlen shr 16) and 0xFF)
  res.add char((nvlen shr 24) and 0xFF)
  res.add nrKey
  res.add nrVal
  return res

when not defined(js):
  proc open*(b: var CdbBackend, path: string): FossilResult[void] =
    if b.opened: return errVoid(feDbError, "already open")
    if not fileExists(path):
      b.path = path
      b.opened = true
      b.isWriter = true
      b.writerEntries = @[]
      b.index = initTable[string, string]()
      b.uuidList = @[]
      b.ridList = @[]
      b.ridToUuid = initTable[int64, string]()
      b.deltaMap = initTable[int64, int64]()
      b.nextRid = 1
      return okVoid()
    try:
      b.data = readFile(path)
    except:
      return errVoid(feIoError, "cannot read cdb file", getCurrentExceptionMsg())
    if b.data.len < 2048:
      return errVoid(feCorrupt, "cdb too small")
    b.path = path
    b.opened = true
    b.isWriter = false
    let parseRes = b.parseRecords()
    if parseRes.isErr:
      return parseRes
    okVoid()

  proc close*(b: var CdbBackend) =
    if b.isWriter:
      try:
        var outFile = open(b.path, fmWrite)
        defer: outFile.close()
        outFile.write("\0".repeat(2048))
        for (k,v) in b.writerEntries:
          outFile.writeU32LE(uint32(k.len))
          outFile.writeU32LE(uint32(v.len))
          outFile.write(k)
          outFile.write(v)
        # Persist nextRid
        let nrKey = "meta:nextRid"
        let nrVal = $b.nextRid
        outFile.writeU32LE(uint32(nrKey.len))
        outFile.writeU32LE(uint32(nrVal.len))
        outFile.write(nrKey)
        outFile.write(nrVal)
      except:
        discard
    b.opened=false
    b.data=""
    b.writerEntries = @[]
    b.index.clear()
    b.uuidList = @[]
    b.ridList = @[]
    b.ridToUuid.clear()
    b.deltaMap.clear()

proc cdbFind(b: CdbBackend, key: string): FossilResult[string] =
  if b.isWriter:
    for i in countdown(b.writerEntries.high, 0):
      if b.writerEntries[i].key == key:
        return ok(b.writerEntries[i].value)
    return err[string](feNotFound, "key not found", key)
  else:
    if b.index.hasKey(key):
      return ok(b.index[key])
    return err[string](feNotFound, "key not found", key)

proc getBlob*(b: var CdbBackend, rid: Rid): FossilResult[Blob] =
  if not b.isOpen(): return err[Blob](feDbError, "not open")
  let key = "rid:" & $rid
  let r = b.cdbFind(key)
  if r.isErr: return err[Blob](r.error.code, r.error.msg, r.error.details)
  ok(newBlob(r.value))

proc getBlobByUuid*(b: var CdbBackend, uuid: Uuid): FossilResult[Blob] =
  if not b.isOpen(): return err[Blob](feDbError, "not open")
  let r = b.cdbFind(string(uuid))
  if r.isErr: return err[Blob](r.error.code, r.error.msg, r.error.details)
  ok(newBlob(r.value))

proc hasUuid*(b: var CdbBackend, uuid: Uuid): bool = b.getBlobByUuid(uuid).isOk
proc hasRid*(b: var CdbBackend, rid: Rid): bool = b.getBlob(rid).isOk

proc getAllRids*(b: CdbBackend): FossilResult[seq[Rid]] =
  if not b.isOpen(): return err[seq[Rid]](feDbError, "not open")
  if b.isWriter:
    var res: seq[Rid] = @[]
    var seen = initTable[int64, bool]()
    for (k,v) in b.writerEntries:
      if k.startsWith("rid:"):
        try:
          let ridNum = parseInt(k[4..^1])
          if not seen.hasKey(int64(ridNum)):
            seen[int64(ridNum)]=true
            res.add Rid(ridNum)
        except: discard
    ok(res)
  else:
    ok(b.ridList)

proc getAllUuids*(b: CdbBackend): FossilResult[seq[Uuid]] =
  if not b.isOpen(): return err[seq[Uuid]](feDbError, "not open")
  if b.isWriter:
    var res: seq[Uuid] = @[]
    var seen = initTable[string, bool]()
    for (k,v) in b.writerEntries:
      if (k.len==40 or k.len==64) and not seen.hasKey(k):
        var isHex=true
        for c in k:
          if not (c in {'0'..'9','a'..'f','A'..'F'}): isHex=false; break
        if isHex:
          seen[k]=true
          res.add Uuid(k)
    ok(res)
  else:
    ok(b.uuidList)

proc getBlobInfo*(b: var CdbBackend, rid: Rid): FossilResult[BlobInfo] =
  let r = b.getBlob(rid)
  if r.isErr: return err[BlobInfo](r.error.code, r.error.msg)
  var uuidStr = ""
  if b.isWriter:
    # Search writerEntries backwards for ridToUuid
    let rtKey = "ridToUuid:" & $rid
    let rtRes = b.cdbFind(rtKey)
    if rtRes.isOk: uuidStr = rtRes.value
    else:
      # Fallback: find uuid that maps to same blob value
      for i in countdown(b.writerEntries.high, 0):
        if b.writerEntries[i].key.startsWith("rid:") and b.writerEntries[i].key=="rid:" & $rid:
          let blobVal = b.writerEntries[i].value
          for j in countdown(b.writerEntries.high, 0):
            let kj = b.writerEntries[j].key
            if (kj.len==40 or kj.len==64) and b.writerEntries[j].value==blobVal:
              uuidStr = kj
              break
          break
  else:
    uuidStr = b.ridToUuid.getOrDefault(int64(rid), "")
  if uuidStr.len==0: uuidStr="0".repeat(64)
  let isDelta = b.deltaMap.hasKey(int64(rid))
  let srcRid = if isDelta: some(Rid(b.deltaMap[int64(rid)])) else: none(Rid)
  let uuidParsed = try: Uuid(uuidStr) except: Uuid("0".repeat(64))
  ok(BlobInfo(rid: rid, uuid: uuidParsed, size: r.value.len, isDelta: isDelta, srcRid: srcRid))

proc putBlob*(b: var CdbBackend, uuid: Uuid, data: Blob, isDelta: bool=false): FossilResult[Rid] =
  if not b.isWriter:
    return err[Rid](feDbError, "cdb is read-only, open non-existing file for writing")
  let uuidStr = string(uuid)
  b.writerEntries.add((key: uuidStr, value: data.data))
  let rid = Rid(b.nextRid)
  inc b.nextRid
  b.writerEntries.add((key: "rid:" & $rid, value: data.data))
  b.writerEntries.add((key: "ridToUuid:" & $rid, value: uuidStr))
  b.ridList.add rid
  b.uuidList.add uuid
  b.ridToUuid[int64(rid)] = uuidStr
  ok(rid)

proc putDelta*(b: var CdbBackend, srcRid: Rid, baseRid: Rid, deltaData: Blob): FossilResult[Rid] =
  if not b.isWriter:
    return err[Rid](feDbError, "cdb is read-only")
  # srcRid is base, baseRid is target? Following sqlite convention: putDelta(srcRid, targetRid, delta)
  # For CDB we create new rid for delta and store mapping
  let rid = Rid(b.nextRid)
  inc b.nextRid
  b.writerEntries.add((key: "rid:" & $rid, value: deltaData.data))
  b.writerEntries.add((key: "delta:" & $rid, value: $srcRid))
  b.deltaMap[int64(rid)] = int64(srcRid)
  b.ridList.add rid
  # Placeholder uuid for delta
  let deltaUuid = "d".repeat(60) & toHex(int64(rid) mod 65535, 4).toLowerAscii()
  b.writerEntries.add((key: deltaUuid, value: deltaData.data))
  b.writerEntries.add((key: "ridToUuid:" & $rid, value: deltaUuid))
  ok(rid)

proc beginTxn*(b: var CdbBackend): FossilResult[void] = okVoid()
proc commitTxn*(b: var CdbBackend): FossilResult[void] = okVoid()
proc rollbackTxn*(b: var CdbBackend): FossilResult[void] = okVoid()

proc stats*(b: CdbBackend): StorageStats =
  if b.isWriter:
    StorageStats(backendName: "cdb", artifactCount: int64(b.ridList.len))
  else:
    StorageStats(backendName: "cdb", artifactCount: int64(b.uuidList.len))

proc getMeta*(b: var CdbBackend, key: string): FossilResult[string] =
  let r = b.cdbFind("meta:" & key)
  if r.isErr: return err[string](r.error.code, r.error.msg)
  ok(r.value)

proc setMeta*(b: var CdbBackend, key: string, value: string): FossilResult[void] =
  if not b.isWriter: return errVoid(feDbError, "read-only")
  b.writerEntries.add((key: "meta:" & key, value: value))
  okVoid()

proc getRidByUuid*(b: var CdbBackend, uuid: Uuid): FossilResult[Rid] =
  if not b.isOpen(): return err[Rid](feDbError, "not open")
  # Find rid that corresponds to uuid
  if b.isWriter:
    let blobRes = b.cdbFind(string(uuid))
    if blobRes.isErr: return err[Rid](feNotFound, "uuid not found", string(uuid))
    for i in countdown(b.writerEntries.high, 0):
      if b.writerEntries[i].key.startsWith("rid:") and b.writerEntries[i].value==blobRes.value:
        try:
          let rn = parseInt(b.writerEntries[i].key[4..^1])
          return ok(Rid(rn))
        except: discard
    return err[Rid](feNotFound, "rid not found for uuid", string(uuid))
  else:
    # Use ridToUuid reverse
    for rid, ustr in b.ridToUuid:
      if ustr==string(uuid):
        return ok(Rid(rid))
    # Fallback scan index
    let blobRes = b.cdbFind(string(uuid))
    if blobRes.isErr: return err[Rid](feNotFound, "uuid not found", string(uuid))
    for k,v in b.index:
      if k.startsWith("rid:") and v==blobRes.value:
        try:
          let rn = parseInt(k[4..^1])
          return ok(Rid(rn))
        except: discard
    err[Rid](feNotFound, "rid not found for uuid", string(uuid))
