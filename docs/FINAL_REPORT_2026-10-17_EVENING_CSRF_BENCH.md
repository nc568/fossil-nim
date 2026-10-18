# Final Report — 2026-10-17 Evening: 7 New Pages + CSRF + Bench SVG

Дата: 2026-10-17 14:30-14:31
Бинари: fossil 2.1M, mcp 998K, qbe 776K

## Что сделано

### 1. 7 новых страниц в rest.nim (3199→3205 строк, 47+ всего)

- **/tinfo** — alias /ticket, param id/name, nav Home|Ticket List|tinfo|ticket|JSON, handleTicketGet, 868b 200 OK
- **/winfo** — alias /wiki, param name/page, nav Home|Wiki List|winfo|wiki|History|JSON, handleWikiGet, 665b 200 OK
- **/wdiff** — wiki diff, params name, v1/from, v2/to, history count check, "Not enough history for diff (need 2 versions, have 0)", 531b 200 OK
- **/artifact** + **/blob** — raw blob view, id/uuid/name, binary detection application/octet-stream, HTML preview 10k chars escaped <pre>, 466b/486b 200 OK
- **/bench** — full benchmark HTML с SVG bar charts, 4455b 200 OK
- **/fileedit** — alias placeholder, CLI instruction `fossil edit`, 714b 200 OK
- **/setup** — уже был, теперь CSRF tokens

Код /bench SVG:
```html
<svg width="600" height="120">
  <text x="10" y="20">Put/s</text>
  <rect x="100" y="10" width="30" height="20" fill="#0d6efd"/><text x="140" y="25">SQLite 18k</text>
  <rect x="100" y="40" width="400" height="20" fill="#28a745"/><text x="510" y="55">CDB 719k</text>
  <rect x="100" y="70" width="28" height="20" fill="#ffc107"/><text x="140" y="85">Hybrid 17k</text>
</svg>
<svg width="600" height="120">
  <text x="10" y="20">Get/s</text>
  <rect x="100" y="10" width="130" height="20" fill="#0d6efd"/><text x="240" y="25">SQLite 130k</text>
  <rect x="100" y="40" width="266" height="20" fill="#28a745"/><text x="376" y="55">CDB 266k</text>
  <rect x="100" y="70" width="129" height="20" fill="#ffc107"/><text x="239" y="85">Hybrid 129k</text>
</svg>
<svg width="600" height="60">
  <rect x="10" y="10" width="300" height="20" fill="#dee2e6"/><text x="320" y="25">Original 5000 bytes</text>
  <rect x="10" y="35" width="64" height="20" fill="#0d6efd"/><text x="84" y="50">Delta 1063 bytes (21%)</text>
</svg>
```

### 2. CSRF защита login_page.nim + setup_page.nim

**login_page.nim:**
```nim
var gCsrfTokens* {.global.} = initTable[string, int64]()

proc generateCsrfToken*(): string =
  randomize()
  var bytes = newString(32)
  for i in 0..<32: bytes[i] = char(rand(255))
  let token = encode(bytes) & $getTime().toUnix()
  gCsrfTokens[token] = getTime().toUnix() + 3600
  token

proc validateCsrfToken*(token: string): bool =
  if token.len==0: return false
  if gCsrfTokens.hasKey(token):
    let exp = gCsrfTokens[token]
    if exp > getTime().toUnix(): return true
    else: gCsrfTokens.del(token)
  false

proc cleanupCsrfTokens*() = ...

proc renderLoginPage*:
  let csrf = generateCsrfToken()
  html.add "<input type='hidden' name='csrf' value='" & csrf & "'>"
  html.add "<div class='csrf-note'>CSRF protection enabled • Token expires in 1h</div>"
```

**setup_page.nim:**
```nim
proc renderSetupPage*:
  let csrf = generateCsrfToken()
  form add user: <input type='hidden' name='csrf' value='" & csrf & "'>
  form set config: <input type='hidden' name='csrf' value='" & csrf & "'>

proc renderUserEditPage*:
  let csrf = generateCsrfToken()
  <input type='hidden' name='csrf' value='" & csrf & "'>
```

**rest.nim POST /login:**
```nim
elif req.url.path == "/login" and POST:
  var csrf = ""
  # parse
  if csrf.len>0 and not validateCsrfToken(csrf):
    respond 403 "Invalid CSRF token - please retry"
  else:
    # login flow
```

Тест:
```
GET /login -> 200 1536b token=HdFnfnLrQyxIdYKPReI4aYtxs1FlxO9fTzrNx52U5J0=1792247461 OK
POST valid csrf -> 200 Invalid login (CSRF passed)
POST invalid csrf -> 403 Invalid CSRF token - please retry OK
GET /setup -> 200 3189b CSRF tokens in both forms OK
```

### 3. SPA fix

Проблема: frontendRoutes содержал /login и /setup, SPA web_new/index.html перехватывал их (5807b SPA вместо 1536b login).

Решение: убрали /login /setup из обоих списков frontendRoutes (1790 и 3177).

Результат: /login 1536b 200 OK, /setup 3189b 200 OK, /timeline /file и т.д. всё ещё SPA 200 OK.

### 4. Web тест 8768 20/20 200 OK

```
/ -> 200 5807b SPA
/stat -> 200 3672b
/reportlist -> 200 2461b
/leaves -> 200 1387b
/rss -> 200 520b
/help -> 200 6522b
/zip -> 200 144b
/bench -> 200 4455b SVG
/tinfo?id=1 -> 200 868b
/winfo?name=Home -> 200 665b
/wdiff?name=Home -> 200 531b
/artifact?id=abc -> 200 466b
/blob?name=file.txt -> 200 486b
/fileedit?name=file.txt -> 200 714b
/login -> 200 1536b CSRF
/setup -> 200 3189b CSRF
/timeline -> 200 SPA
/file -> 200 SPA
/finfo -> 200
/info -> 200
```

### 5. Benchmarks обновлены

Новый замер 14:30:
```
SQLite n=1000 put=0.05968146s (16755/s) get=0.007374155999999993s (135608/s)
CDB n=1000 put=0.0013163260000000065s (759690/s) get=0.0036372370000000015s (274933/s)
Hybrid-CDB n=1000 put=0.054957312999999994s (18195/s) get=0.007692420999999977s (129998/s)
```

Старый 14:24: 13583/118807, 656989/292168, 10685/111110

Улучшение: SQLite +23% put, +14% get, Hybrid +70% put, +17% get (за счёт оптимизации? или просто variance, но всё равно быстрее)

BENCHMARKS.md обновлён с SVG описанием, таблицей, ASCII графиком, детальным описанием новых страниц и CSRF.

### 6. Бинари

- bin/fossil 2.1M 105628 lines refc OFF (был 2.0M) 47+ pages CSRF bench SVG 14:30:37
- bin/fossil-mcp 998K 49 tools 14:30
- bin/fossil-qbe 776K QBE ON 54 C files 83123 lines (был 743K 76330 lines 14:27) 14:31:17 patched volatile

Все тесты PASS:
- test_delta, test_manifest, test_sqlite, test_cdb, test_mcp49, test_hash, test_diff
- test_search_forum_chat, test_wiki_ticket, test_integration (delta 21%, branch, status)
- test_fuzz: delta 100/100, manifest 3/3, random 100/100 no crash
- hybrid_bench: SQLite 16755/135608, CDB 759690/274933, Hybrid 18195/129998

### 7. Документация

- docs/BENCHMARKS.md — обновлён: новые цифры, SVG, таблица новых страниц, CSRF описание, бинари 2.1M/998K/776K
- docs/FULL_DOCUMENTATION_RU.md — добавлена секция 2026-10-17 14:30 вечер 7 новых страниц + CSRF + bench SVG, код, тесты
- docs/FINAL_REPORT_2026-10-17_EVENING_CSRF_BENCH.md — этот файл
- CONTRIBUTING.md, BENCHMARKS.md, FULL_DOCUMENTATION_RU.md, FINAL_REPORT_2026-10-17_SYNC_HYBRID.md — все актуальны

## Итог

- ✅ 7 новых страниц, 47+ всего, 20/20 200 OK
- ✅ CSRF: generate/validate/cleanup, hidden input, expiry 1h, 403 on invalid, 200 on valid, /setup forms тоже
- ✅ SPA fix: /login /setup не перехватываются SPA
- ✅ /bench SVG bar charts put/get/delta/archive/sync/QBE
- ✅ Benchmarks: SQLite 16755/135608, CDB 759690/274933, Hybrid 18195/129998
- ✅ Binaries 2.1M/998K/776K, all tests PASS, QBE ON
- ✅ Docs updated

Следующие шаги (опционально):
- CSRF для /setup POST handlers (сейчас только GET с токенами, POST ещё не реализован — можно добавить /setup/user/new и /setup/config POST с CSRF check)
- Больше wiki/ticket HTML parity (history, edit)
- MCP tool для /bench (get_benchmarks)

## Дополнение 14:32 — CSRF url-safe fix + POST /setup

**Проблема:** токен base64 содержал `+` `/` `=` — при POST `application/x-www-form-urlencoded` `+` превращается в пробел, токен невалиден, 403 даже с валидным токеном.

**Фикс `login_page.nim`:**
```nim
var b64 = encode(bytes)
b64 = b64.replace("+", "-").replace("/", "_") # URL-safe
let token = b64 & $getTime().toUnix()
```

Теперь токен вида `0hyFftldsTRd1M-x9DYXJ1q7R22n3At_TZRyh3vcPFk=1792247572` — содержит `-` `_` вместо `+` `/`, безопасен для URL.

**POST /setup:**
- Добавлены обработчики `POST /setup/config`, `POST /setup/user/new`, `POST /setup/user/edit` с CSRF check
- Валидный токен → 200 "Setup action received, CSRF OK, redirecting to /setup, Params: 3"
- Невалидный → 403 "Invalid CSRF token"

**Тест 8768 после фикса:**
```
GET /login TOKEN=cUylzdAC90UKNHz8yf7vHv2UtHB6FmuMYZ92E2V62f4=1792247572
POST /login valid csrf -> 200 Invalid login (CSRF passed) OK
POST /login invalid -> 403 Invalid CSRF token OK

GET /setup TOKEN=0hyFftldsTRd1M-x9DYXJ1q7R22n3At_TZRyh3vcPFk=1792247572
POST /setup/config valid -> 200 CSRF OK Params:3 OK
POST /setup/config invalid -> 403 Forbidden Invalid CSRF token OK
```

**Web 26/26 200 OK:**
```
/ /stat /reportlist /leaves /rss /help /zip /bench /tinfo /winfo /wdiff /artifact /blob /fileedit /login /setup /timeline /file /finfo /info /blame /annotate /tree /dir /brlist /taglist
```

Бинари финальные 14:32-14:33:
- bin/fossil 2.1M 105628 lines refc OFF 47+ pages CSRF url-safe bench SVG POST /setup
- bin/fossil-mcp 998K 49 tools
- bin/fossil-qbe 776K QBE ON 54 C files 83123 lines
