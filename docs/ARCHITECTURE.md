# Architecture - Fossil Nim Port

## 1. Philosophy

Original Fossil is an amalgamation build: ~180 C files concatenated into one `fossil.c` (~800k LOC with SQLite). This gives simplicity but hurts modularity, testability, and IDE support.

**Nim port goals:**
1. **Modularity**: each subsystem is an independent Nim module with clear interface
2. **C interop, not rewrite**: keep proven C libs (SQLite, zlib, OpenSSL) as `importc`
3. **Pluggable storage**: abstract `StorageBackend` concept, not hardcoded SQLite
4. **API first**: CLI is a thin wrapper over `fossil/api` library
5. **MCP first**: AI agents can operate Fossil via structured tools
6. **QBE/cproc friendly**: generated C must be portable

## 2. Layered Architecture

```
+---------------------------+
|  CLI (src/fossil/cli)     |  <- user entry
+---------------------------+
|  API (REST + JSON)        |  <- http, scripting
+---------------------------+
|  MCP (Model Context)      |  <- AI agents
+---------------------------+
|  VCS Core                 |
|  - checkout, commit,      |
|    branch, merge, diff,   |
|    stash, blame, timeline |
+---------------------------+
|  Sync                     |
|  - protocol (xfer cards), |
|    http transport,        |
|    clone/push/pull        |
+---------------------------+
|  Artifact / Manifest      |
|  - hash, parse, delta     |
+---------------------------+
|  Storage Abstraction      |
|  backend.nim concept      |
+---------------------------+
|  DB / C Interop           |
|  sqlite3, mdbx, lmdb, cdb |
+---------------------------+
```

### Dependency rule: upper layers may import lower, never reverse.

## 3. Core Types (`types.nim`)

```nim
Rid = distinct int64        # Record ID, DB rowid
Uuid = distinct string      # SHA3-256 hex, 64 chars, or SHA1 40 chars for compat
Blob = object               # Fossil Blob: data + size, refcounted
ArtifactType = enum         # manifest, cluster, wiki, ticket, etc.
Delta = object              # copy/insert ops
```

- `Blob` is wrapper over `string` with explicit length, mimics original `Blob` but safe.
- All DB interactions return `Result[T, FossilError]` (using `std/options` + custom error).

## 4. Storage Abstraction

```nim
type StorageBackend* = concept b
  b.open(path: string): Result[void, FossilError]
  b.close()
  b.getArtifact(uuid: Uuid): Result[Blob, FossilError]
  b.putArtifact(uuid: Uuid, data: Blob): Result[Rid, FossilError]
  b.hasArtifact(uuid: Uuid): bool
  b.getManifest(rid: Rid): Result[Manifest, FossilError]
  b.deltaChain(rid: Rid): seq[Rid]
```

- `sqlite_backend`: implements original schema: tables `blob`, `delta`, `event`, `tag`, etc.
- `libmdbx_backend`: 2 DBIs: `artifacts` (uuid->blob), `meta` (rid->flags), `links` (parent->child). Uses libmdbx's append + GC.
- `lmdb_backend`: similar but single writer.
- `cdb_backend`: read-only, for `fossil export --cdb` to serve static clones via HTTP.

Migration path: `fossil rebuild --backend libmdbx` reads from sqlite and writes to mdbx.

## 5. Delta

Fossil delta format: sequence of operations:
- `len@off` - copy `len` bytes from source at `off`
- `len:literal` - insert literal

Implemented in `delta.nim` with 100% compat with original `delta.c`. Includes `deltaCreate`, `deltaApply`, `deltaOutputSize`.

We keep algorithm identical for interoperability.

## 6. Artifact / Manifest

Manifest is text format:

```
C comment...
D 2024-12-01T12:00:00.000
F file hash perm
...
M uuid
P parent...
R sha3...
Z checksum
```

Parser in `artifact/manifest.nim` is hand-written, zero-copy where possible, uses Nim's `parseutils`.

Hashing: SHA3-256 (primary) + SHA1 (legacy). Wrapper over OpenSSL or nimcrypto, but for QBE we use embedded C implementation `sh3.c` via importc.

## 7. VCS Core

Each VCS operation is a module with function `run*` returning Result.

Example `checkout.nim`:
- reads `vvar` table (checkout db)
- materializes files via delta chain
- handles symlinks, exec bits

`commit.nim`:
- scans working tree
- builds manifest
- computes delta vs parent
- inserts into storage

All VCS functions are pure library functions, CLI just parses args and calls them. This enables API/MCP reuse.

## 8. Sync Protocol

Fossil sync is HTTP POST with custom framing:
- client sends list of artifacts it has
- server sends missing artifacts as `xfer` cards
- same reverse

Implemented in `sync/protocol.nim` as state machine, transport pluggable (http, ssh).

## 9. Web Server

We don't use Jester. We use `std/asynchttpserver` wrapped to match Fossil's own HTTP semantics (CGI-like). Router maps `/timeline`, `/info`, `/wiki`, `/api/v1/*`.

Pages are `nim` procs generating HTML via `karax`-like DSL but we use simple `htmlgen` to avoid heavy deps and keep QBE compat.

## 10. API & MCP

- `api/rest.nim`: defines OpenAPI-like routes, returns JSON. Auth via bearer or cookie.
- `api/json_api.nim`: legacy `/json` endpoint compat.

- `mcp/server.nim`: JSON-RPC 2.0 over stdio (MCP spec). Handles `initialize`, `tools/list`, `tools/call`, `resources/list`, `resources/read`.
- `mcp/tools.nim`: defines all tools with JSON Schema input.

MCP design ensures AI agents can do full Fossil workflow without parsing CLI text.

## 11. C Interop

All C headers wrapped in `db/c_interop.nim`:

```nim
{.push header: "<sqlite3.h>".}
type sqlite3 {.importc: "sqlite3", incompleteStruct.} = object
proc sqlite3_open(...) {.importc.}
{.pop.}
```

For libmdbx/lmdb we vendor minimal headers in `cinterop/include/` to avoid system dep.

Zlib: use Nim's `zippy` or `importc` zlib.

## 12. QBE / cproc Compatibility

Nim's C backend generates code that normally uses:
- `__attribute__((...))`
- `__builtin_frame_address`
- computed goto for exception handling

With `-d:qbeCompat` we:
- Define `NIM_NO_ATTRIBUTE`, `NIM_NO_BUILTIN`
- Force `nimOldCaseObjects` off, use `--exceptions:goto`? No, we use `--exceptions:quirky` which uses setjmp but we replace with `setjmp` shim? Actually for QBE we use `--exceptions:goto` is not supported, so we use `--panics:on` + `Result` types, no exceptions in hot path.
- Provide custom `nimbase.h` that maps `NIM_INTBITS` etc to plain C11.
- Avoid `alloca` by `-d:nimNoAlloca`.

Final C files in `build/cgen` are compiled by cproc:
```
cproc -std=c11 -D_XOPEN_SOURCE=700 -Ibuild/cgen -I cinterop/include -o fossil ...
```

## 13. Build System

- `nimble build` - normal
- `nimble buildQbe` - generates C only
- `Makefile` - wraps both, plus `make qbe` runs cproc

## 14. Testing Strategy

- `tests/test_delta.nim` - roundtrip vs original fossil binary
- `tests/test_manifest.nim` - parse all manifests from fossil repo itself
- `tests/test_storage.nim` - same workload on all backends, compare
- `tests/test_mcp.nim` - JSON-RPC compliance

## 15. Search & Archive

### Search (`src/fossil/search/search.nim`)
- FTS5 virtual table `search_fts USING fts5(id, kind, title, content, tokenize='porter unicode61')` + regular `search_index` for fallback LIKE and mtime
- `indexDocumentSqlite` does DELETE FROM search_fts before INSERT to avoid FTS5 duplicate (FTS5 has no UNIQUE on id, PK is rowid)
- Auto-index hooks in all write paths: commit (commit+files), wiki, ticket, forum thread+post, chat, git import
- CLI `fossil search <query> [--limit]` and `fossil search --reindex` (calls reindexAll: files 500 + commits 1000 + branches + wiki tags)
- REST `/api/v1/search?q=` + web `/search?q=`, MCP tool `search`
- Tested 2026-10-17: commit auto-index, reindex dedup, wiki/ticket/forum/chat via API

### Archive (`src/fossil/vcs/archive.nim`)
- Real ZIP (STORE method, no compression, avoids zlib dep) and TAR (USTAR) generation
- CRC32 table 256 entries, toLittleEndian16/32, dosTimeDate
- ZIP: local header 0x04034b50 + central dir 0x02014b50 + EOCD 0x06054b50, offset tracking
- TAR: 512-byte header, octal fields, checksum with spaces, 2 zero blocks
- `createArchiveFromRepo` via listFilesSqlite(10000) filtered by path + getFileContentSqlite
- CLI `fossil zip/tarball/archive --branch --path --output --format`, auto-detect .zip/.tar.gz
- REST `/zip` and `/tarball` return real binary Content-Type application/zip/x-tar + Content-Disposition attachment
- Tested: 3 files -> 373 bytes ZIP valid zipfile, 4096 bytes TAR valid tarfile, path filter ?path=src

## 16. Future

- Replace Tcl/Tk parts? Fossil uses TH1 (mini Tcl). We port TH1 to Nim as `web/th1.nim` interpreter.
- WASM build for browser checkout? Nim -> JS possible.
- Incremental migration: ability to open original `.fossil` files read-only via sqlite backend, then `rebuild` to new backend.
- Search: trigram index, diff content, filters (branch/user/date), cleanup on delete, incremental watcher, autocomplete, header live results
- Archive: DEFLATE compression option, tar.gz, incremental archive

