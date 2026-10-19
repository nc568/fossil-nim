# Foccil DB — Portability: C, JavaScript, wasm, cproc/QBE

## 1. Target matrix

| Target | Command | State |
|---|---|---|
| Native C (gcc/clang) | `nim c --mm:arc` | ✅ 26 + 18 tests |
| JavaScript (V8/Node) | `nim js` | ✅ digest identical to native, byte for byte |
| wasm32 | `sh tools/wasm/build.sh` | ✅ 328 KB, runs under Node |
| cproc → QBE → musl | `sh tools/db/cproc/check.sh` | ✅ 22/22 TUs, and the smoke binary links and runs |

## 2. C ↔ JS parity

`tests/t_portable.nim` runs a fixed scenario (DDL, inserts, aggregates, `GROUP BY`,
`LIKE`, `CASE`, transactions, errors) and prints a digest: column names + row count +
32-bit FNV-1a over the values.

```
$ nim c  -r tests/t_portable.nim | md5sum
0376a7c4c0dfd8cf602e8fcff9dddb40  -
$ nim js -r tests/t_portable.nim | md5sum
0376a7c4c0dfd8cf602e8fcff9dddb40  -
```

Requirements that make this possible: no `hash()` over floats (backend-dependent) and no
64-bit arithmetic with overflow (JS numbers are doubles). Hence 32-bit FNV-1a with explicit
masking: every intermediate value is below 2⁵³, so the result is bit-identical on x86-64
and on V8.

## 3. wasm

### 3.1 Obstacles and resolutions

1. **Nim 2.2.12 has no `--os:wasi`.** Working combination: `--os:any --cpu:wasm32`.
2. **`--mm:arc` fails on freestanding:** `lib/system/arc.nim` references
   `emulatedThreadVars`, which is not imported for this target. A one-line patch
   (`elif compileOption("tlsEmulation"):`) is applied idempotently by `tools/bootstrap.sh`.
3. **`-d:noSignalHandler`** is required: otherwise Nim emits `signal(SIGFPE, …)`, absent
   from wasi-libc.
4. **`-d:useMalloc`** — otherwise Nim pulls in its page allocator, which needs `SysLock`.
5. **`-d:foccilNoClock`** pins the clock to the epoch: queries become reproducible and the
   core needs no time syscall.
6. **Compiler and linker are zig.** `zig cc -target wasm32-wasi` provides a C compiler,
   `wasm-ld` and wasi-libc in one 47 MB archive — no emscripten, no wasi-sdk. Nim cannot
   take `--clang.exe="zig cc"` (space in the name), so `tools/bootstrap.sh` creates
   `zigcc`/`zigld` wrappers.

### 3.2 Bridge protocol

Six exports (each export is attack surface, hence few):

```
foccil_version()            -> cstring
foccil_init()               -> void
foccil_exec(sql, params)    -> cstring (TSV payload)
foccil_exec_n(sql, params)  -> i32 (payload length)
foccil_last_ptr()           -> cstring (pointer to the last payload)
malloc/free                 -> for host-side string marshalling
```

Payload format:

```
1\nOK\n<cols joined by \t>\n<row count>\n<row>\n<row>…
1\nERR\n<CODE>\n<message>
```

A cell is `type:value` (`i:` int, `r:` real, `s:` text, `b:` blob, `n:` NULL).
Escaping (`\\`, `\t`, `\n`) happens once, on the way out.

**Important:** JS strings are not marshalled into wasm automatically. The host must
allocate inside the module (`malloc`), copy UTF-8 bytes and pass the pointer — exactly what
`tools/wasm/run.js` does. This also makes the trust boundary explicit.

### 3.3 Size

| Step | Bytes |
|---|---|
| naive `-O2` build | 2 250 464 |
| `-Oz` + `--strip-all` + `--gc-sections` | **328 770** |

A 6.8× reduction from flags alone — the kind of thing a CI gate should catch, not
production.

Next targets: 150 KB (own bump allocator instead of wasi-libc), 100 KB
(`-d:foccilNoAlloc` with a fixed-buffer arena).

## 4. cproc / QBE

### 4.1 The result

```
$ sh tools/db/cproc/check.sh
cproc gate: 22/22 translation units compiled
PASS: cproc->QBE->musl binary compiles, links and runs correctly
```

Every translation unit of the engine goes through **cproc → QBE → musl**, and the result
is not just an object file: a real program (`tools/db/cproc/smoke.nim`) is built, linked
and executed, and its output is compared against the expected one. A compile that
produces a binary which does not work would not be a gate.

### 4.2 Why it used to be 1/22 — three separate causes, none of them in the engine

| # | Symptom | TUs | Real cause |
|---|---|---|---|
| 1 | `qbe:-: unknown keyword extern` | 18 | **wrong QBE version.** cproc `d1c53dd` emits `extern $g` for globals with external linkage. That is valid **QBE 1.3**, not QBE 1.2 — `build.sh` was pinned to 1.2. cproc is not buggy; the two halves of the toolchain were from different years. |
| 2 | `assignment to pointer discards qualifiers` | 7 | **Nim codegen.** Nim passes `const` globals by pointer where C says the object is const (`&DefaultOptions`, RTTI tables, const sets). GCC warns; cproc rejects. |
| 3 | `long double`, `__uint128_t`, `case 48 ... 57` | 3 | **Nim's standard library** assumes GCC: musl's `math.h` declares `sqrtl`/`powl`, `pure/hashes.nim` emits a `__uint128_t` multiply, `pure/parseutils.nim` uses GNU case ranges. |

After fixing the QBE version alone the gate went **1/22 → 12/22**. That is the whole story
of issue K9L-35, and it is a *documentation* failure rather than a compiler bug: nothing in
cproc's README says which QBE it needs, and nothing fails at `make` time — you find out
much later, on a five-line C file.

### 4.3 What the gate shims, and what it does not

All three remaining causes are outside `src/`. The gate works around them, and every
workaround is **derived at gate time**, never committed and never hand-edited:

* **nimbase postlude** (`check.sh`): `#undef NIM_CONST` / `#define NIM_CONST` empty. Const
  globals move from `.rodata` to `.data`; the engine never writes them, so nothing changes
  semantically. This alone fixed 7 units.
* **`math.h` shim** (`shimgen.py`): a minimal header with the double subset. Only `fabs`
  is used today; anything else fails the gate loudly instead of silently pulling libm in.
* **stdlib patch** (`shimgen.py --install`): `pure/hashes.nim` takes its own portable
  128-bit fallback instead of the `__uint128_t` emit, and `pure/parseutils.nim` has its
  five `of '0'..'9':` ranges expanded into plain case labels — exactly the expansion Nim
  itself performs for compilers without the GNU extension. Originals are kept as
  `*.foccil-orig`, and every run re-derives from those backups, so the patch is idempotent
  and reversible. `shimgen.py --check` fails loudly if the stdlib no longer has the shape
  it patches, instead of silently producing a no-op.

`import std/x` resolves past the search path (and `patchFile()` ignores `std/` imports
too), so these two files genuinely cannot be shadowed from the project — patching the
installed toolchain is the only option that does not fork the stdlib into the repo.

### 4.4 Cost, measured rather than claimed

| | cproc → QBE → musl (static) | gcc (dynamic) |
|---|---|---|
| text | 418 KB | 376 KB |
| data | 40 KB | 6.7 KB |

Not an apples-to-apples comparison — musl is linked statically, glibc is not — so read it
as "the same order of magnitude", not as a regression budget. The `NIM_CONST` relaxation
is the only part attributable to the shim, and it is a `.rodata` → `.data` move, not growth.

### 4.5 What is still open

* The three stdlib issues are reported as a single upstream note (K9L-36): a Nim project
  cannot be built with a strict-C11 compiler without patching `parseutils` and `hashes`.
  If Nim ever gains a `-d:strictC11` that selects its own fallbacks, the shim disappears.
* `build.sh` now refuses to run with QBE < 1.3 instead of producing a toolchain that fails
  a thousand lines later.
* The gate is a *separate* build profile; `tools/test.sh` still uses gcc. A green gate does
  not by itself prove the shipped builds are cproc-clean — the smoke binary does, which is
  why it is part of the gate.

**Bottom line:** "must compile with cproc/QBE" is now a measurement with a working binary
at the end of it, and the three things that used to block it are documented, shimmed
outside the engine, and self-checking.

### 4.6 K9L-36, checked on clean C without Nim: real limitation, no report

The claim was "any `#include <math.h>` breaks cproc". Reproduced with no Nim
anywhere in sight, but the first explanation was wrong: it is not `math.h` and
not the `long double` *type*.

```c
/* ok */    long double g;                              /* parses, compiles     */
/* ok */    long double sqrtl(long double);              /* prototype, fine      */
/* ok */    static long double f(long double x);         /* declaration, fine    */
/* FAILS */ static inline long double f(long double x) { return x; }
            int g(void) { return 0; }
```

```
$ cproc -std=c11 -c -o min.o min.c
cproc-qbe: long double is not yet supported
```

So the trigger is a **definition** of a `static inline` function whose
parameters or bodies touch `long double` — even when it is never called. And
musl's `math.h` contains exactly that shape, six times, via `__ISREL_DEF`:

```c
static inline int __islessl(long double __x, long double __y) { ... }
```

Two facts follow, and they are different from the report we almost filed:

* It **is** a real cproc limitation, not our build. GCC compiles the same file;
  cproc rejects it; nothing here is Nim-specific.
* It is **already documented upstream**: cproc's README lists `long double`
  under what it does not implement (its issue #3, "requires qbe support"). A
  new bug report would be closed as a duplicate of a known limitation.

What is *not* documented, and what is worth one upstream sentence, is the
consequence: because unused `static inline` definitions are still code-generated,
a standard header that merely *declares* `long double` helpers poisons the whole
translation unit. Either skipping codegen for unused static inline bodies, or
printing `file:line` in that diagnostic, would turn a confusing failure into an
honest one. Our side is already handled: the gate compiles against a minimal
`math.h` shim with the double subset, so `fabs` works and anything new fails
loudly.

**Verdict:** confirmed on clean C, so the "was it our build?" doubt is closed —
but it is a known limitation, so there is no report to send, and this is
recorded here rather than filed.

### 4.7 The toolchain is pinned, and the standard library is patched

`tools/db/cproc/versions.env` is the single source of truth, and
`versions.sh` compares the installed toolchain against it:

```
$ sh tools/db/cproc/versions.sh
nim=2.2.12 qbe=1.3 cproc=d1c53dd musl=1.2.5
```

A mismatch is a hard failure, not a warning — that is what would have caught
K9L-35 on day one. `build.sh` stamps what it actually built (`qbe/.foccil-version`,
`cproc/.foccil-commit`, `musl/.foccil-version`), because QBE and cproc print no
version, and `shimgen.py` refuses to run when the installed Nim is not the pinned
one: the shim rewrites stdlib files *by shape*, so a silent version skew would
mean silently patching nothing.

**Read this before running the gate on a fresh machine:** the cproc build
requires a **patched Nim standard library**, and `check.sh` applies the patch
itself (idempotent, derived from `*.foccil-orig` backups). Two files change —
`pure/hashes.nim` takes its portable 128-bit fallback instead of the
`__uint128_t` emit, and `pure/parseutils.nim` gets its GNU case ranges expanded
— plus a NIM_CONST postlude in the generated `nimbase.h`. The engine source is
untouched. If you find unexplained stdlib changes on the machine, that is this,
and `*.foccil-orig` are the originals; the patch is not needed for the native,
JS or wasm builds, which use gcc/clang.
