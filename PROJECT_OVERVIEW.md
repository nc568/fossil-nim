# Fossil-Nim Project Overview

This file is generated to give a quick overview of all files in the port.

## Top-level

- `fossil.nimble` - package definition + tasks (build, buildQbe, mcp, test)
- `config.nims` - Nim compiler config, QBE compat flags
- `Makefile` - wrappers for build, qbe, test
- `README.md` / `README_RU.md` - main docs in EN/RU
- `PROJECT_OVERVIEW.md` - this file

## src/fossil/

### Core

- `types.nim` - Rid, Uuid, Blob, Result, error codes. Foundation for everything.
- `config.nim` - FossilConfig, storage kind, env loading, repo detection

### db/

- `c_interop.nim` - central C header wrappers (sqlite3.h, zlib.h)

### storage/

- `backend.nim` - StorageBackend concept (interface)
- `sqlite_backend.nim` - SQLite implementation, 100% compatible with original
- `libmdbx_backend.nim` - libmdbx (recommended) - fast KV, ACID, zero-copy
- `lmdb_backend.nim` - LMDB - similar but single writer
- `cdb_backend.nim` - CDB - read-only, for archival/CDN

### delta/

- `delta.nim` - Fossil delta format (copy/insert), compatible with delta.c

### artifact/

- `manifest.nim` - Manifest parsing (C, D, F, P, etc cards), validation
- `artifact.nim` - Artifact resolution, delta chain

### vcs/

- `checkout.nim` - checkout root detection, status, materialize
- `commit.nim` - commit building manifest + storing blobs
- `diff.nim` - diff blobs (LCS, unified, JSON)
- `branch.nim` - branch list/create/close
- `timeline.nim` - timeline entries, filtering
- `merge.nim` - 3-way merge with conflict markers

### sync/

- `protocol.nim` - xfer cards (file, gimme, igot, cookie), sync exchange
- `http.nim` - HTTP transport for sync (POST /xfer, GET /clone)

### web/

- `server.nim` - async HTTP server, handles /, /timeline, /api/*
- `router.nim` - router with exact + prefix routes

### wiki/

- `wiki.nim` - wiki page list/get/save

### ticket/

- `ticket.nim` - ticket list/get/create

### api/

- `rest.nim` - REST API handlers, ApiServer, OpenAPI-like routes

### mcp/

- `tools.nim` - MCP tool definitions + JSON Schemas
- `server.nim` - JSON-RPC 2.0 over stdio, handles initialize, tools/list, tools/call, resources/*, prompts/*

### cli/

- `main.nim` - CLI dispatcher, commands: init, status, diff, commit, timeline, mcp, server, rebuild, branch, open, version, help

### utils/

- `hash.nim` - SHA3-256 / SHA1 wrapper (OpenSSL or sh3.c for QBE)
- `compress.nim` - zlib compress/uncompress wrapper

## cinterop/include/

- `qbe_nimbase.h` - shim for nimbase.h that removes GCC attributes, uses C11

## docs/

- `ARCHITECTURE.md` / `ARCHITECTURE_RU.md` - architecture deep dive
- `STORAGE_BACKENDS.md` / `STORAGE_BACKENDS_RU.md` - storage comparison
- `MCP_API.md` / `MCP_API_RU.md` - MCP server spec
- `CPROC_QBE.md` / `CPROC_QBE_RU.md` - QBE compatibility guide
- `BUILD.md` / `BUILD_RU.md` - build instructions
- `PORTING_PLAN.md` / `PORTING_PLAN_RU.md` - full porting roadmap
- `API.md` - REST API spec
- `README.md` - docs index

## tests/

- `all_tests.nim` - runs delta roundtrip, manifest parse, backend type checks, MCP registry, hash

## examples/

- `mcp_client.py` - Python example of MCP stdio client
- `api_client.py` - Python example of REST API client
- `README.md` - examples index

## Build outputs

- `bin/fossil` - main binary (clang/gcc)
- `bin/fossil-mcp` - standalone MCP server
- `bin/fossil-qbe` - QBE-built binary (via cproc)
- `build/cgen/` - generated C files for QBE build

## How modules connect

```
CLI -> VCS -> Artifact -> Delta -> Storage -> C interop
        |
        +-> Config
        +-> Types

API -> VCS (same as CLI, but returns JSON)
MCP -> VCS (same as CLI, but via JSON-RPC)

Web -> Router -> Pages -> VCS + Storage

Sync -> Protocol -> HTTP transport -> Storage
```

All VCS functions are pure library functions returning `Result`, so CLI, API, MCP can reuse them without parsing text.

## QBE Compatibility Path

```
Nim source -> nim c --compileOnly -d:qbeCompat -> build/cgen/*.c
                                              -> sed remove __attribute__
                                              -> cproc -O2 -o fossil-qbe *.c -lsqlite3 -lz
```

- `config.nims` sets `--mm:refc --threads:off --panics:on` for QBE
- `qbe_nimbase.h` replaces GCC builtins
- No exceptions in hot path, only Result
- No closure iterators

## Storage Backend Decision Tree

- Need 100% compat with C fossil? -> sqlite
- New repo, max performance? -> libmdbx (recommended)
- System has only LMDB? -> lmdb
- Need static archive for CDN? -> cdb (export)

All backends implement same `StorageBackend` concept, so `fossil rebuild --backend libmdbx old.fossil new.fossil` works.

## MCP Tools

Exposed to AI agents:

- `fossil_status`, `fossil_diff`, `fossil_commit`, `fossil_log`, `fossil_timeline`
- `fossil_branch_list/create`, `fossil_checkout`, `fossil_blame`, `fossil_stash_*`
- `fossil_wiki_list/get/create`, `fossil_ticket_list/get/create/update`
- `fossil_sql` (read-only), `fossil_artifact_get`, `fossil_rebuild`, `fossil_sync`, `fossil_info`

Resources:

- `fossil://timeline`, `fossil://status`, `fossil://wiki/{page}`, `fossil://file/{path}@{rev}`, etc.

## What is NOT yet ported (TODO)

- Full checkout DB handling (vvar table)
- Full merge with Myers diff
- Sync protocol full implementation (xfer cards parsing done, but need integration)
- Web UI pages (50 pages)
- TH1 interpreter
- Markdown renderer
- Forum, chat
- `fossil bisect`, `fossil blame` full
- `fossil clean`, `fossil add`, `fossil rm`

These are outlined in PORTING_PLAN.md.

## License

BSD-2-Clause, same as original Fossil.
