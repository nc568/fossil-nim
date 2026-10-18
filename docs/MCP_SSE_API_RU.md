# MCP SSE + Промпты + API Auth + OpenAPI (RU)

## MCP Транспорты

### stdio (по умолчанию)

```bash
fossil mcp serve
```

JSON-RPC 2.0 поверх stdin/stdout, протокол 2024-11-05.

### SSE (Server-Sent Events) + POST

```bash
fossil mcp serve --sse --port 3000 --bind 127.0.0.1
```

Эндпоинты:
- `GET /sse` - SSE поток (text/event-stream)
- `POST /message` - JSON-RPC сообщения
- `GET /` - HTML справка

Пример:

```bash
fossil mcp serve --sse --port 3000 &
curl -X POST http://127.0.0.1:3000/message -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

Реализация в `src/fossil/mcp/server.nim`: `runStdioLoop`, `runSseLoop`, `runSseLoopSync`.

## MCP Промпты

Промпты - шаблоны для LLM.

### list

```json
{"jsonrpc":"2.0","id":1,"method":"prompts/list"}
```

Ответ: `commit-message`, `code-review`, `release-notes`.

### get

```json
{
  "jsonrpc":"2.0","id":2,"method":"prompts/get",
  "params":{"name":"commit-message","arguments":{"diff":"- old + new","branch":"trunk"}}
}
```

Ответ с `description` и `messages` для LLM.

Реализованные промпты:
- `commit-message` - генерация коммит-сообщения из diff, правила 50 символов, imperative, conventional commits
- `code-review` - ревью с проверкой багов, безопасности, производительности, стиля, тестов
- `release-notes` - релиз-ноты с Features, Bug Fixes, Breaking Changes, Contributors

Код: `handlePromptsList`, `handlePromptsGet`.

## API Auth

Bearer токен через env `FOSSIL_API_TOKEN`:

```bash
export FOSSIL_API_TOKEN=secret123
fossil server -P 8080
# Без токена - 401
curl -X POST http://127.0.0.1:8080/api/v1/commit -d '{"message":"test"}'
# С токеном
curl -X POST http://127.0.0.1:8080/api/v1/commit -H "Authorization: Bearer secret123" -H "Content-Type: application/json" -d '{"message":"test"}'
# Через query
curl "http://127.0.0.1:8080/api/v1/timeline?token=secret123"
# Через cookie
curl -H "Cookie: token=secret123" http://127.0.0.1:8080/api/v1/commit
```

Реализация `checkAuth` в `rest.nim` проверяет Authorization Bearer/Token, ?token=, Cookie token=. Если `FOSSIL_API_TOKEN` не задан - auth отключен.

Защищенные маршруты: `POST /api/v1/commit` требует auth если токен задан, GET публичные.

## OpenAPI 3.0

Эндпоинты спеки:

```bash
curl http://127.0.0.1:8080/api/v1/openapi.json
curl http://127.0.0.1:8080/openapi.json
```

Возвращает OpenAPI 3.0.3 JSON с info, servers, securitySchemes (bearerAuth, cookieAuth), schemas (Error, Status, TimelineEntry), paths (/status, /timeline, /branches, /file, /diff, /commit, /info, /xfer, /clone).

HTML индекс `/` показывает ссылки на openapi и примеры auth.

## Тестирование

```bash
echo '{"jsonrpc":"2.0","id":1,"method":"prompts/list"}' | ./bin/fossil mcp serve
./bin/fossil mcp serve --sse --port 13000 &
curl -X POST http://127.0.0.1:13000/message -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' -H "Content-Type: application/json"
FOSSIL_API_TOKEN=secret123 ./bin/fossil server -P 18080 &
curl http://127.0.0.1:18080/api/v1/openapi.json | jq .info
```
