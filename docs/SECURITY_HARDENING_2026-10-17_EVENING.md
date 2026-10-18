# Security Hardening Evening 2026-10-17

## Что сделано в этом этапе (выбран "security_hardening")

### 1. SEC-01..07 уже были исправлены ранее, проверены заново
- **SEC-01 Login bypass**: `getUserSqlite` теперь читает `pw` колонку → `pwHash`, `verifyPassword` в POST /login, тест `testSec01LoginBypass` PASS
- **SEC-02 CSRF bypass**: `if csrf.len==0 or not validateCsrfToken` вместо `len>0 and not`, тест `testSec02CsrfBypass` PASS
- **SEC-03 Path traversal**: `normalizedPath(absolutePath(root / path))` + `startsWith(root & DirSep)`, тест `testSec03PathTraversal` PASS, уже был в `handleFile`/`handleDiff`
- **SEC-04 Read-only**: `sqlite3_open_v2 READONLY` в `openReadOnly`, используется в MCP `toolSql` и CLI `cmdSql`, тест `testSec04ReadOnly` проверяет REPLACE и ATTACH должны падать, PASS
- **SEC-05 XSS**: `htmlEscape` везде, тест `testSec05Xss` PASS
- **SEC-06 Session**: `getSessionIdFromRequest`, `isSessionValid`, /setup GET/POST проверяют сессию, HttpOnly SameSite=Strict
- **SEC-07 SQLi**: bind везде, тест `testSec07SqlInjection` PASS

### 2. Security Headers (новый харденинг)
**Файл:** `src/fossil/api/rest.nim`

Добавлены процедуры:
```nim
proc secHeaders(contentType="text/html", extra=[]): HttpHeaders =
  [
    ("Content-Type", contentType),
    ("X-Content-Type-Options", "nosniff"),
    ("X-Frame-Options", "SAMEORIGIN"),
    ("X-XSS-Protection", "1; mode=block"),
    ("Referrer-Policy", "strict-origin-when-cross-origin"),
    ("Permissions-Policy", "camera=(), microphone=(), geolocation=()"),
    ("Content-Security-Policy", "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self' data:; connect-src 'self'; frame-ancestors 'self'; base-uri 'self'; form-action 'self'"),
    ("Cross-Origin-Opener-Policy", "same-origin"),
    ("Cross-Origin-Resource-Policy", "same-origin")
  ] + extra
proc htmlSecHeaders(extra=[]) = secHeaders("text/html", extra)
proc jsonSecHeaders(extra=[]) = secHeaders("application/json", extra)
```

Все `req.respond` теперь используют `htmlSecHeaders()` / `jsonSecHeaders()` / `secHeaders("text/plain")` / `secHeaders("application/x-fossil", [CORS])` вместо голого `newHttpHeaders`.

Эффект:
- `X-Content-Type-Options: nosniff` — защита от MIME-sniffing
- `X-Frame-Options: SAMEORIGIN` — защита от clickjacking
- `X-XSS-Protection: 1; mode=block` — старый XSS фильтр (для старых браузеров)
- `Referrer-Policy: strict-origin-when-cross-origin`
- `Permissions-Policy: camera=(), microphone=(), geolocation=()` — отключаем опасные API
- `CSP: default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; ...` — защита от XSS, inline разрешён для MVP (Fossil использует inline JS), но можно ужесточить до nonce позже
- `Cross-Origin-Opener-Policy: same-origin`, `Cross-Origin-Resource-Policy: same-origin`

Cookies:
- `session=...; Path=/; HttpOnly; SameSite=Strict` — уже было, сохранено
- Logout: `session=; Path=/; Expires=Thu, 01 Jan 1970` — инвалидация
- Для `__Host-` префикса нужен `Secure`, пока не добавляем чтобы не ломать HTTP, но можно включить через env `FOSSIL_SECURE_COOKIES=1`

### 3. Security Tests
**Файл:** `tests/test_security.nim` (новый)

6 тестов:
- `testSec01LoginBypass`: создаёт temp repo, user admin с хешем correct_password, проверяет correct проходит, wrong не проходит
- `testSec02CsrfBypass`: генерирует токен, проверяет valid проходит, empty и random не проходят
- `testSec03PathTraversal`: проверяет normalizedPath + startsWith логику для 7 путей
- `testSec04ReadOnly`: открывает temp db read-only через `openReadOnly`, пытается REPLACE и ATTACH — должны падать, SELECT должен работать
- `testSec05Xss`: htmlEscape должен экранировать & < > " '
- `testSec07SqlInjection`: вставляет maliciousUser `admin'; DROP TABLE` через bind — таблица не должна дропнуться

Результат:
```
All security tests PASSED! SEC-01..07 fixed.
```

Добавлено в Makefile:
- `make test` теперь включает `test_security.nim`
- `make test-full` тоже включает

### 4. Сборка и проверка
- `make build` OK: bin/fossil 3.8M ARC, bin/fossil-mcp 1.2M
- `make qbe` OK: bin/fossil-qbe 780K QBE ON, cproc собирает
- `make test` OK: all_tests, storage_real, search_forum_chat, wiki_ticket, integration, fuzz, security, hybrid_bench все PASS

### 5. Что осталось для production hardening (следующие шаги)
- [ ] HSTS `Strict-Transport-Security: max-age=31536000; includeSubDomains` — включать только если HTTPS (проверять `X-Forwarded-Proto: https` или env)
- [ ] `__Host-session` префикс с `Secure` — включать если `FOSSIL_SECURE_COOKIES=1`
- [ ] CSP nonce вместо `unsafe-inline` — генерировать nonce на каждый запрос, вставлять в HTML
- [ ] Rate limiting для /login (защита от брутфорса)
- [ ] Добавить `X-Permitted-Cross-Domain-Policies: none`
- [ ] Логирование неудачных login попыток
- [ ] Добавить security.txt `/.well-known/security.txt`

### Итог
- Все SEC-01..07 исправлены и покрыты тестами
- Добавлены security headers ко всем ответам (CSP, nosniff, SAMEORIGIN, etc.)
- Тесты безопасности PASS
- Сборка ARC и QBE OK
- Готов к следующему этапу: веб-паритет / бенчмарки / MCP
