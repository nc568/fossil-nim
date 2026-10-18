# REST API

Base URL: `http://localhost:8080`

## Core Endpoints (JSON)

Base URL: `http://localhost:8080/api/v1`

### GET /api/v1/status
Returns working tree status (real checkout status via vcsCheckout.status).

Response:
```json
{
  "ok": true,
  "data": {
    "branch": "trunk",
    "modified": ["file.nim"],
    "untracked": ["new.txt"]
  }
}
```

### GET /api/v1/timeline?limit=20&branch=trunk
Returns timeline entries from real `event` table with filters.

### GET /api/v1/file?path=src/main.nim&rev=HEAD
Returns file content at revision (via manifest parsing).

### GET /api/v1/branches
List branches via `tag LIKE 'sym-%'` with COUNT and MAX(mtime).

### GET /api/v1/diff?file=main.nim
Returns unified diff via LCS DP (real diffBlobs).

### POST /api/v1/commit
Body:
```json
{
  "message": "fix bug",
  "files": ["main.nim"],
  "branch": "trunk"
}
```

### GET /api/v1/info
Returns version, storage backend, etc.

## Sync Endpoints (Fossil Protocol, non-JSON)

These implement Fossil's xfer protocol for clone/push/pull.

### GET /clone
Returns bundle of all artifacts as file cards.

Format:
```
file <uuid> <size>
<data>
file <uuid> <size>
<data>
...
```

Content-Type: `application/x-fossil`

Used by `fossil clone http://host/ local.fossil` and `pull`.

### POST /xfer
Fossil sync exchange. Request body is list of cards, response is list of cards.

Request cards:
- `igot <uuid>` - client has artifact
- `gimme <uuid>` - client wants artifact
- `file <uuid> <size>\n<data>` - client pushes artifact

Response cards:
- `gimme <uuid>` - server wants artifact (for push)
- `file <uuid> <size>\n<data>` - server provides artifact (for pull, proactive push)

Logic:
- Server imports any `file` cards from request via `putBlob`.
- Server computes `localUuids` via `getAllUuids`.
- `syncExchangeSqlite`:
  - For each `igot` from remote that local lacks -> `gimme` (request missing)
  - For each `gimme` from remote that local has -> `file` (provide requested)
  - For each local uuid that remote doesn't have (from igot list) -> `file` (proactive push for pull)
- Response encoded via `encodeCard`.

Used by:
- `fossil push http://host/` - sends igot list, receives gimme, sends file
- `fossil pull http://host/` - sends igot, receives file (xfer first, then fallback to /clone)
- `fossil sync` - pull + push

### Example sync flow (push)

```
Client -> Server: POST /xfer
  igot abc...
  igot def...

Server: has 0, needs 2 -> responds gimme
  gimme abc...
  gimme def...

Client -> Server: POST /xfer
  file abc... <size>\n<data>
  file def... <size>\n<data>

Server: imports file cards, now has 2
  (empty response)
```

### Example sync flow (pull)

```
Client (has 1) -> Server (has 7): POST /xfer
  igot <1 uuid>

Server: has 6 extra, client lacks -> responds file
  file <uuid> <size>\n<data> x6

Client: imports 6 files, now has 7
```

## Web UI

### GET /
Simple HTML page with links to `/api/v1/status`, `/api/v1/timeline`, `/api/v1/branches`, `/api/v1/info`, and notes about MCP and sync endpoints.

## CLI Mapping

- `fossil server -P 8080` starts API server with both JSON and xfer endpoints
- `fossil clone <url> <file>` -> GET /clone
- `fossil push <url>` -> POST /xfer igot -> gimme -> file
- `fossil pull <url>` -> POST /xfer igot -> file (fallback to GET /clone)
- `fossil sync <url>` -> pull + push

## Future

- Auth (bearer, cookie)
- OpenAPI spec
- JSON sync endpoint alternative

List tickets.

## Auth

- Cookie auth (same as Fossil web UI)
- Bearer token: `Authorization: Bearer <token>` (configured via `fossil config api-token`)

## OpenAPI

Spec at `/api/openapi.json` (TODO).
