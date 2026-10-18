## Storage Backend Concept - Nim 2.x compatible

import ../types
import std/[options]

type
  BlobInfo* = object
    rid*: Rid
    uuid*: Uuid
    size*: int
    isDelta*: bool
    srcRid*: Option[Rid]

  StorageStats* = object
    artifactCount*: int64
    totalSize*: int64
    backendName*: string

  StorageBackendKind* = enum
    sbkSqlite
    sbkLibMdbx
    sbkLmdb
    sbkCdb

# Concept definition - Nim 2.x syntax, void procs without 'is'
type StorageBackend* = concept b, var b2
  b.kind is StorageBackendKind
  b.name is string
  b.isOpen is bool
  b2.open(string) is FossilResult[void]
  b2.close()
  b.getBlob(Rid) is FossilResult[Blob]
  b.getBlobByUuid(Uuid) is FossilResult[Blob]
  b.getBlobInfo(Rid) is FossilResult[BlobInfo]
  b.hasUuid(Uuid) is bool
  b.hasRid(Rid) is bool
  b2.putBlob(Uuid, Blob, bool) is FossilResult[Rid]
  b2.putDelta(Rid, Rid, Blob) is FossilResult[Rid]
  b.getAllRids() is FossilResult[seq[Rid]]
  b.getAllUuids() is FossilResult[seq[Uuid]]
  b2.beginTxn() is FossilResult[void]
  b2.commitTxn() is FossilResult[void]
  b2.rollbackTxn() is FossilResult[void]
  b.stats() is StorageStats
  b.getMeta(string) is FossilResult[string]
  b2.setMeta(string, string) is FossilResult[void]

# Helper for generic code
proc getBlobOrErr*[T: StorageBackend](backend: T, rid: Rid): Blob =
  let r = backend.getBlob(rid)
  if r.isErr: raise newException(IOError, r.error.msg)
  r.value

template withTxn*[T: StorageBackend](backend: var T, body: untyped) =
  let beginRes = backend.beginTxn()
  if beginRes.isErr:
    raise newException(IOError, "beginTxn failed: " & beginRes.error.msg)
  try:
    body
    let commitRes = backend.commitTxn()
    if commitRes.isErr:
      raise newException(IOError, "commit failed: " & commitRes.error.msg)
  except:
    discard backend.rollbackTxn()
    raise

proc ensureOpen*[T: StorageBackend](b: T): FossilResult[void] =
  if not b.isOpen():
    errVoid(feDbError, "backend not open")
  else:
    okVoid()
