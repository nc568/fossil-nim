# Foccil DB — Wiki

**RU:** [Домашняя страница вики на русском](Home.ru.md)

A SQL engine in Nim (ARC) for the Foccil-nim project. Runs from one source on C, JS and
WebAssembly. Not a port of SQLite — a rewrite with the legacy cut out.

## Start here

| Page | What is inside |
|---|---|
| [Architecture](../en/architecture.md) | pipeline, why no opcode VM, scopes, planner, transactions |
| [Security model](../en/security.md) | threats, capabilities, the 20 security tests, honest limits |
| [Portability](../en/portability.md) | C / JS / wasm / cproc, parity digests, wasm recipe and size |
| [Roadmap](../en/plan.md) | v0.1 done → v0.5, with "done when" criteria |
| [SQLite pain points](../en/research-painpoints.md) | what hurts users and how we answer it |
| [Storage engine](../en/storage.md) | VFS tiers, 4 KiB pages, LRU cache, freelist |
| [WAL](../en/wal.md) | durability contract, frame checksums, group commit, checkpoint |

## Quick facts

```
Engine size        4 492 LOC          (SQLite: ~150 000)
Tests              26 core + 20 security + 17 storage + 17 WAL
Backend parity     native == JS, byte for byte (md5 0376a7c4…)
wasm              328 KB, no emscripten, no wasi-sdk
Point lookup      185 842 q/s  (was 56 q/s before the index planner)
Biggest open item  cproc/QBE compilation — blocked upstream, reproducer attached
```

## How to run

```sh
sh tools/bootstrap.sh   # Nim, qbe, cproc, musl, zig into ~/.cache/tc
sh tools/test.sh        # 6-stage gate
nim c -r -d:release --mm:arc tools/bench.nim
sh tools/wasm/build.sh && node tools/wasm/run.js
sh tools/cproc/check.sh # compatibility scoreboard
```

## Conventions

* Values enter SQL **only** as parameters. No exceptions.
* A feature without a test is not done.
* Docs ship in RU and EN in the same commit as the code.
* Any change in wasm size or per-query memory comes with a measurement.
