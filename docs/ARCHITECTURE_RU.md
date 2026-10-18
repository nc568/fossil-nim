# Архитектура - Порт Fossil на Nim

## 1. Философия

Оригинальный Fossil - это амальгама: ~180 C файлов склеены в один `fossil.c` (~800k строк с SQLite). Это дает простоту сборки, но убивает модульность, тестируемость, поддержку IDE.

**Цели Nim-порта:**
1. **Модульность**: каждая подсистема - независимый Nim-модуль с четким интерфейсом
2. **C-интероп, а не переписывание**: проверенные C-библиотеки (SQLite, zlib, OpenSSL) остаются как `importc`
3. **Подключаемое хранилище**: абстрактный концепт `StorageBackend`, а не захардкоженный SQLite
4. **API-first**: CLI - тонкая обертка над библиотекой `fossil/api`
5. **MCP-first**: AI-агенты могут работать с Fossil через структурированные инструменты
6. **Дружелюбность к QBE/cproc**: сгенерированный C должен быть переносимым

## 2. Слоистая архитектура

```
+---------------------------+
|  CLI (src/fossil/cli)     |  <- точка входа пользователя
+---------------------------+
|  API (REST + JSON)        |  <- http, скрипты
+---------------------------+
|  MCP (Model Context)      |  <- AI-агенты
+---------------------------+
|  Ядро VCS                 |
|  - checkout, commit,      |
|    branch, merge, diff    |
+---------------------------+
|  Артефакт / Манифест      |
|  - hash, parse, delta     |
+---------------------------+
|  Абстракция хранилища     |
|  backend.nim концепт      |
+---------------------------+
|  DB / C Interop           |
|  sqlite3, mdbx, lmdb, cdb |
+---------------------------+
```

Правило зависимостей: верхние слои могут импортировать нижние, никогда наоборот.

## 3. Базовые типы (`types.nim`)

```nim
Rid = distinct int64        # Record ID, rowid в БД
Uuid = distinct string      # SHA3-256 hex, 64 символа, или SHA1 40 для совместимости
Blob = object               # Fossil Blob: данные + размер, refcounted
ArtifactType = enum         # manifest, cluster, wiki, ticket и т.д.
Delta = object              # операции copy/insert
```

- `Blob` - обертка над `string` с явной длиной, имитирует оригинальный `Blob`, но безопасно.
- Все взаимодействия с БД возвращают `Result[T, FossilError]`.

## 4. Абстракция хранилища

```nim
type StorageBackend* = concept b
  b.open(path: string): Result[void, FossilError]
  b.close()
  b.getArtifact(uuid: Uuid): Result[Blob, FossilError]
  b.putArtifact(uuid: Uuid, data: Blob): Result[Rid, FossilError]
  b.hasArtifact(uuid: Uuid): bool
  b.getManifest(rid: Rid): Result[Manifest, FossilError]
  b.deltaChain(rid: Rid): seq[Rid]
```

- `sqlite_backend`: реализует оригинальную схему: таблицы `blob`, `delta`, `event`, `tag` и т.д.
- `libmdbx_backend`: 2 DBI: `artifacts` (uuid->blob), `meta` (rid->flags), `links` (parent->child). Использует append + GC libmdbx.
- `lmdb_backend`: аналогично, но один писатель.
- `cdb_backend`: только чтение, для `fossil export --cdb` для раздачи статических клонов через HTTP.

Путь миграции: `fossil rebuild --backend libmdbx` читает из sqlite и пишет в mdbx.

## 5. Дельта

Формат дельты Fossil: последовательность операций:
- `len@off` - скопировать `len` байт из исходника со смещением `off`
- `len:literal` - вставить литерал

Реализовано в `delta.nim` с 100% совместимостью с оригинальным `delta.c`. Включает `deltaCreate`, `deltaApply`, `deltaOutputSize`.

Мы сохраняем алгоритм идентичным для интероперабельности.

## 6. Артефакт / Манифест

Манифест - текстовый формат:

```
C comment...
D 2024-12-01T12:00:00.000
F file hash perm
...
M uuid
P parent...
R sha3...
Z checksum
```

Парсер в `artifact/manifest.nim` написан вручную, zero-copy где возможно, использует `parseutils` Nim.

Хеширование: SHA3-256 (основной) + SHA1 (легаси). Обертка над OpenSSL или nimcrypto, но для QBE используем встроенную C-реализацию `sh3.c` через importc.

## 7. Ядро VCS

Каждая VCS-операция - модуль с функцией `run*`, возвращающей Result.

Пример `checkout.nim`:
- читает таблицу `vvar` (checkout db)
- материализует файлы через цепочку дельт
- обрабатывает симлинки, биты исполняемости

`commit.nim`:
- сканирует рабочее дерево
- строит манифест
- вычисляет дельту относительно родителя
- вставляет в хранилище

Все VCS-функции - чистые библиотечные функции, CLI только парсит аргументы и вызывает их. Это позволяет переиспользовать в API/MCP.

## 8. Протокол синхронизации

Синхронизация Fossil - HTTP POST с кастомным фреймингом:
- клиент отправляет список имеющихся артефактов
- сервер отправляет отсутствующие как карты `xfer`
- то же в обратную сторону

Реализовано в `sync/protocol.nim` как стейт-машина, транспорт подключаемый (http, ssh).

## 9. Веб-сервер

Мы не используем Jester. Используем `std/asynchttpserver`, обернутый под семантику HTTP Fossil (CGI-like). Роутер мапит `/timeline`, `/info`, `/wiki`, `/api/v1/*`.

Страницы - `nim` процедуры, генерирующие HTML через `htmlgen`, чтобы избежать тяжелых зависимостей и сохранить совместимость с QBE.

## 10. API и MCP

- `api/rest.nim`: определяет маршруты в стиле OpenAPI, возвращает JSON. Аутентификация через bearer или cookie.
- `api/json_api.nim`: совместимость с легаси `/json` эндпоинтом.

- `mcp/server.nim`: JSON-RPC 2.0 поверх stdio (спецификация MCP). Обрабатывает `initialize`, `tools/list`, `tools/call`, `resources/list`, `resources/read`.
- `mcp/tools.nim`: определяет все инструменты с JSON Schema входом.

Дизайн MCP гарантирует, что AI-агенты могут делать полный workflow Fossil без парсинга текста CLI.

## 11. C Interop

Все C заголовки обернуты в `db/c_interop.nim`:

```nim
{.push header: "<sqlite3.h>".}
type sqlite3 {.importc: "sqlite3", incompleteStruct.} = object
proc sqlite3_open(...) {.importc.}
{.pop.}
```

Для libmdbx/lmdb мы вендорим минимальные заголовки в `cinterop/include/`, чтобы избежать системных зависимостей.

Zlib: используем `zippy` Nim или `importc` zlib.

## 12. Совместимость с QBE / cproc

C-бэкенд Nim генерирует код, который обычно использует:
- `__attribute__((...))`
- `__builtin_frame_address`
- computed goto для обработки исключений

С `-d:qbeCompat` мы:
- Определяем `NIM_NO_ATTRIBUTE`, `NIM_NO_BUILTIN`
- Форсируем `nimOldCaseObjects` off, используем `--panics:on` + типы `Result`, без исключений на горячем пути.
- Предоставляем кастомный `nimbase.h`, который мапит `NIM_INTBITS` и т.д. на обычный C11.
- Избегаем `alloca` через `-d:nimNoAlloca`.

Итоговые C-файлы в `build/cgen` компилируются cproc:
```
cproc -std=c11 -D_XOPEN_SOURCE=700 -Ibuild/cgen -I cinterop/include -o fossil ...
```

## 13. Система сборки

- `nimble build` - обычно
- `nimble buildQbe` - генерирует только C
- `Makefile` - оборачивает оба, плюс `make qbe` запускает cproc

## 14. Стратегия тестирования

- `tests/test_delta.nim` - roundtrip против оригинального бинаря fossil
- `tests/test_manifest.nim` - парсит все манифесты из самого репозитория fossil
- `tests/test_storage.nim` - одинаковая нагрузка на всех бэкендах, сравнение
- `tests/test_mcp.nim` - соответствие JSON-RPC

## 15. Поиск и архив

### Поиск (`src/fossil/search/search.nim`)
- Виртуальная таблица FTS5 `search_fts USING fts5(id, kind, title, content, tokenize='porter unicode61')` + обычная `search_index` для fallback LIKE и mtime
- `indexDocumentSqlite` делает DELETE FROM search_fts перед INSERT чтобы избежать дублей FTS5 (у FTS5 нет UNIQUE по id, PK - внутренний rowid)
- Хуки авто-индексации во всех путях записи: commit (коммит+файлы), wiki, ticket, forum thread+post, chat, git import
- CLI `fossil search <query> [--limit]` и `fossil search --reindex` (вызывает reindexAll: файлы 500 + коммиты 1000 + ветки + wiki теги)
- REST `/api/v1/search?q=` + web `/search?q=`, MCP инструмент `search`
- Тестировано 2026-10-17: авто-индекс коммитов, дедупликация reindex, wiki/ticket/forum/chat через API

### Архив (`src/fossil/vcs/archive.nim`)
- Реальная генерация ZIP (метод STORE, без сжатия, избегает зависимости zlib) и TAR (USTAR)
- Таблица CRC32 256 записей, toLittleEndian16/32, dosTimeDate
- ZIP: локальный заголовок 0x04034b50 + central dir 0x02014b50 + EOCD 0x06054b50, отслеживание offset
- TAR: заголовок 512 байт, octal поля, checksum с пробелами, 2 нулевых блока
- `createArchiveFromRepo` через listFilesSqlite(10000) с фильтром по path + getFileContentSqlite
- CLI `fossil zip/tarball/archive --branch --path --output --format`, авто-определение .zip/.tar.gz
- REST `/zip` и `/tarball` возвращают реальный бинарный Content-Type application/zip/x-tar + Content-Disposition attachment
- Тестировано: 3 файла -> 373 байта ZIP валидный zipfile, 4096 байт TAR валидный tarfile, фильтр path ?path=src

## 16. Будущее

- Заменить Tcl/Tk части? Fossil использует TH1 (мини Tcl). Мы портируем TH1 в Nim как `web/th1.nim` интерпретатор.
- WASM сборка для checkout в браузере? Nim -> JS возможно.
- Инкрементальная миграция: возможность открывать оригинальные `.fossil` файлы в режиме только чтения через sqlite бэкенд, затем `rebuild` в новый бэкенд.
- Поиск: trigram индекс, содержимое diff, фильтры (branch/user/date), очистка при удалении, инкрементальный watcher, автодополнение, live результаты в header
- Архив: опция сжатия DEFLATE, tar.gz, инкрементальный архив
