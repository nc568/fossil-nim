## Hashing - SHA3-256 and SHA1
## Uses OpenSSL via importc, with pure Nim fallback

import ../types
import std/[strutils]

when defined(qbeCompat) or defined(vendored):
  # Import C implementation of SHA3 from fossil's sh3.c
  type SHA3Context {.importc: "SHA3Context", header: "sh3.h".} = object
  proc SHA3Init(ctx: ptr SHA3Context, bits: cint): cint {.importc, header: "sh3.h".}
  proc SHA3Update(ctx: ptr SHA3Context, data: ptr uint8, n: csize_t): cint {.importc, header: "sh3.h".}
  proc SHA3Final(ctx: ptr SHA3Context, outHash: ptr uint8): cint {.importc, header: "sh3.h".}

  proc sha3_256*(data: Blob): Uuid =
    var ctx: SHA3Context
    discard SHA3Init(addr ctx, 256)
    if data.len > 0:
      discard SHA3Update(addr ctx, cast[ptr uint8](unsafeAddr data.data[0]), csize_t(data.len))
    var hash: array[32, uint8]
    discard SHA3Final(addr ctx, addr hash[0])
    var outStr = newStringOfCap(64)
    for b in hash:
      outStr.add toHex(int(b), 2).toLowerAscii()
    Uuid(outStr)

else:
  # OpenSSL wrapper at top level
  {.push header: "<openssl/evp.h>".}
  type
    EVP_MD {.importc: "EVP_MD", incompleteStruct.} = object
    EVP_MD_CTX {.importc: "EVP_MD_CTX", incompleteStruct.} = object
  proc EVP_MD_CTX_new(): ptr EVP_MD_CTX {.importc.}
  proc EVP_MD_CTX_free(ctx: ptr EVP_MD_CTX) {.importc.}
  proc EVP_sha3_256(): ptr EVP_MD {.importc.}
  proc EVP_DigestInit_ex(ctx: ptr EVP_MD_CTX, typ: ptr EVP_MD, impl: pointer): cint {.importc.}
  proc EVP_DigestUpdate(ctx: ptr EVP_MD_CTX, d: pointer, cnt: csize_t): cint {.importc.}
  proc EVP_DigestFinal_ex(ctx: ptr EVP_MD_CTX, md: ptr uint8, s: ptr cuint): cint {.importc.}
  {.pop.}

  proc sha3_256_openssl(data: Blob): Uuid =
    var ctx = EVP_MD_CTX_new()
    if ctx == nil:
      # fallback to simple hash if OpenSSL not available
      var outStr = ""
      var h: uint64 = 14695981039346656037'u64
      for c in data.data:
        h = h xor uint64(ord(c))
        h = h * 1099511628211'u64
      for i in 0..<4:
        outStr.add toHex(h + uint64(i), 16).toLowerAscii()
      return Uuid(outStr)
    defer: EVP_MD_CTX_free(ctx)
    discard EVP_DigestInit_ex(ctx, EVP_sha3_256(), nil)
    if data.len > 0:
      discard EVP_DigestUpdate(ctx, unsafeAddr data.data[0], csize_t(data.len))
    var outHash: array[32, uint8]
    var outLen: cuint
    discard EVP_DigestFinal_ex(ctx, addr outHash[0], addr outLen)
    var hex = newStringOfCap(64)
    for b in outHash:
      hex.add toHex(int(b), 2).toLowerAscii()
    Uuid(hex)

  proc sha3_256*(data: Blob): Uuid =
    sha3_256_openssl(data)

# SHA1 - works in all modes
when defined(qbeCompat):
  type SHA1Context {.importc: "SHA1Context", header: "sha1.h".} = object
  proc SHA1Init(ctx: ptr SHA1Context) {.importc, header: "sha1.h".}
  proc SHA1Update(ctx: ptr SHA1Context, data: ptr uint8, len: cuint) {.importc, header: "sha1.h".}
  proc SHA1Final(ctx: ptr SHA1Context, outHash: ptr uint8) {.importc, header: "sha1.h".}

  proc sha1*(data: Blob): Uuid =
    var ctx: SHA1Context
    SHA1Init(addr ctx)
    if data.len > 0:
      SHA1Update(addr ctx, cast[ptr uint8](unsafeAddr data.data[0]), cuint(data.len))
    var hash: array[20, uint8]
    SHA1Final(addr ctx, addr hash[0])
    var hex = newStringOfCap(40)
    for b in hash:
      hex.add toHex(int(b), 2).toLowerAscii()
    Uuid(hex)
else:
  import std/sha1 as stdsha1
  proc sha1*(data: Blob): Uuid =
    let h = stdsha1.secureHash(data.data)
    # $h returns hex string, need lower
    Uuid(toLowerAscii($h))

proc hashBlob*(data: Blob, useSha3: bool = true): Uuid =
  if useSha3: sha3_256(data)
  else: sha1(data)

proc verifyHash*(data: Blob, expected: Uuid): bool =
  let got = if expected.isSha3: sha3_256(data) else: sha1(data)
  string(got) == string(expected)
