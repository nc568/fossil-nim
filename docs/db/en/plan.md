# Foccil DB — Roadmap

Every milestone must be **verifiable by a test**. Definition of done:
`sh tools/test.sh` is green, new tests cover the new behaviour, docs updated in both
languages.

## v0.1 — Core (done)

| # | Item | Status |
|---|---|---|
| 1 | Value model, comparison, affinity, strict typing | ✅ |
| 2 | Tokenizer without regex, slice tokens, deterministic literals | ✅ |
| 3 | Parser: DDL, DML, SELECT, CTE, JOIN, compound, PRAGMA, EXPLAIN | ✅ |
| 4 | Executor: projection, aggregates, sort, limits, subqueries | ✅ |
| 5 | Constraints: PK, UNIQUE, NOT NULL, CHECK, DEFAULT | ✅ |
| 6 | Transactions: DML journal + catalog snapshot for DDL | ✅ |
| 7 | Secondary indexes + equality planner (3300× on point lookups) | ✅ |
| 8 | Public API, parameters, prepared-statement cache | ✅ |
| 9 | 26 functional tests | ✅ |
| 10 | 20 security tests (injection, limits, fuzzing, static anti-unsafe) | ✅ |
| 11 | C ↔ JS backend parity by digest | ✅ |
| 12 | wasm32 module + bridge + Node host | ✅ |
| 13 | `foccilMinimalFloat` profile (no libm) | ✅ |

## v0.2 — On-disk storage

Goal: survive a process restart, keep the executor interface unchanged.

| # | Item | Done when |
|---|---|---|
| 1 | `Vfs` abstraction (memory / file / custom), no syscalls in the core | the same suite runs on memory-VFS and file-VFS |
| 2 | Pager: 4 KiB pages, LRU cache, dirty pages | hit ratio measured; repeated reads do no I/O |
| 3 | WAL: frames with salt + checksum, checkpointing | "write torn mid-frame → DB opens and does not lie" test |
| 4 | B+tree: insert/search/delete/scan, split/merge | differential test against the in-memory index on 1e6 keys |
| 5 | Freelist + auto-vacuum | file size stays flat under insert/delete cycles |
| 6 | Crash recovery | fuzzer that kills the process at random points |
| 7 | Page encryption (XChaCha20-Poly1305, key supplied outside SQL) | without the key the file is unreadable; with it, all data is intact |

## v0.3 — Planner and performance

1. Cost-based index selection using `ANALYZE` statistics.
2. Composite and covering indexes, index-only scans.
3. Index-ordered output (no materialise for `ORDER BY` on an indexed column).
4. Predicate pushdown into subqueries and CTEs.
5. Targets: point lookup > 500k queries/s, insert > 100k rows/s.

## v0.4 — Features

1. Full-text search (FTS5-shaped: inverted index, ranking).
2. JSON: `json_extract`, `json_each`, `->`, `->>`.
3. Window functions.
4. Triggers (carefully: a privilege-escalation channel — opt-in only).
5. Full `ALTER TABLE` (table rebuild preserving data).

## v0.5 — cproc/QBE and embedded targets

1. Close the remaining cproc blockers (see `portability.md`).
2. Build without wasi-libc (own bump allocator) — target < 150 KB wasm.
3. Optional `-d:foccilNoAlloc` for bare metal: arena over a fixed buffer.

## Standing lines (not milestones)

* **Security.** Every new capability passes one filter: can it be expressed without adding
  a "SQL → filesystem/network/process" channel?
* **Consumption.** Any growth in wasm size or per-query memory comes with a measurement.
* **Docs.** RU and EN are updated in the same commit as the code.
* **Tests.** A feature without a test is not done.

## Open questions for the owner

1. License (currently TBD) — decides whether SQLite file-format code can be reused.
2. Do we need binary compatibility with the SQLite file format? This heavily affects the
   v0.2 B+tree design.
3. Bare-metal targets: a specific chip/OS in mind?
4. Priority: full-text search or window functions?
