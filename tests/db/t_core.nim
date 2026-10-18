## Core behaviour test-suite.
##
## Every test is written against the public API only — no reaching into engine
## internals — so these tests survive a storage-backend swap.

import std/[unittest, strutils]
import fossil/db/api

proc q(db: Db; sql: string; params: Params = @[]): seq[Row] =
  db.execute(sql, params).rows

proc q1(db: Db; sql: string; params: Params = @[]): Value =
  let rs = db.execute(sql, params)
  if rs.rows.len == 0 or rs.rows[0].len == 0: return nullValue()
  rs.rows[0][0]

suite "values and typing":
  test "literal round trip":
    let db = openMemory()
    check q1(db, "SELECT 1").asInt == 1
    check q1(db, "SELECT 1.5").asFloat == 1.5
    check q1(db, "SELECT 'abc'").toText == "abc"
    check q1(db, "SELECT NULL").kind == vkNull
    check q1(db, "SELECT 0x10").asInt == 16
    check q1(db, "SELECT TRUE").truthy == true
    check q1(db, "SELECT 1_000").asInt == 1000

  test "arithmetic promotion":
    let db = openMemory()
    check q1(db, "SELECT 2 + 3").asInt == 5
    check q1(db, "SELECT 7 / 2").asInt == 3        # int/int stays int
    check q1(db, "SELECT 7.0 / 2").asFloat == 3.5
    check q1(db, "SELECT 1 / 0").kind == vkNull    # division by zero -> NULL
    check q1(db, "SELECT 'a' || 'b'").toText == "ab"
    check q1(db, "SELECT 'x' || NULL").kind == vkNull

  test "three-valued logic":
    let db = openMemory()
    check q1(db, "SELECT NULL = NULL").kind == vkNull
    check q1(db, "SELECT NULL IS NULL").truthy
    check q1(db, "SELECT NULL IS NOT NULL").truthy == false
    check q1(db, "SELECT NOT NULL").kind == vkNull

  test "functions":
    let db = openMemory()
    check q1(db, "SELECT upper('abc')").toText == "ABC"
    check q1(db, "SELECT substr('abcdef', 2, 3)").toText == "bcd"
    check q1(db, "SELECT length('héllo')").asInt == 6   # bytes, documented
    check q1(db, "SELECT coalesce(NULL, NULL, 5)").asInt == 5
    check q1(db, "SELECT typeof(1.0)").toText == "real"
    check q1(db, "SELECT hex('AB')").toText == "4142"
    check q1(db, "SELECT abs(-7)").asInt == 7
    check q1(db, "SELECT round(3.14159, 2)").asFloat == 3.14

suite "DDL and DML":
  setup:
    discard

  test "create, insert, select":
    let db = openMemory()
    discard db.execute("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL, age INTEGER)")
    discard db.execute("INSERT INTO users (name, age) VALUES (?, ?)", toParams([textValue("ann"), intValue(30)]))
    discard db.execute("INSERT INTO users (name, age) VALUES (?, ?)", toParams([textValue("bob"), intValue(25)]))
    let rows = q(db, "SELECT id, name, age FROM users ORDER BY id")
    check rows.len == 2
    check rows[0][1].toText == "ann"
    check rows[0][0].asInt == 1
    check db.changes == 0   # SELECT resets changes

  test "multi-row insert and defaults":
    let db = openMemory()
    discard db.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, v TEXT DEFAULT 'd', n INT DEFAULT 0)")
    discard db.execute("INSERT INTO t (id) VALUES (1), (2)")
    check q(db, "SELECT v FROM t WHERE id = 2")[0][0].toText == "d"
    check q(db, "SELECT COUNT(*) FROM t")[0][0].asInt == 2

  test "not null, unique and check constraints":
    let db = openMemory()
    discard db.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, email TEXT UNIQUE, n INT CHECK (n >= 0))")
    discard db.execute("INSERT INTO t (email, n) VALUES ('a@b', 1)")
    expect DbError:
      discard db.execute("INSERT INTO t (email, n) VALUES ('a@b', 2)")
    expect DbError:
      discard db.execute("INSERT INTO t (email, n) VALUES ('c@d', -1)")
    discard db.execute("CREATE TABLE u (x INT NOT NULL)")
    expect DbError:
      discard db.execute("INSERT INTO u (x) VALUES (NULL)")

  test "strict typing rejects lossy stores":
    let db = openMemory()
    discard db.execute("CREATE TABLE t (n INTEGER)")
    expect DbError:
      discard db.execute("INSERT INTO t (n) VALUES ('not a number')")
    discard db.execute("INSERT INTO t (n) VALUES ('42')")
    check q(db, "SELECT n FROM t")[0][0].kind == vkInt

  test "update and delete with returning":
    let db = openMemory()
    discard db.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, v INT)")
    discard db.execute("INSERT INTO t (v) VALUES (1), (2), (3)")
    let upd = db.execute("UPDATE t SET v = v * 10 WHERE v >= 2 RETURNING id, v")
    check upd.rows.len == 2
    check upd.rows[0][1].asInt == 20
    check db.changes == 2
    let del = db.execute("DELETE FROM t WHERE v = 20 RETURNING id")
    check del.rows.len == 1
    check del.rows[0][0].asInt == 2
    check q(db, "SELECT COUNT(*) FROM t")[0][0].asInt == 2

  test "alter table":
    let db = openMemory()
    discard db.execute("CREATE TABLE t (a INT)")
    discard db.execute("INSERT INTO t (a) VALUES (1)")
    discard db.execute("ALTER TABLE t ADD COLUMN b TEXT DEFAULT 'x'")
    check q(db, "SELECT b FROM t")[0][0].toText == "x"
    discard db.execute("ALTER TABLE t RENAME TO t2")
    check db.tableExists("t2")
    discard db.execute("ALTER TABLE t2 RENAME COLUMN b TO c")
    check q(db, "SELECT c FROM t2")[0][0].toText == "x"

suite "queries":
  proc seed(): Db =
    result = openMemory()
    discard result.execute("CREATE TABLE emp (id INTEGER PRIMARY KEY, name TEXT, dept TEXT, salary INT)")
    discard result.execute(
      "INSERT INTO emp (name, dept, salary) VALUES " &
      "('ann','eng',100), ('bob','eng',80), ('cid','ops',60), ('dan','ops',60), ('eve','hr',50)")

  test "where / order / limit / offset":
    let db = seed()
    check q(db, "SELECT name FROM emp WHERE salary > 60 ORDER BY salary DESC").len == 2
    check q(db, "SELECT name FROM emp ORDER BY id LIMIT 2 OFFSET 1").len == 2
    check q(db, "SELECT name FROM emp LIMIT 2 OFFSET 1")[0][0].toText == "bob"

  test "group by / having / aggregates":
    let db = seed()
    let rows = q(db, "SELECT dept, COUNT(*) c, SUM(salary) s FROM emp GROUP BY dept ORDER BY dept")
    check rows.len == 3
    check rows[0][0].toText == "eng"
    check rows[0][1].asInt == 2
    check rows[0][2].asInt == 180
    let hv = q(db, "SELECT dept FROM emp GROUP BY dept HAVING COUNT(*) > 1")
    check hv.len == 2
    check q1(db, "SELECT MAX(salary) FROM emp").asInt == 100
    check q1(db, "SELECT AVG(salary) FROM emp").asFloat == 70.0
    check q1(db, "SELECT group_concat(name) FROM emp WHERE dept = 'eng'").toText == "ann,bob"

  test "distinct":
    let db = seed()
    check q(db, "SELECT DISTINCT dept FROM emp").len == 3
    check q(db, "SELECT DISTINCT salary FROM emp ORDER BY salary").len == 4

  test "joins":
    let db = openMemory()
    discard db.execute("CREATE TABLE d (id INT PRIMARY KEY, title TEXT)")
    discard db.execute("CREATE TABLE e (id INT PRIMARY KEY, dept_id INT, name TEXT)")
    discard db.execute("INSERT INTO d VALUES (1, 'eng'), (2, 'ops')")
    discard db.execute("INSERT INTO e VALUES (1, 1, 'ann'), (2, 1, 'bob'), (3, 99, 'zed')")
    check q(db, "SELECT e.name, d.title FROM e JOIN d ON e.dept_id = d.id").len == 2
    let left = q(db, "SELECT e.name, d.title FROM e LEFT JOIN d ON e.dept_id = d.id ORDER BY e.id")
    check left.len == 3
    check left[2][1].kind == vkNull

  test "subqueries and CTEs":
    let db = seed()
    check q(db, "SELECT name FROM emp WHERE dept IN (SELECT dept FROM emp WHERE salary = 100)").len == 2
    check q1(db, "SELECT (SELECT MAX(salary) FROM emp)").asInt == 100
    check q(db, "WITH rich AS (SELECT * FROM emp WHERE salary > 70) SELECT COUNT(*) FROM rich")[0][0].asInt == 2
    check q1(db, "SELECT COUNT(*) FROM emp WHERE EXISTS (SELECT 1 FROM emp e2 WHERE e2.salary > 90)").asInt == 5

  test "case expressions":
    let db = seed()
    let rows = q(db, "SELECT name, CASE WHEN salary >= 80 THEN 'high' ELSE 'low' END FROM emp ORDER BY id")
    check rows[0][1].toText == "high"
    check rows[4][1].toText == "low"

  test "like and between":
    let db = seed()
    check q(db, "SELECT name FROM emp WHERE name LIKE 'a%'").len == 1
    check q(db, "SELECT name FROM emp WHERE name LIKE '_ob'").len == 1
    check q(db, "SELECT name FROM emp WHERE salary BETWEEN 60 AND 80").len == 3

  test "views":
    let db = seed()
    discard db.execute("CREATE VIEW rich AS SELECT name, salary FROM emp WHERE salary >= 80")
    check q(db, "SELECT name FROM rich ORDER BY name").len == 2

  test "compound selects":
    let db = seed()
    check q(db, "SELECT dept FROM emp WHERE salary = 100 UNION SELECT dept FROM emp WHERE salary = 50").len == 2
    check q(db, "SELECT dept FROM emp UNION ALL SELECT dept FROM emp").len == 10

suite "indexes":
  test "index is maintained and used for lookups":
    let db = openMemory()
    discard db.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, k TEXT, v INT)")
    for i in 0 ..< 200:
      discard db.execute("INSERT INTO t (k, v) VALUES (?, ?)",
                         toParams([textValue("k" & $i), intValue(i)]))
    discard db.execute("CREATE INDEX idx_k ON t (k)")
    check q(db, "SELECT v FROM t WHERE k = 'k150'")[0][0].asInt == 150
    discard db.execute("UPDATE t SET k = 'moved' WHERE v = 150")
    check q(db, "SELECT v FROM t WHERE k = 'moved'")[0][0].asInt == 150
    check q(db, "SELECT COUNT(*) FROM t WHERE k = 'k150'")[0][0].asInt == 0

  test "unique index rejects duplicates":
    let db = openMemory()
    discard db.execute("CREATE TABLE t (a INT, b INT)")
    discard db.execute("INSERT INTO t VALUES (1, 2)")
    discard db.execute("CREATE UNIQUE INDEX ux ON t (a, b)")
    expect DbError:
      discard db.execute("INSERT INTO t VALUES (1, 2)")

  test "explain reports index usage when the planner picks one":
    let db = openMemory()
    discard db.execute("CREATE TABLE t (a INT, b TEXT)")
    discard db.execute("CREATE INDEX ix_a ON t (a)")
    let rs = db.execute("EXPLAIN SELECT b FROM t WHERE a = 7")
    check rs.rows[0][1].toText.contains("USING INDEX ix_a")

  test "explain reports the scan":
    let db = openMemory()
    discard db.execute("CREATE TABLE t (a INT)")
    let rs = db.execute("EXPLAIN SELECT * FROM t")
    check rs.rows.len > 0
    check rs.rows[0][1].toText.contains("SCAN")

suite "transactions":
  test "rollback restores data":
    let db = openMemory()
    discard db.execute("CREATE TABLE t (a INT)")
    discard db.execute("INSERT INTO t VALUES (1)")
    discard db.execute("BEGIN")
    discard db.execute("INSERT INTO t VALUES (2)")
    discard db.execute("UPDATE t SET a = 99 WHERE a = 1")
    check q(db, "SELECT COUNT(*) FROM t")[0][0].asInt == 2
    discard db.execute("ROLLBACK")
    check q(db, "SELECT COUNT(*) FROM t")[0][0].asInt == 1
    check q(db, "SELECT a FROM t")[0][0].asInt == 1

  test "commit keeps data":
    let db = openMemory()
    discard db.execute("CREATE TABLE t (a INT)")
    discard db.execute("BEGIN")
    discard db.execute("INSERT INTO t VALUES (1)")
    discard db.execute("COMMIT")
    check q(db, "SELECT COUNT(*) FROM t")[0][0].asInt == 1

  test "rollback also undoes structural changes":
    let db = openMemory()
    discard db.execute("CREATE TABLE keep (a INT)")
    discard db.execute("BEGIN")
    discard db.execute("CREATE TABLE gone (a INT)")
    discard db.execute("INSERT INTO keep VALUES (5)")
    discard db.execute("ROLLBACK")
    check not db.tableExists("gone")
    check q(db, "SELECT COUNT(*) FROM keep")[0][0].asInt == 0
