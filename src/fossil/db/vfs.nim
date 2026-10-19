## Storage abstraction — the only place in Foccil DB that is allowed to do I/O.
##
## Why a separate layer:
##   * the engine (`engine.nim`) must stay pure: same code runs in native, JS and
##     wasm, where there is no `open()` at all;
##   * tests can run the *same* schema against memory and against a real file,
##     which is how persistence bugs get caught before they reach a user;
##   * a host that wants to store pages in its own artifact store implements one
##     small interface instead of patching the engine.
##
## Pages are `string`s on purpose. Nim strings are binary-safe byte buffers, so
## no pointer arithmetic and no `addr`/`cast` is needed anywhere in this file —
## the same property the engine is held to.

when not defined(js):
  import std/os
import fossil/db/errors

const
  HasFileVfs* = (not defined(js)) and declared(fileExists)
    ## True when the target has a filesystem at all. `--os:any` targets (the
    ## wasm module, the cproc matrix) have no `std/os` file API, so the file
    ## backend is compiled out there instead of failing to build. The memory
    ## VFS is always available, which is what the engine itself needs.

type
  VfsKind* = enum
    vfsMemory = "memory"
    vfsFile = "file"

  Vfs* = ref object
    ## A paged byte store. Offsets are absolute byte offsets, never page
    ## numbers: the pager owns the page layout, the VFS only moves bytes.
    kind*: VfsKind
    mem: string              ## memory backend (works everywhere, incl. JS/wasm)
    when HasFileVfs:
      f: File                ## file backend (native only)
      path*: string
    isOpen*: bool
    ioReads*: int            ## number of physical reads (energy proxy)
    ioWrites*: int           ## number of physical writes
    syncs*: int              ## number of fsync calls (energy proxy)
    bytesMoved*: int

    # Crash injection, off by default and zero cost when off. Set `crashAt` to a
    # byte count and the store dies once that many bytes have been written: the
    # write that crosses the line is torn (only its head lands) and every later
    # write is dropped, which is what a power cut actually looks like. Reads keep
    # working, because the bytes are still on the platter.
    crashAt*: int
    dead*: bool

proc openMemoryVfs*(): Vfs =
  Vfs(kind: vfsMemory, mem: "", isOpen: true)

proc openFileVfs*(path: string): Vfs =
  ## Creates the file if missing. Truncation is never implicit: an existing
  ## file keeps its contents, because losing a database on open is the kind of
  ## bug that costs users their data.
  ##
  ## Not available in the JS target, where there is no filesystem; a host that
  ## wants persistence in the browser supplies its own VFS implementation.
  when not HasFileVfs:
    fail(unsupported, "this target has no filesystem: use the memory VFS")
  else:
    result = Vfs(kind: vfsFile, path: path, isOpen: true)
    try:
      # `fmReadWrite` maps to "w+" and *truncates*: opening an existing database
      # with it silently wipes the file. Only a missing file may be created.
      if fileExists(path):
        result.f = open(path, fmReadWriteExisting)
      else:
        result.f = open(path, fmReadWrite)
    except CatchableError:
      failf(ioErr, "cannot open $1", path)

proc close*(v: Vfs) =
  if not v.isOpen: return
  when HasFileVfs:
    if v.kind == vfsFile:
      flushFile(v.f)
      v.f.close()
  v.isOpen = false

proc size*(v: Vfs): int =
  if not v.isOpen: return 0
  case v.kind
  of vfsMemory:
    result = v.mem.len
  of vfsFile:
    when HasFileVfs:
      let cur = getFilePos(v.f)
      setFilePos(v.f, 0, fspEnd)
      result = int(getFilePos(v.f))
      setFilePos(v.f, cur, fspSet)

proc readAt*(v: Vfs; off: int; dst: var string; len: int): bool =
  ## Reads exactly `len` bytes at `off`. Returns false instead of raising:
  ## a short read is a normal condition the pager turns into a zero page or a
  ## corruption error, depending on the page.
  if not v.isOpen or off < 0 or len < 0: return false
  if off + len > v.size: return false
  case v.kind
  of vfsMemory:
    dst = v.mem[off ..< off + len]
  of vfsFile:
    when HasFileVfs:
      dst.setLen(len)
      setFilePos(v.f, off, fspSet)
      if readChars(v.f, dst, 0, len) != len: return false
    else:
      return false
  inc v.ioReads
  inc v.bytesMoved, len
  true

proc writeAt*(v: Vfs; off: int; src: string): bool =
  ## Grows the store as needed; a gap is zero-filled, never left as garbage.
  if v.dead and v.crashAt > 0: return false      # the machine is off
  if not v.isOpen or off < 0: return false
  var body = src
  if v.crashAt > 0 and v.bytesMoved + body.len > v.crashAt:
    # Tear this write, then stay dead. Truncating instead of dropping the whole
    # write is the point: a half-written page is exactly what recovery must
    # survive, and a store that only ever loses whole writes tests nothing.
    let room = max(0, v.crashAt - v.bytesMoved)
    body.setLen(min(room, body.len))
    v.dead = true
  case v.kind
  of vfsMemory:
    if off + body.len > v.mem.len:
      let newLen = off + body.len
      let old = v.mem.len
      v.mem.setLen(newLen)
      for i in old ..< newLen: v.mem[i] = '\0'
    for i in 0 ..< body.len: v.mem[off + i] = body[i]
  of vfsFile:
    when HasFileVfs:
      setFilePos(v.f, off, fspSet)
      if body.len > 0:
        if writeChars(v.f, body, 0, body.len) != body.len: return false
    else:
      return false
  inc v.ioWrites
  inc v.bytesMoved, body.len
  true

proc snapshot*(v: Vfs): string =
  ## The bytes as they are on the platter right now. Used by the crash tests to
  ## restart from exactly what survived, not from what the program wanted.
  case v.kind
  of vfsMemory: v.mem
  of vfsFile:
    when HasFileVfs:
      var all = ""
      discard v.readAt(0, all, v.size)
      all
    else: ""

proc reopenFrom*(v: Vfs; bytes: string): Vfs =
  result = openMemoryVfs()
  result.mem = bytes

proc truncate*(v: Vfs; n: int) =
  if not v.isOpen or n < 0: return
  case v.kind
  of vfsMemory:
    if n < v.mem.len: v.mem.setLen(n)
  of vfsFile:
    when HasFileVfs:
      # Portable enough: cut by rewriting the file through a temp copy.
      # Only used by tests and by explicit shrink; never on the hot path.
      var keep = ""
      if n > 0:
        discard v.readAt(0, keep, min(n, v.size))
      v.f.close()
      writeFile(v.path, keep)
      v.f = open(v.path, fmReadWrite)

proc sync*(v: Vfs) =
  ## Make previous writes durable. This is the only call that costs a real
  ## fsync, so the pager calls it once per flush, not once per page.
  if not v.isOpen: return
  when HasFileVfs:
    if v.kind == vfsFile:
      flushFile(v.f)
  inc v.syncs

proc kindName*(v: Vfs): string =
  case v.kind
  of vfsMemory: "memory"
  of vfsFile:
    when HasFileVfs: "file:" & v.path
    else: "file:unavailable"
