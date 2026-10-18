## Backend-parity test.
##
## This file must compile to **C, JavaScript and wasm** and print a byte-identical
## digest on all three. If the digest differs, the engines disagree and one of
## them is lying — that is the single most valuable test for a port.
##
##   nim c  -r  tests/db/t_portable.nim     -> native
##   nim js -r  tests/db/t_portable.nim     -> node
##   nim c  -r  --os:standalone ...      -> wasm (see tools/db/wasm/build.sh)

import std/[strutils, hashes]
import fossil/db/api

proc digest(rs: ResultSet): string =
  ## Stable, backend-independent checksum over a result set.
  ## Not `hash()` on floats (backend representations differ) — values are
  ## formatted through the same `toText` the engine uses for CAST.
  ## 32-bit FNV-1a with explicit masking: every intermediate stays below 2^53,
  ## so the value is bit-identical on a 64-bit CPU and on a JS double.
  var h: int64 = 2166136261'i64
  for r in rs.rows:
    for v in r:
      let s = $v.kind & ":" & v.toText
      for ch in s:
        h = (h xor int64(ord(ch))) and 0xFFFF_FFFF'i64
        h = (h * 16777619'i64) and 0xFFFF_FFFF'i64
  rs.cols.join(",") & "|" & $rs.rows.len & "|" & $h

proc run(db: Db; sql: string; params: Params = @[]): string =
  try:
    digest(db.execute(sql, params))
  except DbError as e:
    "ERR:" & e.code.codeName & ":" & e.msg

proc main() =
  let db = openMemory()
  var lines: seq[string]
  lines.add run(db, "CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT NOT NULL, score INT, tag TEXT)")
  lines.add run(db, "INSERT INTO t (name, score, tag) VALUES ('ann', 90, 'a'), ('bob', 75, 'b'), ('cid', 60, 'a'), ('dan', NULL, 'c')")
  lines.add run(db, "SELECT COUNT(*), SUM(score), AVG(score) FROM t")
  lines.add run(db, "SELECT tag, COUNT(*) FROM t GROUP BY tag ORDER BY tag")
  lines.add run(db, "SELECT name FROM t WHERE score > ? ORDER BY score DESC", toParams([intValue(60)]))
  lines.add run(db, "SELECT name, score * 2 + 1 FROM t ORDER BY id LIMIT 2")
  lines.add run(db, "SELECT upper(name) || '-' || coalesce(tag, 'x') FROM t ORDER BY id")
  lines.add run(db, "SELECT name FROM t WHERE name LIKE 'b%'")
  lines.add run(db, "SELECT CASE WHEN score >= 75 THEN 'hi' ELSE 'lo' END FROM t ORDER BY id")
  lines.add run(db, "UPDATE t SET score = score + 5 WHERE tag = 'a'")
  lines.add run(db, "SELECT name, score FROM t ORDER BY id")
  lines.add run(db, "DELETE FROM t WHERE score < 70")
  lines.add run(db, "SELECT COUNT(*) FROM t")
  lines.add run(db, "INSERT INTO t (name) VALUES ('dup')")
  lines.add run(db, "SELECT name FROM t WHERE id IN (SELECT id FROM t WHERE tag = 'a') ORDER BY name")
  lines.add run(db, "SELECT 1/0, abs(-3), round(2.567, 2), typeof(1), typeof('x'), length('abcd')")
  lines.add run(db, "SELECT x FROM nope")
  lines.add run(db, "SELECT * FROM t LIMIT 1")
  # transactions
  lines.add run(db, "BEGIN")
  lines.add run(db, "INSERT INTO t (name, score) VALUES ('tmp', 1)")
  lines.add run(db, "ROLLBACK")
  lines.add run(db, "SELECT COUNT(*) FROM t")

  echo "===== foccil-db portability digest ====="
  for i, line in lines:
    echo i, " ", line
  echo "===== end ====="

main()
