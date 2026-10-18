# Foccil DB — English docs

[Русская документация](../ru/README.md) · [Wiki](../wiki/Home.md)

| Document | Contents |
|---|---|
| [architecture.md](architecture.md) | pipeline, why no opcode VM, scopes, planner, transactions |
| [security.md](security.md) | threat table, capabilities, all 20 security tests, honest limits |
| [portability.md](portability.md) | C/JS/wasm/cproc, parity digests, wasm recipe, cold numbers |
| [plan.md](plan.md) | v0.1 → v0.5 with "done when" criteria, open questions |
| [research-painpoints.md](research-painpoints.md) | SQLite pain points and our answer to each |

Design one-liners that explain most of the codebase:

* **Tree-walking, not a VM.** On wasm/V8, direct recursion over a small AST beats an opcode
  dispatch loop; it is also ~2.5k LOC cheaper and has no program counter to corrupt.
* **Fresh scope per SELECT.** Otherwise subqueries corrupt the outer column map — both a
  correctness bug and an information leak.
* **Strict typing by default.** Lossy conversion is an error; flexibility is opt-in.
* **Catalog snapshot for DDL, undo journal for DML.** A dropped table cannot be restored by
  a row journal; a cheap journal handles the common case.
* **Everything banned is tested.** A static test scans the core for `ptr`/`cast`/`addr`.
