# Nim config for Fossil-Nim port
# QBE compatibility flags

when defined(qbeCompat):
  # Minimal flags that make generated C more portable
  switch("define", "noSignalHandler")
  switch("define", "useMalloc")
  switch("define", "nimNoAlloca")
  switch("define", "nimEmulateOverflowChecks")
  switch("mm", "refc") # refc simpler than orc for QBE
  switch("threads", "off")
  switch("panics", "on")
  switch("stackTrace", "off")
  switch("lineTrace", "off")
  switch("passC", "-DQBE_COMPAT=1 -std=c11 -D_XOPEN_SOURCE=700 -I./cinterop/include -I./cinterop/sqlite -I./cinterop/mdbx -I./cinterop/lmdb -I./cinterop/sha3")
  switch("passL", "-lm -lz")
  --exceptions: "quirky"
else:
  # ARC - deterministic refcount, no GC pauses, no cycle collector
  # For projects needing cycle collection, use -d:useOrc or --mm:orc
  # ARC is pure ARC, no GC, smallest runtime, QBE-friendly C (no GC symbols)
  # ORC = ARC + cycle collector (handles ref cycles, 3.9M vs 3.8M ARC vs 2.1M refc)
  when defined(useOrc):
    switch("mm", "orc")
  elif defined(useRefc):
    switch("mm", "refc")
  else:
    switch("mm", "arc")
  switch("threads", "off") # threads:off avoids GC-safety checks for globals gConfig, gCsrfTokens
  switch("opt", "speed")
  switch("passC", "-I./cinterop/include -I./cinterop/sqlite -I./cinterop/mdbx -I./cinterop/lmdb -I./cinterop/sha3")
  switch("passL", "-lsqlite3 -lz -lm -lcrypto -lssl")

# Vendored mode - compile sqlite/lmdb/sha3 from source for static QBE builds
# Note: mdbx.c requires mdbx-internals.h which is not vendored (needs full libmdbx source)
# So we skip mdbx.c in vendored mode; libmdbx backend will be disabled or use system lib
when defined(vendored):
  switch("passC", "-I./cinterop/sqlite -I./cinterop/lmdb -I./cinterop/sha3 -DSQLITE_THREADSAFE=0 -DSQLITE_OMIT_LOAD_EXTENSION -DSQLITE_OMIT_WAL=0")
  switch("compile", "cinterop/sqlite/sqlite3.c")
  switch("compile", "cinterop/lmdb/mdb.c")
  switch("compile", "cinterop/lmdb/midl.c")
  switch("compile", "cinterop/sha3/sha3.c")
  switch("compile", "cinterop/sha3/sh3_wrapper.c")

# For QBE compat we vendor sha3 but NOT sqlite unless vendored flag is set
# This allows dynamic linking with -lsqlite3 for QBE builds (573K binary)
# Static build with vendored sqlite needs -d:vendored -d:qbeCompat and cinterop/sqlite/sqlite3.c present
when defined(qbeCompat):
  when defined(vendored):
    if fileExists("cinterop/sqlite/sqlite3.c"):
      switch("compile", "cinterop/sqlite/sqlite3.c")
  if fileExists("cinterop/sha3/sha3.c"):
    switch("compile", "cinterop/sha3/sha3.c")
  if fileExists("cinterop/sha3/sh3_wrapper.c"):
    switch("compile", "cinterop/sha3/sh3_wrapper.c")

when defined(release):
  switch("opt", "speed")
  switch("define", "danger")
