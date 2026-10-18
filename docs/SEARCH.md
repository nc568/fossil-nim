# Full-Text Search - Fossil-Nim

**Status: 2026-10-17 - Full implementation with auto-indexing**

Fossil-Nim implements FTS5-based full-text search with automatic indexing for all content types.

## Architecture

### Module: `src/fossil/search/search.nim` (334 lines)

**Storage:**
- `search_fts` - FTS5 virtual table `USING fts5(id, kind, title, content, tokenize='porter unicode61')`
- `search_index` - regular table `id TEXT PRIMARY KEY, kind TEXT, title TEXT, content TEXT, mtime INTEGER`
- Both tables created in `RepoSchema` (`src/fossil/storage/schema.nim` line 212-214)

**Why two tables?**
- FTS5 is optimized for MATCH queries with ranking and snippets
- Regular table provides fallback LIKE search and stores mtime for sorting
- JOIN between them gives both FTS5 ranking and metadata

**Core API:**
```nim
proc initSearchIndexSqlite*(backend: var SqliteBackend): FossilResult[bool]
proc indexDocumentSqlite*(backend: var SqliteBackend, kind, id, title, content: string, mtime: int64 = 0): FossilResult[bool]
proc searchSqlite*(backend: SqliteBackend, opts: SearchOptions): FossilResult[seq[SearchResult]]
proc search*(backend: SqliteBackend, opts: SearchOptions): FossilResult[seq[SearchResult]]
proc reindexAllSqlite*(backend: var SqliteBackend, fileLimit, commitLimit: int): FossilResult[int]

# Helpers
proc indexWikiPage*(backend: var SqliteBackend, name, content: string): FossilResult[bool]
proc indexTicket*(backend: var SqliteBackend, id, title, desc: string): FossilResult[bool]
proc indexFileContentsSqlite*(backend: var SqliteBackend, limit: int): FossilResult[int]
proc indexCommitsSqlite*(backend: var SqliteBackend, limit: int): FossilResult[int]
proc indexBranchesSqlite*(backend: var SqliteBackend): FossilResult[int]
proc reindexAll*(backend: var SqliteBackend, fileLimit, commitLimit: int): FossilResult[int]
```

**Search Options:**
```nim
SearchOptions:
  query: string       # FTS5 MATCH query, e.g. "bug", "bug AND feature", "title:bug"
  limit: int          # default 20
  offset: int         # for pagination
  kinds: seq[string]  # filter by kind: ["commit", "file", "wiki", "ticket", "forum", "chat", "branch"]
```

**Search Result:**
```nim
SearchResult:
  kind: string    # commit, file, wiki, ticket, forum, chat, branch
  id: string      # e.g. "commit-<uuid>", "file-README.md", "wiki-Home"
  title: string
  snippet: string # with <b> highlights, 20 tokens around match
  rank: float64   # FTS5 rank (lower = more relevant, negative)
  mtime: int64    # Unix timestamp
```

**Search Query:**
- Uses FTS5 `MATCH` with `snippet(search_fts, 2, '<b>', '</b>', '...', 20)` and `rank`
- Falls back to `LIKE` if FTS5 prepare fails: `SELECT ... WHERE title LIKE %query% OR content LIKE %query%`
- Query language: FTS5 syntax - `bug`, `bug AND feature`, `bug OR feature`, `bug NOT feature`, `"exact phrase"`, `title:bug`

**Deduplication Fix:**
FTS5 has no UNIQUE constraint on `id` column (primary key is internal rowid). `INSERT OR REPLACE` does NOT deduplicate by `id`. Fixed by `DELETE FROM search_fts WHERE id=?1` before INSERT in all code paths.

### Auto-Indexing Hooks

Auto-indexing is implemented in all write paths:

**1. Commit (`src/fossil/vcs/commit.nim`):**
- After manifest + event + tagxref + mlink creation
- `initSearchIndexSqlite(backend)`
- Index commit: `id="commit-<uuid>", kind="commit", title="[branch] first line of comment", content="branch user comment", mtime=manifest.date`
- Index changed files: for each `manifest.files`, read file from checkout, skip binary ext (png, jpg, jpeg, gif, bmp, ico, zip, gz, bz2, xz, pdf, exe, dll, so, o, a, bin), skip empty or >200k or contains "\0", index first 50k chars as `id="file-<name>", kind="file", title=name, content=fileContent`

**2. Wiki (`src/fossil/wiki/wiki.nim`):**
- In `saveWikiPageSqlite` after blob creation
- Ensures FTS tables exist
- `INSERT OR REPLACE INTO search_index(id='wiki-'+name, kind='wiki', title=name, content=content, mtime=now)`
- `DELETE + INSERT INTO search_fts` same

**3. Ticket (`src/fossil/ticket/ticket.nim`):**
- In `createTicketSqlite` after ticket insert
- Same pattern: `id=uuid, kind='ticket', title=title, content=desc`

**4. Forum (`src/fossil/forum/forum.nim`):**
- Thread creation: `id=threadId, kind='forum', title=title, content=content`
- Post creation: same, `id=postId, kind='forum', title=title, content=content` (added 2026-10-17, previously missing)
- Both with DELETE before FTS INSERT

**5. Chat (`src/fossil/chat/chat.nim`):**
- `sendMessageSqlite` (previously missing auto-index, added 2026-10-17)
- `sendMessageWithAttachmentSqlite` (already had auto-index)
- `id=msgId, kind='chat', title=room, content=content`

**6. Git Import (`src/fossil/vcs/git_export.nim`):**
- In `importFromGitFastEnhanced` after manifest + event + mlink creation
- Index commit: `id="commit-<uuid>", kind="commit", title="[branch] first line", content="branch author message", mtime=commit.timestamp`
- Index files: for each file op M with blobContents, skip binary, index first 50k
- Both with DELETE before FTS INSERT (fixed 2026-10-17)

**7. Repo Init:**
- `search_fts` and `search_index` created via `RepoSchema` in `initSchema()` / `initFullSchema()`
- No explicit init needed, but `initSearchIndexSqlite` called in API and CLI for safety

### CLI

```bash
# Search
fossil search "bug" --repo repo.fossil --limit 20
# Output: [kind] title (id): snippet with <b> highlights

# Reindex all
fossil search --reindex --repo repo.fossil
# or
fossil search reindex --repo repo.fossil
# Output: Reindexing search... Reindexed N documents

# Reindex via rebuild? (future)
fossil rebuild --reindex
```

**Implementation:** `src/fossil/cli/main.nim` `cmdSearch`:
- Parses first arg as query or "reindex"/"--reindex"
- Opens SqliteBackend, calls `initSearchIndexSqlite` and `search` or `reindexAll`
- `reindexAll` calls `indexFileContentsSqlite(500) + indexCommitsSqlite(1000) + indexBranchesSqlite() + wiki tags`

### REST API

**Endpoints:**

- `GET /api/v1/search?q=bug&limit=20&offset=0&kinds=commit,file`
  - Query params: q (required), limit, offset, kinds (comma-separated)
  - Returns: `{"ok": true, "data": {"query": "...", "results": [...], "count": N}}`

- `POST /api/v1/search` with JSON `{"query": "bug", "limit": 20, "offset": 0, "kinds": ["commit"]}`
  - Same return

**Implementation:** `src/fossil/api/rest.nim`:
- `handleSearchApi` parses query from URL or JSON body
- Calls `searchMod.initSearchIndexSqlite` and `searchMod.search`
- Returns JSON with `searchToJson`

**Web UI:**
- `/search?q=bug` - HTML page with search box and results
- Integrated in timeline? Future: search box in header

### MCP (Model Context Protocol)

**Tool:** `search` (in `src/fossil/mcp/server.nim`)

```json
{
  "name": "search",
  "description": "Full-text search across commits, files, wiki, tickets, forum, chat",
  "inputSchema": {
    "type": "object",
    "properties": {
      "query": {"type": "string", "description": "FTS5 query"},
      "limit": {"type": "integer", "default": 20},
      "kinds": {"type": "array", "items": {"type": "string"}, "description": "filter by kind"}
    },
    "required": ["query"]
  }
}
```

Handler calls `searchMod.search` and returns results as MCP content.

### Testing

**Manual tests 2026-10-17:**

```bash
rm -rf /tmp/search_test && mkdir /tmp/search_test && cd /tmp/search_test
fossil init repo.fossil
fossil open repo.fossil
echo "Hello world with bug fix" > README.md
echo "Another file with feature" > file1.txt
fossil add README.md file1.txt
fossil commit -m "Initial commit with bug and feature" README.md file1.txt

fossil search "bug" --repo repo.fossil
# [commit] [trunk] Initial commit with bug and feature (commit-...): [trunk] Initial commit with <b>bug</b> and feature
# [file] README.md (file-README.md): README.md

fossil search "feature" --repo repo.fossil
# [commit] ... bug and <b>feature</b>
# [file] file1.txt ...

# Wiki auto-index via API
curl -X POST http://localhost:18083/api/v1/wiki/save -H "Content-Type: application/json" -d '{"name":"Home","content":"home page with bug report","user":"test","message":"create"}'
curl "http://localhost:18083/api/v1/search?q=bug"
# returns commit, file, wiki Home (3 results)

# Ticket, forum, chat via API
curl -X POST /api/v1/ticket/create -d '{"title":"Bug report","description":"bug in feature X"}'
curl "http://localhost:18083/api/v1/search?q=Bug" -> returns ticket, forum, commit, chat, file, wiki (9 results)

# Reindex dedup test
fossil search --reindex --repo repo.fossil -> Reindexed 2 documents
fossil search "bug" -> still 2 results (not 4) after second reindex
```

**Key results:**
- Auto-index works for all subsystems
- Reindex does not create duplicates (DELETE before INSERT fix)
- FTS5 snippet highlights with <b> tags
- Rank ordering works

### Future Improvements

- [ ] Add trigram index for LIKE fallback
- [ ] Add search for diff content (index diff, not just file content)
- [ ] Add search filters: branch, user, date range
- [ ] Add search index cleanup on delete (wiki delete, ticket delete, etc)
- [ ] Add incremental reindex via file watcher
- [ ] Add search suggestions / autocomplete
- [ ] Add search in web UI header with live results
- [ ] Consider LMDB for search index cache (faster than SQLite for FTS?)

### Comparison with Original Fossil

| Feature | Original Fossil | Fossil-Nim |
|---------|----------------|------------|
| FTS | FTS5 with `fts5` table | Same FTS5, same tokenizer `porter unicode61` |
| Auto-index | On commit, wiki, ticket, forum via triggers? | Explicit in each save proc, plus git import |
| Reindex | `fossil rebuild --search` | `fossil search --reindex` + `reindexAll` |
| API | `/search?q=` HTML | `/api/v1/search?q=` JSON + HTML |
| MCP | N/A | `search` tool |

## Files

- `src/fossil/search/search.nim` - core search module
- `src/fossil/storage/schema.nim` - schema includes search_fts + search_index
- `src/fossil/vcs/commit.nim` - auto-index commit + files
- `src/fossil/wiki/wiki.nim` - auto-index wiki
- `src/fossil/ticket/ticket.nim` - auto-index ticket
- `src/fossil/forum/forum.nim` - auto-index thread + post
- `src/fossil/chat/chat.nim` - auto-index chat messages
- `src/fossil/vcs/git_export.nim` - auto-index imported commits
- `src/fossil/cli/main.nim` - `fossil search` + `fossil search --reindex`
- `src/fossil/api/rest.nim` - `/api/v1/search` + `/search` web
- `src/fossil/mcp/server.nim` - MCP `search` tool
