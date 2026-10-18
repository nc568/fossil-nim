## Core types for Fossil Nim port
## Mirrors fossil's Blob, concepts, but memory safe

import std/[options, strutils, hashes]

type
  Rid* = distinct int64
    ## Record ID - rowid in storage. 0 means invalid.

  Uuid* = distinct string
    ## SHA3-256 hex (64 chars) or SHA1 hex (40 chars) for legacy compat
    ## Always lowercase

  ArtifactType* = enum
    atInvalid = 0
    atManifest = 1      # checkin manifest
    atCluster = 2       # cluster (compressed group)
    atWiki = 3
    atTicket = 4
    atAttachment = 5
    atControl = 6       # tag, etc
    atFile = 7          # file content
    atDelta = 8         # delta manifest

  Blob* = object
    ## Safe wrapper over string, mimics Fossil Blob but immutable-ish
    ## In original C, Blob has dynamic buffer with capacity. Here we use string.
    data*: string

  FossilErrorCode* = enum
    feOk = 0
    feNotFound = 1
    feIoError = 2
    feCorrupt = 3
    feDbError = 4
    feHashMismatch = 5
    feDeltaError = 6
    feManifestError = 7
    feNotRepo = 8
    feConflict = 9
    feAuth = 10
    feInvalidArg = 11

  FossilError* = object
    code*: FossilErrorCode
    msg*: string
    details*: string

  FossilResult*[T] = object
    case ok*: bool
    of true:
      value*: T
    of false:
      error*: FossilError

# --- Rid helpers ---

proc `==`*(a, b: Rid): bool {.borrow.}
proc `<`*(a, b: Rid): bool {.borrow.}
proc `<=`*(a, b: Rid): bool {.borrow.}
proc hash*(r: Rid): Hash = hash(int64(r))
proc `$`*(r: Rid): string = $int64(r)
proc isValid*(r: Rid): bool = int64(r) > 0
proc invalidRid*(): Rid = Rid(0)

# --- Uuid helpers ---

proc `==`*(a, b: Uuid): bool {.borrow.}
proc `<`*(a, b: Uuid): bool {.borrow.}
proc hash*(u: Uuid): Hash = hash(string(u))
proc `$`*(u: Uuid): string = string(u)
proc len*(u: Uuid): int = string(u).len
proc isValid*(u: Uuid): bool =
  let s = string(u)
  if s.len != 40 and s.len != 64: return false
  for c in s:
    if c notin {'0'..'9', 'a'..'f', 'A'..'F'}: return false
  true

proc isSha3*(u: Uuid): bool = string(u).len == 64
proc isSha1*(u: Uuid): bool = string(u).len == 40

proc uuidFromHex*(s: string): FossilResult[Uuid] =
  let lower = s.toLowerAscii()
  if lower.len != 40 and lower.len != 64:
    return FossilResult[Uuid](ok: false, error: FossilError(code: feInvalidArg, msg: "invalid uuid length", details: s))
  for c in lower:
    if c notin {'0'..'9', 'a'..'f'}:
      return FossilResult[Uuid](ok: false, error: FossilError(code: feInvalidArg, msg: "invalid uuid hex", details: s))
  FossilResult[Uuid](ok: true, value: Uuid(lower))

# --- Blob helpers ---

proc newBlob*(data: string = ""): Blob = Blob(data: data)
proc newBlob*(data: seq[byte]): Blob = Blob(data: cast[string](data))
proc len*(b: Blob): int = b.data.len
proc isEmpty*(b: Blob): bool = b.data.len == 0
proc `$`*(b: Blob): string = b.data
proc toString*(b: Blob): string = b.data
proc toBytes*(b: Blob): seq[byte] = cast[seq[byte]](b.data)

proc slice*(b: Blob, a, b2: int): Blob = Blob(data: b.data[a..b2])
proc `&`*(a, b: Blob): Blob = Blob(data: a.data & b.data)

# --- Result helpers ---

proc ok*[T](v: T): FossilResult[T] = FossilResult[T](ok: true, value: v)
proc okVoid*(): FossilResult[void] =
  FossilResult[void](ok: true)

proc err*[T](code: FossilErrorCode, msg: string, details: string = ""): FossilResult[T] =
  FossilResult[T](ok: false, error: FossilError(code: code, msg: msg, details: details))

proc errVoid*(code: FossilErrorCode, msg: string, details: string = ""): FossilResult[void] =
  FossilResult[void](ok: false, error: FossilError(code: code, msg: msg, details: details))

proc map*[T, U](r: FossilResult[T], f: proc(x: T): U): FossilResult[U] =
  if r.ok: ok(f(r.value))
  else: FossilResult[U](ok: false, error: r.error)

proc isOk*[T](r: FossilResult[T]): bool = r.ok
proc isErr*[T](r: FossilResult[T]): bool = not r.ok

proc get*[T](r: FossilResult[T]): T =
  if not r.ok: raise newException(ValueError, "get on Err: " & r.error.msg)
  r.value

proc getError*[T](r: FossilResult[T]): FossilError = r.error

# Specialization for void
proc isOk*(r: FossilResult[void]): bool = r.ok
proc isErr*(r: FossilResult[void]): bool = not r.ok

# --- Constants ---

const
  FossilMagic* = "Fossil repo"
  CheckoutDbName* = "_FOSSIL_"
  RepoDbName* = "*.fossil"
  MaxArtifactSize* = 100 * 1024 * 1024 # 100MB
  HashSha3Len* = 64
  HashSha1Len* = 40

when defined(qbeCompat):
  # In QBE compat mode, disable stack traces for smaller C
  {.push stackTrace: off, lineTrace: off.}
