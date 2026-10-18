# Ревью2 — Мелочі які ще хотів доделать / TODO по аудиту 2026-10-17

Дата ревью: 2026-10-17, архив workspace-01a14a4a-4183-730b-b933-7d059750c572.zip
Вердикт ревью: MVP отличный, но не production для Web из-за security.

## Критические уязвимости (SEC-01..07) — must fix до продакшена

### SEC-01 CRITICAL 9.8 — Обход аутентификации /login (любой пароль)
- **Файлы:** `src/fossil/web/pages/login_page.nim:56-64`, `src/fossil/api/rest.nim:2365-2375`
- **Проблема:** `getUserSqlite` делает `SELECT login, pw, cap, mtime, info` но читает только 0=login и 2=cap, колонка 1 pw пропущена. В `rest.nim` проверяется только `userRes.isOk` (существование пользователя), пароль не проверяется.
- **Эффект:** Вход под admin с любым непустым паролем.
- **Что хотел доделать:**
  - Добавить поле `pwHash: string` в `User`
  - В `getUserSqlite` читать `sqlite3_column_text(stmt,1)` → `pwHash`
  - В `rest.nim` POST /login вызывать `verifyPassword(pass, userRes.value.pwHash)` → 401 если неверно
  - `hashPassword` сейчас SHA1 простой, надо добавить соль как в оригинале Fossil (SHA1 + salt) или хотя бы проверять оба формата
  - Добавить тесты: login с верным/неверным паролем

### SEC-02 HIGH 8.1 — Обход CSRF (при отсутствии поля)
- **Файлы:** `rest.nim:2357`, `2422`
- **Проблема:** `if csrf.len > 0 and not validateCsrfToken(csrf)` — если поле не передано, len==0 → условие false → пропускается, защита аннулируется.
- **Что хотел доделать:**
  - Заменить на `if csrf.len == 0 or not validateCsrfToken(csrf): 403`
  - Сделать токен обязательным для всех POST/PUT/DELETE
  - URL-safe base64 уже сделан (`+`→`-`, `/`→`_`), но надо ещё проверять expiry и one-time use (сейчас токен многоразовый в течение 1h)
  - Добавить `SameSite=Strict` к session cookie и `__Host-` префикс

### SEC-03 HIGH 8.6 — Path Traversal /api/v1/file и /api/v1/diff
- **Файлы:** `rest.nim:178-185`, `246-254`
- **Проблема:** `let full = root / path` без валидации, `../../../../etc/passwd` читается.
- **Что хотел доделать:**
  - `normalizedPath(absolutePath(root / path))` + проверка `startsWith(root & DirSep)` + `full != root`
  - Добавить `DirSep` проверку и для Windows `\`
  - Применить к `/file`, `/finfo`, `/diff`, `/blame`, `/raw`, `/zip`, `/tarball`, `/tree`, `/dir`
  - Добавить unit тест на traversal

### SEC-04 HIGH 7.5 — Обход read-only SQL (REPLACE, ATTACH, PRAGMA, VACUUM INTO)
- **Файлы:** `mcp/server.nim:194-196`, `cli/main.nim:1614`
- **Проблема:** Чёрный список `INSERT, UPDATE, DELETE, DROP, ALTER, CREATE` обходится `REPLACE INTO`, `ATTACH DATABASE`, `PRAGMA writable_schema=ON`, `VACUUM INTO '/tmp/pwn'`
- **Что хотел доделать:**
  - Открывать DB в `SQLITE_OPEN_READONLY` (0x00000001) через `sqlite3_open_v2`
  - Или `sqlite3_set_authorizer` разрешать только `SQLITE_SELECT` и `SQLITE_READ`
  - Удалить blacklist, заменить на флаг
  - Добавить тест: попытка `REPLACE` должна вернуть `SQLITE_READONLY`

### SEC-05 MEDIUM 6.5 — Reflected XSS в full_parity.nim
- **Файлы:** `web/pages/full_parity.nim:43-52`, `76`, `renderBlamePage`
- **Проблема:** `fileName`, `fromRid`, `toRid`, `branch`, `author` вставляются в HTML без экранирования, только `.replace("<","&lt;")` частично.
- **Что хотел доделать:**
  - Создать `htmlEscape` / `xmlEscape` утилиту в `utils/` : `&`→`&amp;`, `<`→`&lt;`, `>`→`&gt;`, `"`→`&quot;`, `'`→`&#39;`
  - Применить ко всем пользовательским переменным в `full_parity.nim`, `extended_pages.nim`, `file_page.nim`, `info_page.nim`, `graph_page.nim`, `timeline.nim`, `ticket.nim`, `wiki.nim`
  - Уже есть `escapeHtml` в `markdown/parser.nim` — унифицировать
  - Добавить CSP header `Content-Security-Policy: default-src 'self'`

### SEC-06 MEDIUM 5.3 — Декоративные сессии
- **Файлы:** `api/rest.nim:48-83`, `web/pages/login_page.nim:140`
- **Проблема:** `validateSessionSqlite` объявлена но нигде не вызывается, `checkAuth` возвращает true если `FOSSIL_API_TOKEN==""`, все страницы `/timeline`, `/file`, `/brlist`, `/setup` без проверки сессии.
- **Что хотел доделать:**
  - Middleware: проверять `Cookie: session=...` → `validateSessionSqlite` → 401 если expired
  - `checkAuth` должен проверять Bearer token И session cookie, а не только env
  - Добавить `session` table cleanup по expire
  - Добавить `HttpOnly`, `Secure`, `SameSite=Strict` к Set-Cookie
  - Добавить `logout` инвалидацию сессии (DELETE FROM session)

### SEC-07 LOW 3.8 — SQL через replace("'", "''")
- **Файлы:** 19 мест: `vcs/commit.nim:301`, `timeline.nim:39`, `branch.nim:85`, `sync/protocol.nim:196`, `blame.nim:41` и др.
- **Проблема:** Конкатенация строк вместо `sqlite3_bind_*`, уязвимо к null bytes, UTF-8.
- **Что хотел доделать:**
  - Заменить все `branchName.replace("'", "''")` на `sqlite3_bind_text`
  - Унифицировать стиль: везде параметризованные запросы как в `file_page.nim`
  - Добавить линтер `grep -r "replace(\"'\", \"''\")"`

## Документация vs Реальность — рассинхрон

### 6 сломанных файлов (nim check)
1. `cli/commands/add.nim`: `undeclared identifier: 'toUnix'` → нет `import std/times`
2. `cli/commands/commit.nim`: `startsWith`, `split` → нет `import std/strutils`
3. `ui/component.nim`: `Future` → нет `import std/asyncdispatch`
4. `ui/core.nim`: `Future` → нет `import std/asyncdispatch`
5. `ui/frontend.nim`: `getTheme`, `getPlatform`, `DefaultRoutes` → мёртвый код, папка `ui/` не импортируется
6. `web/pages/ticket.nim`: `mtime`, `text` field → рассинхрон с `tickets/ticket.nim` новая структура Ticket

**Что хотел доделать:**
- Починить импорты в 2 файлах cli/commands или удалить папку `cli/commands/` (дубль main.nim 1800+ строк)
- Удалить мёртвую папку `src/fossil/ui/` или привести к компилируемому состоянию
- Синхронизировать `web/pages/ticket.nim` с `ticket/ticket.nim`
- Добавить CI `make check` → `nim check` по всем файлам
- В `Makefile` добавить цель `check` которая уже есть но не в CI

### Web Parity 47+ pages — преувеличение
- Многие страницы в `full_parity.nim` и `extended_pages.nim` — статические макеты, не реальная логика Fossil (canvas графики, ветвление ревизий, тегирование артефактов)
- POST `/setup` заглушка: `# For MVP, just redirect to /setup (actual user/config creation would need DB write)` → возвращает HTML "Setup action received" без записи в DB

**Что хотел доделать:**
- Реализовать сохранение в DB для POST `/setup/config` (INSERT OR REPLACE config), `/setup/user/new` (INSERT user с hash), `/setup/user/edit`
- Добавить реальную логику для `/brlist` (branch list GROUP BY), `/taglist`, `/leaves`, `/reportlist` уже есть но проверить SQL
- Добавить HTML escape везде (SEC-05)

### Rebuild CLI
- Заявление "Rebuild supports all backends" ложно: в `cli/main.nim:1745` при не-sqlite бэкенде печатает `"Rebuild to non-sqlite not yet implemented in CLI"`
- На самом деле `hybrid_backend.nim` умеет rebuild, но CLI не вызывает

**Что хотел доделать:**
- В `cmdRebuild` добавить ветку для `hybrid-cdb`, `hybrid-lmdb`, `hybrid-mdbx`, `cdb`, `lmdb`, `libmdbx`
- Вызывать `hybrid_backend.migrateToHybrid` или `copyAllTablesViaAttach`
- Тест: `fossil rebuild --backend hybrid-cdb old.fossil new.fossil` → 264K + 2.6K cdbkv

## Архитектура

### CLI двойная реализация
- `src/fossil/cli/commands/` (add.nim, commit.nim...) заброшены, не импортируются
- `src/fossil/cli/main.nim` 1800+ строк содержит дублирующие реализации тех же команд
- **Что хотел доделать:** Удалить папку `commands/` или вынести команды из main.nim в модули, сделать `import` и тонкий CLI wrapper

### Sync
- Таймауты хардкожены 30s в `sync/http.nim`, нет поддержки прокси и SSL переопределения
- **Что хотел доделать:** Добавить `FOSSIL_PROXY`, `FOSSIL_SSL_NO_VERIFY` env, конфигурируемый timeout

### MCP
- Качественная часть, но SEC-04 read-only bypass
- **Что хотел доделать:** Перевести `toolSql` на `SQLITE_OPEN_READONLY`

## План доведения до Production (из ревью)

### Этап 1 — Безопасность (блокеры)
1. SEC-01 проверка хеша пароля
2. SEC-02 строгая CSRF `csrf.len==0 or not valid`
3. SEC-03 Path Traversal normalizedPath + startsWith root
4. SEC-04 SQLITE_OPEN_READONLY
5. SEC-06 проверка сессий middleware validateSessionSqlite

### Этап 2 — Чистка
1. Починить 6 файлов или удалить мёртвый код `ui/`
2. Синхронизировать ticket.nim
3. CI `make check`

### Этап 3 — Web UI заглушки
1. Реальное сохранение POST /setup в DB
2. Глобальное HTML экранирование
3. Rebuild для MDBX/LMDB/CDB

## Мелочи которые ещё хотел доделать (личный список)

- [ ] SEC-01: добавить `pwHash` в User, читать колонку 1, `verifyPassword` в POST /login
- [ ] SEC-02: `if csrf.len==0 or not validate` вместо `len>0 and not`
- [ ] SEC-03: `normalizedPath` + `startsWith(root)` для /file /diff /finfo /blame /raw /zip /tree
- [ ] SEC-04: `sqlite3_open_v2` с `SQLITE_OPEN_READONLY` для sql tool и CLI sql
- [ ] SEC-05: `htmlEscape` утилита и применить везде в full_parity.nim, extended_pages.nim
- [ ] SEC-06: middleware проверки session cookie, `validateSessionSqlite` вызов, HttpOnly Secure SameSite
- [ ] SEC-07: заменить все `replace("'", "''")` на bind
- [ ] Починить 6 сломанных файлов: добавить импорты times, strutils, asyncdispatch или удалить ui/ и cli/commands/
- [ ] Удалить дубль CLI: либо удалить `cli/commands/`, либо вынести из main.nim
- [ ] Реализовать POST /setup реальную запись в DB (config, user)
- [ ] Реализовать `fossil rebuild --backend hybrid-*` в CLI (сейчас только sqlite→sqlite)
- [ ] Добавить CSP header и `X-Content-Type-Options: nosniff`
- [ ] Добавить `SameSite=Strict` к session cookie
- [ ] Добавить тесты на security: login bypass, CSRF bypass, path traversal, SQL readonly bypass, XSS
- [ ] Добавить `make check` в CI
- [ ] Проверить `escapeHtml` уже есть в markdown/parser.nim — унифицировать
- [ ] Добавить прокси и SSL опции в sync/http.nim
- [ ] Добавить таймаут конфигурируемый через env `FOSSIL_HTTP_TIMEOUT`
- [ ] Добавить `htmlEscape` для author в blame, fileName в diff, branch в brlist
- [ ] Добавить `ARC` везде — уже сделано 14:38, 3.8M ARC no GC, QBE refc 776K
- [ ] Обновить BENCHMARKS.md с ARC цифрами — уже сделано 18544/137640
- [ ] Добавить MCP tool для /bench (get_benchmarks) — идея из прошлого ревью
- [ ] Добавить графики в docs таблицами — уже есть SVG в /bench
- [ ] Убрать vvar — DONE
- [ ] QBE линк с NIM_LIB — DONE в Makefile

## Статус после ревью2

- MVP движка: ✅ Myers diff O(ND), delta, artifact, SQLite, Hybrid 23 таблицы, sync parseCards, wiki/ticket FTS5, QBE 776K, MCP 49 tools, tests PASS
- Web production: ❌ критические уязвимости SEC-01..06, заглушки /setup, XSS, path traversal, декоративные сессии
- Документация: ❌ 6 файлов не компилируются, 0 errors в nim check ложно, 47+ pages преувеличение (30-40% реально)
- После патчей из раздела 7 ревью проект станет безопасным современным аналогом Fossil
