# Исправления безопасности 2026-10-17

## Обзор
Финальная проверка безопасности после достижения полного паритета с Fossil. Все критические уязвимости исправлены, сборка проходит с ARC и QBE.

## SEC-04: Read-only на уровне движка
- **Файл:** `src/fossil/storage/sqlite_backend.nim`
- **Исправление:** Добавлен `sqlite3_open_v2` с флагом `SQLITE_OPEN_READONLY`, реализован `openReadOnly`.
- **Использование:** MCP `toolSql` теперь `openReadOnly` + `defer close`, CLI `cmdSql` тоже read-only.
- **Результат:** Даже если SQL содержит UPDATE/INSERT, запись невозможна.

## SEC-05: XSS через htmlEscape
- **Файлы:** `full_parity.nim`, `extended_pages.nim`, `ticket.nim`, `file_page.nim` и др.
- **Исправление:** Реализован `htmlEscape` экранирующий `& < > " ' \`` и используется для всех полей от пользователя.
- **Результат:** Пользовательский ввод не попадает в HTML напрямую.

## SEC-06: Обход сессии на /setup
- **Файл:** `src/fossil/api/rest.nim`
- **Исправление:**
  - `getSessionIdFromRequest` парсит Cookie `session=`
  - `isSessionValid` вызывает `validateSessionSqlite`
  - GET /setup проверяет сессию, иначе возвращает страницу логина
  - POST /setup проверяет сессию перед CSRF, 401 если невалидна
  - Реальная запись в БД: `setConfigSqlite` для конфига, `INSERT OR REPLACE INTO user` с `hashPassword` для нового пользователя, `UPDATE user` для редактирования, через `sqlite3_bind_*`
- **Результат:** Setup требует валидной сессии.

## SEC-07: SQL-инъекция через конкатенацию
Переведено на `prepare_v2` + `bind`:

- `commit.nim`: INSERT event через `?1..?5` bind
- `timeline.nim`: фильтры branch/user/type через `?` bind
- `branch.nim`: createBranch/closeBranch/getBranchTip через bind
- `blame.nim`: filename через bind
- `protocol.nim`, `http.nim`: event INSERT через bind
- `cli/main.nim` add: UPDATE vfile через bind + проверка path traversal `normalizedPath(absolutePath).startsWith(root)`
- `search.nim`: kinds IN через плейсхолдеры + валидация alphanumeric
- `stash.nim`: DELETE через bind
- `hybrid_backend.nim`: ATTACH путь валидируется `fileExists`, `absolutePath`, запрет `'` и `;`

Оставшиеся `replace("'", "''")` только для локальных файлов ATTACH, валидированных.

## Исправление мёртвого кода
- `cli/commands/add.nim`: добавлен `times`, fix SQL bind
- `cli/commands/commit.nim`: добавлен `strutils`
- `ui/core.nim`: добавлен `asyncdispatch` для Future
- `ui/frontend.nim`: добавлены `getTheme`, `getPlatform`, `DefaultRoutes`
- `web/pages/ticket.nim`: `c.mtime` -> `c.date`, `c.text` -> `c.content`
- `extended_pages.nim`, `full_parity.nim`: исправлена строка `"""` для экранирования кавычек, теперь `result.replace("\"", "&quot;")` корректно

## Проверка сборки
- `make build` OK: ARC 3.8M
- `make build-qbe-c` OK: 54 C файла
- `make qbe` OK: bin/fossil-qbe 780K, QBE ON, cproc собирает
- Тесты `all_tests`, `storage_real`, `search_forum_chat`, `wiki_ticket` OK

Все критические SEC-04/05/06/07 исправлены.
