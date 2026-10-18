# Бэклог для Linear (готов к переносу)

Проект Linear: **Foccil DB** (внутри рабочего пространства Foccil-nim).
Формат ниже совпадает с полями Linear: `Title` / `Description` / `Priority` /
`Estimate` / `Labels` / `Acceptance criteria`. Как только коннектор Linear будет
подключён, задачи создаются из этого файла без правок.

Метки: `area:core`, `area:storage`, `area:security`, `area:portability`, `area:docs`,
`area:tooling`, `kind:feature`, `kind:bug`, `kind:chore`, `risk:high`.

---

## Эпик 1 — Ядро (закрыт, v0.1)

| # | Title | Prio | Est | Состояние |
|---|---|---|---|---|
| 1.1 | Value model + comparison + affinity | High | 3 | Done |
| 1.2 | Tokenizer without regex, slice tokens | High | 3 | Done |
| 1.3 | Parser: DDL/DML/SELECT/CTE/compound | High | 8 | Done |
| 1.4 | Tree-walking executor with slot rows | High | 13 | Done |
| 1.5 | Constraints: PK/UNIQUE/NOT NULL/CHECK/DEFAULT | High | 5 | Done |
| 1.6 | Transactions: DML journal + DDL snapshot | High | 5 | Done |
| 1.7 | Secondary indexes + equality planner | High | 5 | Done |
| 1.8 | Public API + prepared statement cache | Medium | 3 | Done |

## Эпик 2 — Безопасность (закрыт, v0.1)

| # | Title | Prio | Est | Состояние |
|---|---|---|---|---|
| 2.1 | Injection resistance suite (12 payloads) | High | 2 | Done |
| 2.2 | Capability limits (readOnly, allowDdl, row budget) | High | 2 | Done |
| 2.3 | Parser guards (nesting, ATTACH/load_extension rejection) | High | 2 | Done |
| 2.4 | Fuzzing (3000 random + 2000 mutated inputs) | High | 3 | Done |
| 2.5 | Static anti-unsafe source check | Medium | 1 | Done |

## Эпик 3 — Портируемость (v0.1 частично, v0.5 полностью)

| # | Title | Prio | Est | Состояние |
|---|---|---|---|---|
| 3.1 | C ↔ JS digest parity test | High | 2 | Done |
| 3.2 | wasm32 build pipeline (zig + wasi-libc) | High | 5 | Done |
| 3.3 | wasm bridge + TSV protocol + Node host | High | 3 | Done |
| 3.4 | Binary size: 2.25 MB → 328 KB (`-Oz`, strip, gc-sections) | Medium | 2 | Done |
| 3.5 | `foccilMinimalFloat` profile (no libm) | Medium | 3 | Done |
| **3.6** | **Report cproc `extern` bug upstream with reproducer** | **High** | 1 | **Todo** |
| **3.7** | **Report cproc `long double`/math.h bug upstream** | **High** | 1 | **Todo** |
| **3.8** | **cproc gate → 22/22 (depends on 3.6/3.7 or a QBE backend)** | **High** | 13 | **Todo** |
| 3.9 | wasm without wasi-libc (own bump allocator), target < 150 KB | Medium | 8 | Todo |
| 3.10 | `-d:foccilNoAlloc` fixed-buffer arena for bare metal | Low | 8 | Todo |

**3.6 Description.**
`cproc` (master `d1c53dd`) emits invalid QBE IL for a plain extern global:

```c
extern int g_counter;
int use(void) { return g_counter; }
```
→ `qbe:-:5: unknown keyword extern`.
Open an issue with this reproducer, the failing `.ssa` snippet and a proposed patch.
**AC:** issue filed with a link; `tools/cproc/check.sh` regressions tracked.

**3.7 Description.**
Any `#include <math.h>` (musl) fails with `cproc-qbe: long double is not yet supported`,
because cproc parses `long double` prototypes it never uses. Reproducer: `double f(double x){return sqrt(x);}`.
**AC:** issue filed; workaround documented in `docs/*/portability.md` (already done: our
libm-free profile).

## Эпик 4 — Хранилище на диске (v0.2)

| # | Title | Prio | Est | Labels |
|---|---|---|---|---|
| 4.1 | `Vfs` abstraction (memory/file), no syscalls in core | High | 5 | area:storage |
| 4.2 | Pager: 4 KiB pages, LRU cache, dirty tracking | High | 8 | area:storage |
| 4.3 | WAL with per-frame salt + checksum, checkpoint | High | 13 | area:storage, risk:high |
| 4.4 | B+tree: insert/search/delete/scan with split/merge | High | 21 | area:storage, risk:high |
| 4.5 | Freelist + auto-vacuum | Medium | 8 | area:storage |
| 4.6 | Crash-recovery fuzzer (kill at random points) | High | 8 | area:storage, area:security |
| 4.7 | Page encryption (XChaCha20-Poly1305), key outside SQL | High | 13 | area:security |
| 4.8 | `backupTo(path)` — consistent snapshot API (no `VACUUM INTO`) | Medium | 5 | area:storage |

**4.4 AC:** differential test vs the in-memory index on 1e6 keys, byte-identical results;
zero data loss under 1000 random kill points.

**4.7 AC:** without the key the file is unreadable (test asserts a decrypt failure, not
garbage); with the key every row round-trips; the key never appears in SQL, logs or errors.

## Эпик 5 — Планировщик и производительность (v0.3)

| # | Title | Prio | Est |
|---|---|---|---|
| 5.1 | `ANALYZE` statistics + selectivity estimates | High | 8 |
| 5.2 | Cost-based index choice | High | 8 |
| 5.3 | Composite + covering indexes, index-only scan | High | 13 |
| 5.4 | Index-ordered output (no materialise for ORDER BY) | Medium | 5 |
| 5.5 | Predicate pushdown into subqueries/CTEs | Medium | 5 |
| 5.6 | Targets: 500k q/s point lookup, 100k rows/s insert | Medium | 8 |

## Эпик 6 — Функциональность (v0.4)

| # | Title | Prio | Est |
|---|---|---|---|
| 6.1 | Full-text search (FTS5-shaped: inverted index, ranking) | High | 21 |
| 6.2 | JSON: `json_extract`, `json_each`, `->`, `->>` | High | 8 |
| 6.3 | Window functions | Medium | 13 |
| 6.4 | Triggers (opt-in only; privilege-escalation channel) | Low | 8 |
| 6.5 | Full `ALTER TABLE` via transactional table rebuild | Medium | 8 |
| 6.6 | `DECIMAL` over int128 (money without floats) | Medium | 8 |

## Эпик 7 — Документация и процесс (постоянно)

| # | Title | Prio | Est |
|---|---|---|---|
| 7.1 | Keep RU+EN docs in sync in the same commit | High | ongoing |
| 7.2 | `.gitattributes` (LF), `.gitignore`, tag `v0.1.0` | High | 1 |
| 7.3 | CI pipeline calling `tools/test.sh` with toolchain cache | High | 3 |
| 7.4 | Pin cproc commit in `tools/cproc/VERSION` | Medium | 1 |
| 7.5 | Deep-research report on SQLite pain points (prompt ready) | Medium | 5 |

---

## Приоритеты на ближайшие две итерации

**Итерация A (эта неделя):** 3.6, 3.7, 7.2, 7.3, 7.4 — дёшево, снимает неопределённость
и делает проект воспроизводимым.

**Итерация B (следующая):** 4.1, 4.2, 4.3 — pager и WAL; после них данные переживают
перезапуск, и можно показывать замеры на реальном файле.
