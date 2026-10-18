## C interop central file - all C headers

# SQLite
{.push header: "<sqlite3.h>".}
type
  sqlite3* {.importc: "sqlite3", incompleteStruct.} = object
  sqlite3_stmt* {.importc: "sqlite3_stmt", incompleteStruct.} = object
{.pop.}

# zlib
{.push header: "<zlib.h>".}
type
  z_stream* {.importc: "z_stream".} = object
    next_in*: ptr uint8
    avail_in*: cuint
    total_in*: culong
    next_out*: ptr uint8
    avail_out*: cuint
    total_out*: culong
    msg*: cstring
    state*: pointer
    zalloc*: pointer
    zfree*: pointer
    opaque*: pointer
    data_type*: cint
    adler*: culong
    reserved*: culong

proc compress*(dest: ptr uint8, destLen: ptr culong, source: ptr uint8, sourceLen: culong): cint {.importc: "compress", header: "<zlib.h>".}
proc uncompress*(dest: ptr uint8, destLen: ptr culong, source: ptr uint8, sourceLen: culong): cint {.importc: "uncompress", header: "<zlib.h>".}
{.pop.}

# For qbeCompat, we avoid zlib and use pure Nim zippy?
when defined(qbeCompat):
  # Use vendored miniz?
  discard
