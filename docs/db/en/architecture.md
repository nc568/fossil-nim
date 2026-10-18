# Foccil DB — Architecture

## 1. Principles

1. **One source, three backends.** C, JS and wasm are built from the same code. Any
   design that cannot be expressed in all three worlds is rejected.
2. **Nothing extra on the hot path.** No GC, no bytecode VM, no plugin registry, no
   string-built SQL inside the core.
3. **Security is structural, not a review habit.** Dangerous capabilities are absent,
   not switched off by a flag.
4. **Fail closed.** An error beats a silent degradation.

## 2. Pipeline

```
SQL ──tokenizer──▶ tokens ──parser──▶ AST ──executor──▶ ResultSet
                                  │
                                  └── schema/catalog (tables, indexes, constraints)
```

### 2.1 Tokenizer (336 LOC)

* hand-written state machine, no regex (regex is a DoS surface and extra kilobytes);
* a token stores a **slice** of the source (`pos`, `len`), never a copy — lexing a 1 MB
  statement costs one allocation instead of one per token;
* numeric literals are decoded deterministically (`0x1F`, `1_000`, exponents); int64
  overflow promotes to REAL, as in SQLite;
* lookahead is exactly one token and it **does not rewind**. A save/restore design
  re-scans the token on every `peek`, making the lexer quadratic — a bug our tests caught.

### 2.2 Parser (1054 LOC)

* recursive descent plus a precedence ladder for expressions:
  `OR < AND < NOT < comparison < bitwise < ± < */% < || < COLLATE`;
* nesting limit of 64 — prevents stack exhaustion on `((((((…`;
* everything forbidden is rejected **at parse time**: `ATTACH`, `load_extension`,
  `VACUUM INTO`, unknown functions. Bad SQL never reaches the executor.

### 2.3 AST (246 LOC)

A flat object with optional fields instead of a deep variant hierarchy:

* less code (no per-node visitors);
* uniform node size, so allocation size never varies across a plan;
* matching is a single `case` on `kind`, which V8 compiles to a jump table.

Crucial detail: **every constructor sets `aggIdx = -1` explicitly**. Nim zero-initialises
object fields, so a forgotten field would mean "this is aggregate slot 0" and every scalar
function would return NULL. That is exactly the class of bug a type system cannot catch but
one shared constructor can.

### 2.4 Executor (1598 LOC)

Tree-walking execution over a slot-vector row.

Why not an opcode VM like SQLite's:

* a VM costs ~2.5k LOC of opcode implementations plus a program builder;
* on JS/wasm an opcode dispatch loop is the worst shape for the JIT (megamorphic switch,
  indirect dispatch), while direct recursion over a small AST inlines and specialises;
* smaller attack surface: no program counter to corrupt, no opcode table to keep in sync
  with the parser.

The usual cost of tree-walking (re-preparing per execution) is removed by the prepared
statement cache: the AST is immutable after parsing, so parse once and execute many.

#### Scopes

Every `SELECT` creates a **fresh scope** (empty column map). Without it, a subquery
silently shares the outer column map — simultaneously a correctness bug (ambiguous names)
and an information leak. Correlated subqueries resolve through an `outer` chain capped at
depth 32.

#### Planner

Deliberately small and **honest**: at most one index equality (`col = const`), and only
when it strictly narrows the candidate set. Everything else scans. `EXPLAIN` prints the
path that was actually chosen (`SEARCH … USING INDEX …`) and a test asserts it.

Measurement: point lookups went from **56 queries/s** to **185 842 queries/s** (3300×)
once the planner existed. Optimisation must be measurable, not declarative.

#### Transactions

* DML uses an undo journal (insert/update/delete + previous row); rollback replays it
  backwards in O(changes);
* DDL uses a catalog snapshot: a dropped table cannot be restored by a row journal because
  its identity is gone. If a transaction contained DDL, rollback restores the whole
  catalog snapshot.

### 2.5 Values (333 LOC)

* discriminated object: a NULL carries no blob buffer, text carries no int payload;
* total ordering `NULL < numbers < text < blob`, with BOOL folded into numbers so
  `true == 1`;
* int/int comparison is exact; int/real is careful (no loss for large integers);
* hash is consistent with `==` (otherwise `DISTINCT`/`GROUP BY` lie);
* `formatReal` in the `foccilMinimalFloat` profile needs no libm and produces
  **bit-identical** output on C and JS.

## 3. Portability

| Backend | How | Limits |
|---|---|---|
| C | `nim c --mm:arc` | none |
| JS | `nim js` | none |
| wasm32 | `--os:any --cpu:wasm32 --mm:arc -d:useMalloc` + zig (`wasi-libc`, `wasm-ld`) | no I/O; clock pinned (`-d:foccilNoClock`) |
| cproc/QBE | `-d:foccilMinimalFloat` profile | blocked by cproc bugs — see `portability.md` |

Everything banned in the core is enforced **by a test**: `tests/t_security.nim` scans
`src/foccil/db/*.nim` for `ptr`, `cast[`, `addr(`, `unsafeAddr`, `alloc*`, `dealloc` and
fails if any appears.

## 4. Next

v0.2 — paged storage: 4 KiB pager, WAL with frame checksums, B+tree, freelist. It replaces
the in-memory `std/tables` store without touching the executor (`schema.nim` is the swap
boundary).

v0.3 — cost-based planning, composite and covering indexes, `EXPLAIN QUERY PLAN` with
estimates.

v0.4 — FTS, JSON, window functions, triggers.

Full plan: `docs/en/plan.md`.
