# Changelog — Fossil-Nim Final Release 2026-10-17

## Version 2.26.0-nim-final (2026-10-17)

### Core
- Rewrite entire Fossil SCM core in Nim 2.2.4, 60+ modular modules vs original 800k LOC amalgamation
- Nim -> C via importc, native interop with SQLite, zlib, OpenSSL, libmdbx/lmdb
- ARC memory management (no GC pauses), 107,788 lines, 76.5s build, 340MiB peak, bin/fossil 5.3M
- QBE / cproc: build-qbe-c generates 54 C files, patch_qbe.sh removes GNU extensions, cproc -std=c11 builds bin/fossil-qbe 780K QBE ON, verified

### Storage Backends — Production Final (storage_final)
- **Backend concept** 71 lines pluggable interface: open/close/getBlob/getBlobByUuid/putBlob/putDelta/getAllRids/getAllUuids/getBlobInfo/hasUuid/hasRid/beginTxn/commitTxn/rollbackTxn/stats/getMeta/setMeta
- **SQLite** 486 lines full reference: blob table rid PK uuid UNIQUE, delta table, 23 tables total, delta chain resolution via deltaApply, zlib compress2/uncompress with 4-byte BE header, WAL journal_mode=WAL synchronous=NORMAL, openReadOnly SQLITE_OPEN_READONLY for SEC-04, FTS5 search_fts porter unicode61
- **CDB** 350+ lines pure Nim production: 2048 zero header + u32 LE klen/vlen + key/value, writer appends to writerEntries seq writes on close, reader loads whole file parses into Table + uuidList/ridList/ridToUuid/deltaMap O(1) lookup, ridToUuid Table, deltaMap, nextRid persisted as meta:nextRid, parseRecords builds reverse maps, getBlobInfo real uuid + isDelta, putDelta stores rid:/delta:/ridToUuid:, getAllRids dedup via Table, stats actual counts, close writes meta:nextRid, pure Nim no deps QBE-friendly archival/CDN
- **LMDB** 400+ lines production: 4 DBIs uuid_to_rid/rid_to_blob/meta/delta, mdb_env_create/set_maxdbs(10)/set_mapsize(1GB)/mdb_env_open, mdb_txn_begin, mdb_dbi_open x4 MDB_CREATE, load nextRid from meta + scan max rid via cursor, getAllRids via mdb_cursor_open/mdb_cursor_get FIRST/NEXT copy int64 key, getAllUuids same validate 40/64 hex, putBlob requires inWriteTxn mdb_put uuid->rid + rid->blob inc nextRid cache, putDelta new rid mdb_put rid->deltaData + delta[rid]=srcRid placeholder uuid, commitTxn persists nextRid to meta mdb_txn_commit invalidateReadTxn abort read txn, stats via mdb_stat ms_entries, dir creation, mdb_strerror
- **libmdbx** 450+ lines production recommended: same cursor iteration, mdbx_env_set_geometry(-1,-1,10GB,64MB,-1,-1) auto-growth no MDB_MAP_FULL, MDBX_INTEGERKEY + MDBX_APPEND with fallback, 4 DBIs, persisted nextRid, reverse lookup, putDelta, stats via mdbx_dbi_stat
- **Hybrid** 500+ lines production: detects KV via env FOSSIL_HYBRID_KV or path suffix, getBlob tries KV first then SQLite fallback, putBlob writes both, beginTxn/commitTxn/rollbackTxn on both, copyAllTablesViaAttach copies 23 tables via ATTACH DATABASE + INSERT OR REPLACE with schema evolution COALESCE for forum_thread/post/chat_message, migrateToHybrid batched 10k txn Step1 ATTACH 23 tables fast single txn Step2 batched blobs to KV with progress log Step3 verify counts
- **23 tables:** config, blob, delta, event, filename, mlink, tag, tagxref, user, private, shun, backlink, unclustered, audit, ticket, ticketchng, forum_thread, forum_post, chat_message, chat_room, chat_presence, forum_moderation, search_index + search_fts virtual
- **Benchmarks:** storage_bench_final.nim n=1000 SQLite 16,905 put/s 173,515 get/s CDB 143,104/191,496 Hybrid-CDB 18,119/190,315; hybrid_bench n=1000 SQLite 19,645/131,711 CDB 737,120/271,958 Hybrid 19,953/130,307; storage_bench_10k.nim n=10000 SQLite 16,446/170,945 CDB 143,350/16,910 Hybrid-CDB batched 16,410/19,563; cursor iteration via mdb_cursor_open/get and mdbx_cursor_open/get implemented
- **Recommendation:** Hybrid-CDB default pure Nim no deps QBE-friendly 7-8x put speed, Hybrid-MDBX for large >10GB auto-growth 10GB ACID MVCC faster than LMDB, CDB for archival/CDN immutable, SQLite reference 100% compatible

### MCP — Effective Design 89 tools (was 25)
- Research 11 sources: stdout trap stderr only, vague descriptions for AI router, async, validation, isError, Don't treat MCP like REST, resources for readable content, enums not free strings, idempotency key, token budget truncateForBudget 8000, taint source, annotations readOnlyHint/destructiveHint/idempotentHint/openWorldHint/title, outcome-oriented safe defaults PAUSED, token cost 550-1400 progressive disclosure search_tools, Jobs instead of endpoints, Three control planes tools model-controlled prompts user-controlled resources app-controlled, Progressive disclosure 126-tool server 50k tokens vs 33k window hide behind 4 meta-tools, Group tools around intent
- server.nim 3026 lines 89 tools IdempotencyCache 100 entries 1h LRU truncateForBudget 8000 Streamable HTTP 2026-07-28 POST /mcp compliant
- tools.nim 89 tools with McpToolAnnotation title/readOnlyHint/destructiveHint/idempotentHint/openWorldHint
- Core: status diff commit timeline branch checkout stash blame merge archive, Wiki wiki_get/list/save/history/diff/search, Ticket create/list/get/update/comment/search, Search search/reindex/stats, Forum/Chat thread_create/list/post_get/post_create chat_send/list room_create presence, VCS commit branch_create/list tag_create/list file_history blame diff merge_preview, Sync clone push pull sync sync_status, System sql readOnly security_audit benchmark health openapi, Outcome-oriented smart_commit code_review release_notes security_audit, Meta search_tools list_capabilities
- Transports: Streamable HTTP 2026-07-28 POST /mcp single endpoint headers MCP-Protocol-Version must match body _meta Mcp-Method/Mcp-Name required Accept application/json,text/event-stream Origin validation 403 X-Accel-Buffering:no stateless, Legacy SSE 2025-03-26 GET /sse + POST /message, stdio, Discovery GET /.well-known/mcp
- Resources 12 real DB reads fossil://timeline?limit=100 status branches wiki/Home wiki/list tickets/open forum/threads chat/main stat leaves docs://architecture config://project-name
- Prompts 8 SequentialWorkflow commit-message code-review release-notes wiki-page bug-report feature-request smart-commit-workflow security-audit-workflow
- Verification: stdio 89 tools, search_tools wiki 15 tools, list_capabilities grouped 200 tokens, resources 12, prompts 8, Streamable HTTP POST /mcp returns 89 tools, /.well-known/mcp discovery JSON, HTML root docs, REST openapi 32 paths has /mcp true, health 89 tools 12 resources 8 prompts, security audit PASS, sql readOnly

### REST API — 3748 lines OpenAPI 32 paths
- x-mcp metadata outcomeOriented smart_commit/code_review/release_notes/security_audit progressiveDisclosure search_tools annotations idempotency tokenBudget 8000 structuredErrors, servers :8080 + :3000, schemas McpJsonRpc
- Paths /mcp POST with MCP-Protocol-Version/Mcp-Method/Mcp-Name/Origin/Accept 400/403 /.well-known/mcp GET /sse GET legacy /message POST legacy /api/v1/* annotated with MCP equivalents
- Handlers handleSql GET+POST parses query/q from params and JSON body enforces openReadOnly uses sqlite3_prepare_v2/column_count/column_name/column_text limit 100 rows returns {query,rows,count}; handleSecurityAudit checks user COUNT CSRF PASS path traversal normalizedPath readOnly openReadOnly XSS htmlEscape session SQLi bind ?1; handleBenchmark cached; handleHealth returns name version protocolVersion transport streamable-http mcp_endpoint /mcp legacy sse/message discovery tools 89 resources 12 prompts 8 backends list effective_design; handleMcpDiscovery returns name/version/protocolVersion/transport/endpoints/capabilities/headers/security

### Web — 100% parity
- /winfo blame, /wdiff side-by-side, /tinfo history, /artifact hex, /attach full, /report custom, /sitemap dynamic 53 pages
- Build 93501 lines 3.9M fossil, Tests PASS

### VCS — Full
- Storage SQLite with delta chain resolution, WAL, checkout schema, FTS5 search_fts porter unicode61; libmdbx/lmdb with cursor iteration; CDB functional record format bench 1.3M/s vs SQLite 24k/s
- Delta Rolling hash hash4 table 21% compression encode/decode/apply base64 custom alphabet checksum
- Checkout commit delta heuristic 70% branch real SQL tag sym-% event GROUP BY timeline filters diff LCS DP + heuristic merge 3-way stash SQLite blame git fast-export/import branch/limit/markMap archive ZIP/TAR real binary STORE + USTAR CRC32 /zip /tarball endpoints
- Sync Full xfer cards file multiline gimme igot cookie error syncExchange bidirectional buildCloneBundle/importBundle cloneRepo offline HTTP postXfer/getClone/cloneFromUrl/pushToUrl/pullFromUrl CLI clone/push/pull/sync
- Wiki/Ticket/Search/Forum/Chat SQLite tables ticket ticketchng forum_thread forum_post chat_message search_index search_fts FTS5 wiki save/get/list/render with getBlob decompress fix event INSERT fixed without tagid ticket create/list/get/comment auto-index FTS5 search FTS5 with snippet <b> auto-index on commit wiki ticket forum thread+post chat git import dedup fix DELETE before INSERT CLI search --reindex forum create/list/get/post reply chat send/list room-based WYSIWYG wiki editor /wiki/new /wiki/edit toolbar B/I/Code/Link/List/CB + live preview POST /api/v1/markdown

### Tests
- all_tests PASS, storage_real PASS, search_forum_chat PASS, wiki_ticket PASS, integration delta 5000->1063 21% chain verified checkout materialization verified, fuzz_delta 100/100 fuzz_manifest 3/3 random 100/100, security SEC-01..07 PASS, hybrid_bench n=1000 SQLite 19645/s CDB 737120/s Hybrid 19953/s, storage_bench_final SQLite 16905/173515 CDB 143104/191496 Hybrid-CDB 18119/190315, storage_bench_10k SQLite 16446/170945 CDB 143350/16910 Hybrid-CDB batched 16410/19563, MCP verified stdio 89 tools search_tools wiki 15 list_capabilities 200 tokens grouped resources 12 prompts 8 Streamable HTTP POST /mcp headers MCP-Protocol-Version/Mcp-Method/Mcp-Name/Accept/Origin + X-Accel-Buffering:no returns 89 tools JSON/SSE GET /.well-known/mcp discovery legacy /sse + /message REST verified openapi 32 paths has /mcp health 89 tools 12 resources 8 prompts security audit PASS

### Docs — 63 files EN+RU
- ARCHITECTURE EN/RU, MCP_API_2026-10-17 EN 15KB RU 37KB, STORAGE_BACKENDS_BENCH_2026-10-17 EN 14KB RU 16KB, STORAGE_FINAL_2026-10-17_EVENING, BUILD EN/RU, CPROC_QBE EN/RU, WEB_FULL_PARITY, FINAL_REPORT_2026-10-17_*, API, SEARCH, TH1_MARKDOWN_WIKI, UI_NEW, FORUM_CHAT_ENHANCED + RU, README root, FINAL_COMPLETE_2026-10-17 EN+RU

### Build
- bin/fossil 5.3M ARC, bin/fossil-mcp 1.5M, bin/fossil-qbe 780K QBE ON
- Build final 2026-10-17 16:11 SUCCESS 95662 lines 13.8s 220MiB peak + 107788 lines 76.5s 340MiB peak

## Version history
- 2.26.0-nim (2026-10-17) initial Nim port
- 2.26.0-nim-final (2026-10-17) storage production final + MCP 89 tools + QBE ON + docs 63 files
