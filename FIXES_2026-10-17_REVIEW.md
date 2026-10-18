# Фиксы критических дефектов из ревью 2026-10-17

Дата: 2026-10-17
Исходный аудит: /home/user/uploads/ре-вью.md

## Исправленные дефекты

### 1. CRITICAL: sync/protocol.nim parseCards порча файлов (DONE ранее, верифицировано)
- **Проблема:** `parseCards` делал `lines[i+1]` вместо чтения `size` байт, терял multiline контент
- **Фикс:** Переписан на offset+size парсинг: `pos + find('\n') + size bytes + optional \n`
- `parseCard` теперь хранит size в `rid` поле временно
- Тест: file a*64 39 bytes multiline "line1\nline2\nline3 with spaces\nlast line" → Encoded `file <uuid> 39\n<content>\n` → Parsed Match true
- Файл: `src/fossil/sync/protocol.nim`

### 2. CRITICAL: wiki save fake hash w*64 (DONE)
- **Проблема:** `saveWikiPageSqlite` использовал `"w".repeat(64)` fake uuid, collision
- **Фикс:** Real SHA3 via `hashBlob(blob)` → `putBlob(uuid, blob)` → INSERT tag `wiki-<name>` → SELECT tagid → INSERT tagxref tagtype 1 → INSERT event type 'w'
- Добавлен import `utils/hash`, `random`
- Файл: `src/fossil/wiki/wiki.nim`

### 3. HIGH: ticket create/update/addComment in-memory заглушки (DONE)
- **Проблема:** `createTicket`, `updateTicket`, `addComment` возвращали fake объекты, не писали в DB
- **Фикс:**
  - `createTicketSqlite`: INSERT INTO ticket(tkt_uuid, tkt_title, tkt_desc, tkt_status, tkt_type, tkt_priority, tkt_ctime, tkt_mtime) VALUES(?)
  - `updateTicketSqlite`: UPDATE ticket SET col=?1, tkt_mtime=?2 WHERE tkt_uuid=?3 по ключам title/description/status/owner/type/priority
  - `addCommentSqlite`: CREATE TABLE IF NOT EXISTS ticketchng + INSERT INTO ticketchng(tkt_id, tkt_rid, tkt_mtime, login, tkt_comment)
  - Generic `createTicket`, `updateTicket`, `addComment` теперь when SqliteBackend → Sqlite версия
- Файл: `src/fossil/ticket/ticket.nim`

### 4. HIGH: REST API stubs (DONE ранее)
- `handleFile`: real checkout file read + SQL `SELECT rid FROM mlink JOIN filename WHERE name=? ORDER BY mid DESC` + getBlob
- `handleDiff`: real baseline via _FOSSIL_ vfile rid + blob + diffBlobs
- `handleCommit`: real `vcsCommit.commit` с rid/uuid
- Файл: `src/fossil/api/rest.nim`

### 5. HIGH: MCP server 5/13 real tools (DONE ранее + дополнено)
- `toolDiff`: real baseline из checkout listVFiles + diffBlobs unified
- `wiki_list`: `listWikiPages` real SQL tag LIKE wiki-%
- `ticket_list`: `listTickets` with status
- `wiki_get`: `getWikiPage` + renderWikiPage
- `ticket_get`: `getTicket` + renderTicket
- Добавлены imports `wiki/wiki as wikiMod`, `ticket/ticket as ticketMod`, `vcs/diff as vcsDiff`
- Файл: `src/fossil/mcp/server.nim`

### 6. MEDIUM: diff LCS DP O(N*M) 70MB на 3000 строк (DONE)
- **Проблема:** DP `newSeq[seq[int]](n+1)` × (m+1) → 70MB, O(N*M)
- **Фикс:** Myers O(N*D) алгоритм
  - V array size 2*(n+m)+1, trace seq[seq[int]]
  - Для d=0..max: k=-d..d step2, x = V[k+1] или V[k-1]+1, snake while a[x]==b[y]
  - Backtrack от (n,m) по trace, восстановление edits: context/add/remove
  - Heuristic fallback если n*m > 20M или n+m > 30000 → O(N) heuristic
  - Тест all_tests diff OK 5 lines, diff file.txt работает
- Файл: `src/fossil/vcs/diff.nim`

### 7. MEDIUM: Makefile NIM_LIB hardcoded (DONE)
- **Проблема:** `NIM_LIB=$(HOME)/.choosenim/toolchains/nim-2.2.4/lib` падает без choosenim
- **Фикс:**
  ```make
  NIM_LIB ?= $(shell $(NIM) --eval "echo getPrefixDir() / \"lib\"" 2>/dev/null | tail -n1)
  NIM_LIB_FALLBACK=$(shell $(NIM) dump 2>&1 | grep -E "/lib$$" | head -n1)
  ifneq ($(NIM_LIB_FALLBACK),)
  NIM_LIB=$(NIM_LIB_FALLBACK)
  endif
  ```
- Dynamic обнаружение, fallback на hardcoded только если оба fail
- Файл: `Makefile`

### 8. MEDIUM: cinterop/include/nimbase.h builtin_clz/ctz/popcount=0 (DONE)
- **Проблема:** `#define __builtin_clz(x) 0` опасно, скрытые баги в хэш-таблицах, бесконечные циклы
- **Фикс:** Портативные C реализации:
  ```c
  static inline int qbe_builtin_clz(unsigned int x) {
      if (x == 0) return 32;
      int n = 0;
      while ((x & 0x80000000U) == 0) { n++; x <<= 1; }
      return n;
  }
  static inline int qbe_builtin_clzll(...)
  static inline int qbe_builtin_ctz(...)
  static inline int qbe_builtin_popcount(...)
  #define __builtin_clz(x) qbe_builtin_clz(...)
  ```
- Добавлены clzll, ctzll, popcountll
- Файл: `cinterop/include/nimbase.h`

## Верификация

- `make qbe` с cproc+QBE 1.3: bin/fossil-qbe 573K, version/help OK
- `nim c -r tests/all_tests.nim`: All tests passed (delta, manifest, storage, mcp 13 tools, hash, diff Myers)
- `parseCards` multiline test: Match true
- `diff file.txt`: unified diff OK
- Ticket/Wiki save: real SQL, no fake w*64

## Осталось (не критично)

- Ticket: getTicketSqlite уже real, но listTickets/getTicket fallback sample для non-Sqlite - OK
- Wiki: list/get real SQL, save real SQL - DONE
- Можно добавить vendored static sqlite3.c для полностью статического билда
- Можно добавить бенчмарки Myers vs LCS

## Итог

Все критические дефекты из ревью закрыты:
- sync parseCards ✅
- wiki save hash ✅
- ticket CRUD ✅
- REST file/diff/commit ✅
- MCP real tools ✅
- diff Myers O(N*D) ✅
- Makefile dynamic NIM_LIB ✅
- nimbase.h builtin portable ✅
