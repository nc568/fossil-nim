# Push state

Repository: `nc568/fossil-nim`
Branch under development: **`feat/foccil-db-v0.1`** — currently **`b514de4`**
`main` stays at `dd7630e` and is not merged until the implementation is complete.

PR / diff for review:
<https://github.com/nc568/fossil-nim/compare/main...feat/foccil-db-v0.1>

## History of this effort

| Commit | What |
|---|---|
| `f5c3448` | SQL engine rewritten in Nim (ARC) — C, JS and wasm from one source |
| `e207022` | storage layer — VFS + 4 KiB pager with LRU and freelist |
| `50ed8fb` | WAL — `src/fossil/db/wal.nim` + 17 tests, docs in RU and EN |
| `b514de4` | wiki index updated for storage and WAL |

## Gate

**26 core + 20 security + 17 storage + 17 WAL**, 0 failures.
Backend parity digest unchanged: `0376a7c4c0dfd8cf602e8fcff9dddb40`.

```sh
export PATH=$HOME/.cache/tc/nim-2.2.12/bin:$PATH
for t in t_core t_security t_storage t_wal; do
  nim c -r --skipParentCfg:on --mm:arc --hints:off --warnings:off \
      --path:src --outdir:build/db tests/db/$t.nim
done
```

## Two bugs the WAL tests caught

1. The CRC covered its own field — that is, uninitialised memory. Every frame was
   rejected by the reader that had just written it.
2. The commit marker was `-1`, which came back as `4294967295` after the unsigned
   decoding round-trip, so it was never recognised. It is `0x7FFFFFFF` now.

Both were invisible to review and obvious to a test that reads its own writes.

## Notes

- The clone in this workspace has no credential in `.git/config`; pushes use a
  one-shot `x-access-token` URL that is never written to disk.
- The token has contents rights only — `POST /pulls` returns 403, hence the
  compare link above instead of a pull request.
