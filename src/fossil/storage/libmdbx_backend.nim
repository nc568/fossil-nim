## libmdbx Backend - production ready, recommended replacement for SQLite
## Uses libmdbx via C interop (single file mdbx.c or -lmdbx)
## Build with: -d:useMdbx --passL:-lmdbx or vendored mdbx.c
##
## Features vs LMDB:
## - Auto-growth via mdbx_env_set_geometry (no manual mapsize handling)
## - Better crash safety, faster, supports append
## - Same cursor iteration API but with mdbx_ prefix
## - 4 DBIs: uuid_to_rid, rid_to_blob (INTEGERKEY), meta, delta
## - Production: nextRid persisted, reverse lookup, putDelta, stats via cursor

import ../types
import ./backend
import std/[options, strutils, os, tables]

# --- C interop for libmdbx ---

{.push header: "mdbx.h".}
type
  MDBX_env {.importc: "MDBX_env", incompleteStruct.} = object
  MDBX_txn {.importc: "MDBX_txn", incompleteStruct.} = object
  MDBX_dbi {.importc: "MDBX_dbi".} = distinct cuint
  MDBX_val {.importc: "MDBX_val".} = object
    iov_base*: pointer
    iov_len*: csize_t
  MDBX_error_t {.importc: "MDBX_error_t".} = cint
  MDBX_cursor {.importc: "MDBX_cursor", incompleteStruct.} = object
  MDBX_cursor_op {.importc: "MDBX_cursor_op".} = cint
  MDBX_stat {.importc: "MDBX_stat".} = object
    ms_psize: cuint
    ms_depth: cuint
    ms_branch_pages: uint64
    ms_leaf_pages: uint64
    ms_overflow_pages: uint64
    ms_entries: uint64

const
  MDBX_SUCCESS = 0
  MDBX_CREATE = 0x40000
  MDBX_DUPSORT = 0x04
  MDBX_INTEGERKEY = 0x08
  MDBX_APPEND = 0x00020000
  MDBX_FIRST = 0
  MDBX_NEXT = 8
  MDBX_SET = 15
  MDBX_RDONLY = 0x20000
  MDBX_NOTFOUND = -30798

proc mdbx_env_create(env: ptr ptr MDBX_env): cint {.importc.}
proc mdbx_env_open(env: ptr MDBX_env, path: cstring, flags: cuint, mode: cuint): cint {.importc.}
proc mdbx_env_close(env: ptr MDBX_env): cint {.importc.}
proc mdbx_env_set_maxdbs(env: ptr MDBX_env, dbs: cuint): cint {.importc.}
proc mdbx_env_set_geometry(env: ptr MDBX_env, size_lower: int64, size_now: int64, size_upper: int64, growth_step: int64, shrink_threshold: int64, page_size: int64): cint {.importc.}
proc mdbx_txn_begin(env: ptr MDBX_env, parent: ptr MDBX_txn, flags: cuint, txn: ptr ptr MDBX_txn): cint {.importc.}
proc mdbx_txn_commit(txn: ptr MDBX_txn): cint {.importc.}
proc mdbx_txn_abort(txn: ptr MDBX_txn): cint {.importc.}
proc mdbx_dbi_open(txn: ptr MDBX_txn, name: cstring, flags: cuint, dbi: ptr MDBX_dbi): cint {.importc.}
proc mdbx_get(txn: ptr MDBX_txn, dbi: MDBX_dbi, key: ptr MDBX_val, data: ptr MDBX_val): cint {.importc.}
proc mdbx_put(txn: ptr MDBX_txn, dbi: MDBX_dbi, key: ptr MDBX_val, data: ptr MDBX_val, flags: cuint): cint {.importc.}
proc mdbx_del(txn: ptr MDBX_txn, dbi: MDBX_dbi, key: ptr MDBX_val, data: ptr MDBX_val): cint {.importc.}
proc mdbx_strerror(err: cint): cstring {.importc.}
proc mdbx_cursor_open(txn: ptr MDBX_txn, dbi: MDBX_dbi, cursor: ptr ptr MDBX_cursor): cint {.importc.}
proc mdbx_cursor_close(cursor: ptr MDBX_cursor) {.importc.}
proc mdbx_cursor_get(cursor: ptr MDBX_cursor, key: ptr MDBX_val, data: ptr MDBX_val, op: MDBX_cursor_op): cint {.importc.}
proc mdbx_dbi_stat(txn: ptr MDBX_txn, dbi: MDBX_dbi, stat: ptr MDBX_stat, bytes: csize_t): cint {.importc.}

{.pop.}

type
  LibMdbxBackend* = object
    env*: ptr MDBX_env
    dbiUuid*: MDBX_dbi
    dbiBlob*: MDBX_dbi
    dbiMeta*: MDBX_dbi
    dbiDelta*: MDBX_dbi
    txn*: ptr MDBX_txn
    readTxn*: ptr MDBX_txn
    path*: string
    opened*: bool
    inWriteTxn*: bool
    nextRid*: int64
    ridToUuidCache*: Table[int64, string]

proc kind*(b: LibMdbxBackend): StorageBackendKind = sbkLibMdbx
proc name*(b: LibMdbxBackend): string = "libmdbx"
proc isOpen*(b: LibMdbxBackend): bool = b.opened and b.env != nil

proc open*(b: var LibMdbxBackend, path: string): FossilResult[void] =
  if b.opened: return errVoid(feDbError, "already open")
  # Ensure dir exists
  let dirPath = if dirExists(path): path else: parentDir(path)
  if dirPath.len>0 and not dirExists(dirPath):
    try: createDir(dirPath) except: discard
  if not dirExists(path):
    try: createDir(path) except: discard
  var env: ptr MDBX_env
  var rc = mdbx_env_create(addr env)
  if rc != MDBX_SUCCESS:
    return errVoid(feDbError, "mdbx_env_create failed", $rc)
  discard mdbx_env_set_maxdbs(env, 10)
  # Auto-growth: lower -1 (default), now -1, upper 10GB, growth 64MB, shrink 0, page -1
  discard mdbx_env_set_geometry(env, -1, -1, 10*1024*1024*1024, 64*1024*1024, -1, -1)
  rc = mdbx_env_open(env, path.cstring, 0, 0o644)
  if rc != MDBX_SUCCESS:
    return errVoid(feDbError, "mdbx_env_open failed", $cast[cstring](mdbx_strerror(rc)) & " path=" & path)
  b.env = env
  var txn: ptr MDBX_txn
  rc = mdbx_txn_begin(env, nil, 0, addr txn)
  if rc != MDBX_SUCCESS:
    return errVoid(feDbError, "txn_begin failed", $rc)
  var dbiUuid, dbiBlob, dbiMeta, dbiDelta: MDBX_dbi
  var r = mdbx_dbi_open(txn, "uuid_to_rid".cstring, MDBX_CREATE, addr dbiUuid)
  if r != MDBX_SUCCESS: discard mdbx_txn_abort(txn); return errVoid(feDbError, "dbi open uuid failed", $r)
  r = mdbx_dbi_open(txn, "rid_to_blob".cstring, MDBX_CREATE or MDBX_INTEGERKEY, addr dbiBlob)
  if r != MDBX_SUCCESS: discard mdbx_txn_abort(txn); return errVoid(feDbError, "dbi open blob failed", $r)
  r = mdbx_dbi_open(txn, "meta".cstring, MDBX_CREATE, addr dbiMeta)
  if r != MDBX_SUCCESS: discard mdbx_txn_abort(txn); return errVoid(feDbError, "dbi open meta failed", $r)
  r = mdbx_dbi_open(txn, "delta".cstring, MDBX_CREATE, addr dbiDelta)
  if r != MDBX_SUCCESS: discard mdbx_txn_abort(txn); return errVoid(feDbError, "dbi open delta failed", $r)
  rc = mdbx_txn_commit(txn)
  if rc != MDBX_SUCCESS:
    return errVoid(feDbError, "commit failed", $rc)
  b.dbiUuid = dbiUuid
  b.dbiBlob = dbiBlob
  b.dbiMeta = dbiMeta
  b.dbiDelta = dbiDelta
  b.path = path
  b.opened = true
  b.nextRid = 1
  b.ridToUuidCache = initTable[int64, string]()
  # Load nextRid from meta
  var readTxn: ptr MDBX_txn
  if mdbx_txn_begin(env, nil, MDBX_RDONLY, addr readTxn) == MDBX_SUCCESS:
    var k, v: MDBX_val
    let keyStr = "nextRid"
    k.iov_base = unsafeAddr keyStr[0]
    k.iov_len = csize_t(keyStr.len)
    if mdbx_get(readTxn, dbiMeta, addr k, addr v) == MDBX_SUCCESS and v.iov_len>0:
      var s = newString(v.iov_len)
      copyMem(addr s[0], v.iov_base, v.iov_len)
      try: b.nextRid = parseBiggestInt(s) except: discard
      if b.nextRid < 1: b.nextRid = 1
    # Count max rid to ensure nextRid beyond
    var cursor: ptr MDBX_cursor
    if mdbx_cursor_open(readTxn, dbiBlob, addr cursor) == MDBX_SUCCESS:
      var ck, cv: MDBX_val
      var maxRid: int64 = 0
      var cr = mdbx_cursor_get(cursor, addr ck, addr cv, MDBX_FIRST)
      while cr == MDBX_SUCCESS:
        if ck.iov_len == csize_t(sizeof(int64)):
          var rv: int64
          copyMem(addr rv, ck.iov_base, sizeof(int64))
          if rv > maxRid: maxRid = rv
        cr = mdbx_cursor_get(cursor, addr ck, addr cv, MDBX_NEXT)
      mdbx_cursor_close(cursor)
      if maxRid >= b.nextRid:
        b.nextRid = maxRid+1
    discard mdbx_txn_abort(readTxn)
  okVoid()

proc close*(b: var LibMdbxBackend) =
  if b.readTxn != nil:
    discard mdbx_txn_abort(b.readTxn)
    b.readTxn = nil
  if b.txn != nil:
    discard mdbx_txn_abort(b.txn)
    b.txn = nil
  if b.env != nil:
    discard mdbx_env_close(b.env)
    b.env = nil
  b.opened = false
  b.ridToUuidCache.clear()

proc ensureReadTxn(b: var LibMdbxBackend): FossilResult[void] =
  if b.readTxn == nil:
    var rc = mdbx_txn_begin(b.env, nil, MDBX_RDONLY, addr b.readTxn)
    if rc != MDBX_SUCCESS:
      return errVoid(feDbError, "read txn begin failed", $rc)
  okVoid()

proc invalidateReadTxn(b: var LibMdbxBackend) =
  if b.readTxn != nil:
    discard mdbx_txn_abort(b.readTxn)
    b.readTxn = nil

proc getBlob*(b: var LibMdbxBackend, rid: Rid): FossilResult[Blob] =
  if not b.isOpen(): return err[Blob](feDbError, "not open")
  let er = b.ensureReadTxn()
  if er.isErr: return err[Blob](er.error.code, er.error.msg)
  var key: MDBX_val
  var data: MDBX_val
  var ridBE = int64(rid)
  key.iov_base = addr ridBE
  key.iov_len = csize_t(sizeof(ridBE))
  let rc = mdbx_get(b.readTxn, b.dbiBlob, addr key, addr data)
  if rc != MDBX_SUCCESS:
    if rc == MDBX_NOTFOUND:
      return err[Blob](feNotFound, "rid not found", $rid)
    return err[Blob](feDbError, "mdbx_get failed", $rc)
  var s = newString(data.iov_len)
  if data.iov_len > 0:
    copyMem(addr s[0], data.iov_base, data.iov_len)
  ok(newBlob(s))

proc getBlobByUuid*(b: var LibMdbxBackend, uuid: Uuid): FossilResult[Blob] =
  if not b.isOpen(): return err[Blob](feDbError, "not open")
  let er = b.ensureReadTxn()
  if er.isErr: return err[Blob](er.error.code, er.error.msg)
  var key: MDBX_val
  var data: MDBX_val
  let uuidStr = string(uuid)
  if uuidStr.len==0: return err[Blob](feInvalidArg, "empty uuid")
  key.iov_base = unsafeAddr uuidStr[0]
  key.iov_len = csize_t(uuidStr.len)
  var rc = mdbx_get(b.readTxn, b.dbiUuid, addr key, addr data)
  if rc != MDBX_SUCCESS:
    if rc == MDBX_NOTFOUND:
      return err[Blob](feNotFound, "uuid not found", uuidStr)
    return err[Blob](feDbError, "mdbx_get uuid failed", $rc)
  var rid: int64
  copyMem(addr rid, data.iov_base, min(data.iov_len, csize_t(sizeof(rid))))
  b.ridToUuidCache[rid] = uuidStr
  b.getBlob(Rid(rid))

proc hasUuid*(b: var LibMdbxBackend, uuid: Uuid): bool =
  if not b.isOpen(): return false
  discard b.ensureReadTxn()
  var key, data: MDBX_val
  let us = string(uuid)
  if us.len==0: return false
  key.iov_base = unsafeAddr us[0]
  key.iov_len = csize_t(us.len)
  mdbx_get(b.readTxn, b.dbiUuid, addr key, addr data) == MDBX_SUCCESS

proc hasRid*(b: var LibMdbxBackend, rid: Rid): bool =
  if not b.isOpen(): return false
  discard b.ensureReadTxn()
  var key, data: MDBX_val
  var rv = int64(rid)
  key.iov_base = addr rv
  key.iov_len = csize_t(sizeof(rv))
  mdbx_get(b.readTxn, b.dbiBlob, addr key, addr data) == MDBX_SUCCESS

proc putBlob*(b: var LibMdbxBackend, uuid: Uuid, data: Blob, isDelta: bool = false): FossilResult[Rid] =
  if not b.isOpen(): return err[Rid](feDbError, "not open")
  if not b.inWriteTxn:
    return err[Rid](feDbError, "must be in transaction, call beginTxn")
  var keyUuid: MDBX_val
  var valRid: MDBX_val
  let uuidStr = string(uuid)
  if uuidStr.len==0: return err[Rid](feInvalidArg, "empty uuid")
  keyUuid.iov_base = unsafeAddr uuidStr[0]
  keyUuid.iov_len = csize_t(uuidStr.len)
  var rid = b.nextRid
  inc b.nextRid
  valRid.iov_base = addr rid
  valRid.iov_len = csize_t(sizeof(rid))
  var rc = mdbx_put(b.txn, b.dbiUuid, addr keyUuid, addr valRid, 0)
  if rc != MDBX_SUCCESS:
    return err[Rid](feDbError, "put uuid failed", $rc)
  b.ridToUuidCache[rid] = uuidStr
  var keyRid: MDBX_val
  var valBlob: MDBX_val
  keyRid.iov_base = addr rid
  keyRid.iov_len = csize_t(sizeof(rid))
  if data.len > 0:
    valBlob.iov_base = unsafeAddr data.data[0]
    valBlob.iov_len = csize_t(data.len)
  else:
    valBlob.iov_base = nil
    valBlob.iov_len = 0
  rc = mdbx_put(b.txn, b.dbiBlob, addr keyRid, addr valBlob, MDBX_APPEND)
  if rc != MDBX_SUCCESS:
    # Fallback without APPEND (if not monotonic)
    rc = mdbx_put(b.txn, b.dbiBlob, addr keyRid, addr valBlob, 0)
    if rc != MDBX_SUCCESS:
      return err[Rid](feDbError, "put blob failed", $rc)
  ok(Rid(rid))

proc getAllRids*(b: var LibMdbxBackend): FossilResult[seq[Rid]] =
  if not b.isOpen(): return err[seq[Rid]](feDbError, "not open")
  let er = b.ensureReadTxn()
  if er.isErr: return err[seq[Rid]](er.error.code, er.error.msg)
  var cursor: ptr MDBX_cursor
  var rc = mdbx_cursor_open(b.readTxn, b.dbiBlob, addr cursor)
  if rc != MDBX_SUCCESS:
    return err[seq[Rid]](feDbError, "cursor open failed", $rc)
  defer: mdbx_cursor_close(cursor)
  var resultSeq: seq[Rid] = @[]
  var key: MDBX_val
  var data: MDBX_val
  rc = mdbx_cursor_get(cursor, addr key, addr data, MDBX_FIRST)
  while rc == MDBX_SUCCESS:
    if key.iov_len == csize_t(sizeof(int64)):
      var ridVal: int64
      copyMem(addr ridVal, key.iov_base, sizeof(int64))
      resultSeq.add Rid(ridVal)
    rc = mdbx_cursor_get(cursor, addr key, addr data, MDBX_NEXT)
  ok(resultSeq)

proc getAllUuids*(b: var LibMdbxBackend): FossilResult[seq[Uuid]] =
  if not b.isOpen(): return err[seq[Uuid]](feDbError, "not open")
  let er = b.ensureReadTxn()
  if er.isErr: return err[seq[Uuid]](er.error.code, er.error.msg)
  var cursor: ptr MDBX_cursor
  var rc = mdbx_cursor_open(b.readTxn, b.dbiUuid, addr cursor)
  if rc != MDBX_SUCCESS:
    return err[seq[Uuid]](feDbError, "cursor open failed", $rc)
  defer: mdbx_cursor_close(cursor)
  var resultSeq: seq[Uuid] = @[]
  var key: MDBX_val
  var data: MDBX_val
  rc = mdbx_cursor_get(cursor, addr key, addr data, MDBX_FIRST)
  while rc == MDBX_SUCCESS:
    if key.iov_len > 0:
      var s = newString(key.iov_len)
      copyMem(addr s[0], key.iov_base, key.iov_len)
      if s.len == 40 or s.len == 64:
        resultSeq.add Uuid(s)
    rc = mdbx_cursor_get(cursor, addr key, addr data, MDBX_NEXT)
  ok(resultSeq)

proc beginTxn*(b: var LibMdbxBackend): FossilResult[void] =
  if b.inWriteTxn: return errVoid(feDbError, "already in txn")
  var rc = mdbx_txn_begin(b.env, nil, 0, addr b.txn)
  if rc != MDBX_SUCCESS:
    return errVoid(feDbError, "begin txn failed", $rc)
  b.inWriteTxn = true
  okVoid()

proc commitTxn*(b: var LibMdbxBackend): FossilResult[void] =
  if not b.inWriteTxn: return errVoid(feDbError, "not in txn")
  # Persist nextRid
  var k,v: MDBX_val
  let keyStr = "nextRid"
  k.iov_base = unsafeAddr keyStr[0]
  k.iov_len = csize_t(keyStr.len)
  let nextStr = $b.nextRid
  v.iov_base = unsafeAddr nextStr[0]
  v.iov_len = csize_t(nextStr.len)
  discard mdbx_put(b.txn, b.dbiMeta, addr k, addr v, 0)
  let rc = mdbx_txn_commit(b.txn)
  b.txn = nil
  b.inWriteTxn = false
  if rc != MDBX_SUCCESS:
    return errVoid(feDbError, "commit failed", $rc)
  b.invalidateReadTxn()
  okVoid()

proc rollbackTxn*(b: var LibMdbxBackend): FossilResult[void] =
  if b.txn != nil:
    discard mdbx_txn_abort(b.txn)
    b.txn = nil
  b.inWriteTxn = false
  okVoid()

proc stats*(b: var LibMdbxBackend): StorageStats =
  if not b.isOpen(): return StorageStats(backendName: "libmdbx", artifactCount: 0)
  var count: int64 = b.nextRid-1
  if b.readTxn != nil:
    var st: MDBX_stat
    if mdbx_dbi_stat(b.readTxn, b.dbiBlob, addr st, csize_t(sizeof(st))) == MDBX_SUCCESS:
      count = int64(st.ms_entries)
  else:
    var tmpTxn: ptr MDBX_txn
    if mdbx_txn_begin(b.env, nil, MDBX_RDONLY, addr tmpTxn) == MDBX_SUCCESS:
      var st: MDBX_stat
      if mdbx_dbi_stat(tmpTxn, b.dbiBlob, addr st, csize_t(sizeof(st))) == MDBX_SUCCESS:
        count = int64(st.ms_entries)
      discard mdbx_txn_abort(tmpTxn)
  StorageStats(backendName: "libmdbx", artifactCount: count)

proc getMeta*(b: var LibMdbxBackend, key: string): FossilResult[string] =
  let er = b.ensureReadTxn()
  if er.isErr: return err[string](er.error.code, er.error.msg)
  var k: MDBX_val
  var v: MDBX_val
  k.iov_base = unsafeAddr key[0]
  k.iov_len = csize_t(key.len)
  let rc = mdbx_get(b.readTxn, b.dbiMeta, addr k, addr v)
  if rc != MDBX_SUCCESS:
    if rc==MDBX_NOTFOUND: return err[string](feNotFound, "meta not found", key)
    return err[string](feDbError, "meta get failed", $rc)
  var s = newString(v.iov_len)
  if v.iov_len > 0: copyMem(addr s[0], v.iov_base, v.iov_len)
  ok(s)

proc setMeta*(b: var LibMdbxBackend, key: string, value: string): FossilResult[void] =
  if not b.inWriteTxn: return errVoid(feDbError, "need txn")
  var k: MDBX_val
  var v: MDBX_val
  k.iov_base = unsafeAddr key[0]
  k.iov_len = csize_t(key.len)
  v.iov_base = unsafeAddr value[0]
  v.iov_len = csize_t(value.len)
  let rc = mdbx_put(b.txn, b.dbiMeta, addr k, addr v, 0)
  if rc != MDBX_SUCCESS: return errVoid(feDbError, "setMeta failed", $rc)
  okVoid()

proc getBlobInfo*(b: var LibMdbxBackend, rid: Rid): FossilResult[BlobInfo] =
  let blobRes = b.getBlob(rid)
  if blobRes.isErr: return err[BlobInfo](blobRes.error.code, blobRes.error.msg)
  var uuidStr = b.ridToUuidCache.getOrDefault(int64(rid), "")
  if uuidStr.len==0:
    discard b.ensureReadTxn()
    var cursor: ptr MDBX_cursor
    if mdbx_cursor_open(b.readTxn, b.dbiUuid, addr cursor)==MDBX_SUCCESS:
      var k,v: MDBX_val
      var rc = mdbx_cursor_get(cursor, addr k, addr v, MDBX_FIRST)
      while rc==MDBX_SUCCESS:
        if v.iov_len==csize_t(sizeof(int64)):
          var rv: int64
          copyMem(addr rv, v.iov_base, sizeof(int64))
          if rv==int64(rid):
            var s = newString(k.iov_len)
            copyMem(addr s[0], k.iov_base, k.iov_len)
            uuidStr=s
            b.ridToUuidCache[int64(rid)]=s
            break
        rc = mdbx_cursor_get(cursor, addr k, addr v, MDBX_NEXT)
      mdbx_cursor_close(cursor)
  if uuidStr.len==0: uuidStr="0".repeat(64)
  # Check delta
  var isDelta=false
  var srcRid: Option[Rid]=none(Rid)
  discard b.ensureReadTxn()
  var dk, dv: MDBX_val
  var rv = int64(rid)
  dk.iov_base=addr rv; dk.iov_len=csize_t(sizeof(rv))
  if mdbx_get(b.readTxn, b.dbiDelta, addr dk, addr dv)==MDBX_SUCCESS and dv.iov_len==csize_t(sizeof(int64)):
    var base:int64
    copyMem(addr base, dv.iov_base, sizeof(int64))
    isDelta=true
    srcRid=some(Rid(base))
  let uuidParsed = try: Uuid(uuidStr) except: Uuid("0".repeat(64))
  ok(BlobInfo(rid: rid, uuid: uuidParsed, size: blobRes.value.len, isDelta: isDelta, srcRid: srcRid))

proc putDelta*(b: var LibMdbxBackend, srcRid: Rid, baseRid: Rid, deltaData: Blob): FossilResult[Rid] =
  if not b.isOpen(): return err[Rid](feDbError, "not open")
  if not b.inWriteTxn: return err[Rid](feDbError, "need txn")
  var rid = b.nextRid
  inc b.nextRid
  var k,v: MDBX_val
  k.iov_base=addr rid; k.iov_len=csize_t(sizeof(rid))
  if deltaData.len>0:
    v.iov_base=unsafeAddr deltaData.data[0]; v.iov_len=csize_t(deltaData.len)
  else:
    v.iov_base=nil; v.iov_len=0
  var rc = mdbx_put(b.txn, b.dbiBlob, addr k, addr v, MDBX_APPEND)
  if rc!=MDBX_SUCCESS:
    rc = mdbx_put(b.txn, b.dbiBlob, addr k, addr v, 0)
    if rc!=MDBX_SUCCESS: return err[Rid](feDbError, "put delta blob failed", $rc)
  var base = int64(srcRid)
  var dv: MDBX_val
  dv.iov_base=addr base; dv.iov_len=csize_t(sizeof(base))
  rc = mdbx_put(b.txn, b.dbiDelta, addr k, addr dv, 0)
  if rc!=MDBX_SUCCESS: return err[Rid](feDbError, "put delta meta failed", $rc)
  let deltaUuid = "d".repeat(60) & toHex(rid mod 65535, 4).toLowerAscii()
  var uk, uv: MDBX_val
  uk.iov_base=unsafeAddr deltaUuid[0]; uk.iov_len=csize_t(deltaUuid.len)
  uv.iov_base=addr rid; uv.iov_len=csize_t(sizeof(rid))
  discard mdbx_put(b.txn, b.dbiUuid, addr uk, addr uv, 0)
  ok(Rid(rid))

proc getRidByUuid*(b: var LibMdbxBackend, uuid: Uuid): FossilResult[Rid] =
  if not b.isOpen(): return err[Rid](feDbError, "not open")
  discard b.ensureReadTxn()
  var k,v: MDBX_val
  let us = string(uuid)
  k.iov_base=unsafeAddr us[0]; k.iov_len=csize_t(us.len)
  if mdbx_get(b.readTxn, b.dbiUuid, addr k, addr v)!=MDBX_SUCCESS:
    return err[Rid](feNotFound, "uuid not found", us)
  var rid:int64
  copyMem(addr rid, v.iov_base, min(v.iov_len, csize_t(sizeof(rid))))
  ok(Rid(rid))
