#!/usr/bin/env python3
"""Runs the same corpus through the real SQLite and prints the same lines.

Kept deliberately dumb: no clever normalisation, because every clever rule on
this side is a place where the comparison could quietly stop being a comparison.
"""
import sqlite3, sys, os

d = sys.argv[1] if len(sys.argv) > 1 else "tools/db/difftest"
con = sqlite3.connect(":memory:")
con.executescript(open(os.path.join(d, "setup.sql")).read())

def render(v):
    if v is None: return "NULL"
    if isinstance(v, float):
        if v == int(v): return str(int(v))
        return ("%.6f" % v).rstrip("0").rstrip(".")
    if isinstance(v, bytes): return "blob:%d" % len(v)
    return str(v)

i = 0
for raw in open(os.path.join(d, "queries.sql")):
    q = raw.strip()
    if not q: continue
    try:
        cur = con.execute(q)
        rows = ["|".join(render(c) for c in row) for row in cur.fetchall()]
        print("q%d\t%s" % (i, "||".join(rows)))
    except sqlite3.Error:
        print("q%d\tERROR" % i)
    i += 1
