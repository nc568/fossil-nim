## Global configuration for Fossil Nim
import std/[os, tables, strutils]
import ./types

type
  StorageKind* = enum
    skSqlite = "sqlite"
    skLibMdbx = "libmdbx"
    skLmdb = "lmdb"
    skCdb = "cdb"
    skHybridCdb = "hybrid-cdb"
    skHybridLmdb = "hybrid-lmdb"
    skHybridMdbx = "hybrid-mdbx"

  FossilConfig* = object
    repoPath*: string
    checkoutPath*: string
    storageKind*: StorageKind
    verbose*: int
    jsonOutput*: bool
    mcpEnabled*: bool
    apiEnabled*: bool
    apiPort*: int
    apiBind*: string
    userName*: string
    userContact*: string
    ignoreGlob*: seq[string]
    sqliteFlags*: seq[string]
    mdbxMapSize*: int64
    lmdbMapSize*: int64
    qbeCompat*: bool

var gConfig* = FossilConfig(
  storageKind: skSqlite,
  verbose: 0,
  apiPort: 8080,
  apiBind: "127.0.0.1",
  mdbxMapSize: 1024*1024*1024, # 1GB
  lmdbMapSize: 1024*1024*1024,
  qbeCompat: defined(qbeCompat)
)

proc defaultConfig*(): FossilConfig = gConfig

proc loadConfigFromEnv*(): FossilConfig {.gcsafe.} =
  var cfg = FossilConfig(
    storageKind: skSqlite,
    verbose: 0,
    apiPort: 8080,
    apiBind: "127.0.0.1",
    mdbxMapSize: 1024*1024*1024,
    lmdbMapSize: 1024*1024*1024,
    qbeCompat: defined(qbeCompat)
  )
  try:
    if existsEnv("FOSSIL_REPO"): cfg.repoPath = getEnv("FOSSIL_REPO")
    if existsEnv("FOSSIL_STORAGE"):
      case getEnv("FOSSIL_STORAGE").toLowerAscii()
      of "sqlite": cfg.storageKind = skSqlite
      of "libmdbx", "mdbx": cfg.storageKind = skLibMdbx
      of "lmdb": cfg.storageKind = skLmdb
      of "cdb": cfg.storageKind = skCdb
      of "hybrid-cdb", "hybrid": cfg.storageKind = skHybridCdb
      of "hybrid-lmdb": cfg.storageKind = skHybridLmdb
      of "hybrid-mdbx", "hybrid-libmdbx": cfg.storageKind = skHybridMdbx
      else: discard
  except:
    discard
  cfg

proc repoPath*(cfg: FossilConfig): string =
  if cfg.repoPath.len > 0: cfg.repoPath
  else:
    # search upwards for *.fossil or _FOSSIL_
    var dir = getCurrentDir()
    while true:
      for kind, path in walkDir(dir):
        if kind == pcFile and path.endsWith(".fossil"):
          return path
      let f = dir / "_FOSSIL_"
      if fileExists(f): return f
      let parent = parentDir(dir)
      if parent == dir: break
      dir = parent
    ""

proc isRepoValid*(path: string): bool =
  if path.len == 0: return false
  if dirExists(path): return false # repo is file
  fileExists(path)

proc detectStorageKind*(path: string): FossilResult[StorageKind] =
  ## Try to detect backend by file header
  if not fileExists(path):
    return err[StorageKind](feNotFound, "repo not found", path)
  try:
    let f = open(path, fmRead)
    defer: f.close()
    var header: array[64, char]
    let n = f.readChars(header, 0, 64)
    let s = cast[string](header[0..<n])
    if "SQLite format" in s:
      return ok(skSqlite)
    elif "MDBX" in s or "LMDB" in s:
      # rough detection - check if directory
      return ok(skLibMdbx)
    else:
      # default to sqlite for compat
      return ok(skSqlite)
  except:
    return err[StorageKind](feIoError, "cannot read repo header", getCurrentExceptionMsg())

