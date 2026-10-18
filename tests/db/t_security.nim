## Security test-suite.
##
## These tests are the contract: Foccil DB must fail *closed* and must never
## turn untrusted SQL into memory unsafety, data leakage or unbounded work.
##
## Categories
##   1. injection (parameterisation is the only data path)
##   2. authorization / capability limits (DDL, read-only)
##   3. resource exhaustion (nesting, row budget, huge LIMIT)
##   4. input robustness (fuzz: only DbError, never crash)
##   5. error hygiene (no row data in messages)
##   6. static anti-unsafe check over the source tree

import std/[unittest, strutils, os, algorithm]
import fossil/db/api

const InjectionPayloads = [
  "'; DROP TABLE users; --",
  "' OR '1'='1",
  "\" OR \"\"=\"",
  "1; DELETE FROM users",
  "name'); DROP TABLE users;--",
  "\x00'; DROP TABLE users; --",
  "\\'; DROP TABLE users; --",
  "%' OR name LIKE '%",
  "_' OR 1=1 --",
  "admin'--",
  "'||(SELECT name FROM users)||'",
  "𝕏'; DROP TABLE users; --",
]

suite "injection resistance":
  setup:
    discard

  test "payloads stored as data, never executed":
    let db = openMemory()
    discard db.execute("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)")
    for pl in InjectionPayloads:
      discard db.execute("INSERT INTO users (name) VALUES (?)", toParams([textValue(pl)]))
    check db.rowCount("users") == InjectionPayloads.len
    check db.tableExists("users")
    # round-trip must be byte-identical (no escaping games)
    let rows = db.execute("SELECT name FROM users ORDER BY id").rows
    for i, pl in InjectionPayloads:
      check rows[i][0].toText == pl

  test "payload as a LIKE pattern does not escape the pattern slot":
    let db = openMemory()
    discard db.execute("CREATE TABLE t (v TEXT)")
    discard db.execute("INSERT INTO t VALUES ('alpha'), ('beta')")
    let rows = db.execute("SELECT v FROM t WHERE v LIKE ?", toParams([textValue("%' OR '1'='1")])).rows
    check rows.len == 0

  test "quoted identifiers are identifiers, not statements":
    let db = openMemory()
    discard db.execute("CREATE TABLE t (a INT)")
    expect DbError:
      discard db.execute("SELECT * FROM \"t; DROP TABLE t\"")
    check db.tableExists("t")

  test "trailing garbage in a statement is rejected, not ignored":
    let db = openMemory()
    discard db.execute("CREATE TABLE t (a INT)")
    expect DbError:
      discard db.execute("INSERT INTO t VALUES (1); DROP TABLE t")

suite "capabilities":
  test "DDL can be disabled":
    let db = openDb(DbOptions(strictTyping: true, allowDdl: false,
                              maxResultRows: 1_000_000, maxParams: 999))
    expect DbError:
      discard db.execute("CREATE TABLE t (a INT)")
    let e = try:
              discard db.execute("CREATE TABLE t (a INT)")
              ""
            except DbError as err: err.code.codeName
    check e == "AUTH"

  test "read-only connections cannot write":
    let db = openDb(DbOptions(strictTyping: true, readOnly: true,
                              allowDdl: true, maxResultRows: 1_000_000,
                              maxParams: 999))
    let setup = openMemory()
    discard setup.execute("CREATE TABLE t (a INT)")
    # simulate a read-only handle over an existing schema
    db.cat = setup.cat
    expect DbError:
      discard db.execute("INSERT INTO t VALUES (1)")
    check setup.rowCount("t") == 0

  test "there is no ATTACH / load_extension surface":
    let db = openMemory()
    for sql in ["ATTACH DATABASE 'x.db' AS x",
                "SELECT load_extension('evil')",
                "VACUUM INTO 'x.db'"]:
      expect DbError:
        discard db.execute(sql)

suite "resource limits":
  test "deep expression nesting is rejected, not a stack overflow":
    let db = openMemory()
    var sql = "SELECT "
    for _ in 0 ..< 500: sql.add '('
    sql.add "1"
    for _ in 0 ..< 500: sql.add ')'
    expect DbError:
      discard db.execute(sql)

  test "row budget stops runaway queries":
    let db = openDb(DbOptions(strictTyping: true, allowDdl: true,
                              maxResultRows: 100, maxParams: 999))
    discard db.execute("CREATE TABLE big (a INT)")
    for i in 0 ..< 500:
      discard db.execute("INSERT INTO big VALUES (?)", toParams([intValue(i)]))
    expect DbError:
      discard db.execute("SELECT * FROM big")

  test "huge LIMIT does not allocate":
    let db = openMemory()
    discard db.execute("CREATE TABLE t (a INT)")
    discard db.execute("INSERT INTO t VALUES (1)")
    let rows = db.execute("SELECT a FROM t LIMIT 9223372036854775807").rows
    check rows.len == 1
    let neg = db.execute("SELECT a FROM t LIMIT -1").rows
    check neg.len == 0

  test "parameter index abuse is a clean error":
    let db = openMemory()
    expect DbError:
      discard db.execute("SELECT ?1")
    expect DbError:
      discard db.execute("SELECT ?, ?", toParams([intValue(1), intValue(2), intValue(3)]))

suite "type safety":
  test "strict mode refuses lossy stores":
    let db = openMemory()
    discard db.execute("CREATE TABLE t (n INTEGER, s TEXT, b BLOB, f REAL)")
    expect DbError:
      discard db.execute("INSERT INTO t (n) VALUES ('abc')")
    expect DbError:
      discard db.execute("INSERT INTO t (s) VALUES (x'00ff')")
    discard db.execute("INSERT INTO t (b) VALUES (x'00ff')")
    check db.rowCount("t") == 1

  test "NULL never compares equal to anything":
    let db = openMemory()
    discard db.execute("CREATE TABLE t (a INT)")
    discard db.execute("INSERT INTO t VALUES (NULL), (1)")
    check db.execute("SELECT COUNT(*) FROM t WHERE a = NULL").rows[0][0].asInt == 0
    check db.execute("SELECT COUNT(*) FROM t WHERE a IS NULL").rows[0][0].asInt == 1

  test "UNIQUE tolerates multiple NULLs but not duplicates":
    let db = openMemory()
    discard db.execute("CREATE TABLE t (a INT UNIQUE)")
    discard db.execute("INSERT INTO t VALUES (NULL), (NULL), (1)")
    expect DbError:
      discard db.execute("INSERT INTO t VALUES (1)")
    check db.rowCount("t") == 3

suite "error hygiene":
  test "errors carry codes and do not embed row data":
    let db = openMemory()
    discard db.execute("CREATE TABLE t (a INT UNIQUE)")
    discard db.execute("INSERT INTO t VALUES (1)")
    var code = ""
    var msg = ""
    try:
      discard db.execute("INSERT INTO t VALUES (1)")
    except DbError as e:
      code = e.code.codeName
      msg = e.msg
    check code == "CONSTRAINT"
    check not msg.contains("a INT")

const FuzzAlphabet = "SELECT FROM WHERE INSERT INTO VALUES ()*?,;'\"`[]-+/*%.<>=|&0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ \t\n"

suite "fuzzing":
  proc rnd(seed: var uint64): uint64 =
    var x = seed
    x = x xor (x shl 13)
    x = x xor (x shr 7)
    x = x xor (x shl 17)
    seed = x
    x

  test "random byte soup never crashes the engine":
    var seed = 0xDEADBEEF'u64
    let db = openMemory()
    discard db.execute("CREATE TABLE f (a INT, b TEXT)")
    var crashes = 0
    var parsed = 0
    for _ in 0 ..< 3000:
      var n = int(rnd(seed) mod 40) + 1
      var s = newString(n)
      for i in 0 ..< n:
        s[i] = FuzzAlphabet[int(rnd(seed) mod uint64(FuzzAlphabet.len))]
      try:
        discard db.execute(s)
        inc parsed
      except DbError:
        discard
      except CatchableError:
        inc crashes
    check crashes == 0

  test "mutated valid statements never crash":
    var seed = 0x1234567'u64
    let db = openMemory()
    discard db.execute("CREATE TABLE m (id INTEGER PRIMARY KEY, v TEXT)")
    discard db.execute("INSERT INTO m (v) VALUES ('x')")
    const base = "SELECT id, count(*) FROM m WHERE v = 'x' GROUP BY id ORDER BY 1 DESC LIMIT 5"
    var crashes = 0
    for _ in 0 ..< 2000:
      var s = base
      let pos = int(rnd(seed) mod uint64(s.len))
      s[pos] = FuzzAlphabet[int(rnd(seed) mod uint64(FuzzAlphabet.len))]
      try:
        discard db.execute(s)
      except DbError:
        discard
      except CatchableError:
        inc crashes
    check crashes == 0

suite "capability model":
  test "read-only connection cannot change the schema":
    ## Regression: readOnly used to guard DML only, so a read-only handle
    ## could still CREATE/DROP/ALTER tables and indexes.
    var ro = DefaultOptions
    ro.readOnly = true
    let db = openDb(ro)
    expect DbError:
      discard db.execute("CREATE TABLE t (a INTEGER)")
    expect DbError:
      discard db.execute("CREATE INDEX i ON t (a)")
    expect DbError:
      discard db.execute("DROP TABLE t")
    expect DbError:
      discard db.execute("ALTER TABLE t RENAME TO u")
    check db.tableNames().len == 0

  test "read-only connection still reads":
    var ro = DefaultOptions
    ro.readOnly = true
    let db = openDb(ro)
    let rs = db.execute("SELECT 1 + 1")
    check rs.rows[0].asInt(0) == 2

suite "static anti-unsafe check":
  test "engine sources contain no unsafe constructs":
    ## The ARC rewrite promise is enforceable: no raw pointers, no casts,
    ## no unchecked array access in the core.
    # Explicit allowlist: the engine modules only. `c_interop.nim` lives in the
    # same directory but is the host's C bridge -- raw pointers are its job, and
    # scanning it would make this test meaningless.
    const engineModules = ["api.nim", "values.nim", "tokenizer.nim", "ast.nim",
                           "parser.nim", "schema.nim", "funcs.nim", "engine.nim",
                           "errors.nim"]
    const forbidden = ["ptr ", "cast[", "unsafeAddr", "addr(", "alloc0",
                       "allocShared", "dealloc", "unsafe", "{.cast.}",
                       "include \"system"]
    var violations: seq[string]
    for m in engineModules:
      let f = "src/fossil/db/" & m
      if not fileExists(f):
        violations.add f & "  MISSING"
        continue
      let text = readFile(f)
      var lineNo = 0
      for line in text.splitLines():
        inc lineNo
        let code = line.split('#')[0]
        if code.strip().len == 0: continue
        # doc comments are allowed to mention the words
        if line.strip().startsWith("##") or line.strip().startsWith("#"): continue
        for pat in forbidden:
          if code.contains(pat):
            violations.add f & ":" & $lineNo & "  " & pat
    check violations.len == 0
    if violations.len > 0:
      echo "violations:\n", violations.join("\n")
