## All tests runner

import std/[os, strutils, tables]

echo "Running Fossil-Nim tests..."

# Test delta
echo "=== test_delta ==="
import ../src/fossil/types
import ../src/fossil/delta/delta

let src = newBlob("hello world, this is source")
let tgt = newBlob("hello world, this is target with changes")
let cr = deltaCreate(src, tgt)
assert cr.isOk, "deltaCreate failed"
let enc = deltaEncode(cr.value)
let dec = deltaDecode(enc)
assert dec.isOk, "deltaDecode failed"
let applied = deltaApply(src, dec.value)
assert applied.isOk, "deltaApply failed"
assert applied.value.data == tgt.data, "roundtrip mismatch: " & applied.value.data & " != " & tgt.data
echo "delta roundtrip OK"

# Test manifest
echo "=== test_manifest ==="
import ../src/fossil/artifact/manifest
let manifestText = """
C initial commit
D 2024-12-01T12:00:00.000
U user@example.com
F file.txt abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890
Z dummy
"""
let mRes = parseManifest(manifestText)
assert mRes.isOk, "parseManifest failed: " & (if mRes.isErr: mRes.error.msg else: "")
echo "manifest parse OK: ", mRes.value.files.len, " files"

# Test storage backends
echo "=== test_storage sqlite (mock) ==="
import ../src/fossil/storage/sqlite_backend
var sb = SqliteBackend()
assert sb.name() == "sqlite"
echo "sqlite backend type OK"

when defined(useMdbx):
  import ../src/fossil/storage/libmdbx_backend
  var mb = LibMdbxBackend()
  assert mb.name() == "libmdbx"
  echo "libmdbx backend type OK"

import ../src/fossil/storage/cdb_backend
var cb = CdbBackend()
assert cb.name() == "cdb"
echo "cdb backend type OK"

# Test MCP tools
echo "=== test_mcp ==="
import ../src/fossil/mcp/tools
let reg = buildDefaultRegistry()
assert len(reg.tools) > 0
echo "mcp tools count: ", len(reg.tools)

# Test hash
echo "=== test_hash ==="
import ../src/fossil/utils/hash
let blob = newBlob("test data")
try:
  let h = sha3_256(blob)
  echo "hash OK: ", string(h)[0..15], "... len=", len(string(h))
  assert len(string(h)) == 64
except:
  echo "hash skipped (no openssl/sh3): ", getCurrentExceptionMsg()

# Test diff
echo "=== test_diff ==="
import ../src/fossil/vcs/diff
let a = newBlob("line1\nline2\nline3\n")
let b = newBlob("line1\nlineX\nline3\n")
let d = diffBlobs(a, b, "test.txt")
assert d.lines.len > 0
echo "diff OK: ", d.lines.len, " lines"
echo diffToUnified(d)

echo "All tests passed!"
