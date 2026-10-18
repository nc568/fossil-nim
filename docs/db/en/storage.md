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
