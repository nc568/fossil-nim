# MCP Server - Fossil Nim

Model Context Protocol (MCP) is an open protocol for AI agents to interact with tools. Fossil-Nim implements a full MCP server.

## Running

```bash
./bin/fossil mcp serve
# stdio mode (for Claude Desktop, etc)
./bin/fossil mcp serve --stdio

# standalone binary
./bin/fossil-mcp
```

## Transport

- **stdio**: JSON-RPC 2.0 over stdin/stdout, line-delimited
- **sse**: Server-Sent Events over HTTP (for remote agents)
- **http**: Streamable HTTP (new MCP spec)

## Initialization

Client sends:
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "initialize",
  "params": {
    "protocolVersion": "2024-11-05",
    "capabilities": {},
    "clientInfo": {"name": "claude", "version": "1.0"}
  }
}
```

Server responds with capabilities: tools, resources, prompts.

## Tools

All tools are defined in `src/fossil/mcp/tools.nim` with JSON Schema.

### VCS Tools

| Tool | Description | Input |
|------|-------------|-------|
| `fossil_status` | Working tree status | `{repoPath?: string}` |
| `fossil_diff` | Diff working vs repo or rev vs rev | `{rev1?: string, rev2?: string, file?: string}` |
| `fossil_commit` | Commit changes | `{message: string, files?: string[], branch?: string}` |
| `fossil_log` | File history | `{file: string, limit?: int}` |
| `fossil_timeline` | Timeline | `{limit?: int, branch?: string, since?: string}` |
| `fossil_branch_list` | List branches | `{}` |
| `fossil_branch_create` | Create branch | `{name: string, base?: string}` |
| `fossil_checkout` | Checkout revision | `{rev: string}` |
| `fossil_blame` | Annotate file | `{file: string, rev?: string}` |
| `fossil_stash_list` | List stashes | `{}` |
| `fossil_stash_save` | Save stash | `{message?: string}` |
| `fossil_info` | Artifact info | `{uuid: string}` |

### Wiki Tools

| Tool | Description |
|------|-------------|
| `fossil_wiki_list` | List wiki pages |
| `fossil_wiki_get` | Get page content |
| `fossil_wiki_create` | Create/edit page |

### Ticket Tools

| Tool | Description |
|------|-------------|
| `fossil_ticket_list` | List tickets with filter |
| `fossil_ticket_get` | Get ticket details |
| `fossil_ticket_create` | Create ticket |
| `fossil_ticket_update` | Update ticket status |

### Advanced

| Tool | Description |
|------|-------------|
| `fossil_sql` | Read-only SQL query (safe) |
| `fossil_artifact_get` | Get raw artifact by uuid |
| `fossil_rebuild` | Rebuild repo with different backend |
| `fossil_sync` | Sync with remote |

### Example: tool call

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/call",
  "params": {
    "name": "fossil_status",
    "arguments": {"repoPath": "/home/user/myrepo"}
  }
}
```

Response:
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
    "content": [{"type": "text", "text": "M file.nim\n? untracked.txt\n"}],
    "isError": false
  }
}
```

## Resources

MCP Resources expose Fossil data as readable URIs:

- `fossil://timeline?limit=100` - timeline as JSON
- `fossil://wiki/{pagename}` - wiki page markdown
- `fossil://ticket/{id}` - ticket JSON
- `fossil://file/{path}@{rev}` - file content at revision
- `fossil://branch/{name}/timeline` - branch timeline
- `fossil://config` - fossil config

List:
```json
{"jsonrpc":"2.0","id":3,"method":"resources/list","params":{}}
```

Read:
```json
{"jsonrpc":"2.0","id":4,"method":"resources/read","params":{"uri":"fossil://wiki/Home"}}
```

## Prompts

Predefined prompts for common workflows:

- `commit-message` - generate commit message from diff
- `code-review` - review changes in a checkin
- `bisect` - help bisect bug
- `release-notes` - generate release notes from timeline

## Security

- `fossil_sql` is read-only, blocked statements: INSERT, UPDATE, DELETE, DROP, etc. Uses `sqlite3` authorizer or mdbx read-only txn.
- File access restricted to repo root + checkout root.
- `fossil_sync` requires explicit allow in config.
- MCP server runs with same permissions as user.

## Integration Examples

### Claude Desktop

`claude_desktop_config.json`:
```json
{
  "mcpServers": {
    "fossil": {
      "command": "/home/user/fossil-nim/bin/fossil-mcp",
      "args": ["--repo", "/home/user/myproject"]
    }
  }
}
```

### VS Code + Cline

`.vscode/settings.json`:
```json
{
  "cline.mcp.servers": {
    "fossil": {"command": "fossil", "args": ["mcp", "serve"]}
  }
}
```

## Implementation Details

`src/fossil/mcp/server.nim`:

- Uses `std/json` for JSON-RPC
- No async needed for stdio mode (blocking read line)
- For SSE/HTTP mode, uses `asynchttpserver`
- Tools are registered via `proc registerTool(name, schema, handler)`

Each tool handler calls `fossil/vcs/*` library functions, not CLI.

Error handling: tool returns `isError: true` with text containing `FossilError.msg`.

## Future

- `fossil_forum` tools for chat
- Streaming diff for large files
- Notifications: `notifications/resources/changed` when repo changes (via file watcher)
