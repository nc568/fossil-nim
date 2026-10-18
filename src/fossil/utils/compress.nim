## Compression - zlib wrapper

import ../types

when defined(qbeCompat):
  # Pure Nim fallback - no compression for QBE (or use miniz C)
  proc compressBlob*(data: Blob): Blob = data
  proc decompressBlob*(data: Blob, origSize: int): FossilResult[Blob] = ok(data)
else:
  import std/[strutils]
  {.push header: "<zlib.h>".}
  proc compress2(dest: ptr uint8, destLen: ptr culong, source: ptr uint8, sourceLen: culong, level: cint): cint {.importc: "compress2", header: "<zlib.h>".}
  proc uncompress(dest: ptr uint8, destLen: ptr culong, source: ptr uint8, sourceLen: culong): cint {.importc: "uncompress", header: "<zlib.h>".}
  {.pop.}

  proc compressBlob*(data: Blob): Blob =
    if data.len==0: return data
    var destLen = culong(data.len + data.len div 10 + 12)
    var dest = newString(destLen)
    var srcLen = culong(data.len)
    let rc = compress2(cast[ptr uint8](addr dest[0]), addr destLen, cast[ptr uint8](unsafeAddr data.data[0]), srcLen, 6)
    if rc!=0:
      return data # fallback
    dest.setLen(destLen)
    newBlob(dest)

  proc decompressBlob*(data: Blob, origSize: int): FossilResult[Blob] =
    if data.len==0: return ok(data)
    var destLen = culong(origSize)
    var dest = newString(origSize)
    let rc = uncompress(cast[ptr uint8](addr dest[0]), addr destLen, cast[ptr uint8](unsafeAddr data.data[0]), culong(data.len))
    if rc!=0:
      return err[Blob](feIoError, "decompress failed", $rc)
    dest.setLen(destLen)
    ok(newBlob(dest))
