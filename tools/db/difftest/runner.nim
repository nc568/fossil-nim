## Runs a corpus through Foccil DB and prints one normalised line per query.
##
## The output format is the contract with the reference runner
## (`reference.py`, which uses the real SQLite through Python's sqlite3): one
## line per query, `q<index>\t<row>||<row>...`, values rendered by the same
## rules on both sides. Anything either side cannot express is printed as
## `q<index>\tERROR ...` so a divergence is visible rather than silent.

import std/[os, strutils]
import fossil/db/api
import fossil/db/values

proc render(v: Value): string =
  case v.kind
  of vkNull: "NULL"
  of vkInt: $v.asInt
  of vkReal:
    let f = v.asFloat
    # One canonical spelling: no trailing zeros, no exponent games for the
    # magnitudes this corpus uses (that is what `formatFloat`'s shortest round
    # trip is not for). Integers stored as floats print as integers, which is
    # what SQLite does too.
    if f == f.int.float: $f.int
    else:
      # Trailing zeros only. Stripping *all* zeros turned 0.5 into "5", which
      # looked like an engine bug for two runs and was not one — a comparison
      # harness that lies is worse than no comparison at all.
      var t = formatFloat(f, ffDecimal, 6)
      while t.len > 1 and t[^1] == '0': t.setLen(t.len - 1)
      if t.len > 1 and t[^1] == '.': t.setLen(t.len - 1)
      t
  of vkText: v.toText
  of vkBlob: "blob:" & $v.bl.len
  of vkBool: (if v.bo: "1" else: "0")

proc main() =
  let dir = if paramCount() >= 1: paramStr(1) else: "tools/db/difftest"
  let db = openMemory()
  discard db.execScript(readFile(dir / "setup.sql"))
  var i = 0
  for raw in readFile(dir / "queries.sql").splitLines:
    let q = raw.strip
    if q.len == 0: continue
    var line = "q" & $i & "\t"
    try:
      let rs = db.execute(q)
      var rows: seq[string]
      for row in rs.rows:
        var cells: seq[string]
        for v in row: cells.add render(v)
        rows.add cells.join("|")
      line.add rows.join("||")
    except DbError:
      # The *fact* of refusal is what is compared, not the wording: SQLite says
      # "no such column: name" and this engine says NOTFOUND, and neither is
      # wrong. Message similarity is not a compatibility property.
      line.add "ERROR"
    echo line
    inc i

main()
