## Real storage backend test with actual files

import std/[os, strutils, options]
import ../src/fossil/types
import ../src/fossil/storage/sqlite_backend
import ../src/fossil/storage/cdb_backend
import ../src/fossil/utils/hash

echo "=== test_storage_real sqlite ==="

let tmpPath = "/tmp/fossil-nim-test-sqlite.fossil"
if fileExists(tmpPath): removeFile(tmpPath)

var backend = SqliteBackend()
let openRes = backend.open(tmpPath)
assert openRes.isOk, "open failed: " & openRes.error.msg
echo "open OK: ", tmpPath

let schemaRes = backend.initSchema()
assert schemaRes.isOk, "initSchema failed: " & schemaRes.error.msg
echo "create table OK"

# Now test put/get
let data = newBlob("hello world artifact")
let uuid = hashBlob(data)
echo "uuid: ", $uuid

let putRes = backend.putBlob(uuid, data, false)
assert putRes.isOk, "putBlob failed: " & putRes.error.msg
let rid = putRes.value
echo "putBlob OK rid=", $rid

let getRes = backend.getBlob(rid)
assert getRes.isOk, "getBlob failed"
assert getRes.value.data == data.data, "data mismatch"
echo "getBlob by rid OK"

let getByUuidRes = backend.getBlobByUuid(uuid)
assert getByUuidRes.isOk, "getBlobByUuid failed"
assert getByUuidRes.value.data == data.data
echo "getBlobByUuid OK"

let has = backend.hasUuid(uuid)
assert has, "hasUuid failed"
echo "hasUuid OK"

let allRidsRes = backend.getAllRids()
assert allRidsRes.isOk
echo "getAllRids OK count=", allRidsRes.value.len

let metaSet = backend.setMeta("test-key", "test-value")
assert metaSet.isOk, "setMeta failed"
let metaGet = backend.getMeta("test-key")
assert metaGet.isOk and metaGet.value == "test-value"
echo "meta OK"

backend.close()
echo "close OK"

# Test CDB backend
echo "\n=== test_storage_real cdb ==="
let cdbPath = "/tmp/fossil-nim-test.cdb"
if fileExists(cdbPath): removeFile(cdbPath)
var cdb = CdbBackend()
let cdbOpen = cdb.open(cdbPath)
assert cdbOpen.isOk, "cdb open failed"
echo "cdb open OK (writer mode)"

let cdbData = newBlob("cdb artifact data")
let cdbUuid = hashBlob(cdbData)
let cdbPut = cdb.putBlob(cdbUuid, cdbData, false)
assert cdbPut.isOk, "cdb put failed"
echo "cdb put OK rid=", $cdbPut.value

cdb.close()
echo "cdb close OK (wrote file)"

# Check file exists
assert fileExists(cdbPath)
echo "cdb file exists size=", getFileSize(cdbPath)

echo "\nAll real storage tests passed!"
