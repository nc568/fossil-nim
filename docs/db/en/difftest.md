# Differential testing against real SQLite

`tools/db/difftest/` runs one corpus of SQL through two engines — this one and
the real SQLite — and compares the answers row by row.

The rule that makes it worth anything: **a divergence is a finding, not a
tolerance.** Every query in the corpus either matches SQLite exactly, or has an
entry in "Known differences" below with a reason. A query that disagrees and is
not listed is a bug, by definition.

## How it runs

```sh
sh tools/db/difftest/run.sh      # 56/56 queries match SQLite as of 2026-10-19
```

- `setup.sql` — schema and data, run once per engine;
- `queries.sql` — one statement per line, in order;
- `runner.nim` — this engine, printing `q<index>\t<row>||<row>`;
- `reference.py` — the real SQLite through Python's `sqlite3`, printing the same;
- `run.sh` — builds, runs both, diffs, prints the first differences.

Both sides normalise the same way: `NULL` for null, integers as decimal, reals
without trailing zeros, text as-is. Errors compare as the fact of refusal, not as
a message — SQLite says `no such column: name`, this engine says `NOTFOUND`, and
neither wording is a compatibility property.

## What it found on its first run

Three real divergences, all invisible to the unit tests because the unit tests
were written by the same person who wrote the engine and encoded the same
assumptions:

| Query | SQLite | This engine (before) | Cause |
|---|---|---|---|
| `7 / 2` | `3` | `3.5` | integer division kept its type only when the result was exact |
| `max(1, 2)` | `2` | `1` | every `max(...)` was routed to the aggregate path |
| `cast('42' AS INTEGER)` | `42` | `0` | the cast used `asInt`, which answers "how would this index an array" |

All three are fixed, and the corpus now matches 56 of 56.

The first fix is worth reading twice. The code said `if x mod y == 0: return
intValue(x div y)  # SQLite: int/int stays int`. The comment was right and the
code did something else, and no unit test noticed because the test that covered
division asserted `7 / 2 == 3.5` — the same wrong assumption, written down twice.

## Known differences (deliberate, and why)

| Difference | This engine | SQLite | Why it stays |
|---|---|---|---|
| error *text* | `NOTFOUND`, `LIMIT`, … | sentences | codes are for programs, sentences are for humans; neither is a contract |
| row order without `ORDER BY` | insertion/group order | unspecified | SQL says undefined; the corpus always sorts when it matters |
| type affinity | strict by default | permissive | a lossy store is a silent data-corruption bug; `strict = false` reproduces SQLite |
| `Infinity` / `NaN` in reals | rejected at the boundary | stored as `Inf` | not reachable from SQL text on either side, so the difference is in C interop only |

## Decision: no SQLite file-format compatibility

The engine does **not** read or write the SQLite file format, and this is
deliberate:

- the storage layer here is our own — 4 KiB pages, WAL frames with CRC32, the
  B+tree from `btree.nim`, page encryption with random nonces. SQLite's format
  is a 20-year accumulation that includes a legacy freelist, overflow-page
  arithmetic with different constants, and a record format tuned for its own
  varint encoding;
- matching it byte for byte would mean adopting every one of those decisions,
  including the ones this project exists to avoid, and it would freeze the page
  layout before K9L-83 can put a MAC on each page;
- the compatibility that actually matters to users is **SQL semantics** and the
  C API shape, and both are tested — the corpus above is that test.

What would change this: a user who needs to open an existing `.sqlite` file. The
road to that is an import tool that reads SQLite and writes this format, not a
second storage engine inside this one.
