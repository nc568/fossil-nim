# Web Full Parity + Git Export/Import Fixes - 2026-10-17

## Summary
On 2026-10-17, two major tasks were completed:
1. **Git fast-export/import full implementation** (was stub with empty commits)
2. **Web full parity** - added 10+ missing pages for complete Fossil UI

Also cleaned up workspace (951 MB → 9.6 MB) by removing .bun, .npm caches.

## Git Export/Import - From Stub to Full

### Before (stub 98 lines)
```nim
proc exportToGitFast*(backend: SqliteBackend, opts: GitExportOptions): FossilResult[string] =
  # Only empty commits, no file content
  output.add "commit refs/heads/" & branch & "\n"
  output.add "mark :" & $mark & "\n"
  output.add "data 0\n\n\n"
  
proc importFromGitFast*(backend: SqliteBackend, inputPath: string): FossilResult[int] =
  # Only counts commits, no real import
  var count=0
  for line in content.splitLines():
    if line.startsWith("commit "): inc count
  ok(count)
```

### After (full 512 lines)
**Export:**
- `getFilesForManifestSqlite()` - queries mlink+filename+blob with fallback, returns file list with rid+uuid
- Blob marks from 10000+, M 100644 ops, parent tracking per branch, ASC sort by mtime reversed to chronological oldest-first
- Real file content: `blob\nmark :10000\ndata 25\nHello World\nmore content\n\n`
- Commit with author, email, timestamp, message, from parent, file ops
- Example 400 bytes for 1 commit with 2 files, 533 bytes for 2 commits

**Import:**
- Two-pass: first pass extracts blobs (mark -> content, putBlob, blobRids table)
- Second pass parseGitFastImport (author/email/timestamp, fromMark, M/D ops, branch)
- Manifest building C/D/U/E/P/F/R cards, putBlob, event INSERT, mlink+filename INSERT
- Parent tracking prevRidByBranch, returns count

**Bugs fixed:**
1. Infinite loop in CLI arg parsing: `try: limit=parseInt() except: discard; i+=2` - i+=2 was inside except only, not always. Fixed to multi-line try/except with i+=2 outside.
2. Commit included repo.fossil files: buildManifestFromWorkingTree scanned all files including *.fossil, *.fossil-shm, *.fossil-wal. Added filter.
3. Commit file args ignored: cmdCommit didn't parse file args, opts.files always empty. Fixed to collect non-option args.
4. Export order wrong: getTimeline returns newest-first, but git fast-export needs oldest-first. Added reverse().
5. Import mlink wrong columns: INSERT INTO mlink(mid, fnid, fid, isaux) - wrong order and non-existing column. Fixed to (mid, fid, fnid).
6. Import parser blob vs commit confusion: when blob after commit, data line was mistaken as commit message, overwriting message with "Second file". Fixed by saving commit when encountering blob.

**Test:**
- 3-commit roundtrip: commit1 a=v1, commit2 a=v2,b=b1, commit3 a=v3,b=b2,c=c1
- Export 65 lines, 3 commits oldest-first with from references
- Import 3 commits, timeline correct
- Checkout files v3,b2,c1 - SUCCESS

## Web Full Parity

### New module: full_parity.nim (400+ lines)
- renderDiffPage, renderBlamePage, renderTreePage, renderBrlistPage, renderTaglistPage, renderRawPage, renderHelpPage, renderSitemapPage
- getBranchesForBrlist, getTagsForTaglist

### Enhanced rest.nim (2220 → 2546 lines, +326)
**New API handlers:**
- handleBlame, handleBrlist, handleTaglist, handleTree, handleRaw

**New web pages:**
- /diff, /blame, /annotate, /tree, /dir, /brlist, /taglist, /raw, /zip, /tarball, /help, /sitemap

**Tests:**
All endpoints tested with curl, 200 OK:
- /help, /sitemap, /brlist, /tree, /diff?name=README.md, /blame?name=README.md
- /api/v1/brlist, /api/v1/taglist, /api/v1/blame?name=README.md

### Comparison
| Feature | Before | After |
|---------|--------|-------|
| Pages | ~20 | 30+ (core full parity) |
| Diff | basic | Myers with unified, buttons to history/blame/file/raw |
| Blame | missing | table with lineNum, author, date, content |
| Tree/Dir | missing | breadcrumb, dirs 📁, files 📄, ZIP/Tarball links |
| Brlist | missing | table with branch, commits, last mtime, tip, actions |
| Taglist | missing | table with tag, type, count |
| Help | basic | complete with all pages, API, CLI, storage, QBE, MCP |
| Sitemap | missing | grouped by Core VCS, Wiki, Tickets, Forum & Chat, Search & Help, API |

## Workspace Cleanup
- Before: 951.6 MB across 574 files, 29 files not saved (over 128 MB limit)
- After: 9.6 MB, 176 files
- Removed: .bun (873M), .npm (305M), fossil-nim/bin (8.8M), fossil-nim/build (2.5M)
- Kept: src (784K), docs (316K), cinterop (1.7M with mdbx.c), bin-tools (996K with cproc/qbe)

## Build
- 102831 lines (was 101862), 1.8M binary
- SuccessX with warnings only (unused imports, GC-unsafe gApiConfig)
- Binary at /tmp/fossil_new, tested help, timeline, diff, blame, tree, brlist, etc.

## Documentation
- docs/WEB_FULL_PARITY.md (7.6K) + WEB_FULL_PARITY_RU.md (9.9K)
- This summary: WEB_FULL_PARITY_SUMMARY_2026-10-17.md
- Help page /help and sitemap /sitemap in web UI

## Next Steps
- Real ZIP/Tarball generation
- Wiki history wcontent/whistory
- Reportlist for tickets
- Graph rendering with JS
- Search auto-index (already has FTS5, need auto-index on commit)

## Files Changed
- src/fossil/vcs/git_export.nim: 98 → 512 lines, full implementation
- src/fossil/vcs/commit.nim: added filter for *.fossil files
- src/fossil/cli/main.nim: fixed arg parsing infinite loop, added file args for commit, fixed timeline --limit parsing
- src/fossil/web/pages/full_parity.nim: NEW 400+ lines
- src/fossil/api/rest.nim: 2220 → 2546 lines, +326, new handlers and pages
- docs/WEB_FULL_PARITY.md, WEB_FULL_PARITY_RU.md: NEW
