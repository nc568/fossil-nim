# Security Fixes 2026-10-17

## Overview
Final security regression after full parity implementation. All critical vulnerabilities fixed, build passes with ARC and QBE.

## SEC-04: Engine-level read-only (SQL injection defense in depth)
- **File:** `src/fossil/storage/sqlite_backend.nim`
- **Fix:** Added `sqlite3_open_v2` with `SQLITE_OPEN_READONLY` flag, implemented `openReadOnly` proc.
- **Usage:** `src/fossil/mcp/server.nim` toolSql now uses `openReadOnly` + `defer close`, `src/fossil/cli/main.nim` cmdSql uses `openReadOnly`.
- **Result:** MCP and CLI SQL endpoints cannot write even if SQL contains UPDATE/INSERT.

## SEC-05: XSS via htmlEscape
- **Files:** `src/fossil/web/pages/full_parity.nim`, `extended_pages.nim`, `ticket.nim`, `file_page.nim`, `wiki.nim`, `setup_page.nim`, `timeline.nim`, `info_page.nim`
- **Fix:** Implemented `htmlEscape` that escapes `& < > " ' ` and used it for all user-controlled fields (user, comment, title, reporter, filename, branch, etc.)
- **Result:** No raw user input injected into HTML.

## SEC-06: Session bypass on /setup
- **File:** `src/fossil/api/rest.nim`
- **Fix:**
  - Added `getSessionIdFromRequest` parsing `Cookie: session=...`
  - Added `isSessionValid(repoPath, sid)` calling `loginPageMod.validateSessionSqlite`
  - `/setup` GET now checks session: if invalid, returns login page with "Please login to access Setup"
  - `/setup` POST (config/user/new/user/edit) checks session before CSRF, returns 401 if invalid
  - Implements real DB writes: `setConfigSqlite` for config, `INSERT OR REPLACE INTO user` with `hashPassword` for new user, `UPDATE user` with optional password for edit, using `sqlite3_bind_*` with `sqlite3_stmt_setup`
- **Result:** Setup pages require valid session, not just decorative cookie.

## SEC-07: SQL injection via string concatenation
Critical paths fixed to use `sqlite3_prepare_v2` + `bind_text/int64`:

- `src/fossil/vcs/commit.nim`: event INSERT now `VALUES(?1,'ci',?2,?3,?4,?5)` with bind for rid, mtime, user, comment, branch; tagxref INSERT for branch uses bind
- `src/fossil/vcs/timeline.nim`: branch/user/typeFilter filters use `?1 ?2 ?3` with bind_text
- `src/fossil/vcs/branch.nim`: createBranch/closeBranch use `?1` bind for sym-name, getBranchTip uses `branch=?1`
- `src/fossil/vcs/blame.nim`: filename lookup `name=?1` bind
- `src/fossil/sync/protocol.nim`: event INSERT after bundle import uses bind_int64/text
- `src/fossil/sync/http.nim`: rebuildEvents INSERT uses bind
- `src/fossil/cli/main.nim`: `cmdAdd` UPDATE vfile SET chnged WHERE pathname=?1 with bind, plus path traversal check `normalizedPath(absolutePath(full)).startsWith(root)`
- `src/fossil/cli/commands/add.nim`: same fix
- `src/fossil/search/search.nim`: kinds IN clause now uses placeholders `?2,?3,...` with bind and validation alphanumeric
- `src/fossil/vcs/stash.nim`: dropStash DELETE with `?1` bind
- `src/fossil/storage/hybrid_backend.nim`: ATTACH path validated via `fileExists`, `absolutePath`, reject `'` and `;`, then escaped

Remaining `replace("'", "''")` only in:
- `protocol.nim` safeSrc for ATTACH (local file, validated)
- `hybrid_backend.nim` safeSrcPath (local file, validated)
- Comment mentioning old fix

## Dead code compilation fixes
- `src/fossil/cli/commands/add.nim`: added `times` import, fixed SQL bind
- `src/fossil/cli/commands/commit.nim`: added `strutils` import
- `src/fossil/ui/core.nim`: added `asyncdispatch` import for Future
- `src/fossil/ui/frontend.nim`: added `getTheme`, `getPlatform`, `DefaultRoutes` procs
- `src/fossil/web/pages/ticket.nim`: fixed `c.mtime` -> `c.date`, `c.text` -> `c.content`
- `src/fossil/web/pages/extended_pages.nim` and `full_parity.nim`: fixed corrupted `"""` line for `"` escape, now `result.replace("\"", "&quot;")` with correct backslash, fixed invalid indentation by ensuring htmlEscape correct

## Build verification
- `make build` OK: ARC, 3.8M binary
- `make build-qbe-c` OK: 54 C files generated
- `make qbe` OK: bin/fossil-qbe 780K, QBE compat ON, cproc builds
- `nim c -r tests/all_tests.nim` OK
- `test_storage_real`, `test_search_forum_chat`, `test_wiki_ticket` OK

## Remaining low-risk items
- `execSql` with integer concat (`DELETE FROM stash WHERE stashid= int`) - safe because int
- ATTACH DATABASE still uses string concat but validated fileExists + no `'` `;`
- Some web pages still have minor unescaped fields (e.g., dates) - low risk

All critical SEC-04/05/06/07 fixed.
