# SQLite pain points — and what we do about each one

Collected from public discussions (Reddit r/programming, r/Database, Hacker News, dev
blogs, lobste.rs) and first-hand use. Each pain point gets either a concrete design
decision or an explicit "not our problem, and here is why".

## 1. Single writer
**Pain.** The most common complaint. People hit `SQLITE_BUSY`, tune `busy_timeout`, then
migrate to Postgres.
**We do.** Document the model honestly (one writer is the price of ACID on one file); WAL
in v0.2 gives readers non-blocking access; `busy`/`locked` are explicit error codes; group
commit batches fsyncs.
**We don't.** Promise many writers. It cannot be delivered without distributed consensus.

## 2. Types are not enforced
**Pain.** "I stored text in an integer column and SQLite did not notice." SQLite's own
developers admitted in 2021 that making flexible typing the default was arguably wrong.
**We do.** Strict typing **by default**; a lossy conversion is a `TYPE` error. Flexible
typing is opt-in and must be signed for.

## 3. `ALTER TABLE` as a lottery
**Pain.** Countless "migration via table rebuild → data loss" reports; the most emotional
topic of 2025–2026.
**We do.** `ADD/RENAME` work natively; `DROP COLUMN` is refused for indexed columns (an
error beats silent corruption); v0.4 adds a full table rebuild as *one* transaction using
the already-tested catalog snapshot.

## 4. SQL reaching the filesystem
**Pain.** `ATTACH`, `load_extension`, `VACUUM INTO` are three ways "SQL" becomes "I/O" —
and a whole vulnerability class.
**We do.** They do not exist. Rejected by the parser. Not a flag that can be flipped.

## 5. Unexplained performance
**Pain.** "Why is this query slow?" — and silence.
**We do.** `EXPLAIN` prints the path actually chosen, and a test asserts the index is
picked. The planner is deliberately small and predictable: one index equality or a scan.
Predictability beats cleverness you cannot explain. Benchmarks live in the repository.

## 6. Replication and backups
**Pain.** "Does not scale beyond one machine", "backups by hand".
**We do (v0.2+).** No `VACUUM INTO`; instead an API-level `backupTo(path)` producing a
page-consistent snapshot, so SQL still cannot write files. Replication stays outside the
core: the engine provides a deterministic WAL, transport is the wrapper's job.

## 7. Energy and size
**Pain.** "SQLite is megabytes and does busy work on an MCU"; SD cards die from write
amplification.
**We do.** No GC (ARC) — no pauses, no unpredictable heap growth; wasm is 328 KB after
`-Oz`/`--gc-sections`/`--strip-all` (from 2.25 MB); a libm-free profile; a per-query row
budget that protects against your own mistakes, not just attacks. Planned: a fixed-buffer
arena for bare metal.

## 8. Silence on typos
**Pain.** A function typo returns `NULL`; the bug hunt takes a week.
**We do.** Unknown functions are a **prepare-time** error. `load_extention` stops the
statement instead of returning NULL.

## 9. Prepared-statement API complexity
**Pain.** Forgot to finalise → leak; wrong parameter index → silently the wrong query.
**We do.** `Prepared` is a `ref` under ARC (deterministic, cannot be forgotten); a
statement cache keyed by SQL text; out-of-range parameters are a `RANGE` error; both
positional and named parameters, validated.

## 10. What we deliberately do not solve

| Pain | Why not |
|---|---|
| "Thousands of writers per second" | That is not an embedded database. |
| "Distributed SQL" | A different product. |
| "Materialised views" | v0.4+ as a query cache, never as a freshness guarantee. |
| "Money as decimal" | Real pain. A `DECIMAL` type over int128 is on the backlog, not in v0.2. |
| "Users and grants inside the DB" | Authorisation belongs outside, as capabilities in `DbOptions`. |

## 11. Provenance
Public discussions 2019–2026: "SQLite is not a toy database", "Why does SQLite have such a
bad rep", "Why ALTER TABLE is such a problem for SQLite", "Who has SQLite in production",
notes on solving the single-writer limitation (2026), and the official SQLite forum thread
on flexible typing.

For a deeper, citation-backed study, see `docs/ru/research-prompt.md` — a ready-to-send
prompt for a research agent.
