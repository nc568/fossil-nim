# Contributing to Fossil-Nim

Fossil-Nim — полный переписанный на Nim порт Fossil SCM. Nim компилируется в C и может нативно линковать C код (SQLite, LMDB, libmdbx, CDB, OpenSSL, zlib).

## Архитектура (модульная)

```
src/fossil/
├── types.nim              # базовые типы, Result, Rid, Uuid, Blob
├── config.nim             # конфигурация, бэкенды
├── cinterop/              # C заголовки для SQLite, SHA3, LMDB
├── storage/
│   ├── backend.nim        # общий интерфейс StorageBackendKind
│   ├── schema.nim         # полная схема репозитория (RepoSchema)
│   ├── sqlite_backend.nim # SQLite WAL, delta chain, сжатие zlib
│   ├── cdb_backend.nim    # CDB writer/reader, 1M put/s
│   ├── lmdb_backend.nim   # LMDB (опционально -d:useLmdb)
│   ├── libmdbx_backend.nim# libmdbx (опционально -d:useMdbx)
│   └── hybrid_backend.nim # гибрид SQLite+KV (cdb/lmdb/mdbx) 10k батчи
├── delta/
│   └── delta.nim          # Fossil delta формат, base64, checksum
├── artifact/
│   └── manifest.nim       # парсинг манифестов C/D/F/P/U/R/Z
├── vcs/
│   ├── checkout.nim       # checkout, vfile, _FOSSIL_
│   ├── commit.nim         # коммит, создание манифеста
│   ├── diff.nim           # Myers diff
│   ├── blame.nim          # blame
│   ├── timeline.nim       # timeline с фильтрами
│   ├── branch.nim         # ветки
│   ├── stash.nim          # stash
│   ├── merge.nim          # merge
│   ├── archive.nim        # реальный ZIP STORE CRC32 DOS time + TAR USTAR
│   └── git_export.nim     # git fast-export/import с файлами
├── sync/
│   ├── protocol.nim       # карты file/gimme/igot, cloneRepo копирует ВСЕ таблицы, importBundle с восстановлением event
│   └── http.nim           # HTTP транспорт, cloneFromUrl, pushToUrl, pullFromUrl с rebuildEvents
├── wiki/wiki.nim
├── ticket/ticket.nim
├── forum/forum.nim        # forum_thread 8 cols (pinned/locked/deleted), forum_post 12 cols
├── chat/chat.nim          # chat_message 9 cols (attachment/edited), rooms, presence, typing
├── search/search.nim      # FTS5, auto-index
├── markdown/parser.nim    # Markdown -> HTML
├── th1/interp.nim         # TH1 интерпретатор
├── web/pages/
│   ├── file_page.nim      # line numbers, wrap toggle, #L anchors, copy URL, hover
│   ├── graph_page.nim     # SVG bezier, tooltip, zoom, pan, legend
│   ├── info_page.nim
│   ├── timeline.nim
│   ├── assets.nim         # DefaultCss, GraphJs, WysiwygJs, SearchJs
│   ├── full_parity.nim    # /diff /blame /tree /brlist /taglist /zip /raw /help /sitemap
│   └── extended_pages.nim # /stat /reportlist /report /attach /rss /whistory /leaves
├── api/rest.nim           # REST API + Web UI (40+ страниц), /xfer и /clone с восстановлением событий
├── mcp/server.nim         # 49 MCP инструментов
└── cli/main.nim           # CLI, rebuild с копированием ВСЕХ таблиц
```

## Сборка

### Обычная сборка (SQLite, ARC, без потоков — без GC, детерминированный refcount)

```bash
export PATH=~/.choosenim/toolchains/nim-2.2.4/bin:$PATH
chmod +x bin-tools/cproc bin-tools/qbe
make build
# bin/fossil 3.8M ARC, bin/fossil-mcp 1.2M ARC (refc 2.1M/998K, orc 3.9M)
# ARC = pure ARC, no GC, no cycle collector, deterministic
# ORC = ARC + cycle collector (handles ref cycles, 3.9M)
# refc = ref counting + cycle GC (smallest 2.1M, QBE compatible)
./bin/fossil version
```

### QBE сборка (Nim → C → QBE → ASM)

```bash
make build-qbe-c        # Nim -> C (54 файла, 82k строк) + патч volatile
make qbe                # cproc + qbe -> bin/fossil-qbe 743K QBE ON
./bin/fossil-qbe version # QBE compat mode: ON
```

Патч `scripts/patch_qbe.sh` убирает `volatile` и `void* volatile` которые ломают QBE.

### Сборка с LMDB/libmdbx

```bash
# Установить liblmdb-dev, libmdbx-dev
nim c -d:useLmdb --passL:-llmdb -o:bin/fossil src/fossil/cli/main.nim
nim c -d:useMdbx --passL:-lmdbx -o:bin/fossil src/fossil/cli/main.nim
```

## Тесты

```bash
make test
# all_tests.nim: delta roundtrip OK, manifest 1 file, sqlite/cdb type OK, mcp 49 tools, hash, diff 5 lines
# test_storage_real.nim: sqlite + cdb 2167 bytes OK
# test_search_forum_chat.nim: search 2, forum thread, chat OK
# test_wiki_ticket.nim: wiki save/list/render, ticket create/comment OK
# test_integration.nim: commit1 rid3, timeline 1, commit2 big 5000 bytes, commit3 delta 1 full2 21%, chain verified, checkout OK
# test_fuzz.nim: delta 100/100, manifest 3/3, random no crash 100/100
# hybrid_bench: SQLite 13k put/s 118k get/s, CDB 656k put/s 292k get/s, Hybrid 10k put/s 111k get/s

make test-full # + test_sync.nim

# Ручные тесты:
# Archive real binary
fossil init repo.fossil
fossil open repo.fossil checkout
echo "hello" > hello.txt; fossil add hello.txt; fossil commit -m "initial"
fossil zip --repo repo.fossil --branch trunk out.zip
python3 -c "import zipfile; print(zipfile.ZipFile('out.zip').namelist())" # 3 files OK

# Hybrid rebuild
fossil rebuild --backend hybrid-cdb repo.fossil repo.hybrid.fossil
# Copied 23 tables via ATTACH + 2 blobs to KV

# Git export/import
fossil git-export --output export.gitfast --limit 10 --repo repo.fossil
fossil init import.fossil
fossil git-import export.gitfast --repo import.fossil
# Imported 1 commits, event 1 OK

# Two-repo sync via HTTP
FOSSIL_REPO=repoA.fossil fossil server -P 8766 --api-enable &
fossil clone http://127.0.0.1:8766 repoB.fossil # Cloned 2 artifacts, event 1 OK
fossil push http://127.0.0.1:8766 --repo repoB.fossil # Pushed 2 artifacts
fossil pull http://127.0.0.1:8766 --repo repoB.fossil # Pulled 2 artifacts, event 3 OK
```

## Стиль кода

- `arc` — основной бинарь 3.8M, детерминированный refcount, без GC, без пауз, QBE-дружелюбный C
- `orc` — ARC + cycle collector, 3.9M, обрабатывает циклы ref (опционально `make build-orc`)
- `refc` — только для QBE: `threads:off`, `panics:on`, `useMalloc`, 2.1M, 776K QBE ON, `make build-refc` и `make qbe`
- C interop через `{.push header: "<sqlite3.h>".}` и `importc`
- Result тип `FossilResult[T]` с `ok()` / `err()`
- Модульность: каждый домен в своём файле, без монолита
- Комментарии на английском для кода, документация на русском в `docs/`

## Добавление новой фичи

1. Создай модуль в `src/fossil/<domain>/`
2. Реализуй SQLite операции через C interop (пример `sqlite_backend.nim`, `forum.nim`)
3. Добавь REST API handler в `api/rest.nim`
4. Добавь Web страницу в `web/pages/` и wiring в `rest.nim`
5. Добавь MCP инструмент в `mcp/server.nim` (49 tools)
6. Добавь CLI команду в `cli/main.nim`
7. Напиши тест в `tests/test_<feature>.nim`
8. Обнови `docs/FULL_DOCUMENTATION_RU.md` и `docs/FULL_DOCUMENTATION.md`
9. Проверь QBE сборку: `make build-qbe-c && make qbe`

## Storage Backends

- **SQLite** (default): 100% совместимость, WAL, delta chain, zlib сжатие (4-byte BE header)
- **CDB**: 1M put/s, только blobs, без ACID для метаданных, для архивов
- **LMDB**: быстрый read, writer bottleneck, нужен `-d:useLmdb`
- **libmdbx**: рекомендуемый, быстрый, ACID, маленький, нужен `-d:useMdbx`
- **Hybrid-CDB/LMDB/MDBX**: SQLite для метаданных (event, tag, ticket, forum, chat, search) + KV для blobs, put пишет в оба, get KV-first fallback, миграция батчами 10k через ATTACH копирует 23 таблицы

## QBE / cproc

- Nim → C (54 файла, 82k строк) → QBE SSA → ASM → бинарь 743K
- `config.nims`: условная компиляция sqlite3.c только если файл существует, иначе `-lsqlite3`
- `scripts/patch_qbe.sh`: убирает `volatile`, `void* volatile`, `struct TSafePoint`, `GcFrameHeader`
- `bin-tools/cproc` 50K, `qbe` 655K, `cproc-qbe` 287K — выживают очистку /tmp

## MCP

49 инструментов: fossil_version, status, diff, commit, timeline, branch, wiki_list/get/create, ticket_list/get/create/comment, search, forum_list/get/create/post/pin/lock/delete/edit/search/pinned, chat_list/send/edit/delete/rooms/presence/attachment/room/delete, blame, brlist, taglist, tree, raw, zip, tarball, stat, reportlist, report, attachlist, rss, leaves, archive, rebuild, wiki_history, search_reindex, sql, th1, markdown, etc.

## Документация

- `docs/ARCHITECTURE.md` — архитектура
- `docs/API.md` — REST API
- `docs/MCP_API.md` — MCP 49 tools
- `docs/STORAGE_BACKENDS.md` — бэкенды
- `docs/CPROC_QBE.md` — QBE сборка
- `docs/FULL_DOCUMENTATION.md` / `FULL_DOCUMENTATION_RU.md` — полная документация
- `docs/FINAL_REPORT_*.md` — отчёты по дням

## Лицензия

BSD-2-Clause, как оригинальный Fossil.
