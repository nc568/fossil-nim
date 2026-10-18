## Foccil DB — quick start / быстрый старт
##
## Run / запуск:
##   nim c -r --path:src examples/db_quickstart.nim
##
## The engine lives in `src/fossil/db/` and is imported as `fossil/db/api`.
## It is pure Nim, ARC, no GC, no C dependencies — the same source compiles
## to native C, to plain JavaScript and to WebAssembly.

import fossil/db/api

# 1. In-memory database. Persistence arrives with the VFS/pager milestone.
let db = openMemory()

# 2. Schema. Strict typing is the default: a lossy conversion is an error,
#    not a silent coercion.
discard db.execute("""
  CREATE TABLE ticket (
    id     INTEGER PRIMARY KEY,
    title  TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'open'
  )
""")

# 3. Data always travels as parameters. There is no string concatenation path
#    and no way to smuggle SQL through a value.
for (title, status) in [("first ticket", "open"), ("second ticket", "closed")]:
  discard db.execute(
    "INSERT INTO ticket (title, status) VALUES (?, ?)",
    toParams([textValue(title), textValue(status)]))

# 4. Read it back.
let rs = db.execute("SELECT id, title FROM ticket WHERE status = ? ORDER BY id",
                    toParams([textValue("open")]))
for row in rs.rows:
  echo row.asInt(0), ". ", row.asText(1)

# 5. The planner tells you what it actually did — no guessing.
for row in db.execute("EXPLAIN SELECT id FROM ticket WHERE id = ?",
                      toParams([intValue(1)])).rows:
  echo "plan: ", row.asText(1)          # columns are (id, detail)

# 6. Capabilities are opt-in: DDL and writes can be revoked per database.
var ro = DefaultOptions
ro.readOnly = true
let readOnlyDb = openDb(ro)
try:
  discard readOnlyDb.execute("CREATE TABLE x (a INTEGER)")
except DbError as e:
  echo "blocked as expected: ", e.code

echo "rows in ticket: ", db.rowCount("ticket"),
     " | engine: ", sqliteVersion()
