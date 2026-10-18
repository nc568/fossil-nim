# Gap Analysis - Что осталось сделать для полного порта Fossil

Дата: 2026-10-01
Текущий статус: ~15% ядра портировано, каркас и инфраструктура готовы, тесты и QBE работают.

## 1. Оригинальный Fossil - состав

По данным https://fossil-scm.org/home/dir?ci=trunk&name=src, в src/ ~150 файлов C:

**Ядро VCS (критично):**
- `add.c` (38k), `checkout.c` (21k), `checkin.c` (121k), `branch.c` (40k), `merge.c` (57k), `merge3.c` (38k), `diff.c` (131k), `diffcmd.c` (50k), `bisect.c` (22k), `blame.c`? часть `finfo.c` (35k), `stash.c`? часть `checkin.c`, `leaf.c` (8k), `descendants.c` (22k), `tag.c`? часть `manifest.c`, `undo.c`? `purge.c` (23k), `clean.c`? часть `add.c`, `revert.c`?

**Хранение:**
- `db.c` (187k) - обертки SQLite, самая большая, `blob.c` (58k), `delta.c` (22k), `deltacmd.c` (5k), `deltafunc.c` (16k), `content.c` (39k), `shun.c`?, `schema.c` (26k), `rebuild.c` (48k)

**Синхронизация:**
- `clone.c` (14k), `http.c` (34k), `http_socket.c` (6k), `http_ssl.c` (38k), `http_transport.c` (15k), `xfer.c`? часть `http.c`, `export.c` (60k), `import.c` (67k), `bundle.c` (26k)

**Веб UI (огромный):**
- `cgi.c` (96k), `web.c`? `dispatch.c` (60k), `browse.c` (39k), `info.c` (147k), `timeline.c`? часть `event.c` (19k), `graph.c` (35k), `diff.tcl`? но C часть, `file.c` (91k), `doc.c` (49k), `wiki.c`? `wikiform.c`?, `search.c` (91k), `setup.c` (93k), `login.c` (97k), `json.c` (77k) + `json_*.c` (10 файлов по 10-20k), `chat.c` (51k), `forum.c` (103k), `ticket.c`? `report.c` (42k), `attach.c` (61k), `backlink.c` (15k), `captcha.c` (21k), `moderate.c` (11k)

**Подсистемы:**
- `wiki.c`, `ticket.c`, `forum.c`, `chat.c`, `search.c`, `attach.c`, `report.c`

**Утилиты:**
- `blob.c`, `bag.c` (5k), `file.c`, `path.c` (22k), `glob.c` (8k), `match.c` (14k), `encode.c` (23k), `gzip.c` (3k), `md5.c` (14k), `sha1.c` (16k), `sha3.c`?, `th1.c`? (Tcl), `markdown.c` (86k), `markdown_html.c` (30k), `pikchrshow.c` (22k), `comformat.c` (31k), `printf.c` (42k), `regexp.c` (36k), `color.c` (17k)

**Всего:** ~2.5M строк C без SQLite, ~3.5M с SQLite.

## 2. Что портировано в Fossil-Nim (текущий)

| Модуль Nim | Оригинал C | Статус | Покрытие |
|------------|------------|--------|----------|
| `types.nim` | `blob.c` часть | ✅ Done | 100% базовых типов |
| `config.nim` | `configure.c` часть | ✅ Done | 70% |
| `storage/backend.nim` | - | ✅ Done | Интерфейс |
| `storage/sqlite_backend.nim` | `db.c` + `blob.c` | 🟡 Partial | 30%: put/get/has, initSchema, meta, но нет deltaChain, event, tag, mlink, etc. |
| `storage/libmdbx_backend.nim` | - | 🟡 Partial | 40%: open/close/put/get, но нет курсора, итерации, links, meta nextRid |
| `storage/lmdb_backend.nim` | - | 🟡 Partial | 40% аналогично |
| `storage/cdb_backend.nim` | - | 🟡 Partial | 30%: pure Nim, writer stub, reader только cdbFind, нет hash table |
| `delta/delta.nim` | `delta.c` | 🟡 Partial | 60%: encode/decode/apply работают, но create - naive greedy, не rolling hash как оригинал, не оптимальный размер |
| `artifact/manifest.nim` | `manifest.c` | 🟡 Partial | 50%: парсит C,D,F,P,U,B,T,Z,R, но нет Q,W,checksum валидации, R/R-card integrity |
| `artifact/artifact.nim` | `content.c` | 🟡 Partial | 30%: resolve stub, нет delta chain |
| `vcs/checkout.nim` | `checkout.c` | 🔴 Stub | 10%: find root, status dummy, нет vfile, vvar, materialize |
| `vcs/commit.nim` | `checkin.c` | 🟡 Partial | 30%: build manifest, put blob, но нет delta vs parent, нет hooks, нет vfile |
| `vcs/diff.nim` | `diff.c` | 🟡 Partial | 40%: LCS naive, не Myers, нет word diff, нет binary diff полностью |
| `vcs/branch.nim` | `branch.c` | 🟡 Partial | 20%: dummy list |
| `vcs/timeline.nim` | `event.c` | 🟡 Partial | 20%: dummy entries |
| `vcs/merge.nim` | `merge.c` + `merge3.c` | 🟡 Partial | 30%: 3-way с маркерами, нет file-level merge |
| `vcs/stash.nim` | часть `checkin.c` | 🟡 Partial | 20%: save/list/apply/drop stubs |
| `vcs/blame.nim` | `finfo.c` часть | 🟡 Partial | 20%: dummy blame |
| `vcs/add.nim` | `add.c` | 🟡 Partial | 40%: add/rm/rename файлы, но нет vfile таблицы |
| `sync/protocol.nim` | `http.c` часть | 🟡 Partial | 30%: parse file/gimme/igot/cookie, нет полного state machine |
| `sync/http.nim` | `http_transport.c` | 🟡 Partial | 20%: postXfer/getClone via httpclient |
| `web/server.nim` | `cgi.c` + `dispatch.c` | 🟡 Partial | 20%: 2 маршрута, нет 50 страниц |
| `web/router.nim` | `dispatch.c` | ✅ Done | 80% базовый роутер |
| `wiki/wiki.nim` | `wiki.c` | 🟡 Partial | 20% |
| `ticket/ticket.nim` | `ticket.c` | 🟡 Partial | 20% |
| `forum/forum.nim` | `forum.c` | 🟡 Partial | 10% |
| `api/rest.nim` | `json.c` + `json_*.c` | 🟡 Partial | 30%: 6 маршрутов, placeholder |
| `mcp/tools.nim` | - | ✅ Done | 100%: 13 инструментов с JSON Schema |
| `mcp/server.nim` | - | 🟡 Partial | 60%: JSON-RPC работает, initialize/tools/list/resources, но tool handlers dummy (не вызывают реальный VCS) |
| `cli/main.nim` | `main.c` | 🟡 Partial | 50%: dispatcher, init с реальной схемой, status/diff/timeline stubs |
| `cli/main_qbe.nim` | - | ✅ Done | 100% QBE minimal, 12 C файлов, чистый C11, 67K binary, работает |
| `utils/hash.nim` | `sha1.c` + `sha3.c` | ✅ Done | 90%: OpenSSL EVP, для QBE sh3.c import, но sh3.c не вендорен |
| `utils/compress.nim` | `gzip.c` | ✅ Done | 80%: zlib wrapper, для QBE no-op |
| `db/c_interop.nim` | - | 🟡 Partial | 20%: только sqlite3 и zlib |

**Итого:** ~38 модулей Nim, ~4000 строк, покрывают ~15% функционала C Fossil, но инфраструктура (модульность, бэкенды, MCP, API, QBE) готова на 80%.

## 3. Что осталось - детальный список

### Критичный путь для MVP (чтобы fossil-nim мог заменить C fossil для базового использования)

#### A. Хранение (Storage) - 40% осталось
- [ ] Реализовать `deltaChain(rid)` - чтение цепочки дельт из таблицы delta
- [ ] Реализовать `getManifest(rid)` - парсинг манифеста из blob
- [ ] Реализовать курсор итерацию для libmdbx/lmdb: `getAllRids`, `getAllUuids` сейчас возвращают пусто
- [ ] Реализовать `links` DBI для DAG (parent->child)
- [ ] Реализовать `meta` nextRid загрузку/сохранение (сейчас всегда 1)
- [ ] Реализовать `putDelta` - хранение дельты с ссылкой на srcRid
- [ ] Реализовать `rebuild` команду: конвертация sqlite -> libmdbx/lmdb/cdb и обратно, с батчами и транзакциями
- [ ] Бенчмарки: сравнить все бэкенды на 1M артефактов
- [ ] Вендорить `mdbx.c` (1 файл) и `lmdb` (`mdb.c` + `midl.c`) и `sqlite3.c` амальгаму для static QBE сборки

#### B. Дельта - 40% осталось
- [ ] Реализовать оригинальный алгоритм rolling hash из `delta.c` (хеш-таблица 4-байтовых последовательностей) для оптимального размера дельты
- [ ] Реализовать `deltaOutputSize` точно как оригинал
- [ ] Тест vs оригинальный fossil binary: `fossil delta` и `fossil undelta` roundtrip на 1000 случайных файлах
- [ ] Поддержка checksum в дельте

#### C. Артефакты - 70% осталось
- [ ] Полный парсер манифестов: все карты `B`, `C`, `D`, `F`, `J`, `K`, `L`, `M`, `N`, `P`, `Q`, `R`, `T`, `U`, `W`, `Z` с валидацией
- [ ] Проверка `Z` checksum (SHA3)
- [ ] Поддержка `cluster` артефактов (сжатая группа)
- [ ] `artifact.nim`: реализовать `resolveBlob` с delta chain: найти базовый blob, применить цепочку дельт
- [ ] Хеширование: вендорить `sh3.c` из Fossil (чистый C, QBE-совместим) для QBE сборки

#### D. VCS Core - 80% осталось
- [ ] `checkout.nim`: 
  - Чтение `_FOSSIL_` / `.fslckout` - это SQLite с таблицами `vvar`, `vfile`, `vlink`
  - `vfile` - список файлов в checkout, с rid, chnged, deleted
  - Материализация файлов: для каждого файла найти blob, резолвить delta chain, записать на диск с правильными правами
  - Обработка симлинков, исполняемых бит
  - `checkout.c` 21k LOC -> нужно портировать ~5k Nim
- [ ] `commit.nim`:
  - Сканировать рабочее дерево с учетом ignore globs (уже есть `add.nim`)
  - Сравнивать с `vfile` чтобы найти modified/added/deleted
  - Для каждого modified файла вычислить дельту vs parent, решить хранить как full или delta (эвристика оригинала: если delta < 70% full, хранить delta)
  - Построить манифест, вычислить SHA3, вставить в storage
  - Обновить `vfile` и `event` таблицы
  - Поддержка `allowEmpty`, `private`, `branch`, `baseline`, `message`
- [ ] `add.nim`:
  - Интеграция с `vfile` таблицей, а не только файловой системой
  - Поддержка `fossil addremove`
- [ ] `branch.nim`:
  - Реальная реализация через таблицу `tag`: `SELECT name FROM tag WHERE type='branch'`
  - `createBranch`: вставить tag артефакт
  - `closeBranch`: `sym-branch` -> `closed`
- [ ] `timeline.nim`:
  - Запрос к `event` таблице: `SELECT uuid, comment, user, mtime, branch FROM event ORDER BY mtime DESC LIMIT ?`
  - Фильтры по branch, user, since, file (через `mlink`)
  - Граф: `graph.c` 35k -> нужен алгоритм построения графа чекинов
- [ ] `diff.nim`:
  - Реализовать Myers diff (оригинал `diff.c` 131k)
  - Поддержка `diff --binary`, `diff --tk`, `diff --from --to`
  - Word diff
- [ ] `merge.nim`:
  - Портировать `merge3.c` 38k - 3-way merge файлов
  - Обработка конфликтов с маркерами `<<<<<<<`
  - `fossil merge --integrate`
- [ ] `stash.nim`:
  - Хранение stash как артефакт типа `stash`?
  - `saveStash`: вычислить diff рабочего дерева, сохранить как blob, добавить в stash таблицу
  - `applyStash`: применить diff
- [ ] `blame.nim`:
  - Для каждой строки файла найти чекин где она появилась: пройти timeline файла, для каждого чекина diff
  - Оригинал использует `finfo.c` и `annotate`
- [ ] Новые модули:
  - `bisect.nim` (22k) - бинарный поиск бага
  - `clean.nim` - удаление extra файлов
  - `revert.nim` - откат
  - `undo.nim` - undo
  - `tag.nim` - теги
  - `leaf.c` -> `leaf.nim` - поиск листьев
  - `descendants.c` -> `descendants.nim`

#### E. Синхронизация - 70% осталось
- [ ] Полный протокол xfer: карты `cookie`, `file`, `gimme`, `igot`, `clone`, `push`, `pull`, `login`, `error`
- [ ] State machine: клиент отправляет `gimme` для отсутствующих, сервер отвечает `file`, и наоборот
- [ ] `http.c` 34k + `http_transport.c` 15k -> портировать HTTP клиент/сервер с поддержкой прокси, SSL, auth
- [ ] `clone.c` 14k - клонирование репо
- [ ] `bundle.c` 26k - bundle import/export
- [ ] `export.c` 60k + `import.c` 67k - git fast-export/import
- [ ] Тест: sync два репо через `xfer`

#### F. Веб UI - 90% осталось (самый большой)
- [ ] `cgi.c` 96k - CGI парсинг, cookie, login
- [ ] `dispatch.c` 60k - роутер всех страниц
- [ ] Портировать 50+ страниц:
  - `timeline.c` -> `pages/timeline.nim` (уже есть stub, нужен полный HTML + graph.js)
  - `info.c` 147k -> `pages/info.nim`
  - `file.c` 91k -> `pages/file.nim` + `pages/dir.nim`
  - `diff` страницы
  - `wiki.c` -> `pages/wiki.nim` (история, редактирование, WYSIWYG)
  - `ticket.c` + `report.c` -> `pages/ticket.nim`
  - `forum.c` 103k -> `pages/forum.nim`
  - `chat.c` 51k -> `pages/chat.nim`
  - `search.c` 91k -> `pages/search.nim`
  - `setup.c` 93k -> `pages/setup.nim`
  - `login.c` 97k -> `pages/login.nim`
  - `json.c` 77k + `json_*.c` 10 файлов -> уже есть `api/rest.nim` базовый, нужен полный JSON API как в оригинале
- [ ] TH1 интерпретатор: мини Tcl, 2000 LOC C, нужен для шаблонов wiki/ticket
  - Портировать как `web/th1.nim` - интерпретатор TH1
- [ ] Markdown: `markdown.c` 86k + `markdown_html.c` 30k -> портировать как `web/markdown.nim`
- [ ] `graph.c` 35k + `graph.js` 30k - граф чекинов
- [ ] Статика: `default.css` 51k, `*.js` 20 файлов
- [ ] `captcha.c` 21k - капча для анонимных
- [ ] `security_audit.c` 38k

#### G. Подсистемы - 80% осталось
- [ ] Wiki: полная реализация с историей, diff, search, attachments (`attach.c` 61k)
- [ ] Ticket: TH1 формат тикетов, кастомные поля, reports, timeline
- [ ] Forum: треды, посты, модерация (`moderate.c` 11k), подписки
- [ ] Chat: комнаты, сообщения, notifications (звуки `bflat2.wav` и т.д.)
- [ ] Search: FTS, `search.c` 91k
- [ ] Attachments: `attach.c`

#### H. API - 70% осталось
- [ ] Реальные обработчики вместо placeholder: `handleStatus` должен вызывать `vcs/checkout.status`, `handleTimeline` -> `timeline.getTimeline`, `handleFile` -> `artifact.getBlob`, `handleDiff` -> `vcs/diff.diffBlobs`
- [ ] Auth: bearer token, cookie, login
- [ ] OpenAPI spec в `/api/openapi.json`
- [ ] Пагинация, фильтры
- [ ] Портировать `json.c` и `json_*.c` (10 файлов) - JSON API как в оригинале Fossil: `/json/timeline`, `/json/wiki`, etc.

#### I. MCP - 40% осталось (хороший прогресс, но handlers dummy)
- [ ] Реальные handlers: `fossil_status` -> `checkout.status`, `fossil_diff` -> `diff.diffBlobs`, `fossil_commit` -> `commit.commit`, `fossil_timeline` -> `timeline.getTimeline`, `fossil_branch_list` -> `branch.listBranches`, `fossil_wiki_*` -> `wiki.*`, `fossil_ticket_*` -> `ticket.*`, `fossil_blame` -> `blame.blameFile`, `fossil_sql` уже с safety check, но нужно подключить реальный SQLite authorizer
- [ ] Resources: реализовать чтение `fossil://file/{path}@{rev}` - получить файл в ревизии, `fossil://wiki/{page}`, `fossil://ticket/{id}`, `fossil://timeline`, `fossil://branches`
- [ ] Prompts: `commit-message` - сгенерировать сообщение из diff, `code-review` - ревью, `release-notes` - из timeline
- [ ] Notifications: `notifications/resources/changed` когда репо меняется (file watcher)
- [ ] SSE и HTTP транспорт для MCP (сейчас только stdio)

#### J. CLI - 50% осталось
- [ ] Реальные команды вместо stubs: `status`, `diff`, `commit`, `timeline`, `branch`, `open`, `clone`, `sync`, `wiki`, `ticket`, `forum`, `search`, `bisect`, `blame`, `stash`, `clean`, `add`, `rm`, `mv`, `export`, `import`, `bundle`, `rebuild`
- [ ] Парсинг опций как в оригинале: `fossil help <command>` показывает опции
- [ ] `fossil sql` - read-only с authorizer
- [ ] `fossil server` - запустить веб + API

#### K. QBE - 20% осталось
- [ ] ✅ Minimal QBE билд работает (12 C файлов, 67K, чистый C11)
- [ ] ❌ Full QBE билд (52 файла) не собирается с `-std=c11 -D_XOPEN_SOURCE=700` из-за `memmem` (strutils) и `accept4` (asynchttpserver)
  - Решение 1: собрать с `-D_GNU_SOURCE` (работает, но не чистый C11)
  - Решение 2: создать `main_qbe_full.nim` без `api/rest.nim` (без asynchttpserver) но с MCP stdio (который QBE-совместим)
  - Решение 3: патчить Nim stdlib: заменить `memmem` на ручной поиск, `accept4` на `accept` + `fcntl`
- [ ] Вендорить `sh3.c` (SHA3) и `sqlite3.c` амальгаму для static сборки без системных либ
- [ ] Вендорить `mdbx.c` и `lmdb` (`mdb.c` + `midl.c`) с патчами для cproc
- [ ] Протестировать с реальным `cproc` (в sandbox нет cproc, только gcc)
- [ ] Документировать точные команды для cproc сборки

#### L. Тесты - 70% осталось
- [ ] ✅ `all_tests.nim` - delta, manifest, storage mock, mcp, hash, diff
- [ ] ✅ `test_storage_real.nim` - реальный SQLite put/get
- [ ] ❌ `test_checkout.nim` - создание checkout, materialize файлов
- [ ] ❌ `test_commit.nim` - commit с реальными файлами
- [ ] ❌ `test_branch.nim`
- [ ] ❌ `test_timeline.nim`
- [ ] ❌ `test_merge.nim`
- [ ] ❌ `test_sync.nim` - sync два репо
- [ ] ❌ `test_wiki.nim`, `test_ticket.nim`, `test_forum.nim`
- [ ] ❌ `test_mcp.nim` - JSON-RPC compliance, tool calls с реальным репо
- [ ] ❌ `test_api.nim` - REST API
- [ ] ❌ `test_qbe.nim` - QBE билд и запуск
- [ ] ❌ Fuzz тесты для delta, manifest

#### M. Документация - 20% осталось
- [ ] ✅ Базовая документация EN+RU готова (ARCHITECTURE, STORAGE, MCP, CPROC, BUILD, PORTING_PLAN, FULL, LSP, TEST_RESULTS)
- [ ] ❌ Детальная документация по каждому модулю (сейчас только overview)
- [ ] ❌ Примеры использования как библиотеки (Nim API)
- [ ] ❌ Миграция с C fossil: пошагово с командами
- [ ] ❌ OpenAPI spec
- [ ] ❌ MCP промпты документация с примерами
- [ ] ❌ Бенчмарки бэкендов
- [ ] ❌ Руководство по контрибьютингу

## 4. Приоритеты

### P0 - Критично для MVP (чтобы можно было использовать как замену C fossil для базовых операций)

1. **Storage**: cursor итерация для libmdbx/lmdb, deltaChain, getManifest, putDelta, rebuild
2. **Delta**: rolling hash алгоритм для оптимального размера
3. **Artifact**: resolveBlob с delta chain
4. **Checkout**: чтение _FOSSIL_ DB, materialize файлов
5. **Commit**: полный commit с delta, vfile, event
6. **CLI**: реальные status, diff, commit, timeline, branch, open

Оценка: ~10k строк Nim, 2-3 недели.

### P1 - Важно для полноценного использования

7. **Sync**: xfer протокол, clone, sync
8. **Diff**: Myers diff
9. **Merge**: merge3
10. **MCP**: реальные handlers
11. **API**: реальные handlers
12. **Web**: базовые страницы timeline, info, file, diff (без TH1)

Оценка: ~15k строк, 3-4 недели.

### P2 - Для полного паритета с C fossil

13. **Web**: все 50 страниц, TH1, Markdown, graph, search, login, setup, captcha
14. **Wiki/Ticket/Forum/Chat**: полные подсистемы
15. **JSON API**: все json_*.c
16. **QBE**: full QBE билд без GNU расширений, static вендор
17. **Тесты**: все тесты
18. **Доки**: полные доки, бенчмарки, примеры

Оценка: ~20k строк, 2-3 месяца.

## 5. Риски

- **TH1**: 2000 LOC C, свой язык, нужен интерпретатор - сложно, но можно портировать
- **Markdown**: 86k C, можно использовать существующую Nim библиотеку `markdown` вместо портирования
- **Web UI**: 50 страниц, каждая 500-1000 LOC C с `cgi_printf` - много работы, но можно делать постепенно
- **QBE**: Nim stdlib использует GNU расширения (`memmem`, `accept4`, `epoll`) - нужно либо патчить stdlib, либо избегать модулей, либо собирать с `_GNU_SOURCE` (не чистый C11, но работает с cproc? cproc поддерживает _GNU_SOURCE? Нужно проверить)

## 6. Что уже хорошо

- ✅ Модульная архитектура - легко добавлять модули
- ✅ Storage abstraction - легко добавлять бэкенды
- ✅ MCP работает (JSON-RPC), 13 инструментов, легко добавить реальные handlers
- ✅ QBE minimal работает (67K, C11)
- ✅ Тесты и CI (make check, make test)
- ✅ Документация EN+RU базовая готова
- ✅ LSP работает (nim check 0 ошибок)

## 7. Следующие шаги (рекомендация)

1. **Неделя 1**: P0 Storage + Delta + Artifact
   - Реализовать cursor для libmdbx/lmdb
   - Реализовать rolling hash delta
   - Реализовать resolveBlob с delta chain
   - Тесты vs оригинальный fossil binary

2. **Неделя 2**: P0 Checkout + Commit + CLI
   - Портировать checkout.c (vvar, vfile)
   - Портировать checkin.c базовый
   - Реальные CLI команды status, diff, commit, timeline

3. **Неделя 3**: P1 Sync + Diff/Myers + Merge + MCP/API реальные handlers
   - xfer протокол
   - Myers diff
   - merge3
   - MCP handlers вызывают реальный VCS

4. **Неделя 4**: P1 Web базовый + P2 начало
   - timeline, info, file страницы
   - TH1 интерпретатор начало

Итого: через месяц можно иметь MVP, через 3 месяца - полный паритет.

## 8. Ссылки

- Оригинал Fossil src: https://fossil-scm.org/home/dir?ci=trunk&name=src&type=tree
- Дельта формат: https://fossil-scm.org/home/doc/trunk/www/delta_format.wiki
- Файл формат: https://fossil-scm.org/home/doc/trunk/www/fileformat.wiki
- Наш проект: `PROJECT_OVERVIEW.md`, `docs/PORTING_PLAN_RU.md`, `docs/TEST_RESULTS.md`
