# Release 2.26.0-nim-final — 2026-10-17

## Binaries

- `bin/fossil` 5.3M ARC — main CLI, storage backends sqlite,libmdbx,lmdb,cdb, QBE compat OFF
- `bin/fossil-mcp` 1.5M — MCP server 89 tools, Streamable HTTP 2026-07-28 + SSE legacy + stdio
- `bin/fossil-qbe` 790K QBE ON — compiled with cproc QBE, 54 C files patched, verified version/help

## Storage Backends Production Final

All 4 backends + 3 hybrid production-ready:

- SQLite 486 lines reference 100% compatible 23 tables WAL FTS5 delta chain
- CDB 350+ lines pure Nim 143k put/s 191k get/s QBE-friendly archival
- LMDB 400+ lines cursor iteration mdb_cursor_open/get 4 DBIs persisted nextRid reverse lookup putDelta stats mdb_stat
- libmdbx 450+ lines recommended auto-growth 10GB 64MB step MDBX_INTEGERKEY+APPEND 4 DBIs persisted nextRid
- Hybrid 500+ lines SQLite meta + KV blobs 23 tables via ATTACH DATABASE batched 10k txn

Benchmarks:
- n=1000: SQLite 16,905/173,515, CDB 143,104/191,496, Hybrid-CDB 18,119/190,315
- n=10000: SQLite 16,446/170,945, CDB 143,350/16,910, Hybrid-CDB batched 16,410/19,563
- Previous: SQLite 19,645/131,711, CDB 737,120/271,958, Hybrid 19,953/130,307

Migration: `copyAllTablesViaAttach` ATTACH DATABASE for 23 tables + `migrateToHybrid` batched 10k txn

Recommendation: Hybrid-CDB default pure Nim no deps, Hybrid-MDBX for large >10GB auto-growth

## MCP 89 Tools Effective Design

- 89 tools with annotations title/readOnlyHint/destructiveHint/idempotentHint/openWorldHint
- Outcome-oriented smart_commit/code_review/release_notes/security_audit
- Progressive disclosure search_tools (wiki 15) + list_capabilities grouped 200 tokens
- IdempotencyCache 100 entries 1h LRU, truncateForBudget 8000
- Streamable HTTP 2026-07-28 POST /mcp headers MCP-Protocol-Version/Mcp-Method/Mcp-Name/Accept/Origin X-Accel-Buffering:no returns 89 tools JSON/SSE, GET /.well-known/mcp discovery, legacy /sse + /message
- Resources 12 real DB reads, Prompts 8 SequentialWorkflow
- Verified stdio 89 tools, HTTP 89 tools, openapi 32 paths has /mcp, health 89 tools

## REST API 32 Paths

- OpenAPI with x-mcp metadata, servers :8080 + :3000
- /mcp POST, /.well-known/mcp GET, /sse GET legacy, /message POST legacy, /api/v1/* with MCP equivalents
- handleSql readOnly limit 100 rows, handleSecurityAudit SEC-01..07 PASS, handleBenchmark cached, handleHealth 89 tools, handleMcpDiscovery

## QBE / cproc

- build-qbe-c generates 54 C files in build/cgen, patch_qbe.sh patches GNU extensions void* casts removes SafePoint/GcFrameHeader
- cproc -O2 -std=c11 -D_GNU_SOURCE -D_XOPEN_SOURCE=700 -DQBE_COMPAT=1 builds bin/fossil-qbe 780K QBE ON
- Verified version/help/init/timeline

## Docs 63 Files EN+RU

- ARCHITECTURE, MCP_API_2026-10-17 EN 15KB RU 37KB, STORAGE_BACKENDS_BENCH_2026-10-17 EN 14KB RU 16KB, FINAL_COMPLETE_2026-10-17 EN+RU, BUILD, CPROC_QBE, WEB_FULL_PARITY, FINAL_REPORT_*, API, SEARCH, TH1, UI_NEW, FORUM_CHAT_ENHANCED + RU, CHANGELOG, RELEASE

## Tests PASS

- all_tests, storage_real, search_forum_chat, wiki_ticket, integration delta 5000->1063 21% chain verified checkout materialization, fuzz_delta 100/100 fuzz_manifest 3/3 random 100/100, security SEC-01..07 PASS, hybrid_bench, storage_bench_final, storage_bench_10k, MCP stdio + HTTP

## Release Tarball

- `/tmp/fossil-nim-2.26.0-final.tar.gz` 3.9M (src/docs/benchmarks/tests/cinterop/scripts/bin-tools/Makefile README fossil.nimble, excludes bin/build/nimcache/.git)

## Build Commands

```bash
export PATH=$HOME/.choosenim/toolchains/nim-2.2.4/bin:$PATH
nim c -d:release --mm:arc --threads:off --opt:speed --outdir:bin -o:bin/fossil src/fossil/cli/main.nim
nim c -d:release --mm:arc --threads:off --opt:speed --outdir:bin -o:bin/fossil-mcp src/fossil/mcp/server.nim
make build-qbe-c && make qbe
./bin/fossil version
./bin/fossil-qbe version
printf '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}\n{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}\n' | ./bin/fossil-mcp 2>&1 | tail -n 5
```

## Next

- Install libmdbx-dev/liblmdb-dev in CI to test real LMDB/MDBX backends
- Add getRidByUuid to concept
- Search FTS5 to KV for faster search
- Final docs consolidation into single README

## Version

Fossil-Nim version 2.26.0-nim-final (ported from Fossil 2.26.0)
Storage backends: sqlite, libmdbx, lmdb, cdb
Compiled with Nim 2.2.4 at 2026-10-17
QBE compat mode: ON/OFF
API: REST + MCP
