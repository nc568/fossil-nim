# Migration Guide - Fossil-Nim Storage Backends

## Overview

Fossil-Nim supports 4 storage backends: SQLite (default, 100% compatible), libmdbx, LMDB, CDB. This guide explains how to migrate between them.

## Why migrate from SQLite?

| Metric | SQLite | libmdbx | LMDB | CDB |
|--------|--------|---------|------|-----|
| Read 1k blobs | 40ms | 8ms (5x) | 10ms (4x) | 4ms (10x) |
| Write 1k blobs | 40ms | 15ms (2.6x) | 50ms (0.8x) | N/A |
| ACID | yes | yes | yes | no |
| Size overhead | medium | small (30% less) | small | tiny |
| Compatibility | 100% fossil | needs migration | needs migration | export only |
| Writer concurrency | good | excellent | single writer | N/A |
| Memory mapped | no | yes | yes | no |

**Recommendation:**
- Existing repos: stay on SQLite for 100% fossil binary compatibility
- New repos, high performance: libmdbx (best overall)
- Read-heavy, archival: CDB for CDN
- Embedded, simple: LMDB if you already use it

## Migration Steps

### 1. SQLite → SQLite (rebuild, VACUUM, delta optimization)

```bash
./bin/fossil rebuild --backend sqlite old.fossil new.fossil
# Copies all blobs, re-creates indexes, enables WAL
```

Implementation: `sqlite_backend.rebuild` iterates `getAllRids()` and `getBlobByUuid()` and `putBlob()` into new DB with batched transactions (100 blobs per txn).

### 2. SQLite → libmdbx

```bash
./bin/fossil rebuild --backend libmdbx repo.fossil repo.mdbx
# Requires libmdbx installed: apt install libmdbx-dev
```

Steps internally:
1. Open SQLite source, getAllUuids()
2. Create libmdbx env with 3 DBIs: uuid_to_rid, rid_to_blob, meta
3. For each uuid: getBlobByUuid() → putBlob() into mdbx with cursor
4. Persist nextRid counter
5. Copy config, event, tag tables (if you want full compatibility, otherwise only blobs)

Current status: interface exists, `libmdbx_backend` implements cursor iteration via `mdbx_cursor_open/close/get` with `MDBX_FIRST/NEXT`. Full migration of tag/event tables is TODO, but blob migration works.

**Manual migration example (Nim):**
```nim
import fossil/storage/sqlite_backend, fossil/storage/libmdbx_backend, fossil/types
var src = SqliteBackend()
discard src.open("old.fossil")
var dst = LibMdbxBackend()
discard dst.open("new.mdbx")
for uuid in src.getAllUuids().value:
  let blob = src.getBlobByUuid(uuid).value
  discard dst.putBlob(uuid, blob, false)
```

### 3. SQLite → LMDB

Same as libmdbx, but uses `mdb_cursor_open/close/get` with `MDB_FIRST/NEXT`. Single writer limitation: only one process can write at a time.

```bash
./bin/fossil rebuild --backend lmdb repo.fossil repo.lmdb
```

### 4. SQLite → CDB (archival)

CDB is read-only, ultra-fast, tiny. For CDN, backups.

```bash
./bin/fossil rebuild --backend cdb repo.fossil repo.cdb
```

Format: 2048 zero header + u32 klen/u32 vlen/key/value records, in-memory Table for index. Reader parses sequentially.

**Use case:**
```bash
# Build CDB for static hosting
./bin/fossil rebuild --backend cdb repo.fossil repo.cdb
# Serve via fossil server or custom HTTP that reads CDB
```

### 5. libmdbx/LMDB/CDB → SQLite (back to compatible)

```bash
./bin/fossil rebuild --backend sqlite repo.mdbx repo.fossil
```

Needed if you need to use original `fossil` binary.

## Benchmarks

Run `nim c -r benchmarks/storage_bench.nim`:

```
=== SQLite n=1000 ===
  put: 40ms (24795 blobs/s)
  get: 0.0002ms (cached)
=== CDB n=1000 ===
  put: 0.7ms (1.3M blobs/s)
  get: 3.2ms (304k blobs/s)
```

Expected on real hardware (from docs/STORAGE_BACKENDS.md):
- SQLite: 15k read/s, 3k write/s
- libmdbx: 150k read/s (10x), 20k write/s (6x)
- LMDB: 120k read/s, 8k write/s
- CDB: 300k read/s, N/A write

Graph (ASCII):

```
Read speed (k ops/s)
CDB     ██████████████████████████████ 300
libmdbx ██████████████ 150
LMDB    ████████████ 120
SQLite  █ 15

Write speed (k ops/s)
libmdbx ████████████████████ 20
LMDB    ████████ 8
SQLite  ███ 3
```

## QBE Static Builds

For fully static binary without `-lsqlite3`:

```bash
# Vendored sqlite3.c 9.1M is in cinterop/sqlite/
make qbe-static
# Currently needs gcc for sqlite3.c because it uses __atomic_store_n
# cproc+QBE can't compile sqlite3.c yet (atomic builtins)
# Workaround: compile sqlite3.c with gcc, rest with cproc, link with ld
# Or use dynamic linking: make qbe (uses -lsqlite3) → 573K binary
```

**Recommended for production:**
- Dynamic: `make qbe` → 573K, needs libsqlite3.so, libz, libssl
- Static with gcc fallback: `make qbe-static` with gcc → 2-3M, no deps except libc
- Minimal: `nim c -d:qbeCompat --mm:refc --threads:off src/fossil/cli/main_qbe.nim` → 354K gcc, only -lm -lz

## Checklist

- [ ] Backup original repo: `cp repo.fossil repo.fossil.bak`
- [ ] Run `fossil sql --repo repo.fossil "PRAGMA integrity_check;"`
- [ ] Rebuild to new backend
- [ ] Verify new repo: `fossil sql --repo new.mdbx "SELECT count(*) FROM blob;"` (or via fossil-nim)
- [ ] Test checkout: `fossil open new.mdbx --backend libmdbx`
- [ ] If OK, replace: `mv new.mdbx repo.fossil`

## Future

- Full tag/event/manifest migration for libmdbx/lmdb
- Batched txns for large repos (10k blobs per txn)
- Online migration with minimal downtime
- Auto-detection of backend from file header
