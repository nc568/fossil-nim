# Foccil DB — Portability: C, JavaScript, wasm, cproc/QBE

## 1. Target matrix

| Target | Command | State |
|---|---|---|
| Native C (gcc/clang) | `nim c --mm:arc` | ✅ 26 + 18 tests |
| JavaScript (V8/Node) | `nim js` | ✅ digest identical to native, byte for byte |
| wasm32 | `sh tools/wasm/build.sh` | ✅ 328 KB, runs under Node |
| cproc → QBE | `sh tools/cproc/check.sh` | ⚠️ 1/22 TUs, blockers live in cproc |

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

### 4.1 What exists

* `tools/cproc/build.sh` builds **qbe 1.2**, **cproc** (git `d1c53dd`) and **musl 1.2.5**.
  musl is mandatory: glibc headers use GNU extensions cproc cannot parse.
* `tools/cproc/nimbase_cproc.h` turns `nimbase.h` into clean C11: `__GNUC__` is not
  defined, `__attribute__` is neutralised, overflow intrinsics degrade to plain arithmetic
  (the engine checks overflow itself).
* `tools/cproc/check.sh` is a **measurable gate**: it compiles every TU with cproc and
  groups failures by root cause, so progress is a number, not an opinion.
* The `-d:foccilMinimalFloat` profile removed the libm dependency (own `round`, `fmod`,
  `pow10`), which **eliminated** the `long double` blocker entirely.

### 4.2 Current state: 1/22 TUs

| Cause | TUs | Whose |
|---|---|---|
| `qbe: unknown keyword extern` | 18 | **cproc** |
| `assignment to pointer discards qualifiers` | 4 | cproc (const strictness) |

### 4.3 Minimal cproc reproducer (ready to upstream)

```c
/* min.c */
extern int g_counter;
int use(void) { return g_counter; }
```

```
$ cproc -std=c11 -c -o min.o min.c
qbe:-:5: unknown keyword extern
cproc: codegen: process ... exited with status 1
```

Five lines of standard C, zero extensions, reproducible without Nim. Until this is fixed,
no non-trivial project can use cproc.

Second blocker, also reproducible in isolation:

```c
#include <math.h>
double f(double x) { return sqrt(x); }
```

→ `cproc-qbe: long double is not yet supported` (cproc parses the `sqrtl`/`powl`
prototypes from the musl header and gives up). We worked around it by dropping `math.h`
from our cproc profile, but cproc will hit this for any libm user.

### 4.4 Plan

1. File both reproducers against `michaelforney/cproc` with draft patches.
2. Until upstream fixes land, keep the gate informative (`exit 1` only in strict mode;
   `tools/test.sh` does not block the build).
3. Fallback if upstream stalls: a thin "Nim-C → QBE" backend for the subset this engine
   emits. The core already uses nothing but C11 — enforced by a static test.

**Bottom line:** "must compile with cproc/QBE" moved from *hope* to *measured*: causes are
named, the culprit is cproc, there is a 5-line reproducer and a documented workaround path.
