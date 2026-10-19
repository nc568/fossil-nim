# Отчёт и комментарии по работе `fossil-nim` (в ходе разработки веб-бэкендов `uirelays`)

Репозиторий: `https://github.com/nc568/fossil-nim` (`Fossil-Nim version 2.26.0-nim`)
Сборка: `nim c --mm:arc --threads:off -d:release` (`bin/fossil` и `bin/fossil-mcp`)
Тестовый полигон: ведение репозитория `/home/user/uirelays.fossil` (коммиты, ветки, тикеты, Wiki, полнотекстовый поиск FTS5, MCP-сервер).

---

## Что работает отлично

1. **Чистая сборка с `--mm:arc`**: и CLI (`src/fossil/cli/main.nim`), и MCP-сервер (`src/fossil/mcp/main.nim`) компилируются на Nim 2.2.2 с `--mm:arc` за ~3 секунды без единой ошибки компиляции.
2. **Высокая скорость работы**: операции `fossil init`, `fossil open`, `fossil status`, `fossil wiki create/list/get`, `fossil search` (FTS5) выполняются мгновенно (< 50 мс).
3. **Автоматическая FTS5-индексация**: при коммитах и создании Wiki-страниц/тикетов данные сразу попадают в `search_fts`, и `fossil search <query>` мгновенно находит совпадения по коду, коммитам и Wiki.
4. **Архитектура MCP (`fossil_search_tools`)**: прогрессивное раскрытие схем инструментов (Progressive Disclosure) в `fossil-mcp` — отличное архитектурное решение для экономии контекстного окна LLM.

---

## Замеченные баги и особенности (с точными координатами в коде)

### 1. `fossil commit` коммитит все неотслеживаемые (`?`) файлы и игнорирует индекс `vfile`
- **Где**: `src/fossil/vcs/commit.nim`, строки `59–72` (`buildManifestFromWorkingTree`).
- **Что происходит**: когда пользователь выполняет `fossil add file1.nim`, а затем `fossil commit -m "..."` (без явного перечисления файлов в командной строке `commit`), массив `opts.files` пуст. В этом случае `buildManifestFromWorkingTree` делает `for path in walkDirRec(checkoutPath):` и добавляет в манифест коммита **абсолютно все файлы на диске**, включая неотслеживаемые (`?`) файлы, скомпилированные бинарники и временные артефакты.
- **Чего не хватает**:
  1. При `opts.files.len == 0` коммит должен брать список отслеживаемых файлов из таблицы `vfile` в базе чекаута `_FOSSIL_` (куда пишет `fossil add` и `fossil rm`), а не сканировать весь диск `walkDirRec`.
  2. При `fossil status` и `fossil add` не хватает поддержки `.fossil-settings/ignore-glob` и/или `.gitignore`.

### 2. Усечение времени коммита (`Julian Date` `float` → `int64`) — все коммиты имеют время `12:00`
- **Где**: `src/fossil/vcs/commit.nim`, строки `313`, `319`, `369`, `381`.
- **Что происходит**: функция `toJulianDate(manifest.date)` корректно вычисляет юлианскую дату как `float` (`unix / 86400.0 + 2440587.5`), где дробная часть хранит точное время суток. Но при записи в таблицу `event` и `tagxref` вызывается:
  ```nim
  discard sqlite3_bind_int64(stmt, 2, int64(jd))
  ```
- **Последствия**:
  1. Дробная часть юлианской даты отбрасывается (`int64(2461332.48) == 2461332`). Поскольку юлианский день начинается в полдень, любой коммит отображается в `fossil timeline` как `12:00` предыдущего дня (`2026-10-18 12:00`).
  2. Все коммиты, сделанные в один день, получают одинаковый `mtime = 2461332`, что ломает хронологическую сортировку `ORDER BY mtime DESC`.
- **Как исправить**: заменить `sqlite3_bind_int64(stmt, ..., int64(jd))` на `sqlite3_bind_double(stmt, ..., cdouble(jd))` (в схеме SQLite колонка `mtime` имеет тип `REAL`).

### 3. Ошибка имён SQL-колонок в MCP-инструментах `fossil_ticket_close` и `fossil_ticket_update`
- **Где**: `src/fossil/mcp/server.nim`, строки `1410`, `1420`, `1457`.
- **Что происходит**: в схеме таблицы `ticket` (`src/fossil/storage/schema.nim`) колонки называются `tkt_uuid`, `tkt_title`, `tkt_status`, `tkt_mtime`. Однако в `src/fossil/mcp/server.nim` написаны прямые SQL-запросы с несуществующими именами колонок `status`, `title`, `mtime`:
  ```nim
  # server.nim:1457 (fossil_ticket_close)
  if sqlite3_prepare_v2(db.db, "UPDATE ticket SET status='closed', mtime=?1 WHERE tkt_uuid=?2".cstring, -1, addr stmt, nil)==0:
  ```
- **Последствия**: `sqlite3_prepare_v2` возвращает ошибку (`no such column: status`), поэтому:
  - `fossil_ticket_close` всегда возвращает `{"isError":true,"text":"Failed to close ticket"}`;
  - `fossil_ticket_update` всегда возвращает `"Updated ticket <id>: no fields to update"`.
- **Как исправить**: вызывать уже готовые и правильно написанные функции `ticketMod.closeTicketSqlite(db, ticketId)` и `ticketMod.updateTicketSqlite(db, ticketId, updates)` из `src/fossil/ticket/ticket.nim`, где используются правильные колонки `tkt_status`, `tkt_title`, `tkt_mtime`.

### 4. В CLI `fossil ticket` нет команд закрытия и изменения статуса тикета
- **Где**: `src/fossil/cli/main.nim`, строки `930–986` (`cmdTicket`).
- **Что происходит**: CLI поддерживает только `fossil ticket <list|get|create|comment>`, хотя в `src/fossil/ticket/ticket.nim` уже реализованы `closeTicketSqlite`, `reopenTicketSqlite`, `updateTicketSqlite`, `deleteTicketSqlite`.
- **Предложение**: добавить в `cmdTicket` подкоманды `close <id>`, `reopen <id>` и `update <id> --status <open|closed|fixed|verified> --priority <1..4> --owner <user>`.

### 5. Комментарии к тикетам (`ticketchng`) не подгружаются при `fossil ticket get <id>`
- **Где**: `src/fossil/ticket/ticket.nim`, строки `118–167` (`getTicketSqlite`) и строка `314` (`addCommentSqlite`).
- **Что происходит**:
  1. `fossil ticket comment <id> <text>` записывает комментарий в таблицу `ticketchng`, но `getTicketSqlite` делает `SELECT` только из таблицы `ticket` и не запрашивает `SELECT tkt_id, login, tkt_mtime, tkt_comment FROM ticketchng WHERE tkt_id=?1 ORDER BY tkt_mtime ASC`. Поэтому `fossil ticket get <id>` всегда возвращает пустой массив `"comments":[]`.
  2. В `addCommentSqlite` (строка 314) `let commentId = $getTime().toUnix() & "_" & $rand(1000)` вызывается без предварительного `randomize()`, поэтому при каждом вызове из CLI генерируется один и тот же суффикс `_595`.
  3. Если передать несуществующий `id` в `getTicketSqlite` (строка 166), вместо ошибки `err[Ticket](feNotFound, ...)` возвращается заглушка `Sample ticket <id>`.

### 6. `fossil diff` без аргументов не показывает diff всего рабочего дерева
- **Где**: `src/fossil/cli/main.nim` (`cmdDiff`).
- **Что происходит**: вызов `fossil diff` без аргументов выводит `Usage: fossil diff <file> [--unified|--json]` и завершается с кодом 1.
- **Чего не хватает**: при вызове `fossil diff` без имени файла удобно автоматически проходить по всем модифицированным (`M`) файлам из `status` и выводить их unified diff (как это делают `git diff` и оригинальный `fossil diff`).

### 7. Небольшая несогласованность глаголов в подкомандах CLI
- Для тикетов и вики используется `create` (`fossil ticket create`, `fossil wiki create`), а для веток — только `new` (`fossil branch new <name>`, тогда как `fossil branch create` возвращает ошибку usage).
- Для чтения вики поддерживаются `get|show|cat`, но привычный `fossil wiki view` выдаёт `Unknown wiki subcommand: view`. Добавление алиасов `create`/`new` и `view`/`get` во все подкоманды сделает CLI ещё удобнее.

### 8. Права доступа (`chmod +x`) и флаги памяти в `fossil_nim.nimble`
- В `src/fossil/vcs/commit.nim:80` права файла жёстко заданы как `var perm = "644"`, поэтому бит исполняемости (`fpUserExec` -> `isExe`) не сохраняется при коммите.
- В `fossil_nim.nimble` в задачах `build`, `release`, `mcp` прописан `--mm:refc`, хотя весь проект уже прекрасно совместим с `--mm:arc`.
