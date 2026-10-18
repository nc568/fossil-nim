# WAL: durability without guessing (v0.2, slice 2)

Status: **implemented and tested** (2026-10-19). File: `src/fossil/db/wal.nim`,
tests: `tests/db/t_wal.nim` (17 tests).

## Contract

> A transaction is durable **if and only if** its commit frame is on disk with a
> valid checksum. Recovery applies that prefix and nothing else.

An interrupted transaction does not partially survive. It disappears entirely —
which is the only behaviour a user can reason about.

## Layout

```
int8   0          magic "FOCWAL01"
int32  8          generation salt
int32  12         base page count (at the last checkpoint)
int32  16         header checksum
       P, 2P, ... frame: [pid:i32][salt:i32][crc:i32][payload: 4 KiB]

pid >= 1        page image
pid == 0x7FFFFFFF  commit marker; payload[0..3] = resulting page count
```

The commit marker is a **positive** sentinel on purpose. A negative value has to
survive a round-trip through unsigned decoding, and the first version silently
turned `-1` into `4294967295`, so the marker was never recognised.

## What each mechanism buys

| Mechanism | What it prevents |
|---|---|
| per-frame CRC-32 over *pid + salt + payload* | a torn write being replayed as if it were complete |
| generation salt in the header | stale frames of a previous checkpoint being replayed at all |
| commit marker | half of a transaction becoming visible |
| one `sync()` per commit | paying an fsync per page |

The CRC **must not** cover its own field: the first implementation checksummed the
finished header, i.e. uninitialised bytes, and rejected every frame it wrote.

## Group commit

`appendFrame` stages page images and never syncs. `commit` writes the marker and
performs exactly one sync. Twenty pages under one commit cost one fsync; twenty
separate commits cost twenty. The test measures this rather than asserting it, and
also measures the opposite case so the tradeoff stays visible.

## Checkpoint

`checkpoint()` flushes the pager, bumps the salt and rewrites the header. Old frames
are **not truncated**: they stop matching the salt, which makes replay halt at the
first stale frame. Truncation would rewrite a file that is about to be appended to.

## Why single-writer

SQLite's best-known operational pain (see `research-painpoints.md`) is the single
writer and the `database is locked` wall. This design does not hide that — it makes
it explicit: one log, one writer, no lock negotiation to debug at 3 a.m. Concurrency
belongs to the host, which can serialise writes deliberately.

## Not here yet

- crash-recovery fuzzer that kills the process mid-write for 1000 iterations (K9L-46);
- page encryption (K9L-47);
- growing the WAL past one checkpoint in place (blocked on the B+tree storage format).

## Run

```sh
nim c -r --skipParentCfg:on --path:src tests/db/t_wal.nim
```
