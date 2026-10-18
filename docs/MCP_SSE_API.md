# MCP SSE + Prompts + API Auth + OpenAPI

## MCP Transports

### stdio (default)

```bash
fossil mcp serve
# or
fossil mcp serve --stdio
```

JSON-RPC 2.0 over stdin/stdout, protocol 2024-11-05.

Example:

```bash
echo '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | fossil mcp serve
```

### SSE (Server-Sent Events) + POST

```bash
fossil mcp serve --sse --port 3000 --bind 127.0.0.1
```

Endpoints:

- `GET /sse` - SSE stream (text/event-stream), sends endpoint event
- `POST /message` - JSON-RPC messages
- `GET /` - HTML help page

Example:

```bash
# Start server
fossil mcp serve --sse --port 3000 &
# List tools
curl -X POST http://127.0.0.1:3000/message -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
# List prompts
curl -X POST http://127.0.0.1:3000/message -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","id":2,"method":"prompts/list"}'
# Get prompt
curl -X POST http://127.0.0.1:3000/message -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","id":3,"method":"prompts/get","params":{"name":"commit-message","arguments":{"diff":"- old + new"}}}'
```

Implementation in `src/fossil/mcp/server.nim`:

- `runStdioLoop` - stdio loop
- `runSseLoop` - async HTTP server with SSE
- `runSseLoopSync` - sync wrapper

## MCP Prompts

Prompts are templates for LLMs to generate text.

### List

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "prompts/list"
}
```

Response:

```json
{
  "prompts": [
    {"name": "commit-message", "description": "Generate commit message from diff"},
    {"name": "code-review", "description": "Review changes"},
    {"name": "release-notes", "description": "Generate release notes"}
  ]
}
```

### Get

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "prompts/get",
  "params": {
    "name": "commit-message",
    "arguments": {
      "diff": "diff --git a/file b/file\n- old\n+ new",
      "branch": "trunk"
    }
  }
}
```

Response:

```json
{
  "description": "Generate commit message from diff",
  "messages": [
    {
      "role": "user",
      "content": {
        "type": "text",
        "text": "Generate a concise commit message for branch trunk based on this diff:\n\n..."
      }
    }
  ]
}
```

### Implemented prompts

- `commit-message`: args `diff`, `branch` - generates commit message template with rules (50 chars first line, imperative, conventional commits)
- `code-review`: args `diff`, `file` - review template checking bugs, security, performance, style, tests
- `release-notes`: args `since`, `commits` - release notes template with Features, Bug Fixes, Breaking Changes, Contributors

Code: `handlePromptsList`, `handlePromptsGet` in `server.nim`

## API Auth

### Bearer Token

Set env var `FOSSIL_API_TOKEN`:

```bash
export FOSSIL_API_TOKEN=secret123
fossil server -P 8080
```

Then require token for protected routes (`POST /api/v1/commit`):

```bash
# Without token - 401
curl -X POST http://127.0.0.1:8080/api/v1/commit -d '{"message":"test"}'
# {"ok":false,"error":"Unauthorized","code":401}

# With Authorization header
curl -X POST http://127.0.0.1:8080/api/v1/commit -H "Authorization: Bearer secret123" -H "Content-Type: application/json" -d '{"message":"test"}'

# With query param
curl "http://127.0.0.1:8080/api/v1/timeline?token=secret123"

# With cookie
curl -H "Cookie: token=secret123" http://127.0.0.1:8080/api/v1/commit
```

Implementation: `checkAuth` in `rest.nim` checks:

- `Authorization: Bearer <token>`
- `Authorization: Token <token>`
- `?token=<token>` query param
- `Cookie: token=<token>`

If `FOSSIL_API_TOKEN` not set, auth is disabled (allow all) for backward compat.

### Protected routes

- `POST /api/v1/commit` requires auth if token set
- `GET` routes are public by default (can be made to require auth by setting `requiresAuth: true` in `registerDefaultRoutes`)

## OpenAPI 3.0

Spec endpoint:

```bash
curl http://127.0.0.1:8080/api/v1/openapi.json
curl http://127.0.0.1:8080/openapi.json
```

Returns OpenAPI 3.0.3 JSON with:

- Info: title, version, license
- Servers
- SecuritySchemes: bearerAuth (http bearer), cookieAuth (apiKey cookie)
- Schemas: Error, Status, TimelineEntry
- Paths: `/api/v1/status`, `/api/v1/timeline`, `/api/v1/branches`, `/api/v1/file`, `/api/v1/diff`, `/api/v1/commit`, `/api/v1/info`, `/xfer`, `/clone`

Example spec snippet:

```json
{
  "openapi": "3.0.3",
  "info": {
    "title": "Fossil-Nim API",
    "description": "Fossil-Nim REST API - Git-like DVCS with SQLite/LMDB/MDBX backends, MCP support",
    "version": "2.26.0-nim"
  },
  "components": {
    "securitySchemes": {
      "bearerAuth": {
        "type": "http",
        "scheme": "bearer",
        "bearerFormat": "JWT or API token"
      }
    }
  },
  "paths": {
    "/api/v1/commit": {
      "post": {
        "summary": "Create commit",
        "security": [{"bearerAuth": []}]
      }
    }
  }
}
```

HTML index at `/` shows links to openapi and auth examples.

## Testing

```bash
# MCP prompts via stdio
echo '{"jsonrpc":"2.0","id":1,"method":"prompts/list"}' | ./bin/fossil mcp serve
echo '{"jsonrpc":"2.0","id":2,"method":"prompts/get","params":{"name":"commit-message","arguments":{"diff":"- old + new"}}}' | ./bin/fossil mcp serve

# MCP SSE
./bin/fossil mcp serve --sse --port 13000 &
curl -X POST http://127.0.0.1:13000/message -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' -H "Content-Type: application/json"

# API auth + openapi
FOSSIL_API_TOKEN=secret123 ./bin/fossil server -P 18080 &
curl http://127.0.0.1:18080/api/v1/openapi.json | jq .info
curl -X POST http://127.0.0.1:18080/api/v1/commit -d '{"message":"test"}' # 401
curl -X POST http://127.0.0.1:18080/api/v1/commit -H "Authorization: Bearer secret123" -d '{"message":"test"}' -H "Content-Type: application/json" # 200
```

## Future

- Full SSE streaming (keep connection open, push events)
- OAuth2 / JWT validation
- Rate limiting
- OpenAPI UI (Swagger)
- More prompts: `ticket-description`, `wiki-summary`, etc.
