## Micro-benchmark: measures the three numbers that matter for an embedded DB.
##   * insert throughput (single-row, prepared + params)
##   * point lookup through a secondary index
##   * full scan + aggregate
## Run: nim c -r -d:release --mm:arc tools/db/bench.nim

import std/[monotimes, times, strformat, os]
import fossil/db/api

proc now(): float = epochTime()

proc bench() =
  const N = 50_000
  let db = openMemory()
  discard db.execute("CREATE TABLE item (id INTEGER PRIMARY KEY, sku TEXT, qty INT, price REAL)")
  discard db.execute("CREATE INDEX ix_sku ON item (sku)")

  var t0 = now()
  discard db.execute("BEGIN")
  for i in 0 ..< N:
    discard db.execute("INSERT INTO item (sku, qty, price) VALUES (?, ?, ?)",
                       toParams([textValue("SKU" & $i), intValue(i mod 1000),
                                 realValue(float64(i) * 1.5)]))
  discard db.execute("COMMIT")
  var dt = now() - t0
  echo &"insert      {N} rows in {dt*1000:.0f} ms  -> {float64(N)/dt:.0f} rows/s"

  t0 = now()
  var hits = 0
  for i in 0 ..< 20_000:
    let rs = db.execute("SELECT qty FROM item WHERE sku = ?",
                        toParams([textValue("SKU" & $(i mod N))]))
    hits += rs.rows.len
  dt = now() - t0
  echo &"index lookup 20000 queries in {dt*1000:.0f} ms -> {20000.0/dt:.0f} q/s (hits={hits})"

  t0 = now()
  let agg = db.execute("SELECT sku, COUNT(*), SUM(qty) FROM item GROUP BY sku")
  dt = now() - t0
  echo &"group by     {N} rows in {dt*1000:.0f} ms -> {float64(N)/dt:.0f} rows/s (groups={agg.rows.len})"

  t0 = now()
  let scan = db.execute("SELECT COUNT(*), SUM(qty) FROM item WHERE qty > 500")
  dt = now() - t0
  echo &"filter scan  {N} rows in {dt*1000:.0f} ms (rows={scan.rows.len})"

when isMainModule:
  bench()
