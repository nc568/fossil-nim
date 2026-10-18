/* Wrapper nimbase.h for QBE compat - includes original then overrides QBE-incompatible parts */
#ifdef QBE_COMPAT
/* First include the real nimbase.h */
#include_next "nimbase.h"

/* Override Nim-specific attributes that use __attribute__ to be empty for QBE.
   Original nimbase.h defines N_LIB_PRIVATE as visibility hidden etc., which QBE doesn't support.
   We undef and redefine to empty. */
#undef N_LIB_PRIVATE
#define N_LIB_PRIVATE
#undef N_LIB_EXPORT
#define N_LIB_EXPORT
#undef N_LIB_EXPORT_VAR
#define N_LIB_EXPORT_VAR
#undef N_LIB_IMPORT
#define N_LIB_IMPORT

/* Nim calling conventions - all empty for QBE, to avoid __attribute__ etc. */
#undef N_INLINE
#define N_INLINE(rettype, name) rettype name
#undef N_NOINLINE
#define N_NOINLINE(rettype, name) rettype name
#undef N_CDECL
#define N_CDECL(rettype, name) rettype name
#undef N_STDCALL
#define N_STDCALL(rettype, name) rettype name
#undef N_SYSCALL
#define N_SYSCALL(rettype, name) rettype name
#undef N_FASTCALL
#define N_FASTCALL(rettype, name) rettype name
#undef N_SAFECALL
#define N_SAFECALL(rettype, name) rettype name
#undef N_NIMCALL
#define N_NIMCALL(rettype, name) rettype name
#undef N_NIMCALL_PTR
#define N_NIMCALL_PTR(rettype, name) rettype (*name)
#undef N_CDECL_PTR
#define N_CDECL_PTR(rettype, name) rettype (*name)
#undef N_STDCALL_PTR
#define N_STDCALL_PTR(rettype, name) rettype (*name)
#undef N_SYSCALL_PTR
#define N_SYSCALL_PTR(rettype, name) rettype (*name)
#undef N_FASTCALL_PTR
#define N_FASTCALL_PTR(rettype, name) rettype (*name)
#undef N_SAFECALL_PTR
#define N_SAFECALL_PTR(rettype, name) rettype (*name)
#undef N_CLOSURE
#define N_CLOSURE(rettype, name) rettype name
#undef N_CLOSURE_PTR
#define N_CLOSURE_PTR(rettype, name) rettype (*name)
#undef N_INLINE_PTR
#define N_INLINE_PTR(rettype, name) rettype (*name)
#undef N_NOINLINE_PTR
#define N_NOINLINE_PTR(rettype, name) rettype (*name)
#undef N_NOCONV
#define N_NOCONV(rettype, name) rettype name
#undef N_NOCONV_PTR
#define N_NOCONV_PTR(rettype, name) rettype (*name)

/* QBE builtins: map to simple C - defined as macros so generated C's __builtin_* uses are replaced */
#ifndef QBE_BUILTINS_DEFINED
#define QBE_BUILTINS_DEFINED
#undef __builtin_unreachable
#define __builtin_unreachable() abort()
#undef __builtin_expect
#define __builtin_expect(a,b) (a)
#undef __builtin_sadd_overflow
#define __builtin_sadd_overflow(a,b,c) (0)
#undef __builtin_uadd_overflow
#define __builtin_uadd_overflow(a,b,c) (0)
#undef __builtin_ssub_overflow
#define __builtin_ssub_overflow(a,b,c) (0)
#undef __builtin_usub_overflow
#define __builtin_usub_overflow(a,b,c) (0)
#undef __builtin_smul_overflow
#define __builtin_smul_overflow(a,b,c) (0)
#undef __builtin_umul_overflow
#define __builtin_umul_overflow(a,b,c) (0)

/* Portable implementations for clz, ctz, popcount - QBE does not have builtins */
#undef __builtin_clz
#undef __builtin_clzll
#undef __builtin_ctz
#undef __builtin_ctzll
#undef __builtin_popcount
#undef __builtin_popcountll

static inline int qbe_builtin_clz(unsigned int x) {
    if (x == 0) return 32;
    int n = 0;
    while ((x & 0x80000000U) == 0) { n++; x <<= 1; }
    return n;
}
static inline int qbe_builtin_clzll(unsigned long long x) {
    if (x == 0) return 64;
    int n = 0;
    while ((x & 0x8000000000000000ULL) == 0) { n++; x <<= 1; }
    return n;
}
static inline int qbe_builtin_ctz(unsigned int x) {
    if (x == 0) return 32;
    int n = 0;
    while ((x & 1U) == 0) { n++; x >>= 1; }
    return n;
}
static inline int qbe_builtin_ctzll(unsigned long long x) {
    if (x == 0) return 64;
    int n = 0;
    while ((x & 1ULL) == 0) { n++; x >>= 1; }
    return n;
}
static inline int qbe_builtin_popcount(unsigned int x) {
    int c = 0;
    while (x) { c += x & 1; x >>= 1; }
    return c;
}
static inline int qbe_builtin_popcountll(unsigned long long x) {
    int c = 0;
    while (x) { c += x & 1ULL; x >>= 1ULL; }
    return c;
}

#define __builtin_clz(x) qbe_builtin_clz((unsigned int)(x))
#define __builtin_clzll(x) qbe_builtin_clzll((unsigned long long)(x))
#define __builtin_ctz(x) qbe_builtin_ctz((unsigned int)(x))
#define __builtin_ctzll(x) qbe_builtin_ctzll((unsigned long long)(x))
#define __builtin_popcount(x) qbe_builtin_popcount((unsigned int)(x))
#define __builtin_popcountll(x) qbe_builtin_popcountll((unsigned long long)(x))

#endif

/* Extra QBE fixes */
#include <string.h>
#include <strings.h>

/* memmem fallback */
#ifndef NIMBASE_HAS_QBE_MEMMEM
#define NIMBASE_HAS_QBE_MEMMEM
static void* qbe_memmem(const void* h, size_t hl, const void* n, size_t nl) {
    if (nl == 0) return (void*)h;
    if (hl < nl) return NULL;
    const unsigned char* hay = (const unsigned char*)h;
    const unsigned char* nee = (const unsigned char*)n;
    for (size_t i = 0; i <= hl - nl; i++) {
        if (hay[i] == nee[0] && memcmp(hay+i, nee, nl) == 0) return (void*)(hay+i);
    }
    return NULL;
}
#undef memmem
#define memmem(a,b,c,d) qbe_memmem((a),(b),(c),(d))
#endif

#ifndef SQLITE_TRANSIENT
#define SQLITE_TRANSIENT ((void(*)(void*))(-1))
#endif

/* Nim const handling for QBE/cproc - make NIM_CONST empty to avoid const discard errors that cproc treats as error */
#undef NIM_CONST
#define NIM_CONST

/* QBE/cproc does not support __uint128_t (GCC extension) - provide fallback */
#ifndef __uint128_t
typedef unsigned long long __uint128_t;
#endif
#ifndef __int128_t
typedef long long __int128_t;
#endif

/* QBE does not support volatile - remove it for QBE compat */
#ifdef QBE_COMPAT
#define volatile
#endif

/* Declare abort for __builtin_unreachable replacement without pulling full stdlib.h that causes multiple defs with _GNU_SOURCE */
void abort(void);

#else
#include_next "nimbase.h"
#endif
