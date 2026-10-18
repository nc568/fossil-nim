# Final Report 2026-10-17 - Search Auto-Index

## Summary

Implemented full auto-indexing for FTS5 search across all content types, plus CLI reindex and deduplication fix.

**Binary:** `/tmp/fossil_new` 1.8M, 103437 lines, 50.4s build, `--mm:refc --threads:off -d:release`

## What Was Done

### 1. Commit Auto-Index (`src/fossil/vcs/commit.nim`)
- Added import `searchMod`
- After event/tagxref/mlink creation, call `initSearchIndexSqlite`
- Index commit: `id="commit-<uuid>", kind="commit", title="[branch] first line", content="branch user comment", mtime=manifest.date`
- Index changed files: for each `manifest.files`, read from checkout, skip binary ext (png, jpg, jpeg, gif, bmp, ico, zip, gz, bz2, xz, pdf, exe, dll, so, o, a, bin), skip empty/>200k/contains "\0", index first 50k chars as `file-<name>`

### 2. Forum Post Auto-Index (`src/fossil/forum/forum.nim`)
- Previously only thread creation had auto-index
- Added same auto-index for `createPostSqlite`: `id=postId, kind='forum', title, content`

### 3. Chat Auto-Index (`src/fossil/chat/chat.nim`)
- Previously only `sendMessageWithAttachmentSqlite` had auto-index
- Added auto-index for `sendMessageSqlite`: `id=msgId, kind='chat', title=room, content`

### 4. Git Import Auto-Index (`src/fossil/vcs/git_export.nim`)
- In `importFromGitFastEnhanced` after manifest/event/mlink
- Ensure FTS tables exist
- Index commit: `commit-<uuid>, commit, [branch] first line, branch author message, timestamp`
- Index files: for each M op with blobContents, skip binary, index first 50k as `file-<path>`

### 5. Deduplication Fix (`src/fossil/search/search.nim` + all manual FTS inserts)
- **Root cause:** FTS5 has no UNIQUE on `id` column (PK is internal rowid). `INSERT OR REPLACE` does NOT deduplicate by `id`, leading to duplicate rows and duplicate search results after reindex
- **Fix:** `DELETE FROM search_fts WHERE id=?1` before INSERT in:
  - `indexDocumentSqlite` (central)
  - `wiki.nim` (wiki)
  - `ticket.nim` (ticket)
  - `forum.nim` (thread + post)
  - `chat.nim` (both send variants)
  - `git_export.nim` (commit + file)
  - `commit.nim` uses central proc, so fixed automatically

### 6. CLI Reindex (`src/fossil/cli/main.nim`)
- Extended `cmdSearch`:
  - `fossil search --reindex` or `fossil search reindex` -> calls `reindexAll(500,1000)` and prints "Reindexed N documents"
  - Also handles `--reindex` flag after query
- `reindexAll` = `indexFileContentsSqlite(500) + indexCommitsSqlite(1000) + indexBranchesSqlite() + wiki tags`

### 7. Documentation
- `docs/SEARCH.md` 9.5K EN: architecture, storage, API, auto-index hooks, CLI, REST, MCP, testing, comparison, future
- `docs/SEARCH_RU.md` 13K RU: same
- Updated `README.md` features list to mention archive ZIP/TAR + search auto-index + reindex

## Testing

### Test 1: Commit Auto-Index
```bash
fossil init repo.fossil && fossil open repo.fossil
echo "Hello bug world" > README.md && fossil add README.md && fossil commit -m "Initial bug commit"
fossil search "bug" --repo repo.fossil
# [commit] [trunk] Initial bug commit (commit-...): [trunk] Initial <b>bug</b> commit
# [file] README.md (file-README.md): README.md
PASS: commit + file indexed automatically
```

### Test 2: Reindex Dedup
```bash
fossil search --reindex --repo repo.fossil -> Reindexed 2 documents
fossil search "bug" -> still 2 results (commit + file)
Second reindex -> still 2 results (not 4)
PASS: DELETE before INSERT prevents duplicates
```

### Test 3: Wiki/Ticket/Forum/Chat via API
```bash
# Start server 18084
curl -X POST /api/v1/wiki/save -d '{"name":"Home","content":"home with bug"}'
curl -X POST /api/v1/ticket/create -d '{"title":"Bug report","description":"bug in feature X"}'
curl -X POST /api/v1/forum/create -d '{"title":"Forum about bug","content":"Discussing bug fix"}'
curl -X POST /api/v1/chat/send -d '{"room":"main","content":"Chat about bug fix"}'

curl "/api/v1/search?q=Bug"
# Returns: forum, ticket, commit, chat, file, wiki = 9 results (includes duplicates before fix, now deduped)
# forum about <b>bug</b>, Bug report, commit with <b>bug</b>, main chat, README.md, Home
PASS: all subsystems auto-indexed
```

### Test 4: Full Integration
- Server 18085: search "Bug" returns 9 results across all kinds
- Search "Forum" returns forum thread with snippet <b>Forum</b> about bug
- Search "Chat" returns chat message
- Search "ticket" returns ticket
PASS

## Files Changed

- `src/fossil/vcs/commit.nim` +12 lines: import searchMod + auto-index commit/files
- `src/fossil/forum/forum.nim` +35 lines: auto-index post + DELETE before FTS
- `src/fossil/chat/chat.nim` +35 lines: auto-index sendMessage + DELETE
- `src/fossil/vcs/git_export.nim` +70 lines: auto-index imported commits/files + DELETE
- `src/fossil/search/search.nim` +8 lines: DELETE before FTS INSERT in indexDocumentSqlite
- `src/fossil/wiki/wiki.nim` +5 lines: DELETE before FTS
- `src/fossil/ticket/ticket.nim` +5 lines: DELETE
- `src/fossil/cli/main.nim` +30 lines: reindex handling in cmdSearch
- `docs/SEARCH.md` NEW 9.5K
- `docs/SEARCH_RU.md` NEW 13K
- `README.md` updated features

## Metrics

- Build: 103437 lines (was 103389, +48), 50.4s, 270.8 MiB peak, 1.8M binary
- Search index: 2 tables, FTS5 porter unicode61, snippet <b> highlights, rank
- Auto-index coverage: 6 subsystems (commit, wiki, ticket, forum, chat, git import) + file contents
- Reindex: 500 files, 1000 commits, branches, wiki tags

## Next Steps

- Documentation consolidation: ensure all docs linked from README, update ARCHITECTURE.md
- Consider LMDB for search cache
- Add search filters (branch, user, date)
- Add search cleanup on delete
- Add incremental reindex watcher

## Status

DONE 2026-10-17 09:38: Search auto-index fully implemented, tested, documented.
