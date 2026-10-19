# cproc / QBE gate

```sh
sh tools/db/cproc/build.sh     # toolchain into ~/.cache/tc (qbe 1.3, cproc, musl)
sh tools/db/cproc/check.sh     # the gate
```

Expected output:

```
cproc gate: 22/22 translation units compiled
PASS: cproc->QBE->musl binary compiles, links and runs correctly
```

`check.sh` does five things, in order:

1. derives the stdlib shims from the *installed* Nim (`shimgen.py --install`);
2. assembles a `nimbase.h` cproc can parse (prelude + stock + postlude);
3. generates C with the same flags as the native build, minus the config that
   links sqlite3 for the test builds;
4. compiles every translation unit with `cproc` against musl headers and groups
   the failures by root cause — progress is a number, not an opinion;
5. builds `smoke.nim` with cproc, links it with musl, runs it and compares the
   output. A compile that yields a binary which does not work is not a gate.

## Three things that were blocking it, and what they really were

**`qbe: unknown keyword extern` (18 of 22 units).** Not a cproc bug. cproc
emits `%r =w loadw extern $g` for globals with external linkage, which is QBE
**1.3** syntax; `build.sh` used to fetch QBE 1.2. Fixing the version alone took
the gate from 1/22 to 12/22. `build.sh` now probes the backend and refuses a
QBE that cannot parse that line.

**`assignment to pointer discards qualifiers` (7 units).** Nim passes `const`
globals by pointer where C says the object is const (`&DefaultOptions`, RTTI
tables, const sets). GCC warns; cproc rejects. The postlude makes `NIM_CONST`
empty: those objects move from `.rodata` to `.data`, which the engine never
notices because it never writes them.

**Three GCC-isms inside Nim's own stdlib** (`pure/hashes.nim` emits a
`__uint128_t` multiply, `pure/parseutils.nim` uses GNU case ranges, musl's
`math.h` declares `long double` prototypes). `import std/x` resolves past the
search path and `patchFile()` ignores `std/` imports, so these cannot be
shadowed from the project. `shimgen.py` rewrites them in place, keeping
`*.foccil-orig` backups and always deriving from those backups, so the patch is
idempotent and reversible. Semantics are preserved: the hashes shim selects
Nim's own portable fallback, and the parseutils shim performs the expansion Nim
itself performs for compilers without the GNU extension.

Nothing in `src/` is patched, and nothing derived here is committed
(`tools/db/cproc/shim/` is in `.gitignore`).
