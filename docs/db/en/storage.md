# Storage: VFS + pager (v0.2, slice 1)

Status: **implemented and tested** (2026-10-19). Files: `src/fossil/db/vfs.nim`,
`src/fossil/db/pager.nim`, `tests/db/t_storage.nim` (17 tests).

## Why a separate layer

The engine must stay pure Nim with no I/O: the same code runs in a browser and in
wasm, where `open()` does not exist. So bytes move through one narrow interface:

```
engine (in-memory tables)  →  pager (pages, cache, dirty, freelist)  →  VFS (bytes)
```

Any host that stores pages elsewhere (artifact store, browser IndexedDB) implements
`Vfs` and nothing else changes.

## VFS

Two backends:

| Backend | Where | Notes |
|---|---|---|
| `openMemoryVfs()` | everywhere, including JS and wasm | `string` used as a byte buffer |
| `openFileVfs(path)` | native only | raises `UNSUPPORTED` on the JS target |

Pages are `string`s on purpose: Nim strings are binary-safe and need no pointer
arithmetic, so this file contains no `ptr`, `cast` or `addr` either.

Accounting that the tests assert on: `ioReads`, `ioWrites`, `bytesMoved`.

## Pager

* **Page size 4 KiB.** One page per syscall, page-aligned.
* **Page 0 is the header**: magic `FOCDB\x01`, format version, page count, freelist head.
  A foreign, truncated or older-version file is rejected with `CORRUPT` — never
  interpreted as valid pages.
* **LRU cache, 64 pages by default** (256 KiB resident). `readPage` returns a copy, so
  nothing outside the pager can hold a reference to a page that may be evicted.
* **Dirty tracking.** Eviction drops clean pages; if everything is dirty it flushes
  first. `flush()` writes dirty pages, then the header, then calls `sync()` **once** —
  fsync is the dominant energy cost, so it is never per page.
* **Freelist.** Freed pages are reused; a double free is refused with `MISUSE` instead
  of creating a cycle that would corrupt the chain. `freeCount()` and `integrityOk()`
  make the structure inspectable from tests.
* **`close()` flushes.** Dropping a connection never discards dirty pages.

## Bugs this slice caught (and fixed)

These were real, in code that already passed review:

1. **`fmReadWrite` truncates.** Opening an existing database wiped it, because Nim maps
   `fmReadWrite` to `"w+"`. Fixed: existing files open with `fmReadWriteExisting`;
   only a missing file is created. *This is the kind of bug that costs users their data.*
2. **`failf` was a template.** It resolved `%` at the call site, so it worked only if
   the caller happened to import `strutils` — and only with exactly one argument.
   Rewritten as a proc with a `$` converter: `failf(corrupt, "bad page $1", pid)`.
3. **`errors.nim` did not import `strutils`.** Consequence of the above.
4. **First data page was allocated at id 0**, which collided with the header.
5. **Freelist had no double-free guard** → a freed page pointed at itself.

## What is *not* here yet

WAL, B+tree, crash-recovery fuzzing, page encryption, `backupTo()` — the next slices
of v0.2. The pager is deliberately simple until those exist; it is easier to add WAL
to a pager that is obviously correct than to debug both at once.

## How to run

```sh
nim c -r --skipParentCfg:on --path:src tests/db/t_storage.nim
```

`--skipParentCfg:on` is required inside `fossil-nim`: the host `config.nims` links
`-lsqlite3 -lssl`, which this layer does not need.

## How the engine actually uses it (K9L-67, done)

The SQL layer does not talk to the pager. It talks to `rowstore.nim`, which has
two backends behind one interface:

* `skMemory` — an insertion-ordered map, the behaviour the engine was written
  and tested against;
* `skDisk` — **one** B+tree for the whole database, keyed by
  `tableId (4 bytes BE) ‖ rowid (8 bytes, sign bit flipped)`, so a scan of one
  table is a prefix range and `ORDER BY rowid` is free.

The catalog is not a binary struct. `dbfile.nim` regenerates the DDL from the
model and stores it as **text** under `tid 0, tag 1`; opening a database replays
that DDL through the ordinary `CREATE` executor. A table that loads is therefore
a table that would have been created correctly, and there is no second decoder
that has to stay in agreement with the parser. Column-level `CHECK`,
table-level `CHECK`, `DEFAULT`, `COLLATE NOCASE` and `REFERENCES` are all
printed from the model (see `ast.toSql`), because a reloaded table that accepts
rows the original refused is a data-integrity bug reported months later as "the
database let bad rows in".

Writes are staged: `put`/`del` fill an overlay, and the tree is touched once per
commit, which is what makes rollback free and what gives the WAL something
meaningful to make durable.

Two costs that are real and are not hidden:

* **Indexes are rebuilt at open.** Index entries live in memory; the rows do not.
  After a table is re-bound to its rows, `rebuildIndexes` walks them once. Without
  it, every index-chosen lookup answers "no rows" for a table that is full of
  them — which is exactly what the first version did, and why `t_disk` now has a
  test for it. Persisting indexes would remove the walk and is future work.
* **The schema is re-parsed at open.** Reading a few hundred bytes of DDL and
  running it is cheap at this size, and it buys the single-code-path property
  above.

Measured on this sandbox (`stress_btree 1000000`, memory VFS, 4 KiB pages,
1024-page cache): insert 24 475 ops/s, random lookup 16 144 ops/s, full ordered
scan of 10⁶ keys 0.40 s, structural verify 0.39 s, tree height 2, 13 253 nodes.
Those numbers are slow in absolute terms — random lookups are almost all cache
misses through the pager — and they are reported rather than smoothed over.
