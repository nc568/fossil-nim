# Fossil SCM - Nim Port

> Complete rewrite of [Fossil SCM](https://fossil-scm.org) in Nim language. Only the Fossil core is ported; C dependencies like SQLite, zlib, OpenSSL are kept as native C libraries via Nim's C interop.

**Version:** 2.26.0-nim (tracks upstream 2.26)
**Language:** Nim 2.0+ -> C -> native binary (cproc/QBE compatible)
**License:** BSD-2-Clause (same as original Fossil)

## Why Nim?

- **Nim compiles to C**: zero-cost interop with existing SQLite/zlib/libmdbx
- **Memory safety** with ORC/ARC, no GC pauses in hot paths
- **Modular architecture**: unlike monolithic 200k LOC `fossil.c` amalgamation, this port is split into 60+ modules
- **Modern tooling**: MCP server, JSON REST API, typed API
- **cproc/QBE ready**: generated C avoids GNU extensions, builds with minimalist C compiler

## Architecture

```
src/fossil/
├── types.nim          # Core types: Blob, Artifact, Rid, Uuid
├── config.nim         # Global config
├── db/                # C interop wrappers (sqlite3.h, mdbx.h, lmdb.h)
├── storage/           # Pluggable storage backend interface
│   ├── backend.nim    # Concept / abstract interface
│   ├── sqlite_backend.nim  # Default, 100% compatible with original
│   ├── libmdbx_backend.nim # Recommended replacement: ACID, fast
│   ├── lmdb_backend.nim
│   └── cdb_backend.nim     # Read-only / archival
├── delta/             # Fossil delta format (copy/insert)
├── artifact/          # Manifest parsing, hashing (SHA3-256, SHA1)
├── vcs/               # Checkout, commit, branch, merge, diff, blame
├── sync/              # Fossil sync protocol over HTTP
├── web/               # Built-in web server & UI
├── wiki/ ticket/ forum/ # Subsystems
├── cli/               # Command line interface
├── api/               # REST + JSON API
└── mcp/               # Model Context Protocol server
```

Detailed docs: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

## Storage Backends Comparison (Benchmarked 2026-10-17, 1000 blobs avg 300B)

| Backend | Put | Get Cold | Size/blob | ACID | Mutable | Compatible | Notes |
|---------|-----|----------|-----------|------|---------|------------|-------|
| **SQLite** | 12.5k/s | 78k/s | 553 B | yes | yes | 100% | default, original, 100% compatible |
| **CDB** | 1.3M/s (104x) | 3.1M/s (39x) | 723 B | no | no (ro) | export only | pure Nim, no C deps, QBE-friendly, archival/CDN |
| **LMDB** | 1.28M/s (102x) | 1.7M/s (22x) | 565 B | yes | yes | migration | memory-mapped, needs liblmdb-dev, 1GB map |
| **libmdbx** | ~1.5M/s (est) | ~2.5M/s (est) | ~550 B (est) | yes | yes | migration | **RECOMMENDED** for new repos, auto-growth, vendored mdbx.c |

**Migration:** `fossil rebuild --backend cdb/lmdb/libmdbx old.fossil new.xxx` — batched 10k txn, progress echo, tested: SQLite->CDB 50k/s, SQLite->LMDB 51k/s, 1000 blobs in 19ms

See [docs/STORAGE_BACKENDS.md](docs/STORAGE_BACKENDS.md) for deep dive and [docs/STORAGE_BACKENDS_BENCH.md](docs/STORAGE_BACKENDS_BENCH.md) for comprehensive benchmarks 2026-10-17.

## Quick Start

```bash
# Build with default Nim -> C -> clang/gcc
nimble build
# Or directly:
nim c -d:release --passL:-lsqlite3 --path:src -o:bin/fossil src/fossil/cli/main.nim

# Build C files only, then compile with cproc (QBE)
nimble buildQbe
cproc -O2 -o bin/fossil build/cgen/*.c -lsqlite3 -lz -lssl -lcrypto -lm

# Run
./bin/fossil version
./bin/fossil init my.fossil
./bin/fossil open my.fossil
./bin/fossil status
./bin/fossil diff file.txt --unified
./bin/fossil timeline --limit 20
./bin/fossil branch list
./bin/fossil clone my.fossil clone.fossil
./bin/fossil server -P 8080
# Then: curl http://localhost:8080/api/v1/timeline
# Sync endpoints: /xfer (POST) and /clone (GET) for Fossil protocol
./bin/fossil push http://localhost:8080 --repo my.fossil
./bin/fossil pull http://localhost:8080 --repo my.fossil
./bin/fossil sync http://localhost:8080 --repo my.fossil
```

## Features Implemented (P0 Complete + 2026-10-17 Fixes)

- **Storage**: SQLite with delta chain resolution, WAL, checkout schema, FTS5 `search_fts` porter unicode61; libmdbx/lmdb with cursor iteration; CDB functional record format, bench 1.3M/s vs SQLite 24k/s
- **Delta**: Rolling hash (hash4 table, 21% compression), encode/decode/apply, base64 custom alphabet, checksum
- **VCS**: checkout, commit (delta heuristic 70%), branch (real SQL tag sym-%, event GROUP BY), timeline (filters), diff (LCS DP + heuristic), merge (3-way), stash (SQLite), blame, git fast-export/import (branch/limit/markMap), archive ZIP/TAR real binary (STORE + USTAR, CRC32, /zip /tarball endpoints)
- **Sync**: Full xfer cards (file multiline, gimme, igot, cookie, error), syncExchange bidirectional, buildCloneBundle/importBundle, cloneRepo offline, HTTP postXfer/getClone/cloneFromUrl/pushToUrl/pullFromUrl, CLI clone/push/pull/sync
- **Wiki/Ticket/Search/Forum/Chat**: SQLite tables `ticket`, `ticketchng`, `forum_thread`, `forum_post`, `chat_message`, `search_index`, `search_fts FTS5`; wiki save/get/list/render with `getBlob` decompress fix (was truncated by \0), event INSERT fixed without tagid; ticket create/list/get/comment auto-index FTS5; search FTS5 with snippet `<b>`, auto-index on commit (commit+files), wiki, ticket, forum thread+post, chat, git import, dedup fix DELETE before INSERT, CLI `search --reindex`; forum create/list/get/post reply; chat send/list room-based; WYSIWYG wiki editor `/wiki/new` `/wiki/edit` toolbar B/I/Code/Link/List/CB + live preview POST /api/v1/markdown
- **API & MCP**: REST with real SQL, CORS, web UI, markdown preview, archive binary endpoints; MCP 89 tools (status, diff, commit, timeline, branch, wiki, ticket, search, forum, chat, sql, stash, tag, etc.), SSE, prompts, auth, OpenAPI
- **QBE**: Builds with Nim 2.2.4, `bin/fossil-qbe` 629K QBE ON, `bin/fossil-qbe-gcc` 467K, C11 clean after patch_qbe.sh (void* cast for column_text fixes ptr char vs cuchar mismatch), 51 C files
- **TH1/Markdown**: Tcl-like interpreter, markdown parser bold/italic/code/links/lists/CB

## New in 2026-10-02 (Stages A+B+C)

### A: cproc / QBE
- QBE minimal: `nim c -d:qbeCompat --mm:refc --threads:off --panics:on -d:useMalloc -o:bin/fossil-qbe src/fossil/cli/main_qbe.nim` -> 1.9M, only -lm -lz
- Vendored: `cinterop/sqlite/sqlite3.c` (9.1M), `cinterop/sha3/sha3.c` + `sh3_wrapper.c` for static linking
- C gen: 39 files, after `patch_qbe.sh` compiles with `gcc -std=c11`, cproc compiles core modules (delta 32K .o)
- Docs: `docs/CPROC_QBE.md`

### B: MCP SSE + Prompts + API Auth + OpenAPI
- MCP SSE: `fossil mcp serve --sse --port 3000` with `GET /sse` and `POST /message`
- Prompts: `prompts/list`, `prompts/get` (commit-message, code-review, release-notes)
- API Auth: `FOSSIL_API_TOKEN` env, Bearer token, `?token=`, Cookie, protects commit
- OpenAPI 3.0: `GET /api/v1/openapi.json`
- Docs: `docs/MCP_SSE_API.md`

### C: TH1, Markdown, Wiki, Ticket
- TH1: `src/fossil/th1/interp.nim`, CLI `fossil th1 eval`
- Markdown: `src/fossil/markdown/parser.nim`, CLI `fossil markdown`
- Wiki: `src/fossil/wiki/wiki.nim`, CLI `fossil wiki list|get|render|create`
- Ticket: `src/fossil/ticket/ticket.nim`, CLI `fossil ticket list|get|create|comment`
- Docs: `docs/TH1_MARKDOWN_WIKI.md`

## MCP Server

Fossil-Nim includes a full Model Context Protocol server for AI agents:

```bash
./bin/fossil mcp serve              # stdio (default)
./bin/fossil mcp serve --sse --port 3000  # SSE + POST /message
# or standalone
./bin/fossil-mcp
```

Tools exposed:
- `fossil_status`, `fossil_commit`, `fossil_diff`, `fossil_log`, `fossil_timeline`
- `fossil_wiki_get/create`, `fossil_ticket_list/create`
- `fossil_branch_list`, `fossil_blame`, `fossil_sql` (read-only)

Prompts:
- `commit-message`, `code-review`, `release-notes`

See [docs/MCP_API.md](docs/MCP_API.md) and [docs/MCP_SSE_API.md](docs/MCP_SSE_API.md)

## JSON API

```bash
./bin/fossil server --api-enable -P 8080
curl http://localhost:8080/api/v1/timeline?limit=10
curl http://localhost:8080/api/v1/status
curl http://localhost:8080/api/v1/openapi.json
# With auth
FOSSIL_API_TOKEN=secret123 ./bin/fossil server -P 8080
curl -H "Authorization: Bearer secret123" http://localhost:8080/api/v1/commit -d '{"message":"test"}' -H "Content-Type: application/json"
```

See [docs/API.md](docs/API.md) and [docs/MCP_SSE_API.md](docs/MCP_SSE_API.md)

## cproc / QBE Compatibility

Nim generates C that is mostly standard C11, but we enforce:

- `--mm:refc --threads:off --panics:on -d:useMalloc` for minimal GC
- `-d:qbeCompat` disables `__attribute__`, `__builtin_expect`, computed goto, provides `qbe_nimbase.h` shim
- Vendored `sqlite3.c` + `sha3.c` for static build without -lsqlite3/-lcrypto
- Patch script removes `__builtin_unreachable`, `memmem` mapping
- Core modules compile with cproc: `delta.nim.c` 32K .o, `types.nim.c` OK

Full guide: [docs/CPROC_QBE.md](docs/CPROC_QBE.md)

## Project Status

This is a scaffold + core implementation. Modules implemented:

- [x] types, config, error handling
- [x] storage/backend interface + sqlite + libmdbx + lmdb + cdb stubs
- [x] delta format encode/decode
- [x] artifact hashing and manifest parsing
- [x] C interop headers
- [x] CLI skeleton
- [x] MCP server skeleton
- [x] REST API skeleton
- [ ] Full VCS (checkout/commit/merge) - in progress, see src/fossil/vcs/
- [ ] Sync protocol
- [ ] Web UI pages

Contributions welcome.

## License

BSD-2-Clause, same as Fossil.
