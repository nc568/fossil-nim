/* qbe_nimbase.h - DEPRECATED, kept for backward compatibility
 * Previously minimal 150-line shim that caused segfaults for version/help.
 * Now replaced by cinterop/include/nimbase.h wrapper that:
 *   - includes original nimbase.h via #include_next
 *   - overrides N_LIB_PRIVATE etc. to empty for QBE
 *   - defines __builtin_* macros to QBE-compatible versions
 *   - provides memmem fallback and SQLITE_TRANSIENT
 *   - avoids defining __attribute__ as empty (which broke glibc extern inline and caused multiple defs)
 * This new wrapper gives:
 *   - help exit 0 with full usage
 *   - version exit 0 without segfault
 *   - gcc fallback builds 455K for full main.nim, 354K for minimal main_qbe.nim
 *   - should also work for cproc/QBE with -I Nim lib path for #include_next
 *
 * For compatibility, this file now just includes the new wrapper.
 */
#ifndef QBE_NIMBASE_H
#define QBE_NIMBASE_H
#include "nimbase.h"
#endif
