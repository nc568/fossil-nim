/* cproc/QBE compatibility prelude for Nim-generated C (ARC).
 *
 * cproc implements C11 without GNU extensions, while Nim's `nimbase.h`
 * assumes GCC/Clang (`__attribute__`, `__builtin_*_overflow`, `__CHAR_BIT__`).
 * This prelude is prepended to a copy of `nimbase.h` (tools/db/cproc/build.sh).
 * Overflow intrinsics degrade to plain arithmetic: the engine performs its own
 * explicit overflow checks (engine.safeAdd), so nothing is hidden here.
 */
#ifndef FOCCIL_CPROC_PRELUDE
#define FOCCIL_CPROC_PRELUDE
#ifndef __CHAR_BIT__
#  define __CHAR_BIT__ 8
#endif
/* We deliberately do NOT define __GNUC__: that makes nimbase.h choose its
 * "no extensions" branch. `__attribute__` is then neutralised below so any
 * remaining use is harmless. */
#define __attribute__(x)
#define __inline inline
#define __restrict
#define __restrict__
#ifndef __has_attribute
#  define __has_attribute(x) 0
#endif
#ifndef __has_builtin
#  define __has_builtin(x) 0
#endif
#define __builtin_saddll_overflow(a,b,r)  (*(r) = (long long)(a) + (long long)(b), 0)
#define __builtin_ssubll_overflow(a,b,r)  (*(r) = (long long)(a) - (long long)(b), 0)
#define __builtin_smulll_overflow(a,b,r)  (*(r) = (long long)(a) * (long long)(b), 0)
#define __builtin_sadd_overflow(a,b,r)    (*(r) = (int)(a) + (int)(b), 0)
#define __builtin_ssub_overflow(a,b,r)    (*(r) = (int)(a) - (int)(b), 0)
#define __builtin_smul_overflow(a,b,r)    (*(r) = (int)(a) * (int)(b), 0)
#define __builtin_uadd_overflow(a,b,r)    (*(r) = (unsigned)(a) + (unsigned)(b), 0)
#define __builtin_usub_overflow(a,b,r)    (*(r) = (unsigned)(a) - (unsigned)(b), 0)
#define __builtin_umul_overflow(a,b,r)    (*(r) = (unsigned)(a) * (unsigned)(b), 0)
#endif
