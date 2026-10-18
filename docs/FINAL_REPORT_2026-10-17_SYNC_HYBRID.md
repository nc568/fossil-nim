# Final Report 2026-10-17 - Hybrid Migration + Sync + Git + Fuzz

## Что было сломано и что починили

### 1. Hybrid Backend Migration — было только blobs, стало ALL TABLES ✅

**Было:**
```nim
proc migrateToHybrid(src, dst):
  for rid in src.getAllRids():
    putBlob(uuid, data) # только blob
```

**Стало:**
```nim
proc copyAllTablesViaAttach(dstSqlite, srcPath):
  ATTACH DATABASE srcPath AS srcDb
  ALTER TABLE ADD COLUMN pinned/locked/deleted/edited/attachment (for old schema migration)
  INSERT OR REPLACE INTO main.config SELECT * FROM srcDb.config
  INSERT OR REPLACE INTO main.event SELECT * FROM srcDb.event
  INSERT OR REPLACE INTO main.filename SELECT * FROM srcDb.filename
  INSERT OR REPLACE INTO main.mlink SELECT * FROM srcDb.mlink
  INSERT OR REPLACE INTO main.tag SELECT * FROM srcDb.tag
  INSERT OR REPLACE INTO main.tagxref SELECT * FROM srcDb.tagxref
  INSERT OR REPLACE INTO main.ticket SELECT * FROM srcDb.ticket
  INSERT OR REPLACE INTO main.forum_thread (with COALESCE fallback for old 5-col -> new 8-col)
  INSERT OR REPLACE INTO main.forum_post (9-col -> 12-col fallback)
  INSERT OR REPLACE INTO main.chat_message (7-col -> 9-col fallback)
  INSERT OR REPLACE INTO main.chat_room, chat_presence, forum_moderation, search_index, delta, blob
  INSERT OR REPLACE INTO main.search_fts SELECT * FROM srcDb.search_fts
  DETACH

proc migrateToHybrid(srcPath, dstPath, kvKind, batchSize):
  Step1: copyAllTablesViaAttach (23 tables)
  Step2: migrate blobs to KV (cdb/lmdb/mdbx) batched 10k
  Step3: verify stats
```

**Тест:**
```bash
fossil init test.fossil
fossil forum create "Test thread" "Hello forum" --user bob --repo test.fossil
fossil chat send "Hello chat" --room main --user bob --repo test.fossil
# src: forum_thread 1, chat_message 1, event 1, blob 2

fossil rebuild --backend hybrid-cdb test.fossil test.hybrid.fossil
# -> Copied 23 tables via ATTACH, 2 blobs to KV, 264K + 2.6K cdbkv

fossil sql "SELECT COUNT(*) FROM forum_thread" --repo test.hybrid.fossil -> 1 OK
fossil sql "SELECT COUNT(*) FROM chat_message" --repo test.hybrid.fossil -> 1 OK
fossil sql "SELECT COUNT(*) FROM event" --repo test.hybrid.fossil -> 1 OK
fossil sql "SELECT COUNT(*) FROM blob" --repo test.hybrid.fossil -> 2 OK
```

**Также исправлен sqlite rebuild:**
```nim
of skSqlite:
  copyAllTablesViaAttach(newDb.db, oldPath) # 23 tables
  migrateBatched(oldDb, newDb) # dedup blobs
```

**Схема обновлена в `storage/schema.nim`:**
- `forum_thread` 5 cols -> 8 cols (pinned, locked, deleted) to match `forum/forum.nim`
- `forum_post` 9 cols -> 12 cols (edited, deleted, attachment)
- `chat_message` 7 cols -> 9 cols (attachment, edited)
- Added `forum_moderation` table

### 2. Clone — было только blobs, стало ALL TABLES ✅

**Было:**
```nim
proc cloneRepo(src, dst):
  for uuid in src.getAllUuids():
    putBlob(uuid, data) # только blob, event 0
```

**Стало:**
```nim
proc cloneRepo(src, dst):
  ATTACH DATABASE src AS srcDb
  ALTER TABLE ADD COLUMN ... (migration)
  INSERT OR REPLACE INTO main.config, event, filename, mlink, tag, tagxref, ticket, forum_thread, forum_post, chat_message, chat_room, chat_presence, forum_moderation, search_index, delta, blob SELECT * FROM srcDb.*
  DETACH
  rebuild search_fts from search_index
  fallback putBlob loop for dedup
```

**Тест:**
```bash
fossil clone repoA.fossil repoB.fossil
# -> Cloned 2 artifacts + 23 tables
sql COUNT(*) FROM event -> 1 OK (было 0)
```

### 3. Sync via HTTP — было односторонний и без событий, стало двухсторонний с восстановлением событий ✅

**Проблемы были:**
- `syncExchangeSqlite` возвращал только file cards (Ls \ Lc), но не gimme для Lc \ Ls -> push не работал (Pushed 0)
- `/xfer` handler импортировал blobs но не создавал event -> после push/pull event count 0 или неполный
- `pullFromUrl` напрямую putBlob без восстановления event -> event не создавался

**Исправления:**

**`sync/protocol.nim`:**
```nim
proc syncExchangeSqlite(localUuids, remoteCards):
  localSet = set(localUuids)
  remoteUuids = set(remoteCards file/igot)
  # Ls \ Lc -> file cards (server -> client, pull)
  for uuid in localUuids:
    if uuid not in remoteUuids: add file card
  # Lc \ Ls -> gimme cards (server asks client, push)
  for card in remoteCards:
    if card.kind==ckIgot and card.uuid not in localSet:
      add gimme card
```

**`api/rest.nim` /xfer handler:**
```nim
# После импорта file cards:
for rid in getAllRids():
  blob = getBlob(rid)
  if looksLikeManifest(blob.data):
    if event not exists for rid:
      parse U, C, R, E from manifest
      INSERT OR IGNORE INTO event(type, mtime, objid, user, comment, branch)
```

**`sync/http.nim`:**
```nim
proc rebuildEventsAfterImport(backend):
  for rid in getAllRids():
    if looksLikeManifest and event not exists:
      INSERT event

proc pullFromUrl:
  после putBlob file cards -> rebuildEventsAfterImport

proc pushToUrl:
  после импорта file cards от сервера -> rebuildEventsAfterImport
  двухфазный: igot -> gimme -> file -> import -> rebuild
```

**Тест двух репозиториев через HTTP (порт 8766):**
```bash
# Repo A: init + commit A (a.txt)
FOSSIL_REPO=repoA.fossil fossil server -P 8766 --api-enable &

fossil clone http://127.0.0.1:8766 repoB.fossil
# Cloned 2 artifacts, event 1 OK, timeline [fafa81d8e0] commit A

# Repo B: commit B (b.txt)
fossil push http://127.0.0.1:8766 --repo repoB.fossil
# Pushed 2 artifacts (было 0)
# repoA: blob 4, event 2, timeline B + A OK

# Repo A: commit A2 (a2.txt)
fossil pull http://127.0.0.1:8766 --repo repoB.fossil
# Pulled 2 artifacts, event 3 OK
# repoB timeline: A2 + A + B OK (3 commits)
```

### 4. Git Export/Import — уже работал, протестирован ✅

```bash
fossil git-export --output export.gitfast --branch trunk --limit 10 --repo test.fossil
# Exported 19 lines, 316 bytes
# blob mark :10000 data 12 hello world
# commit refs/heads/trunk mark :1 author user <user@fossil-nim> ...

fossil init import.fossil
fossil git-import export.gitfast --repo import.fossil
# Imported 1 commits
# event 1, blob 2, timeline OK
```

### 5. Fuzz Tests — NEW ✅

**`tests/test_fuzz.nim`:**
```nim
fuzz_delta: 100 random base/target blobs, deltaCreate + deltaApply roundtrip
  -> passed 100/100

fuzz_manifest: 3 valid manifests with 64-char hex uuids (40 or 64 required)
  -> passed 3/3

fuzz_random_manifest: 100 random printable strings, parseManifest should not crash
  -> passed 100/100 (no crash)

All fuzz tests passed!
```

### 6. All Previous Tests Still PASS ✅

```bash
nim c -r tests/all_tests.nim
# delta roundtrip OK
# manifest parse OK: 1 files
# sqlite backend type OK, cdb backend type OK
# mcp tools count: 49
# hash OK: fc88e0ac...
# diff OK: 5 lines
# All tests passed!

nim c -r tests/test_integration.nim
# Commit1 rid=3 files=2, Timeline count=1, Branches trunk
# Commit2 rid=5, Commit3 rid=7 delta=1 full=2 Delta triggered
# Delta chain OK, Checkout materialization OK
# Delta encode 5000->1063 21% roundtrip OK
# Branch creation OK, Status OK count=3
# All integration tests passed!

nim c -r tests/test_storage_real.nim
# sqlite open OK, putBlob rid=1, getBlob OK, cdb file 2167 bytes
# All real storage tests passed!

nim c -r tests/test_search_forum_chat.nim
# search count=2, forum create/list/get/post reply, chat send/list OK
# All search/forum/chat tests passed!

benchmarks/hybrid_bench.nim
# SQLite 13583 put/s 118807 get/s
# CDB 656989 put/s 292168 get/s
# Hybrid-CDB 10685 put/s 111110 get/s
```

### 7. QBE Binary ✅

- `bin/fossil-qbe` 743K QBE ON from previous build still works: version, help OK
- `build/cgen` 54 C files (was 53) after new code, patched OK
- New QBE link needs NIM_LIB include, but old binary verified OK

### 8. Web Pages — Already Wired ✅

В `api/rest.nim` уже есть wiring для:
- `/stat` -> `extPagesMod.getRepoStatsSqlite` + `renderStatPage`
- `/reportlist` -> `getReportListSqlite` + `renderReportlistPage`
- `/report?id=1` -> `getTicketsForReportSqlite` + `renderReportPage`
- `/attach` / `/attachlist` -> `getAttachmentsSqlite` + `renderAttachPage`
- `/rss` / `/timeline.rss` -> `getTimelineForRssSqlite` + `renderRssPage`
- `/whistory` / `/wcontent` -> `getWikiHistorySqlite` + `renderWikiHistoryPage` / `renderWikiContentPage`
- `/leaves` -> `getLeavesSqlite` + `renderLeavesPage`
- `/zip` / `/tarball` -> real ZIP STORE + TAR USTAR binary (373 bytes test)

### Binaries 2026-10-17 11:55

- `bin/fossil` 2.0M 105628 lines refc, QBE OFF, version 2.26.0-nim
- `bin/fossil-mcp` 1.2M 49 tools (from previous)
- `bin/fossil-qbe` 743K QBE ON

### Что осталось (P2)

- Benchmark graphs in docs (bench numbers ready, need gnuplot or markdown tables)
- Contributing guide, fuzz in CI, two-repo sync via CLI `fossil sync` already works via http.nim
- Migration for pure KV backends (cdb/lmdb/mdbx) still only blobs, not relational - documented as limitation, hybrid solves it
- Web login/setup CSRF polish
- Full 50+ Fossil pages: we have ~30, extended_pages covers remaining, but need more wiring like /tinfo, /winfo etc (minor)
- QBE link with new 54 files: need to update Makefile to include NIM_LIB path for cproc

### Итог

- ✅ Hybrid migration теперь копирует 23 таблицы + blobs в KV (было только blobs)
- ✅ Clone теперь копирует все таблицы через ATTACH (было только blobs, event 0)
- ✅ Sync HTTP теперь двухсторонний: gimme/file + восстановление событий из манифестов
- ✅ Git export/import протестирован: export 316 bytes, import 1 commit OK
- ✅ Two-repo sync через HTTP: clone OK, push 2 artifacts OK, pull 2 artifacts OK, timeline 3 commits OK
- ✅ Fuzz tests: delta 100/100, manifest 3/3, random no crash 100/100
- ✅ All previous tests still PASS
- ✅ QBE binary 743K still works
- ✅ Web pages /stat /reportlist /leaves /rss etc already wired
