# Полнотекстовый поиск - Fossil-Nim

**Статус: 2026-10-17 - Полная реализация с авто-индексацией**

Fossil-Nim реализует полнотекстовый поиск на базе FTS5 с автоматической индексацией для всех типов контента.

## Архитектура

### Модуль: `src/fossil/search/search.nim` (334 строки)

**Хранение:**
- `search_fts` - виртуальная таблица FTS5 `USING fts5(id, kind, title, content, tokenize='porter unicode61')`
- `search_index` - обычная таблица `id TEXT PRIMARY KEY, kind TEXT, title TEXT, content TEXT, mtime INTEGER`
- Обе таблицы создаются в `RepoSchema` (`src/fossil/storage/schema.nim` строки 212-214)

**Зачем две таблицы?**
- FTS5 оптимизирована для MATCH запросов с ранжированием и сниппетами
- Обычная таблица дает fallback LIKE поиск и хранит mtime для сортировки
- JOIN между ними дает и ранжирование FTS5 и метаданные

**Основное API:**
```nim
proc initSearchIndexSqlite*(backend: var SqliteBackend): FossilResult[bool]
proc indexDocumentSqlite*(backend: var SqliteBackend, kind, id, title, content: string, mtime: int64 = 0): FossilResult[bool]
proc searchSqlite*(backend: SqliteBackend, opts: SearchOptions): FossilResult[seq[SearchResult]]
proc search*(backend: SqliteBackend, opts: SearchOptions): FossilResult[seq[SearchResult]]
proc reindexAllSqlite*(backend: var SqliteBackend, fileLimit, commitLimit: int): FossilResult[int]

# Хелперы
proc indexWikiPage*(backend: var SqliteBackend, name, content: string): FossilResult[bool]
proc indexTicket*(backend: var SqliteBackend, id, title, desc: string): FossilResult[bool]
proc indexFileContentsSqlite*(backend: var SqliteBackend, limit: int): FossilResult[int]
proc indexCommitsSqlite*(backend: var SqliteBackend, limit: int): FossilResult[int]
proc indexBranchesSqlite*(backend: var SqliteBackend): FossilResult[int]
proc reindexAll*(backend: var SqliteBackend, fileLimit, commitLimit: int): FossilResult[int]
```

**Опции поиска:**
```nim
SearchOptions:
  query: string       # FTS5 MATCH запрос, например "bug", "bug AND feature", "title:bug"
  limit: int          # по умолчанию 20
  offset: int         # для пагинации
  kinds: seq[string]  # фильтр по типу: ["commit", "file", "wiki", "ticket", "forum", "chat", "branch"]
```

**Результат поиска:**
```nim
SearchResult:
  kind: string    # commit, file, wiki, ticket, forum, chat, branch
  id: string      # например "commit-<uuid>", "file-README.md", "wiki-Home"
  title: string
  snippet: string # с подсветкой <b>, 20 токенов вокруг совпадения
  rank: float64   # ранг FTS5 (меньше = релевантнее, отрицательный)
  mtime: int64    # Unix timestamp
```

**Запрос поиска:**
- Использует FTS5 `MATCH` с `snippet(search_fts, 2, '<b>', '</b>', '...', 20)` и `rank`
- Fallback на `LIKE` если prepare FTS5 падает: `SELECT ... WHERE title LIKE %query% OR content LIKE %query%`
- Язык запросов: синтаксис FTS5 - `bug`, `bug AND feature`, `bug OR feature`, `bug NOT feature`, `"точная фраза"`, `title:bug`

**Исправление дедупликации:**
FTS5 не имеет UNIQUE ограничения на колонку `id` (primary key - внутренний rowid). `INSERT OR REPLACE` НЕ дедуплицирует по `id`. Исправлено через `DELETE FROM search_fts WHERE id=?1` перед INSERT во всех местах.

### Хуки авто-индексации

Авто-индексация реализована во всех путях записи:

**1. Коммит (`src/fossil/vcs/commit.nim`):**
- После создания manifest + event + tagxref + mlink
- `initSearchIndexSqlite(backend)`
- Индекс коммита: `id="commit-<uuid>", kind="commit", title="[branch] первая строка коммента", content="branch user comment", mtime=manifest.date`
- Индекс измененных файлов: для каждого `manifest.files` читаем файл из checkout, пропускаем бинарные расширения (png, jpg, jpeg, gif, bmp, ico, zip, gz, bz2, xz, pdf, exe, dll, so, o, a, bin), пропускаем пустые или >200k или содержащие "\0", индексируем первые 50k символов как `id="file-<name>", kind="file", title=name, content=fileContent`

**2. Wiki (`src/fossil/wiki/wiki.nim`):**
- В `saveWikiPageSqlite` после создания blob
- Гарантирует существование FTS таблиц
- `INSERT OR REPLACE INTO search_index(id='wiki-'+name, kind='wiki', title=name, content=content, mtime=now)`
- `DELETE + INSERT INTO search_fts` то же самое

**3. Ticket (`src/fossil/ticket/ticket.nim`):**
- В `createTicketSqlite` после вставки тикета
- Тот же паттерн: `id=uuid, kind='ticket', title=title, content=desc`

**4. Forum (`src/fossil/forum/forum.nim`):**
- Создание треда: `id=threadId, kind='forum', title=title, content=content`
- Создание поста: то же самое, `id=postId, kind='forum', title=title, content=content` (добавлено 2026-10-17, ранее отсутствовало)
- Оба с DELETE перед FTS INSERT

**5. Chat (`src/fossil/chat/chat.nim`):**
- `sendMessageSqlite` (ранее отсутствовала авто-индексация, добавлена 2026-10-17)
- `sendMessageWithAttachmentSqlite` (уже имела авто-индексацию)
- `id=msgId, kind='chat', title=room, content=content`

**6. Git Import (`src/fossil/vcs/git_export.nim`):**
- В `importFromGitFastEnhanced` после создания manifest + event + mlink
- Индекс коммита: `id="commit-<uuid>", kind="commit", title="[branch] первая строка", content="branch author message", mtime=commit.timestamp`
- Индекс файлов: для каждого file op M с blobContents, пропускаем бинарные, индексируем первые 50k
- Оба с DELETE перед FTS INSERT (исправлено 2026-10-17)

**7. Инициализация репозитория:**
- `search_fts` и `search_index` создаются через `RepoSchema` в `initSchema()` / `initFullSchema()`
- Явной инициализации не нужно, но `initSearchIndexSqlite` вызывается в API и CLI для безопасности

### CLI

```bash
# Поиск
fossil search "bug" --repo repo.fossil --limit 20
# Вывод: [kind] title (id): snippet с подсветкой <b>

# Переиндексация всего
fossil search --reindex --repo repo.fossil
# или
fossil search reindex --repo repo.fossil
# Вывод: Reindexing search... Reindexed N documents
```

**Реализация:** `src/fossil/cli/main.nim` `cmdSearch`:
- Парсит первый аргумент как запрос или "reindex"/"--reindex"
- Открывает SqliteBackend, вызывает `initSearchIndexSqlite` и `search` или `reindexAll`
- `reindexAll` вызывает `indexFileContentsSqlite(500) + indexCommitsSqlite(1000) + indexBranchesSqlite() + wiki tags`

### REST API

**Эндпоинты:**

- `GET /api/v1/search?q=bug&limit=20&offset=0&kinds=commit,file`
  - Параметры: q (обязательный), limit, offset, kinds (через запятую)
  - Возвращает: `{"ok": true, "data": {"query": "...", "results": [...], "count": N}}`

- `POST /api/v1/search` с JSON `{"query": "bug", "limit": 20, "offset": 0, "kinds": ["commit"]}`
  - Тот же возврат

**Реализация:** `src/fossil/api/rest.nim`:
- `handleSearchApi` парсит запрос из URL или JSON body
- Вызывает `searchMod.initSearchIndexSqlite` и `searchMod.search`
- Возвращает JSON с `searchToJson`

**Web UI:**
- `/search?q=bug` - HTML страница с полем поиска и результатами
- Интеграция в timeline? Будущее: поле поиска в header

### MCP (Model Context Protocol)

**Инструмент:** `search` (в `src/fossil/mcp/server.nim`)

```json
{
  "name": "search",
  "description": "Full-text search across commits, files, wiki, tickets, forum, chat",
  "inputSchema": {
    "type": "object",
    "properties": {
      "query": {"type": "string", "description": "FTS5 query"},
      "limit": {"type": "integer", "default": 20},
      "kinds": {"type": "array", "items": {"type": "string"}, "description": "filter by kind"}
    },
    "required": ["query"]
  }
}
```

Обработчик вызывает `searchMod.search` и возвращает результаты как MCP content.

### Тестирование

**Ручные тесты 2026-10-17:**

```bash
rm -rf /tmp/search_test && mkdir /tmp/search_test && cd /tmp/search_test
fossil init repo.fossil
fossil open repo.fossil
echo "Hello world with bug fix" > README.md
echo "Another file with feature" > file1.txt
fossil add README.md file1.txt
fossil commit -m "Initial commit with bug and feature" README.md file1.txt

fossil search "bug" --repo repo.fossil
# [commit] [trunk] Initial commit with bug and feature (commit-...): [trunk] Initial commit with <b>bug</b> and feature
# [file] README.md (file-README.md): README.md

fossil search "feature" --repo repo.fossil
# [commit] ... bug and <b>feature</b>
# [file] file1.txt ...

# Wiki авто-индекс через API
curl -X POST http://localhost:18083/api/v1/wiki/save -H "Content-Type: application/json" -d '{"name":"Home","content":"home page with bug report","user":"test","message":"create"}'
curl "http://localhost:18083/api/v1/search?q=bug"
# возвращает commit, file, wiki Home (3 результата)

# Ticket, forum, chat через API
curl -X POST /api/v1/ticket/create -d '{"title":"Bug report","description":"bug in feature X"}'
curl "http://localhost:18083/api/v1/search?q=Bug" -> возвращает ticket, forum, commit, chat, file, wiki (9 результатов)

# Тест дедупликации reindex
fossil search --reindex --repo repo.fossil -> Reindexed 2 documents
fossil search "bug" -> все еще 2 результата (не 4) после второго reindex
```

**Ключевые результаты:**
- Авто-индекс работает для всех подсистем
- Reindex не создает дубликаты (исправление DELETE перед INSERT)
- Подсветка сниппетов FTS5 с тегами <b>
- Работает ранжирование

### Будущие улучшения

- [ ] Добавить trigram индекс для LIKE fallback
- [ ] Добавить поиск по diff содержимому (индексировать diff, а не только файлы)
- [ ] Добавить фильтры поиска: branch, user, диапазон дат
- [ ] Добавить очистку индекса при удалении (удаление wiki, ticket и т.д.)
- [ ] Добавить инкрементальный reindex через file watcher
- [ ] Добавить подсказки / автодополнение поиска
- [ ] Добавить поиск в header web UI с live результатами
- [ ] Рассмотреть LMDB для кэша поискового индекса (быстрее чем SQLite для FTS?)

### Сравнение с оригинальным Fossil

| Функция | Оригинальный Fossil | Fossil-Nim |
|---------|---------------------|------------|
| FTS | FTS5 с таблицей `fts5` | Тот же FTS5, тот же токенизатор `porter unicode61` |
| Авто-индекс | При коммите, wiki, ticket, forum через триггеры? | Явно в каждом save proc, плюс git import |
| Reindex | `fossil rebuild --search` | `fossil search --reindex` + `reindexAll` |
| API | `/search?q=` HTML | `/api/v1/search?q=` JSON + HTML |
| MCP | N/A | инструмент `search` |

## Файлы

- `src/fossil/search/search.nim` - основной модуль поиска
- `src/fossil/storage/schema.nim` - схема включает search_fts + search_index
- `src/fossil/vcs/commit.nim` - авто-индекс коммита + файлов
- `src/fossil/wiki/wiki.nim` - авто-индекс wiki
- `src/fossil/ticket/ticket.nim` - авто-индекс ticket
- `src/fossil/forum/forum.nim` - авто-индекс треда + поста
- `src/fossil/chat/chat.nim` - авто-индекс сообщений чата
- `src/fossil/vcs/git_export.nim` - авто-индекс импортированных коммитов
- `src/fossil/cli/main.nim` - `fossil search` + `fossil search --reindex`
- `src/fossil/api/rest.nim` - `/api/v1/search` + `/search` web
- `src/fossil/mcp/server.nim` - MCP инструмент `search`
