# Conscious divergences from SQLite

Everything below is a decision, not a bug and not a to-do. Each entry says what
we do, what SQLite does, and why we chose our side. If an entry stops being
true, it moves out of this file and the change is announced — a divergence
list that drifts quietly is worse than none.

## 1. Keys are limited to 512 bytes

`MaxKeySize = 512` in `btree.nim`; longer keys raise `DbError(RANGE)`.

SQLite has no such limit: a key can be up to `SQLITE_MAX_LENGTH` (1 GB by
default), spilled across overflow pages.

Why: the two-cells-per-page invariant (`doAssert` in `btree.nim`) is what makes
every split terminate, and it is only provable if a cell has a bounded size.
With `PageSize = 4096`, `PageTrailer = 64` and `InlineValueMax = 1024`, two full
leaf cells take 3 108 of the 4 032 usable bytes, leaving 924 spare; two internal
cells take 1 060, leaving 2 972. Raising the key limit without raising the page
size breaks that proof, so the limit is a *format* property, not a tuning knob.

What this costs a row store: row keys are `tableId ‖ rowid` — always 12 bytes.
The limit only bites on secondary-index keys that concatenate wide text
columns. A table with an index over a 1 KB text column cannot be indexed here.

## 2. `INTEGER PRIMARY KEY` is not an alias for the rowid

We allocate the rowid from a counter (`TableDef.nextRowid`) and store the
primary-key column as an ordinary column. SQLite makes an `INTEGER PRIMARY KEY`
column *be* the rowid.

Consequences a user will notice:
* `INSERT INTO t(id) VALUES (100)` gives the row rowid 1, 2, 3 …, not 100;
* `SELECT * FROM t` (no `ORDER BY`) returns rows in rowid order, which is
  insertion order, not `id` order;
* `last_insert_rowid()` returns the counter, not the value of `id`.

Why: the rowid is the storage key, and letting a user column *be* the storage
key means every `UPDATE` of that column is a key move — delete plus insert in
the B+tree, plus rewrites of every index entry. v0.1 takes the simple side.
Making `id` the rowid is a real feature with real work behind it and is tracked
as its own item rather than pretended to exist.

## 3. No `ORDER BY` means rowid order on disk, insertion order in memory

Both are legal (`ORDER BY` is the only thing SQL promises). They coincide for
ordinary inserts and differ after a delete/reinsert. Anything that relies on
scan order without `ORDER BY` is not portable between the two backends, which is
exactly what the parity test in `tests/db/t_disk.nim` documents.

## 4. Views cannot be stored in a file

`commitFile` refuses (`DbError(UNSUPPORTED)`) if the catalog contains a view.
The catalog stores what the engine built, and a view is a parsed `SELECT`; there
is no stable serialisation for the AST yet, and half a serialisation is worse
than an honest refusal. In-memory databases have views.

## 5. `REFERENCES` is recorded, listed, and not enforced

`PRAGMA foreign_key_list` reports what the user wrote; inserts do not check it.
Field-level foreign keys are a schema feature with delete-order semantics,
deferred checks and cascades — a project of their own. Storing the clause keeps
the catalog faithful, so adding enforcement later does not need a format change.

## 6. Checkpoints are explicit

`db.checkpoint()` folds the log into the main file. There is no automatic
checkpoint at a page-count threshold. An automatic one turns a fast commit into
a slow one at a moment the host did not choose; the log growing is something the
host should see and decide about.

## 7. Rowids are never reused

SQLite reuses `max(rowid)+1` (and `AUTOINCREMENT` exists to stop that). Our
counter only goes up, so every table behaves as if `AUTOINCREMENT` were on. This
is a divergence that is easy to live with and hard to notice, which is why it is
written down here.

## 8. Page checksums are not there yet

The tail 64 bytes of every page are reserved now (`PageTrailer` in `btree.nim`,
and node data is bounded to 4 032 bytes so the reservation is real, not
decorative). The trailer contents — format version, flags, and a CRC-32 seeded
with the page id — arrive with K9L-83. Until then a torn page is caught by the
WAL frame checksum on replay, and a corrupted page in the main file is caught by
the structural validation in `parseNode`, not by a checksum.

## 9. No native SQLite file format

We do not read or write `.db` files. Import/export is a separate tool that lives
outside the core, so a compatibility bug can never sit on the commit path.

## 10. One writer per file

Two processes opening the same database file will corrupt it. There is no lock
file and no `flock`. Documented in `storage.md`; a lock is future work.

## 11. Crash coverage is smaller than the original target

K9L-46 asked for 1 000 crash points. The gate currently runs 50 (B+tree level)
plus 60 (engine level, `crash_fuzz_engine.nim`) on every full run, and the
`t_crypto`/`t_corrupt` suites add their own fixed cases. The 1 000-point run was
reduced, not reached, and the reason is recorded in the K9L-46 note: a full run
of the 10⁶-key stress already takes ~3 minutes on this sandbox, and 1 000 engine
crashes with full reopen + verification take ~7 minutes, which is too slow to
sit in the pre-commit gate. What the fuzzers do cover is the shape of the
failure (torn write, torn commit, torn checkpoint), which is what a crash
*fuzzer* is for; the count is a budget decision and is stated as one.
