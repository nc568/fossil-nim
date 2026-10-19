# What the fossil-nim audit teaches a database engine

The audit of 2026-10-19 (`docs/SECURITY_AUDIT_2026-10-19_FULL_RU.md`, on `main`)
targets the *server* half of this project — REST, MCP, WebUI, sync — not the
engine. It was read anyway, and it paid for itself: one class in it turned out to
be alive in this codebase, with worse consequences than in the server.

The audit's 33 findings collapse into seven shapes. Each one has an engine-side
analogue, and the interesting column is the last one.

| Shape in the audit | Example there | Analogue in a storage engine | Status here |
|---|---|---|---|
| missing authentication at a boundary | `/clone`, `/xfer`, MCP | SQL reaching the file system or the key | no `ATTACH`, no `load_extension`, key is a `DbOptions` field SQL cannot see (K9L-83) |
| **unverified hash on ingest** | `putBlob` does not check `hash(data) == uuid` | a page read from disk not verified against its checksum/MAC | **partially open** — WAL frames have CRC32, main-file pages have nothing until K9L-83 |
| **size field used before it is checked** | blob header → OOM | cell `valLen` → `newString(total)` | **was broken, now fixed** — see below |
| **recursion or cycle without a budget** | delta chains → stack overflow | overflow-page chain → infinite loop; tree graph → cycle | btree depth capped at 64; overflow chain now has a progress and length budget |
| path traversal | `fossil_rebuild` writing anywhere | VFS path handling | the engine never takes a path from SQL |
| timing oracle | `==` on passwords | `==` on a MAC tag | `constantTimeEq`, single error message |
| unbounded work per request | no rate limit | a query that runs forever | `maxResultRows`, `maxQueryMs`, parser nesting cap |

## What was actually broken

`parseNode` in `btree.nim` trusted every field of the page it was given: kind
byte, cell count, offset table, key length, value length. A single flipped byte
was enough:

```
kind=255 on page 1 -> Defect IndexDefect: index out of bounds, the container is empty
```

That is not a `DbError`. A `Defect` escapes every `except DbError` in the program
and takes the process with it — so one corrupt page kills a server that was
holding a hundred healthy ones. The audit's SEC-12 is the same mistake wearing a
different hat: a length field is a number until you check it.

`readOverflow` had two more:

- `newString(total)` where `total` comes off the disk — ask the file for a
  gigabyte and the allocator obliges;
- a chain whose pages each claim zero bytes makes no progress and never
  terminates: no crash, no allocation, just a database that stops answering.
  A memory watchdog would never see it.

`freeOverflow` walked the same chain with no budget at all.

All four are fixed in `btree.nim`; `t_corrupt` (10 tests) is the regression. The
test was verified the only way that counts: against the *old* code it fails with
the defect above, against the new code it passes.

## How `t_corrupt` is built

A real tree of 400 keys (deep enough for internal nodes) is dumped to bytes, then
mutated one field at a time — kind, count, each offset byte, key and value
lengths, child pointers — plus 2000 seeded random mutations over the page area.
For each mutant the test opens the file and does everything a reader would do.

Only two outcomes are allowed: a correct answer, or a `DbError`. `Defect`,
`CatchableError` and any other exception fail the test, because each of them is
a crash in production. A control case runs the unmodified image first, so a
harness that passes everything cannot masquerade as a passing suite.

## Still open, and known

**There is no page checksum in the main file.** Corrupt data is *refused* now, but
a flipped bit inside a value — one that lands in a payload rather than in the
structure — is returned as data. Nothing detects it. That is exactly the audit's
SEC-06 class ("verify what you ingest") and it is the strongest argument for
K9L-83 that is not about confidentiality: the HMAC over every page turns bit rot
and tampering from "silently wrong" into "refused".

Until then, a corrupt main file is detectable only where the damage happens to
land in structure.

## The general rule this produced

> Every number that comes from a file is an attacker's number until it has been
> compared against a bound the file does not control.

Applied in this codebase: cell counts and offsets against `PageSize`, key lengths
against `MaxKeySize`, value lengths against `MaxValueSize`, chain lengths against
the page count, tree depth against 64, statement nesting against the parser cap,
rows against `maxResultRows`.
