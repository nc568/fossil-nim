# Crash recovery: what survives a power cut (v0.2, slice 4)

Status: **implemented and fuzzed** (2026-10-19). `src/fossil/db/store.nim` joins
the pager and the log; `tests/db/t_crash.nim` and `tools/db/crash_fuzz.nim`
break it on purpose.

## The promise, in one line

> A transaction is either entirely there or entirely absent. Never half.

Everything below exists to keep that sentence true when the process dies in the
middle of a write.

## How the pieces meet

```
          write                stage                 commit
SQL/B+tree ──► pager ──► dirty page ──► WAL frames ──► marker + 1 fsync
                  │                          │
                  └── cache ─────────────────┘
                        newest image wins
```

The pager does not import the log and the log does not import the pager's cache:
`store.nim` plugs the log in through three hooks (`walRead`, `walStage`,
`walCommit`). A pager without a log behaves exactly as it did before, which is
why the storage tests kept passing untouched.

## The index is not an optimisation

When a page is staged and later evicted, the next read must come from the log,
not from the main file — the main file is a commit behind. Without
`walIndex` (page → offset of its newest frame) the reader gets yesterday's row
with no error at all: the worst kind of bug, because it looks like a race and
gets reclassified as "flaky" for a month.

## Checkpoint order

1. stage and commit whatever is dirty;
2. pull every page that exists only in the log back into the cache as dirty;
3. write the main file, **sync**;
4. bump the salt, **sync**.

Step 2 was missing in the first version and the fuzzer found it: pages staged
into the log and since evicted were *clean*, so the fold skipped them, and the
salt bump retired the only copy. The main file was left pointing at pages that
had never been written.

Two syncs, deliberately. Swapping 3 and 4 would retire frames that the main file
does not have yet — a crash in between would lose a committed transaction, which
is the one thing a log may never do.

## How the crash is injected

`Vfs.crashAt` is a byte counter. When a write would cross it, the write is
**torn** — only its head lands — and every later write is dropped. Reads keep
working, because the bytes are still there.

Tearing matters. A store that only ever lost whole writes would never exercise
the checksums, and the checksums are most of the recovery story.

## What the fuzzer actually checks

After restarting from `snapshot()` — the bytes on the platter, not what the
program wanted:

| Check | Meaning |
|---|---|
| opens without an exception | no "opened but unreadable" |
| `btree.verify()` passes | the structure is still a B+tree |
| every committed key has its committed value | no lost commit |
| the in-flight transaction is all-in or all-out | no half-applied state |

The last one classifies keys by **value**, not by presence: a key committed by an
earlier transaction and rewritten by the in-flight one is present either way, so
"does the key exist" answers the wrong question.

## Results

```
t_crash      3 suites, 300 random crash points, 51 checkpoint sweeps
crash_fuzz   1000 iterations, 1000 torn crashes, 0 failures

t_core 26 · t_security 20 · t_storage 17 · t_wal 18 · t_btree 24 · t_crash 3
backend parity md5 0376a7c4c0dfd8cf602e8fcff9dddb40 (unchanged)
```

## Two bugs this slice produced, and what caught them

1. **The checkpoint leak above.** Only a crash *during a checkpoint* exposes it;
   a normal close never does.
2. **CRC in JavaScript.** `int(uint32)` range-checks on the JS backend and C does
   not, so every checksum with the top bit set threw `RangeDefect` in the browser
   and worked natively. The log had never been executed under JS before this
   slice. Fixed by casting through `int32` at the boundary; the test now compares
   checksums as bits, and both backends produce identical bytes.

There was also a duplicated `putI32`/`getI32` in `wal.nim` left over from before
`bytes.nim` existed. It kept the old, unchecked conversion and disagreed with the
shared one. Two implementations of a byte order is two chances to be wrong; the
duplicate is gone.

## Deliberate trade-off

A database file shorter than one page is treated as *new* when opened through
the log path. It means either "never created" or "utterly destroyed" — a file
under 4 KiB cannot hold a single data page. Refusing to open is the other option,
and it turns a crash during first-time creation into a database the user can
never open again. The pager on its own stays strict; leniency belongs to the path
that owns a log, not to the format.

## Not here yet

- fsync failure handling (a disk that lies about its cache);
- torn writes on real hardware — the memory VFS tears, a real one cannot be made
  to on demand;
- group commit across concurrent writers: there is one writer by design.

## Run

```sh
nim c -r --skipParentCfg:on --path:src tests/db/t_crash.nim
nim c -d:release --skipParentCfg:on --path:src tools/db/crash_fuzz.nim && ./build/db/crash_fuzz 1000
```
