# Build Guide

## Requirements

- Nim 2.0+
- clang or gcc (for normal build)
- cproc + QBE (for QBE build)
- libsqlite3-dev, zlib, libssl-dev
- Optional: libmdbx-dev, liblmdb-dev

## Normal Build

```bash
nimble build
# or
make build
```

Binaries in `bin/fossil` and `bin/fossil-mcp`.

## QBE Build

```bash
# Generate C files
nimble buildQbe
# or
make build-qbe-c

# Compile with cproc
make qbe

# Check
./bin/fossil-qbe version
```

## Vendored Build (no system deps)

```bash
# Vendor sqlite3.c and mdbx.c into cinterop/
# Then
nim c -d:vendored -d:release src/fossil/cli/main.nim
```

## Docker

```dockerfile
FROM nimlang/nim:2.0.0-alpine as builder
RUN apk add sqlite-dev zlib-dev openssl-dev
COPY . /src
WORKDIR /src
RUN nimble build

FROM alpine
COPY --from=builder /src/bin/fossil /usr/local/bin/
ENTRYPOINT ["fossil"]
```

## Cross Compilation

Nim supports cross via `--os:any` and custom cc.

For QBE, QBE itself supports x86_64, aarch64, riscv64.

## Troubleshooting

- `sqlite3.h not found`: install libsqlite3-dev or use `-d:vendored`
- `mdbx.h not found`: install libmdbx or use sqlite backend only
- `cproc: command not found`: install cproc from https://git.sr.ht/~mcf/cproc
- Nim cache issues: `rm -rf nimcache build/cgen`
