## Smoke test for the cproc/QBE target: build with cproc, link with musl, run.
##
## It touches every layer that is easy to break silently in a freestanding C
## environment: allocation (ARC), string building, the B+tree through the
## table engine, integer arithmetic, float formatting, and a hash table.

import ../../../src/fossil/db/api

proc main() =
  let db = openDb()
  discard db.execScript("""
    create table t(id integer primary key, name text, score real);
    insert into t values (1, 'alpha', 1.5), (2, 'beta', 2.25), (3, 'gamma', 0.5);
  """)
  var seen = 0
  var acc = 0.0
  for row in db.execute("select id, name, score from t order by id").rows:
    echo row[0].toText, " ", row[1].toText, " ", row[2].toText
    acc = acc + row[2].asFloat
    inc seen
  doAssert seen == 3, "expected three rows"
  doAssert acc == 4.25, "float arithmetic: got " & $acc
  let agg = db.execute("select count(*), max(score) from t").rows
  echo "count=", agg[0][0].toText, " max=", agg[0][1].toText
  echo "smoke: ok"

main()
