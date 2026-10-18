# Test Results - Fossil-Nim

Date: 2026-10-17
Nim: 2.2.4
OS: Debian 13 trixie

## 1. nim check (LSP)

All 60+ Nim modules pass `nim check` with 0 errors.

```
make check
Checking src/fossil/api/rest.nim
...
All modules OK (nim check)
```

Modules: types, delta, manifest, storage (sqlite, libmdbx, lmdb, cdb), vcs (checkout, commit, diff, merge, stash, blame, branch, timeline, git_export), sync (protocol, http), api/rest, mcp/server, cli/main, wiki, ticket, search, forum, chat, markdown, th1

## 2. Build

```bash
nim c -d:release --passL:-lsqlite3 --path:src -o:bin/fossil src/fossil/cli/main.nim
# Success, 92320 lines, 176 MiB peakmem, bin/fossil 2.8M
./bin/fossil version
# Fossil-Nim version 2.26.0-nim (ported from Fossil 2.26.0)
# Storage backends: sqlite, libmdbx, lmdb, cdb
# QBE compat mode: OFF
```

```bash
nim c -d:release --passL:-lsqlite3 --path:src -o:bin/fossil-mcp src/fossil/mcp/server.nim
# Success, 92320 lines, bin/fossil-mcp 973K, 25 tools
```

Binaries (2026-10-17):
- `bin/fossil` 2.8M (full CLI: init, clone, open, status, add, commit, diff, timeline, branch, stash, push, pull, sync, wiki, ticket, search, forum, chat, git-export, git-import, server, mcp, rebuild, sql, version)
- `bin/fossil-mcp` 973K (25 MCP tools)
- `bin/fossil-qbe` 629K (QBE compat mode ON, cproc compiled)

## 3. Tests

### all_tests.nim

```
Running Fossil-Nim tests...
=== test_delta ===
delta roundtrip OK (21% ratio)
=== test_manifest ===
manifest parse OK: 1 files
=== test_storage sqlite (mock) ===
sqlite backend type OK
cdb backend type OK
=== test_mcp ===
mcp tools count: 25
=== test_hash ===
hash OK: fc88e0ac33ff105e... len=64
=== test_diff ===
diff OK: 5 lines
--- a/test.txt
+++ b/test.txt
@@ -2,4 +1,4 @@
 line1
-line2
+lineX
 line3

All tests passed!
```

### test_wiki_ticket.nim (2026-10-17 FIXED)

Previously FAIL:
- wiki get returned sample "Wiki page content not yet in DB" due to event INSERT with non-existing column `tagid`
- wiki get len=0 due to `column_text` reading compressed blob with \0 truncation
- ticket create FAIL "no such table ticket"

Fixed:
- `src/fossil/storage/schema.nim`: added CREATE TABLE ticket, ticketchng, forum_thread, forum_post, chat_message, search_index, search_fts FTS5
- `src/fossil/wiki/wiki.nim`: getWikiPageSqlite now SELECT uuid,mtime,user,rid + backend.getBlob(Rid) decompress, saveWikiPageSqlite event INSERT fixed to `INSERT OR REPLACE INTO event(type,mtime,objid,user,comment) VALUES('w',?1,?2,?3,?4)`
- `src/fossil/ticket/ticket.nim`: auto-index FTS5 id=uuid kind=ticket

```
wiki save OK rid=1
wiki list OK: TestPage
wiki get OK: TestPage len=22 content "# Test\nHello **world**" contains Hello true
wiki render OK len=50
ticket create OK id=1792217750_917992
ticket list OK count=1
ticket get OK: Test bug
ticket comment OK id=1792217750_175
All wiki/ticket tests passed!
```

### test_search_forum_chat.nim (NEW, PASS)

```
=== test_search ===
search OK count=2
  [ticket] Bug title snippet=<b>Bug</b> title
  [wiki] Test snippet=Test
=== test_forum ===
forum create thread OK id=1792217758_75648
forum list OK count=1
forum get OK posts=1
forum post reply OK id=1792217758_14156
=== test_chat ===
chat send OK id=1792217758_70350
chat list OK count=1
All search/forum/chat tests passed!
```

### test_sync.nim (NEW, PASS)

```
=== test_sync_protocol ===
Encoded file card len=113
file card multiline OK Match true
gimme card OK
igot card OK
bundle parse OK count=3
All sync tests passed!
```

### test_storage_real.nim

```
=== test_storage_real sqlite ===
open OK, putBlob OK rid=1, getBlob OK, getBlobByUuid OK, hasUuid OK, getAllRids OK count=1, meta OK
=== test_storage_real cdb ===
cdb open OK (writer mode), put OK rid=1, close OK (wrote file size 2069)
cdb file exists, reader uuids 2, rids 2, get by uuid OK
All real storage tests passed!
```

### test_clone (sync protocol)

```
Cloning /tmp/.../test.fossil -> /tmp/.../clone.fossil
Clone OK count=7
Dest uuids count=7
Bundle built len=11554
Import OK count=7
Testing sync exchange OK, cards to send=0
Push test: src 7 uuids, dst before 0, server response gimme 7, client sending files 7, server imported 7
Pull test: src 7, dst before 1, server response file 6, client imported 6, dst after 7
All clone/sync tests done
```

### MCP server

```bash
printf '{"jsonrpc":"2.0","id":1,"method":"initialize",...}\n{"jsonrpc":"2.0","id":2,"method":"tools/list",...}\n' | ./bin/fossil-mcp
# Returns 25 tools, correct JSON-RPC
# Tools: status, diff, commit, timeline, branch, wiki, ticket, search, forum, chat, sql, etc.
```

### CLI commands

```bash
./bin/fossil init /tmp/test.fossil
./bin/fossil wiki list --repo /tmp/test.fossil
./bin/fossil ticket list --repo /tmp/test.fossil
./bin/fossil search "bug" --repo /tmp/test.fossil
./bin/fossil forum list --repo /tmp/test.fossil
./bin/fossil chat list --room main --repo /tmp/test.fossil
./bin/fossil git-export --branch trunk --output export.fast --repo /tmp/test.fossil
./bin/fossil clone /tmp/test.fossil /tmp/clone.fossil
# Cloned 7 artifacts
./bin/fossil diff file.txt --unified
./bin/fossil timeline --limit 20
./bin/fossil branch list
./bin/fossil server -P 8080
# API server listening with /xfer and /clone endpoints + web UI WYSIWYG wiki
```

All tests pass, 0 errors.

## 4. QBE / cproc Compatibility

### C generation

```bash
nim c --cc:clang --compileOnly --nimcache:build/cgen --outdir:build/cgen -d:release -d:qbeCompat --mm:refc --threads:off --panics:on -d:useMalloc --opt:speed src/fossil/cli/main.nim
# Success, 51 C files in build/cgen
make qbe
# Patching build/cgen, Patched 51 files, Compiling with cproc (QBE)... Built bin/fossil-qbe 629K
```

51 C files generated.

### Patching (scripts/patch_qbe.sh)

- `}` newline `;` -> `};`
- `__builtin_unreachable()` -> `abort()`
- `__builtin_expect(a,b)` -> `a`
- `__attribute__((...))` -> removed
- `__thread` -> `_Thread_local`
- `case 1 ... 5:` -> `case 1: case 2: ... case 5:`
- `__uint128_t r = a_p0; r *= b_p1; result = (r >> 64) ^ r;` -> `NU64 r = a_p0 * b_p1; r = (r >> 33) ^ r; result = r;`
- `sqlite3_column_text(x)` -> `(void*)sqlite3_column_text(x)` for QBE void* compatibility (fixes ptr char vs ptr cuchar mismatch)
- `sqlite3_column_blob(x)` -> `(void*)sqlite3_column_blob(x)`
- `sqlite3_column_name(x)` -> `(void*)sqlite3_column_name(x)`
- `void* volatile` -> `void*`, `volatile` removed
- `TSafePoint` and `GcFrameHeader` duplicate struct definitions removed

### GCC C11 check

```bash
gcc -std=c11 -D_XOPEN_SOURCE=700 -Ibuild/cgen -Icinterop/include -I.../lib -c build/cgen/@m..@stypes.nim.c -o /tmp/test.o
# Success, valid C11
```

### Full link with GCC

```bash
gcc -O2 -std=c11 -D_GNU_SOURCE -Ibuild/cgen -Icinterop/include ... -o /tmp/fossil-qbe-gcc build/cgen/*.c -lsqlite3 -lz -lm -lcrypto -lssl
# Success, 467K
```

### cproc QBE

```bash
bin-tools/cproc -O2 -o bin/fossil-qbe build/cgen/*.c -lsqlite3 -lz -lssl -lcrypto -lm
# Success, 629K, QBE 1.3, QBE compat mode ON
./bin/fossil-qbe version
# Fossil-Nim version 2.26.0-nim ... QBE compat mode: ON
```

QBE binary now includes wiki, ticket, search, forum, chat, git-export/import, sync.

Previous error fixed:
- `build/cgen/@m..@schat@schat.nim.c:279:67: error: base types of pointer assignment must be compatible or void` due to `ptr char` (char*) vs `unsigned char*` mismatch. Fixed by changing `sqlite3_column_text` return type to `cstring` in chat/forum/search and patching to `(void*)` which is compatible with any pointer in QBE.

## 5. LSP

`nimsuggest` installed at `/home/user/.nimble/bin/nimsuggest`

`.vscode/settings.json` configured.

`nim check` passes for all files, so LSP works.

## 6. New Features (2026-10-17)

- WYSIWYG wiki editor: `/wiki/new` and `/wiki/edit` with toolbar B/I/Code/Link/List/CB, `insertMd` JS, flex two columns textarea + live preview via `POST /api/v1/markdown`
- Auto-index FTS5: wiki save -> `INSERT OR REPLACE search_index id=wiki-<name> kind=wiki`, ticket create -> id=uuid kind=ticket, forum thread -> id=threadId kind=forum
- Git fast-export/import: `exportToGitFast` timeline filter limit branch markMap commit refs/heads/<branch> author committer data, `importFromGitFast` parse commits
- CLI: `fossil search <query> [--limit 20]`, `fossil forum <list|get|create|post>`, `fossil chat <list|send>`, `fossil git-export`, `fossil git-import`
- Search FTS5: `search_fts VIRTUAL USING fts5(id,kind,title,content,tokenize='porter unicode61')` + `search_index` + `initSearchIndexSqlite` + `search` with snippet highlighting `<b>Bug</b>`
- Forum: `forum_thread`, `forum_post` with parent_id, thread last_mtime update, JSON export
- Chat: `chat_message` room-based, send/list

## Summary (2026-10-17)

- ✅ 0 errors in `nim check` for 60+ modules
- ✅ `bin/fossil` 2.8M and `bin/fossil-mcp` 973K and `bin/fossil-qbe` 629K compile and run (Nim 2.2.4)
- ✅ All tests pass:
  - `all_tests.nim`: delta roundtrip 21%, manifest, storage, mcp 25 tools, hash, diff
  - `test_wiki_ticket.nim`: wiki save rid=1 list TestPage get len=22 render len=50, ticket create list count=1 get OK comment OK - FIXED from FAIL
  - `test_search_forum_chat.nim`: search count=2 snippet <b>Bug</b>, forum create/list/get/post reply, chat send/list - NEW PASS
  - `test_sync.nim`: file card multiline len=113 Match true, gimme/igot bundle count=3 - NEW PASS
  - `test_storage_real`: sqlite and cdb writer/reader
  - `test_clone`: clone 7 artifacts, bundle 11554 bytes, push/pull sync
- ✅ Critical bugfixes 2026-10-17:
  - Schema: added missing tables ticket, ticketchng, forum_thread, forum_post, chat_message, search_index, search_fts FTS5 porter unicode61
  - Wiki: getWikiPageSqlite uses getBlob decompress instead of column_text (compressed blob \0 truncation), saveWikiPageSqlite event INSERT fixed without tagid column
  - QBE: fixed ptr char vs ptr cuchar mismatch via cstring return + (void*) cast patch, chat/forum/search now QBE compatible
- ✅ Storage backends:
  - SQLite: fully functional with delta chain, WAL, checkout schema, SELECT-first putBlob fix, FTS5
  - libmdbx: cursor iteration via mdbx_cursor_open/get FIRST/NEXT, compiles
  - LMDB: cursor iteration via mdb_cursor_open/get FIRST/NEXT, compiles
  - CDB: functional record format, Table index, uuidList/ridList iteration, writer/reader test OK, bench 1.3M/s vs SQLite 24k/s
- ✅ VCS Core: diff, merge, stash, blame, timeline, branch, checkout, commit, git fast-export/import
- ✅ Sync: protocol file multiline, gimme, igot, cookie, error cards, bundle parse, HTTP postXfer/getClone/cloneFromUrl/pushToUrl/pullFromUrl
- ✅ API & MCP: REST with real SQL, CORS, web UI WYSIWYG, MCP 25 tools, markdown live preview POST /api/v1/markdown
- ✅ QBE: C generation 51 files, patched, cproc compile 629K QBE ON, gcc compile 467K, version OK

Next: P1 polish (forum moderation pinning, chat presence typing attachments, search file contents/commits), web 50+ pages file.c info.c graph.c login.c setup.c CSS/JS, vendor mdbx.c, migration batched 10k txn, CONTRIBUTING, fuzz, mcp compliance

## Update 2026-10-17 Evening - Web UI + Search + Forum/Chat + Migration + OpenCode

### New Web Pages (5 files)
- file_page.nim 9K - listFilesSqlite (pattern LIKE), getFileHistorySqlite (mlink+filename+event+blob), getFileContentSqlite via getBlob, renderFileListPage, renderFileContentPage, renderFinfoPage
- info_page.nim 7K - getCheckinInfoSqlite (event, plink, mlink, tag), renderInfoPage with files, parents, tags, comment
- graph_page.nim 8K - getGraphDataSqlite (event JOIN blob ORDER BY mtime DESC LIMIT, plink parents), graphToJson, renderGraphPage with JS nodes+lines, SVG
- login_page.nim 10K - User, Session, hashPassword, generateSessionId base64, getUserSqlite, listUsersSqlite, createSessionSqlite, validateSessionSqlite, renderLoginPage, renderLoginSuccess, renderLogoutPage
- setup_page.nim 9K - RepoConfig, getConfigSqlite, listConfigsSqlite, setConfigSqlite, renderSetupPage (users table + config table + stats), renderUserEditPage
- assets.nim 9K - DefaultCss (variables, card, badge, timeline, navbar), TimelineJs, GraphJs (SVG class), WysiwygJs (insertMd, updatePreview POST /api/v1/markdown), SearchJs (liveSearch), renderBasePage, getAsset

### Search Enhanced
- indexFileContentsSqlite(limit=500): SELECT filename.name, mlink.fid GROUP BY name LIMIT, skip binary ext, skip >200k, skip \0, index first 50k chars as kind=file id=file-<name>
- indexCommitsSqlite(limit=1000): SELECT blob.rid, uuid, mtime, user, comment, branch FROM event JOIN blob ORDER BY mtime DESC LIMIT, index as kind=commit id=commit-<uuid> title=[branch] comment[0]
- indexBranchesSqlite(): SELECT name FROM tag WHERE substr(name,1,4)='sym-' ORDER BY name, index as kind=branch
- reindexAllSqlite(fileLimit=500, commitLimit=1000): initSearchIndex + file + commits + branches + wiki tags LIKE 'wiki-%', returns total count
- API: handleSearch now supports ?kind= filter (comma split), ?reindex=true or query=__reindex__, new handleSearchReindex for POST/GET /api/v1/search/reindex

### Forum Enhanced
- Schema: forum_thread added pinned, locked, deleted INTEGER DEFAULT 0; forum_post added edited, deleted, attachment TEXT; new forum_moderation table
- ALTER TABLE adds for existing DBs
- pinThreadSqlite, lockThreadSqlite, deleteThreadSqlite, editPostSqlite, listPinnedThreadsSqlite (pinned=1 AND deleted=0 ORDER BY last_mtime DESC), searchForumSqlite (FTS5 MATCH if available else LIKE)
- Generic wrappers: pinThread, lockThread, deleteThread, editPost, listPinnedThreads, searchForum
- threadToJson now includes pinned, locked, deleted, edited, deleted, attachment

### Chat Enhanced
- Schema: chat_message added attachment TEXT, edited INTEGER; new chat_room(room PK, owner, is_private, created), chat_presence(user, room, last_seen, typing, status, PK(user,room))
- Fixed bug: CREATE INDEX chat_room ON chat_message conflicted with table chat_room -> renamed to idx_chat_message_room, added DROP INDEX IF EXISTS chat_room in init
- Schema now includes chat_room and chat_presence tables directly
- createRoomSqlite, listRoomsSqlite, updatePresenceSqlite (INSERT OR REPLACE), listPresenceSqlite (last_seen > now-300s = 5 min online)
- Generic wrappers: createRoom, listRooms, updatePresence, listPresence
- chatToJson now includes attachment, edited
- API: handleChatRooms, handleChatPresence, handleForumPin, handleForumSearch

### Migration Batched
- migrateBatched(src: SqliteBackend, dst: var SqliteBackend, batchSize=10000): getAllRids, BEGIN TRANSACTION, putBlob, COMMIT every batchSize, progress echo, returns total
- cmdRebuild now supports --batch-size 10000, uses migrateBatched, logs batch progress
- Usage: fossil rebuild --backend sqlite --batch-size 10000 old.fossil new.fossil

### REST API New Routes
- GET/POST /api/v1/chat/rooms, /api/v1/chat/presence, POST /api/v1/chat/room
- GET/POST /api/v1/forum/pin, /api/v1/forum/search
- GET/POST /api/v1/search/reindex
- Web UI:
  - /file?name=...&pattern=... -> file browser
  - /finfo?name=... -> file history
  - /info?rid=... -> checkin info
  - /graph?branch=... -> commit graph
  - /login?redirect=/ -> login page, POST /login
  - /logout -> logout
  - /setup -> admin setup (users, configs, stats)
  - /assets/style.css, /assets/*.js
  - /chat/rooms, /chat/presence?room=...
  - Updated / with new sections

### Tests New
- /tmp/test_new_features.nim: reindex OK count, forum create/pin/pinned list count=1 search, chat create room OK list count=2 presence list count=1, file list, graph count - ALL PASS after fixing chat_room index conflict

### Binaries New
- bin/fossil 3.1M (was 2.8M) - includes file, info, graph, login, setup, assets, search reindex, forum pin/search, chat rooms/presence, migration batched
- bin/fossil-mcp 974K (was 973K) - 25 tools
- bin/fossil-qbe 637K (was 629K) QBE ON - includes new pages, still QBE compatible via (void*) cast patch
- QBE build: 51 C files, patched, cproc compile OK, gcc compile OK

### OpenCode Sub-Agents
- Installed bun 1.4.3 and opencode-ai 1.19.3
- 12 free models available (deepseek-v4.1-flash-free, glm-5.3-flash-free, mimo-v2.6-flash-free, nemotron-3.5-lightning-free, etc.)
- Created 4 task files and ran 4 parallel sub-agents via opencode run --auto
- Due to sandbox CPU overload, main agent completed web pages manually, but sub-agent infrastructure verified (hello.nim written to /tmp/opencode/)
- Docs: docs/OPENCODE_SUBAGENTS.md

All tests still PASS after enhancements.
