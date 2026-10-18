# Fossil to Nim - Full Porting Plan

## Scope

Port **only Fossil core**, not SQLite, zlib, OpenSSL. These remain C libraries linked via Nim's `importc`.

Original Fossil codebase:
- ~180 C files, ~200k LOC without SQLite, ~800k with SQLite amalgamation
- Plus TH1 (mini Tcl), Markdown, etc.

We port in phases.

## Phase 1: Foundation (Done - scaffold)

- [x] `types.nim` - Blob, Rid, Uuid, Result
- [x] `config.nim` - global config, env
- [x] `storage/backend.nim` - concept interface
- [x] `storage/sqlite_backend.nim` - reference backend
- [x] `storage/libmdbx/lmdb/cdb` - alternative backends
- [x] `delta/delta.nim` - delta format
- [x] `artifact/manifest.nim` - manifest parsing
- [x] `utils/hash.nim` - SHA3/SHA1
- [x] `cli/main.nim` - CLI dispatcher
- [x] `mcp/*` - MCP server
- [x] `api/rest.nim` - REST API
- [x] Docs

## Phase 2: VCS Core (In Progress)

Need to port:

- `checkout.nim` - currently stub, need to implement:
  - Read checkout DB (vvar table)
  - Materialize files from delta chain
  - Handle exec bits, symlinks
  - Original C: `checkout.c` ~3000 LOC

- `commit.nim` - partial, need:
  - Scan working tree, build manifest
  - Compute delta vs parent
  - Insert into storage
  - Original: `commit.c` ~2500 LOC

- `branch.nim` - done basic, need full tag handling

- `timeline.nim` - done basic, need event table query

- `diff.nim` - done simple LCS, need Myers algorithm like original `diff.c`

- `merge.nim` - done 3-way stub, need full merge with conflict markers like original

- `stash.nim` - TODO

- `blame.nim` - TODO: annotate

- `clean.nim`, `add.nim`, `rm.nim` - TODO

## Phase 3: Sync Protocol

- `sync/protocol.nim` - Fossil sync protocol
  - Original: `xfer.c`, `http.c`, `http_transport.c` ~5000 LOC
  - Need to implement card parsing: `cookie`, `file`, `gimme`, `igot`, etc.
  - HTTP client/server

- `sync/http.nim` - transport

## Phase 4: Web UI

- `web/server.nim` - basic HTTP server done
- `web/router.nim` - TODO: map all Fossil pages
- `web/pages/timeline.nim`, `info.nim`, `wiki.nim`, `ticket.nim`, etc.
- `web/th1.nim` - TH1 interpreter port (mini Tcl) - 2000 LOC C -> Nim
- `web/markdown.nim` - Markdown renderer

Original Fossil has ~50 web pages, each ~500 LOC C that generates HTML via `cgi_printf`.

In Nim port, we generate HTML via DSL, not via C printf.

## Phase 5: Subsystems

- `wiki/wiki.nim` - basic done, need full
- `ticket/ticket.nim` - basic done, need TH1 ticket format parsing
- `forum/forum.nim` - TODO: forum is recent Fossil feature, uses markdown + threads
- `chat/chat.nim` - TODO

## Phase 6: Storage Backend Hardening

- Implement cursor iteration for libmdbx/lmdb (currently `getAllRids` returns empty)
- Implement proper CDB writer with hash tables (currently stub)
- Write migration tool `rebuild` that converts sqlite -> libmdbx etc.
- Benchmark suite

## Phase 7: QBE / cproc

- Done: `qbe_nimbase.h` shim
- Done: `config.nims` with qbeCompat flags
- Done: `Makefile` qbe target
- TODO: actually test with cproc, fix generated C issues (remove attributes via sed is done, but need to verify)
- TODO: vendor sqlite3.c and mdbx.c that are cproc-clean

## Phase 8: API & MCP Hardening

- API: implement OpenAPI spec, auth, pagination
- MCP: implement all tool handlers with real logic (currently many return dummy)
- MCP: add resources for file content, wiki, tickets
- MCP: add prompts for commit message generation etc.

## Phase 9: Testing

- `tests/test_delta.nim` - roundtrip vs original fossil binary (need to have fossil binary)
- `tests/test_manifest.nim` - parse all manifests from fossil repo
- `tests/test_storage.nim` - same workload on all backends
- `tests/test_sync.nim` - sync two repos
- `tests/test_mcp.nim` - JSON-RPC compliance

## Phase 10: Documentation & Release

- Complete English + Russian docs
- Write migration guide from C fossil to Nim fossil
- Performance comparison
- Release binary

## Code Style for QBE Compatibility

- No exceptions in hot path, use `Result`
- No closure iterators, use `seq` or inline iterators
- No `async` in core VCS, only in web/api/mcp servers
- Use `{.push stackTrace: off.}` in hot modules when `qbeCompat`
- Avoid `std/re` (uses PCRE), use `parseutils` or simple string ops
- Avoid `std/json` in core? It's okay, but for QBE we use minimal json parser

## C Interop Strategy

All C libs wrapped in `db/c_interop.nim` or per-backend:

```nim
{.push header: "<sqlite3.h>".}
type sqlite3 {.importc, incompleteStruct.} = object
proc sqlite3_open(...) {.importc.}
{.pop.}
```

For vendored:

```nim
{.compile: "cinterop/sqlite/sqlite3.c".}
```

This compiles C file together with Nim-generated C, so cproc sees one big C file.

## Nimble Tasks

- `nimble build` - normal
- `nimble buildQbe` - generate C only
- `nimble mcp` - build MCP standalone
- `nimble test` - run tests

## Estimated LOC

- Original Fossil core (without SQLite): ~200k C
- Nim port: estimated ~40k Nim (Nim more expressive)
  - types/config: 1k
  - storage: 5k
  - delta: 1k
  - artifact: 3k
  - vcs: 10k
  - sync: 5k
  - web: 10k
  - wiki/ticket/forum: 5k
  - api/mcp/cli: 5k

Currently scaffold is ~5k Nim, need ~35k more.

## How to Contribute

1. Pick a module from Phase 2-5
2. Read original C file from https://fossil-scm.org/home/file?ci=trunk&name=src/<module>.c
3. Port to Nim, keeping same algorithm but using Nim idioms + Result
4. Write test in `tests/`
5. Ensure `nim c -d:qbeCompat --compileOnly` still works (no GCC attributes)

## References

- Fossil docs: https://fossil-scm.org/home/doc/trunk/www/fileformat.wiki
- Fossil delta format: https://fossil-scm.org/home/doc/trunk/www/delta_format.wiki
- LMDB docs: https://lmdb.readthedocs.io/
- libmdbx docs: https://libmdbx.dqdkfa.ru/
- CDB spec: https://cr.yp.to/cdb/cdb.txt
- QBE: https://c9x.me/compile/
- cproc: https://git.sr.ht/~mcf/cproc
- MCP spec: https://spec.modelcontextprotocol.io/
