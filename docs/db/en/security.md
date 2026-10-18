# Foccil DB — Security model

This document states **what** is guaranteed, **how** it is verified, and **where the
guarantees end**.

## 1. Threats we close

| Class | Example | How it is closed |
|---|---|---|
| SQL injection | `"… WHERE name = '" + input + "'"` | No API splices a value into SQL text. Data enters only as parameters |
| Type confusion | `'abc'` stored into `INTEGER` | Strict typing by default: a lossy conversion is an error |
| Filesystem escape | `ATTACH`, `load_extension`, `VACUUM INTO` | Absent. Rejected at parse time |
| Silent typo | `load_extention(...)` → NULL | Unknown function is a prepare-time error |
| Depth DoS | `((((((…` | Nesting limit 64, a `LIMIT` error, never a stack overflow |
| Volume DoS | `SELECT * FROM big` over 10⁹ rows | Per-query row budget, `LIMIT` error |
| Integer overflow | `a + b` wrapping into a negative rowid | Explicit checks, promotion to REAL instead of wrapping |
| Corruption via races | two writers | Single writer, transactions, rollback on close |
| Data leaking into logs | error text containing a row | Errors carry codes and object names, never row data |
| Unsafe code in the core | `ptr`, `cast`, manual allocation | Static test over the sources, fails on appearance |

## 2. Error codes (stable, for code not for logs)

```
OK GENERIC NOMEM READONLY INTERRUPT IOERR CORRUPT NOTFOUND FULL BUSY LOCKED
SCHEMA TOOBIG CONSTRAINT MISMATCH MISUSE AUTH RANGE SYNTAX UNSUPPORTED TYPE
LIMIT PARAM INJECTION
```

`INJECTION` is reserved for the layer that rejects dynamically assembled SQL (section 4).

## 3. Capabilities, not flags

`DbOptions` at open time:

| Field | Meaning |
|---|---|
| `strictTyping` | lossy conversion is an error (default `true`) |
| `readOnly` | reject all writes |
| `allowDdl` | reject `CREATE/DROP/ALTER` (typical for services exposing SQL) |
| `maxResultRows` | per-query row budget (0 = unlimited, default 1 000 000) |
| `maxParams` | parameter count ceiling |
| `maxQueryMs` | time budget (field exists; wired in v0.2) |

Recommended for "web service with user-supplied queries":

```nim
let db = openDb(DbOptions(strictTyping: true, readOnly: true, allowDdl: false,
                          maxResultRows: 10_000, maxParams: 100, maxQueryMs: 2_000))
```

## 4. Rules for embedding code

* Values go **only** through `toParams([...])`. Never concatenate.
* Identifiers cannot be parameterised. If a name comes from outside, it must match an
  allowlist, not be a string:

```nim
const AllowedTables = ["orders", "invoices"]
if table notin AllowedTables: raise newException(ValueError, "bad table")
```

* Dynamically assembled SQL must go through a dedicated strict mode (planned for v0.3,
  error code `INJECTION`).

## 5. Verification

`tests/t_security.nim`, 18 tests:

1. twelve classic injection payloads are stored as **data** and returned byte-identical;
2. a payload as a `LIKE` pattern does not widen the pattern;
3. quotes in identifiers never become expressions;
4. a trailing `;` after a statement is rejected, not ignored;
5. `allowDdl=false` → `AUTH`;
6. `readOnly` → `READONLY`;
7. `ATTACH`/`load_extension`/`VACUUM INTO` do not exist;
8. 500-level nesting → `LIMIT`, not a stack overflow;
9. the row budget trips;
10. `LIMIT 2^63-1` allocates nothing;
11. parameter index abuse → `RANGE`/`PARAM`;
12. strict typing rejects lossy stores;
13. `NULL` equals nothing;
14. `UNIQUE` allows many NULLs but no duplicates;
15. error messages contain no row data;
16. **fuzzing**: 3000 random strings — only `DbError`, no crash;
17. **mutation fuzzing**: 2000 mutations of a valid statement — same;
18. **static check**: no `ptr`, `cast[`, `addr(`, `unsafeAddr`, `alloc*`, `dealloc` in
    `src/foccil/db/*.nim`.

## 6. Where the guarantees end (honestly)

* **Files are not encrypted** in v0.1 (storage is still in memory). Page encryption is
  planned for v0.2 together with the pager; the key is supplied externally and SQL never
  sees it.
* **Timing side channels** are not eliminated: this is a database, not a crypto primitive.
  Compare secrets with a constant-time helper, never with SQL `=`.
* **`random()` is not cryptographically secure** and is documented as such. Crypto-grade
  randomness is deliberately not exposed to SQL: SQL must not be able to weaken a key.
* **Memory is not protected from the host process.** If the host is compromised, the
  database is compromised. The goal is that SQL cannot compromise the host.
