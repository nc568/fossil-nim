# Final Report 2026-10-17 Evening 2 — Full Fix + QBE + Docs

## Выполнено сегодня (продолжение)

### 1. Исправлен Hybrid Migration (ALL TABLES)

**Файл:** `src/fossil/storage/hybrid_backend.nim`

- `copyAllTablesViaAttach` теперь копирует 23 таблицы через ATTACH DATABASE:
  - config, event, filename, mlink, tag, tagxref, user, private, shun, backlink, unclustered, audit, ticket, ticketchng, forum_thread, forum_post, chat_message, chat_room, chat_presence, forum_moderation, search_index, delta, blob
- Добавлены ALTER TABLE ADD COLUMN для миграции старой схемы:
  - forum_thread: pinned, locked, deleted
  - forum_post: edited, deleted, attachment
  - chat_message: attachment, edited
  - CREATE forum_moderation если нет
- Fallback с COALESCE для несовместимых колонок (5-col -> 8-col, 9-col -> 12-col, 7-col -> 9-col)
- Убран vvar из списка (checkout-only, не repo)

**Тест:**
```bash
fossil init test.fossil
fossil forum create "Test" "Hello" --user bob --repo test.fossil
fossil chat send "Hi" --room main --user bob --repo test.fossil
# src: forum_thread 1, chat_message 1, event 1, blob 2

fossil rebuild --backend hybrid-cdb test.fossil test.hybrid.fossil
# Step1: Copying relational tables via ATTACH... Copied 22 tables via ATTACH
# Copied blob table via SQL ATTACH
# Step2: Migrating blobs to KV... 2 blobs
# Migration complete: src 2 artifacts, dst 2 artifacts, 2 blobs migrated to KV
# dst: forum_thread 1 OK, forum_post 1 OK, chat_message 1 OK, event 1 OK, blob 2 OK

fossil rebuild --backend sqlite test.fossil test.sqlite.rebuilt
# Copied 22 tables via ATTACH + 2 blobs, forum_thread 1 OK, chat_message 1 OK, event 1 OK
```

**Схема `storage/schema.nim`:**
- forum_thread 5 -> 8 cols (pinned, locked, deleted) to match forum.nim
- forum_post 9 -> 12 cols (edited, deleted, attachment)
- chat_message 7 -> 9 cols (attachment, edited)
- Добавлен forum_moderation

### 2. Clone — ALL TABLES

**Файл:** `src/fossil/sync/protocol.nim`

Было только blobs -> event 0. Стало через ATTACH 23 таблицы + rebuild search_fts + fallback putBlob.

```bash
fossil clone repoA.fossil repoB.fossil
# Cloned 2 artifacts + 23 tables, event 1 OK (было 0)
```

### 3. Sync HTTP двухсторонний + восстановление событий

**Файлы:** `sync/protocol.nim`, `sync/http.nim`, `api/rest.nim`

**syncExchangeSqlite:**
- Было: только Ls\Lc file cards -> push 0 artifacts
- Стало: Ls\Lc file cards (pull) + Lc\Ls gimme cards (push запрос)

**/xfer handler в rest.nim:**
- После импорта file cards -> итерация всех rids, если blob похож на манифест (C/D/U/R/E) и event не существует -> INSERT event

**http.nim:**
- `rebuildEventsAfterImport` — восстанавливает missing events из манифестов
- `pullFromUrl`: после putBlob file cards -> rebuildEvents
- `pushToUrl`: двухфазный igot -> gimme -> file -> import -> rebuild, также rebuild после импорта от сервера

**Тест 8766:**
```bash
Repo A commit A -> server -P 8766
fossil clone http://127.0.0.1:8766 repoB.fossil # Cloned 2 artifacts, event 1 OK, timeline commit A OK (было 0)
Repo B commit B -> push # Pushed 2 artifacts (было 0), repoA event 2 OK, timeline B+A OK
Repo A commit A2 -> pull in B # Pulled 2 artifacts, event 3 OK (было 2), timeline A2+A+B OK
```

### 4. Git Export/Import — протестирован

```bash
fossil git-export --output export.gitfast --limit 10 --repo test.fossil # 316 bytes, 19 lines
fossil init import.fossil; fossil git-import export.gitfast --repo import.fossil # Imported 1 commits, event 1 OK
```

### 5. Fuzz Tests — NEW

`tests/test_fuzz.nim`:
- fuzz_delta 100 random base/target -> deltaCreate+Apply roundtrip 100/100 OK
- fuzz_manifest 3 valid 64-char hex uuid (40 или 64 требуется) -> 3/3 OK
- fuzz_random_manifest 100 random printable -> no crash 100/100 OK

### 6. Web Pages — уже wired, протестированы 8767

```bash
FOSSIL_REPO=test.fossil fossil server -P 8767 --api-enable &
curl / -> Full Parity home 200 OK
curl /stat -> 3672 bytes 200 OK (RepoStats)
curl /reportlist -> 2461 bytes 200 OK
curl /leaves -> 1387 bytes 200 OK
curl /rss -> 520 bytes 200 OK RSS 2.0
curl /help -> 6522 bytes 200 OK
curl /zip?branch=trunk -> 144 bytes 200 OK real ZIP STORE
curl /api/v1/status -> JSON ok branch trunk
```

Все 40+ страниц уже в `rest.nim`: /timeline, /file, /finfo, /info, /graph, /diff, /blame, /tree, /brlist, /taglist, /zip, /tarball, /raw, /stat, /reportlist, /report, /attach, /attachlist, /rss, /timeline.rss, /wcontent, /whistory, /leaves, /wiki/*, /ticket/*, /forum/*, /chat/*, /search, /login, /setup, /help, /sitemap, /markdown, /th1, /assets/*, /js/*, /css/*

### 7. Makefile + QBE

**Makefile:**
- build: теперь `chmod +x bin-tools/*` + `refc threads:off` + `chmod +x bin/*` + ls -lh
- qbe: использует `CPROC=bin-tools/cproc`, `QBE=bin-tools/qbe`, `NIM_LIB` для nimbase.h, 54 C файла
- test: теперь все тесты + hybrid_bench
- test-full: + test_sync.nim

**QBE Build 2026-10-17 14:27:**
```bash
make build-qbe-c # 54 C files, 83123 lines Nim, Patched 54 files
make qbe # cproc -O2 -DQBE_COMPAT=1 -Ibuild/cgen -Icinterop/include -I.../lib -o bin/fossil-qbe build/cgen/*.c ... -lsqlite3 -lz -lm -lcrypto -lssl
# Built bin/fossil-qbe 776K (was 743K)
./bin/fossil-qbe version # QBE ON OK
./bin/fossil-qbe help | head # Usage OK
```

**Binaries:**
- bin/fossil 2.0M 105628 lines refc 14:26:11 QBE OFF
- bin/fossil-mcp 998K 94526 lines refc 49 tools
- bin/fossil-qbe 776K 54 C files QBE ON 14:27:33

### 8. Docs

- `CONTRIBUTING.md` NEW — архитектура модульная, сборка, тесты, стиль, добавление фичи, бэкенды, QBE, MCP, документация
- `docs/BENCHMARKS.md` NEW — таблицы SQLite/CDB/Hybrid, ASCII графики, delta 21%, archive, sync, web, QBE размеры
- `docs/FULL_DOCUMENTATION_RU.md` — добавлен раздел "Фиксы 2026-10-17 14:30" с hybrid all tables, clone all tables, sync двухсторонний, git, fuzz, web тест, binaries

### Тесты — ALL PASS

```bash
all_tests.nim: delta roundtrip OK, manifest 1 file, sqlite/cdb type OK, mcp 49 tools, hash fc88e0ac, diff 5 lines -> All passed
test_fuzz.nim: fuzz_delta 100/100, fuzz_manifest 3/3, random no crash 100/100 -> All fuzz passed
test_integration.nim: commit1 rid3, timeline 1, commit2 big 5000, commit3 delta 1 full2 21%, chain verified, checkout OK -> All integration passed
test_storage_real.nim: sqlite + cdb 2167 bytes OK
test_search_forum_chat.nim: search 2, forum thread, chat OK
hybrid_bench.nim: SQLite 18318 put/s 130k get/s, CDB 719k put/s 266k get/s, Hybrid 17235 put/s 129k get/s
fossil-qbe version QBE ON OK, fossil version QBE OFF OK
```

### Что осталось (P2, minor)

- Benchmark графики gnuplot (таблицы готовы, можно добавить png)
- Больше веб-страниц /tinfo (alias для /ticket), /winfo (alias для /wiki), /wdiff — minor, 90% уже есть
- CSRF для login/setup — minor
- Pure KV backends (cdb/lmdb/mdbx) только blobs — documented limitation, hybrid решает
- CONTRIBUTING уже DONE, BENCHMARKS DONE, FULL_DOCUMENTATION_RU DONE

### Итог Evening 2

- ✅ Hybrid migration 22 таблицы + blobs в KV (было только blobs, vvar убран)
- ✅ Clone ALL TABLES через ATTACH (было только blobs)
- ✅ Sync HTTP двухсторонний gimme/file + восстановление событий из манифестов (clone, push, pull все OK)
- ✅ Git export/import OK (316 bytes, 1 commit)
- ✅ Two-repo sync via HTTP: clone 2 artifacts event1, push 2 artifacts event2, pull 2 artifacts event3, timeline 3 commits OK
- ✅ Fuzz tests: delta 100/100, manifest 3/3, random no crash 100/100
- ✅ Web /stat /reportlist /leaves /rss /help /zip 200 OK, 40+ страниц wired
- ✅ Makefile обновлён: chmod +x, refc, test-all, QBE с NIM_LIB, 54 C файла
- ✅ QBE binary пересобран 776K QBE ON version/help OK (was 743K)
- ✅ Binaries 2.0M + 998K + 776K, all tests PASS, docs CONTRIBUTING + BENCHMARKS + FULL_DOCUMENTATION_RU
