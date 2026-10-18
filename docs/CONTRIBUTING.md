# Contributing Guide - Fossil-Nim

## Architecture

```
src/fossil/
├── types.nim          # Core types: Blob, Rid, Uuid, FossilResult
├── config.nim         # Global config, env vars
├── storage/           # Pluggable backends (concept StorageBackend)
│   ├── backend.nim    # Concept definition
│   ├── sqlite_backend.nim  # 100% compatible, default
│   ├── libmdbx_backend.nim # Fast, ACID, small
│   ├── lmdb_backend.nim
│   ├── cdb_backend.nim     # Read-only archival
│   └── schema.nim     # SQL schema
├── delta/             # Fossil delta format (copy/insert, base64, checksum)
├── artifact/manifest.nim # Manifest parser Q,W,Z cards
├── vcs/               # VCS core
│   ├── checkout.nim   # _FOSSIL_ handling, materialize
│   ├── commit.nim     # Scan working tree, delta heuristic 70%
│   ├── diff.nim       # Myers O(N*D) + heuristic fallback
│   ├── timeline.nim   # Event table queries
│   ├── branch.nim     # tag LIKE sym-%
│   ├── merge.nim      # 3-way merge with conflict markers
│   ├── stash.nim, blame.nim, add.nim
│   └── git_export.nim # git fast-export/import
├── sync/              # Sync protocol
│   ├── protocol.nim   # Cards file/gimme/igot/cookie/error, bundle
│   └── http.nim       # HTTP transport
├── wiki/wiki.nim      # Real SQL tag wiki-%, TH1+Markdown, FTS auto-index
├── ticket/ticket.nim  # Real SQL ticket table, FTS auto-index
├── forum/forum.nim    # Real SQLite forum_thread + forum_post
├── chat/chat.nim      # Real SQLite chat_message
├── search/search.nim  # FTS5 virtual table, porter tokenizer
├── markdown/parser.nim
├── th1/interp.nim     # Tcl-like interpreter
├── api/rest.nim       # REST + OpenAPI 3.0.3 + Web UI forms
├── mcp/               # MCP server
│   ├── tools.nim      # 25 tools schemas
│   └── server.nim     # JSON-RPC 2.0 stdio + SSE streaming
└── cli/main.nim       # CLI dispatcher
```

## Code Style

- Nim 2.2.4, --mm:orc, --opt:speed
- `FossilResult[T]` for error handling: `ok(value)` / `err[T](code, msg)`
- SQLite interop via `{.push header: "<sqlite3.h>".} importc`
- QBE compat: avoid `__attribute__`, `volatile`, `__uint128_t`, case ranges `0 ... 7`, use `cinterop/include/nimbase.h` wrapper
- No GC in hot paths: `--mm:refc --threads:off --panics:on -d:useMalloc` for QBE

## Adding a new storage backend

1. Create `src/fossil/storage/my_backend.nim`
2. Implement `StorageBackend` concept: `open`, `close`, `getBlob`, `putBlob`, `getAllRids`, `getAllUuids`, etc.
3. Add to `src/fossil/types.nim` StorageKind enum
4. Add to `cmdRebuild` in `cli/main.nim`
5. Test via `tests/test_storage_real.nim`

## Adding a new MCP tool

1. Define schema in `src/fossil/mcp/tools.nim`: `let mySchema = parseJson("""{"type":"object","properties":{...}}""")`
2. Register in `buildDefaultRegistry()`: `reg.registerTool("fossil_my_tool", "desc", mySchema, dummyHandler)`
3. Implement real handler in `src/fossil/mcp/server.nim` `handleToolsCall` case `of "fossil_my_tool": ...`
4. Use `resolveRepoPathMcp`, open `SqliteBackend`, real SQL
5. Test: `printf '{"jsonrpc":"2.0","id":1,"method":"tools/list"...}\n' | ./bin/fossil-mcp`

## Adding a new REST endpoint

1. Implement handler `proc handleMyThing*(req: Request, params: Table[string, string]): Future[JsonNode] {.async, gcsafe.}`
2. Use `resolveRepoPathApi`, `checkAuth` if needed, `jsonOk`/`jsonError`
3. Register in `registerDefaultRoutes()`: `server.routes.add ApiRoute(meth: "GET", path: "/api/v1/mything", handler: handleMyThing, requiresAuth: false)`
4. Add to OpenAPI spec in `handleOpenApi` paths
5. Add Web UI HTML in `cb()` if needed

## QBE / cproc workflow

```bash
# Generate C files
make build-qbe-c  # 47 files, Patched 47 files

# Compile with cproc+QBE (persistent binaries in bin-tools/)
export PATH=$PWD/bin-tools:$PATH
bin-tools/cproc -O2 -std=c11 -D_GNU_SOURCE -D_XOPEN_SOURCE=700 -DQBE_COMPAT=1 -Ibuild/cgen -Icinterop/include -Icinterop/sha3 -Icinterop/sqlite -I$HOME/.choosenim/toolchains/nim-2.2.4/lib -o bin/fossil-qbe build/cgen/*.c cinterop/sha3/sha3.c cinterop/sha3/sh3_wrapper.c -lsqlite3 -lz -lm -lcrypto -lssl

# Or use Makefile
make qbe  # prefers bin-tools/cproc, fallback gcc

# Static (needs gcc for sqlite3.c atomic builtins)
make qbe-static  # currently fails with cproc, uses gcc fallback
```

**Patch script:** `scripts/patch_qbe.sh`:
- Expands case ranges `case 0 ... 7:` → `case 0: case 1: ...`
- Replaces `__uint128_t` → `unsigned long long`
- Casts `sqlite3_column_text/blob/name` const discard
- Removes `volatile`
- Removes `TSafePoint`, `GcFrameHeader`

**nimbase.h wrapper:** `cinterop/include/nimbase.h`:
- `#include_next "nimbase.h"` then undef/redefine `N_LIB_PRIVATE`, `N_INLINE`, etc. as `rettype name` (no `__attribute__`)
- `NIM_CONST` empty, `__uint128_t` fallback, `volatile` empty, `memmem` fallback `qbe_memmem`
- Portable `__builtin_clz/ctz/popcount` via loops, not 0

## Testing

```bash
make test          # all_tests + test_storage_real
nim c -r tests/all_tests.nim
nim c -r tests/test_wiki_ticket.nim
nim c -r tests/test_sync.nim
nim c -r tests/test_search_forum_chat.nim
nim c -r benchmarks/storage_bench.nim
make test-mcp      # MCP JSON-RPC test
```

## Documentation

- All docs in `docs/` + Russian `_RU.md` variants
- `README.md` + `README_RU.md` — quick start, architecture, backends
- `docs/ARCHITECTURE.md` + `_RU.md` — 60+ modules
- `docs/STORAGE_BACKENDS.md` + `_RU.md` — comparison
- `docs/MCP_API.md` + `_RU.md` — 25 tools, resources, prompts
- `docs/MCP_SSE_API.md` + `_RU.md` — SSE transport
- `docs/CPROC_QBE.md` + `_RU.md` — QBE compat, wrapper fix, cproc+QBE 1.3 success
- `docs/BUILD.md` + `_RU.md` — build, QBE, vendored
- `docs/API.md` — REST API
- `docs/MIGRATION_GUIDE.md` — migration steps, benchmarks
- `docs/BENCHMARKS.md` — storage, diff, delta, QBE, MCP, API
- `docs/CONTRIBUTING.md` — this file

## Commit Messages

- Use conventional commits: `feat:`, `fix:`, `docs:`, `perf:`, `refactor:`
- First line 50 chars max, imperative mood
- Reference tickets if any
- Example: `fix(sync): parseCards size-based offset, multiline Match true`

## Pull Requests

1. Fork, create branch `feat/my-feature`
2. `nim check` 0 errors, `make test` PASS, `make qbe` version/help OK
3. Update docs if needed
4. PR with description, test results, benchmark if perf-related

## Code of Conduct

- Be respectful, constructive
- Focus on technical correctness, QBE compat, modularity
- Document in English + Russian where possible
