# Gap Analysis - What remains for full Fossil port

Date: 2026-10-01
Current: ~15% core ported, infrastructure ready, tests and QBE working.

## 1. Original Fossil composition

From https://fossil-scm.org/home/dir?ci=trunk&name=src, src/ has ~150 C files:

**Core VCS (critical):**
- `add.c` (38k), `checkout.c` (21k), `checkin.c` (121k), `branch.c` (40k), `merge.c` (57k), `merge3.c` (38k), `diff.c` (131k), `diffcmd.c` (50k), `bisect.c` (22k), `blame` part of `finfo.c` (35k), `stash` part of `checkin.c`, `leaf.c` (8k), `descendants.c` (22k), `purge.c` (23k)

**Storage:**
- `db.c` (187k) biggest, `blob.c` (58k), `delta.c` (22k), `deltacmd.c` (5k), `deltafunc.c` (16k), `content.c` (39k), `schema.c` (26k), `rebuild.c` (48k)

**Sync:**
- `clone.c` (14k), `http.c` (34k), `http_socket.c` (6k), `http_ssl.c` (38k), `http_transport.c` (15k), `export.c` (60k), `import.c` (67k), `bundle.c` (26k)

**Web UI (huge):**
- `cgi.c` (96k), `dispatch.c` (60k), `browse.c` (39k), `info.c` (147k), `event.c` (19k), `graph.c` (35k), `file.c` (91k), `doc.c` (49k), `search.c` (91k), `setup.c` (93k), `login.c` (97k), `json.c` (77k) + 10 `json_*.c` files, `chat.c` (51k), `forum.c` (103k), `report.c` (42k), `attach.c` (61k), etc.

**Total:** ~2.5M LOC C without SQLite, ~3.5M with.

## 2. What is ported in Fossil-Nim

| Nim Module | Original C | Status | Coverage |
|------------|------------|--------|----------|
| `types.nim` | `blob.c` part | ✅ Done | 100% |
| `config.nim` | `configure.c` | ✅ Done | 70% |
| `storage/backend.nim` | - | ✅ Done | Interface |
| `storage/sqlite_backend.nim` | `db.c` + `blob.c` | 🟡 Partial | 30% |
| `storage/libmdbx_backend.nim` | - | 🟡 Partial | 40% |
| `storage/lmdb_backend.nim` | - | 🟡 Partial | 40% |
| `storage/cdb_backend.nim` | - | 🟡 Partial | 30% |
| `delta/delta.nim` | `delta.c` | 🟡 Partial | 60% |
| `artifact/manifest.nim` | `manifest.c` | 🟡 Partial | 50% |
| `artifact/artifact.nim` | `content.c` | 🟡 Partial | 30% |
| `vcs/checkout.nim` | `checkout.c` | 🔴 Stub | 10% |
| `vcs/commit.nim` | `checkin.c` | 🟡 Partial | 30% |
| `vcs/diff.nim` | `diff.c` | 🟡 Partial | 40% |
| `vcs/branch.nim` | `branch.c` | 🟡 Partial | 20% |
| `vcs/timeline.nim` | `event.c` | 🟡 Partial | 20% |
| `vcs/merge.nim` | `merge.c` + `merge3.c` | 🟡 Partial | 30% |
| `vcs/stash.nim` | part `checkin.c` | 🟡 Partial | 20% |
| `vcs/blame.nim` | `finfo.c` | 🟡 Partial | 20% |
| `vcs/add.nim` | `add.c` | 🟡 Partial | 40% |
| `sync/protocol.nim` | `http.c` part | 🟡 Partial | 30% |
| `sync/http.nim` | `http_transport.c` | 🟡 Partial | 20% |
| `web/server.nim` | `cgi.c` + `dispatch.c` | 🟡 Partial | 20% |
| `web/router.nim` | `dispatch.c` | ✅ Done | 80% |
| `wiki/wiki.nim` | `wiki.c` | 🟡 Partial | 20% |
| `ticket/ticket.nim` | `ticket.c` | 🟡 Partial | 20% |
| `forum/forum.nim` | `forum.c` | 🟡 Partial | 10% |
| `api/rest.nim` | `json.c` + `json_*.c` | 🟡 Partial | 30% |
| `mcp/tools.nim` | - | ✅ Done | 100% 13 tools |
| `mcp/server.nim` | - | 🟡 Partial | 60% JSON-RPC works, handlers dummy |
| `cli/main.nim` | `main.c` | 🟡 Partial | 50% |
| `cli/main_qbe.nim` | - | ✅ Done | 100% QBE minimal, 12 C files, C11, 67K |
| `utils/hash.nim` | `sha1.c` + `sha3.c` | ✅ Done | 90% |
| `utils/compress.nim` | `gzip.c` | ✅ Done | 80% |

Total: ~38 Nim modules, ~4000 LOC, ~15% of C Fossil, but infrastructure 80% ready.

## 3. What remains

### Critical for MVP

**Storage (40% left):**
- deltaChain, getManifest, putDelta, cursor iteration, links DBI, nextRid persistence, rebuild command, vendor mdbx.c/lmdb/sqlite3.c

**Delta (40% left):**
- Rolling hash matching for optimal size, test vs original fossil binary

**Artifact (70% left):**
- Full manifest cards Q,W, Z checksum, cluster, resolveBlob with delta chain, vendor sh3.c

**VCS Core (80% left):**
- checkout: _FOSSIL_ DB (vvar, vfile), materialize via delta chain
- commit: scan vs vfile, delta heuristic 70%, vfile/event update
- add: vfile integration, addremove
- branch: real tag table
- timeline: real event table + graph.c
- diff: Myers algorithm
- merge: merge3.c
- stash, blame, bisect, clean, revert, tag, leaf, descendants

**CLI (50% left):**
- Real status, diff, commit, timeline, branch, open, etc.

### Important

**Sync (70% left):** full xfer cards, state machine, clone/sync/push/pull, bundle, export/import

**MCP (40% left):** real handlers calling VCS, resources file@{rev}, prompts, SSE/HTTP transports

**API (70% left):** real handlers, auth, OpenAPI, port json_*.c

**Web (90% left):** 50+ pages, TH1 interpreter (2000 LOC), Markdown 86k, graph, search, login, setup

### Full parity

**Web:** all pages, TH1 full, Markdown, search, etc.
**Subsystems:** wiki, ticket, forum, chat, attachments full
**QBE:** full QBE build without _GNU_SOURCE, static vendored, test with real cproc
**Tests:** checkout, commit, branch, timeline, merge, sync, wiki, ticket, forum, mcp, api, qbe, fuzz
**Docs:** module docs, Nim API examples, migration guide, benchmarks

## 4. Priorities

**P0 MVP (2-3 weeks, ~10k LOC):** Storage cursor + delta rolling hash + resolveBlob + checkout + commit + CLI real

**P1 Important (3-4 weeks, ~15k LOC):** Sync + Myers diff + Merge + MCP/API real handlers + Web basic

**P2 Full parity (2-3 months, ~20k LOC):** Web all pages + TH1 + Markdown + Subsystems full + QBE full + Tests + Docs

## 5. Risks

- TH1 (2000 LOC, custom language)
- Markdown 86k (can use Nim markdown lib)
- Web UI 50 pages
- QBE: Nim stdlib uses GNU extensions (memmem, accept4, epoll) - need patch or avoid modules or use _GNU_SOURCE

## 6. What's good

- ✅ Modular architecture
- ✅ Storage abstraction
- ✅ MCP works (13 tools)
- ✅ QBE minimal works (67K, C11)
- ✅ Tests and CI (make check, make test)
- ✅ Docs EN+RU basic
- ✅ LSP works (0 errors)

## 7. Next steps

Week 1: P0 Storage + Delta + Artifact
Week 2: P0 Checkout + Commit + CLI
Week 3: P1 Sync + Diff/Myers + Merge + MCP/API real
Week 4: P1 Web basic + TH1 start

See `GAP_ANALYSIS_RU.md` for Russian version.
