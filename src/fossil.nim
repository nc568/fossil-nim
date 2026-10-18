## Fossil-Nim - main library entry point
## Re-exports all modules for convenient import

import ./fossil/types
import ./fossil/config
import ./fossil/storage/backend
import ./fossil/storage/sqlite_backend
import ./fossil/storage/libmdbx_backend
import ./fossil/storage/lmdb_backend
import ./fossil/storage/cdb_backend
import ./fossil/delta/delta
import ./fossil/artifact/manifest
import ./fossil/artifact/artifact
import ./fossil/vcs/checkout
import ./fossil/vcs/commit
import ./fossil/vcs/diff
import ./fossil/vcs/branch
import ./fossil/vcs/timeline
import ./fossil/vcs/merge
import ./fossil/wiki/wiki
import ./fossil/ticket/ticket
import ./fossil/api/rest
import ./fossil/mcp/tools
import ./fossil/mcp/server

export types
export config
export backend
export sqlite_backend
export libmdbx_backend
export lmdb_backend
export cdb_backend
export delta
export manifest
export artifact
export checkout
export commit
export diff
export branch
export timeline
export merge
export wiki
export ticket
export rest
export tools
export server

const FossilNimVersion* = "2.26.0-nim"
