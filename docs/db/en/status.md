# Foccil DB — status sheet

One row per stage. "Reference" means the code was checked against something
outside this repository (SQLite, a published test vector, a spec); "own tests"
means the only evidence is a test we wrote, which shares our assumptions and can
therefore be wrong in the same direction as the code.

Snapshot: branch `feat/foccil-db-v0.1`, latest commit at the time of writing (`git log -1`).

| Stage | Status | LOC | Checked against a reference | Checked only by own tests | cproc gate |
|---|---|---|---|---|---|
| SQL front end (tokenizer, parser, AST, schema) | done | 1892 | — | t_core 26, t_security 20 | compiles (in gate) |
| Execution engine (SELECT/INSERT/UPDATE/DELETE, joins, aggregates, subqueries, CASE, casts) | done | 3033 | **56/56 queries identical to SQLite** (`tools/db/difftest`) | t_core 26 | compiles, and the smoke binary runs a 3-row query through it |
| Values and arithmetic (typing, NULL, coercion, integer division) | done | 398 | via difftest (int division, casts, NULL semantics) | t_core | compiles |
| Scalar & aggregate functions | partial | 406 | via difftest (min/max/abs/length/upper/lower/coalesce) | t_core | compiles |
| Errors, bytes, small helpers | done | 157 | — | t_security (no Defect, no leak) | compiles |
| VFS + pager + header validation | done | 519 | — | t_storage 17, t_corrupt 20 | compiles |
| Write-ahead log (commit, checkpoint, replay) | done | 287 | — | t_wal 18, t_crash 3 (random crash points) | compiles |
| B+tree (search, insert, split, overflow pages, deletion) | done | 632 | — | t_btree 24 + 20-seed model check + 20k-op stress | compiles |
| Corruption resistance (header, freelist, WAL frames, truncation) | done | — (in the four rows above) | contract: correct answer or `DbError` CORRUPT, never `Defect`; verified by running the same tests against the pre-fix code | t_corrupt 20 | compiles |
| Crypto primitives (ChaCha20, HChaCha20, XChaCha20, HMAC-SHA256, KDF, constant-time compare) | done | 324 | **RFC 8439 and draft-irtf-cfrg-xchacha-03 test vectors**, incl. HChaCha20 subkey and 288-byte XChaCha20 keystream | t_crypto 34 (vectors + property tests) | compiles |
| Page encryption in the pager (K9L-83) | **not started — parked by decision**, format fixed in `encryption.md` | 0 | layout decided: 4096 = 4032 payload + 64 trailer, CRC32 or HMAC | — | — |
| Differential testing harness | done | 61 + SQL corpus | is itself the reference (SQLite 3) | — | — |
| cproc → QBE → musl build | done | 312 | cproc 22/22 units, binary linked and its output compared | — | **is the gate** |
| Plain JS backend | done | — | JS digest identical to native, byte for byte | t_crypto 34 on JS | n/a |
| wasm32 | done | — | runs under Node, 328 KB | — | n/a |
| Engine on real storage (K9L-67 → K9L-83) | **not started** (point 5) | 0 | — | — | — |
| Audit duplicate cleanup (K9L-19..22 ↔ K9L-69..81) | **not started** (point 6) | 0 | — | — | — |
| `tools/db/test.sh` | **broken** (K9L-39), suites are run one by one | 34 | — | — | n/a |

## Totals

* engine: **6436 lines** of Nim in `src/fossil/db/`
* tests: **2213 lines**, 162 tests, 0 failures (26 + 20 + 17 + 18 + 24 + 3 + 34 + 20)
* docs: **1303 lines** in `docs/db/en` (mirrored in `docs/db/ru`)
* cproc gate: **22/22** translation units, plus a linked smoke binary

## What this table is not

* It is not a coverage claim: `—` in the reference column means exactly that,
  nothing was compared against an outside implementation.
* The engine is still an **in-memory SQL engine over its own storage layer**;
  the two halves are tested separately and are not yet joined (point 5). Until
  they are, "we rewrote SQLite" is not honest — "we rewrote the SQL engine and
  the storage engine, separately, both green" is.
* Encryption is **not** wired into the pager. The format decision is written
  down; the code is not.
