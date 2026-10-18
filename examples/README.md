# Examples

## MCP Client (Python)

`mcp_client.py` shows how an AI agent interacts with Fossil via MCP stdio transport.

```bash
./bin/fossil-mcp &
python3 examples/mcp_client.py ./bin/fossil-mcp
```

## API Client (Python)

`api_client.py` shows REST API usage.

```bash
./bin/fossil server --api-enable -P 8080 &
python3 examples/api_client.py
```

## Nim API Usage

```nim
import fossil

# Open sqlite backend
var backend = SqliteBackend()
discard backend.open("my.fossil")

# Get timeline
let filter = defaultFilter()
let timeline = backend.getTimeline(filter)
echo timeline

# Commit
var opts = CommitOptions(message: "fix", user: "me")
let res = backend.commit(opts, ".")
echo res
```

## QBE Build Example

```bash
make build-qbe-c
cproc -O2 -std=c11 -Ibuild/cgen -Icinterop/include -o fossil-qbe build/cgen/*.c -lsqlite3 -lz
./bin/fossil-qbe version
```
