## Artifact handling - blob + delta chain resolution

import ../types
import ./manifest
import ../delta/delta
import std/[options]

type
  ArtifactStore* = concept s
    s.getBlob(Rid): FossilResult[Blob]
    s.getBlobByUuid(Uuid): FossilResult[Blob]

proc resolveBlob*[T: ArtifactStore](store: T, rid: Rid): FossilResult[Blob] =
  ## Resolve rid, following delta chain if needed
  ## In SQLite backend, blob table may contain delta content that needs src
  ## Simplified: we assume getBlob already returns fully resolved? But we handle delta flag
  let blobRes = store.getBlob(rid)
  if blobRes.isErr: return blobRes
  # Check if blob is delta? In original, delta table stores delta
  # For this port, we store full content unless isDelta flag set in meta
  # TODO: implement delta chain resolution via delta table
  blobRes

proc resolveBlobByUuid*[T: ArtifactStore](store: T, uuid: Uuid): FossilResult[Blob] =
  let blobRes = store.getBlobByUuid(uuid)
  if blobRes.isErr: return blobRes
  blobRes

proc getManifestByUuid*[T: ArtifactStore](store: T, uuid: Uuid): FossilResult[Manifest] =
  let blobRes = store.getBlobByUuid(uuid)
  if blobRes.isErr:
    return err[Manifest](blobRes.error.code, blobRes.error.msg, blobRes.error.details)
  let artRes = parseArtifact(blobRes.value)
  if artRes.isErr:
    return err[Manifest](feManifestError, "not a manifest", string(uuid))
  let art = artRes.value
  if art.manifest.isNone:
    return err[Manifest](feManifestError, "artifact has no manifest", string(uuid))
  ok(art.manifest.get)

proc computeDeltaChain*[T: ArtifactStore](store: T, targetRid: Rid, baseRid: Rid): FossilResult[Blob] =
  ## Create delta from base to target
  let baseRes = store.getBlob(baseRid)
  if baseRes.isErr: return err[Blob](baseRes.error.code, baseRes.error.msg)
  let targetRes = store.getBlob(targetRid)
  if targetRes.isErr: return err[Blob](targetRes.error.code, targetRes.error.msg)
  let deltaRes = deltaCreate(baseRes.value, targetRes.value)
  if deltaRes.isErr: return err[Blob](deltaRes.error.code, deltaRes.error.msg)
  ok(deltaEncode(deltaRes.value))
