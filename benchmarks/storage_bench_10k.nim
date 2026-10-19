## Extended benchmark 10k blobs
import ../src/fossil/storage/sqlite_backend
import ../src/fossil/storage/cdb_backend
import ../src/fossil/storage/hybrid_backend
import ../src/fossil/types
import ../src/fossil/utils/hash
import std/[times, os, strutils, random]

proc bench(name: string, n: int,
           putProc: proc(data: string): Rid,
           getProc: proc(rid: Rid): string,
           allRidsProc: proc(): seq[Rid]): tuple[putPerSec: float, getPerSec: float, cursorMs: float] =
  var rids: seq[Rid] = @[]
  let t1 = cpuTime()
  for i in 0..<n:
    let data = "blob data " & $i & " " & "x".repeat(200) & " payload " & $rand(1000000)
    rids.add putProc(data)
  let tPut = cpuTime() - t1
  let t2 = cpuTime()
  for rid in rids:
    discard getProc(rid)
  let tGet = cpuTime() - t2
  let t3 = cpuTime()
  let all = allRidsProc()
  let tCursor = cpuTime() - t3
  let putPerSec = if tPut>0: n.float / tPut else: 0
  let getPerSec = if tGet>0: n.float / tGet else: 0
  echo name & " n=" & $n & " put=" & formatFloat(tPut, ffDecimal,3) & "s " & $int(putPerSec) & "/s get=" & formatFloat(tGet, ffDecimal,3) & "s " & $int(getPerSec) & "/s cursor=" & formatFloat(tCursor*1000, ffDecimal,1) & "ms count=" & $all.len
  (putPerSec, getPerSec, tCursor*1000)

when isMainModule:
  echo "=== Extended Benchmark 10k blobs ==="
  let tmpDir = getTempDir() / "bench_10k"
  createDir(tmpDir)
  # SQLite 10k
  block:
    var db = SqliteBackend()
    let path = tmpDir / "bench_sqlite_10k.fossil"
    if fileExists(path): removeFile(path)
    discard db.open(path)
    discard db.initSchema()
    discard db.beginTxn()
    proc putS(data: string): Rid =
      let blob = newBlob(data)
      let uuid = hashBlob(blob)
      let r = db.putBlob(uuid, blob, false)
      if r.isOk: r.value else: Rid(0)
    proc getS(rid: Rid): string =
      let r = db.getBlob(rid)
      if r.isOk: r.value.data else: ""
    proc allS(): seq[Rid] =
      let r = db.getAllRids()
      if r.isOk: r.value else: @[]
    discard bench("SQLite", 10000, putS, getS, allS)
    discard db.commitTxn()
    db.close()
  # CDB 10k
  block:
    var cdb = CdbBackend()
    let path = tmpDir / "bench_cdb_10k.cdb"
    if fileExists(path): removeFile(path)
    discard cdb.open(path)
    proc putC(data: string): Rid =
      let blob = newBlob(data)
      let uuid = hashBlob(blob)
      let r = cdb.putBlob(uuid, blob, false)
      if r.isOk: r.value else: Rid(0)
    proc getC(rid: Rid): string =
      let r = cdb.getBlob(rid)
      if r.isOk: r.value.data else: ""
    proc allC(): seq[Rid] =
      let r = cdb.getAllRids()
      if r.isOk: r.value else: @[]
    discard bench("CDB", 10000, putC, getC, allC)
    cdb.close()
  # Hybrid 10k batched
  block:
    var hybrid = HybridBackend()
    let path = tmpDir / "bench_hybrid_10k.fossil"
    if fileExists(path): removeFile(path)
    if fileExists(path & ".cdbkv"): removeFile(path & ".cdbkv")
    putEnv("FOSSIL_HYBRID_KV", "cdb")
    discard hybrid.open(path)
    var batch = 0
    discard hybrid.beginTxn()
    proc putH(data: string): Rid =
      let blob = newBlob(data)
      let uuid = hashBlob(blob)
      let r = hybrid.putBlob(uuid, blob, false)
      inc batch
      if batch >= 10000:
        discard hybrid.commitTxn()
        discard hybrid.beginTxn()
        batch = 0
      if r.isOk: r.value else: Rid(0)
    proc getH(rid: Rid): string =
      let r = hybrid.getBlob(rid)
      if r.isOk: r.value.data else: ""
    proc allH(): seq[Rid] =
      let r = hybrid.getAllRids()
      if r.isOk: r.value else: @[]
    discard bench("Hybrid-CDB batched 10k", 10000, putH, getH, allH)
    discard hybrid.commitTxn()
    hybrid.close()
  echo "Done 10k"
