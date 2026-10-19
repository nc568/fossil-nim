## The database *file*: one B+tree, one WAL, one schema text.
##
## Layout, in one place because a storage format that is described in three
## places is a format that disagrees with itself:
##
##   page 0        header (magic, page count, root, freelist) — see pager.nim
##   root page     the single B+tree
##   keys          tableId (4 bytes BE) ‖ rowid (8 bytes, sign-flipped)
##   tid 0         reserved for metadata, so no table can collide with it
##   meta tag 1    the schema, as text: one `TABLE <tid> <nextRowid> <name>` line
##                 per table followed by its CREATE statements, then indexes
##                 and views
##   everything else = rows, encoded by rowstore.nim
##
## Why one tree and not one tree per table: the pager header has room for one
## root, and a second level of indirection (a tree of roots) buys nothing at
## this size but costs a page read on every open and a whole class of "the
## directory and the tree disagree" bugs. A 4-byte prefix is enough to separate
## tables and gives a table scan for free, because B+tree keys are ordered.
##
## Why the schema is text and not a binary struct: text can be read by a human,
## diffed, and — more importantly — reloaded by running the same DDL the user
## ran. The catalog is then built by exactly one code path (the DDL executor),
## instead of by that path plus a decoder that must agree with it forever.

import std/[tables, strutils]
import ./errors, ./vfs, ./pager, ./btree, ./store, ./rowstore, ./schema, ./values, ./ast

const
  MetaTid* = 0'u32
  MetaSchemaTag = 1'i64
  SchemaMagic = "foccil-schema 1"

type
  DbFile* = ref object
    s*: Store
    tree*: Btree
    path*: string
    dbPath*, walPath*: string
    catalogText*: string

proc metaKey(tag: int64): string = rowKey(MetaTid, tag)

proc catalogText*(cat: Catalog): string   # forward: used by commitFile below

proc openDbFileOn*(dbVfs, walVfs: Vfs; path = ":vfs:";
                    cachePages = DefaultCachePages): DbFile =
  ## The file, over a pair of already-open VFS handles. Exists so the crash
  ## fuzzer can run the *engine*, not just the B+tree: an in-memory VFS can be
  ## cut at an arbitrary byte offset and reopened from exactly what survived,
  ## which is impossible to do deterministically on a real filesystem.
  result = DbFile(path: path, dbPath: path, walPath: path & "-wal")
  result.s = openStore(dbVfs, walVfs, cachePages)
  result.tree = openBtree(result.s.p)
  let (found, text) = result.tree.get(metaKey(MetaSchemaTag))
  result.catalogText = if found: text else: ""

proc openDbFile*(path: string; cachePages = DefaultCachePages): DbFile =
  ## Opens (or creates) `<path>` plus its `<path>-wal` log, and replays the log.
  ## The database itself is not opened read-write by two processes; that is a
  ## deliberate limitation of v0.1 and it is documented in storage.md.
  openDbFileOn(openFileVfs(path), openFileVfs(path & "-wal"), path, cachePages)

proc flushMeta*(f: DbFile) =
  if f.catalogText.len == 0: return
  f.tree.put(metaKey(MetaSchemaTag), f.catalogText)

proc closeDbFile*(f: DbFile) =
  f.s.close()

proc ensurePersistable(cat: Catalog) =
  if cat.views.len > 0:
    fail(unsupported, "views cannot be saved to a file yet: the catalog stores " &
         "a parsed query, not its text, and there is no stable AST serialisation. " &
         "Drop the view or use an in-memory database.")

proc commitFile*(f: DbFile; cat: Catalog) =
  ## Called once per committed transaction: rows first, then the schema, then
  ## one WAL commit. Order matters — the schema text mentions table ids, and a
  ## crash between the two writes must not leave a table whose rows exist but
  ## whose description does not. It cannot, because both go into the *same*
  ## commit; the ordering is only about which pages the tree touches first.
  ensurePersistable(cat)
  for _, t in cat.tables:
    if t.rs != nil: t.rs.flush()
  f.catalogText = catalogText(cat)
  f.flushMeta()
  f.s.commit()

proc allocTid*(f: DbFile; cat: Catalog): uint32 =
  var mx = MetaTid
  for _, t in cat.tables:
    if t.tid > mx: mx = t.tid
  mx + 1

# ---------------------------------------------------------------------------
# Schema text
# ---------------------------------------------------------------------------

func quoteIdent(s: string): string =
  "\"" & s.replace("\"", "\"\"") & "\""


func ddlFor(t: TableDef): string =
  ## Rebuilds a CREATE TABLE from the *model*, not from the original text.
  ## SQLite stores the statement the user typed; we store what it produced. The
  ## difference is deliberate: a stored statement can drift from the schema the
  ## engine actually built (older SQLite releases did exactly that with
  ## ALTER TABLE), and then the catalog is a comment rather than a record.
  result = "CREATE TABLE " & quoteIdent(t.name) & " ("
  var parts: seq[string] = @[]
  for c in t.cols:
    var p = quoteIdent(c.name)
    if c.typeName.len > 0: p.add " " & c.typeName
    if c.notNull: p.add " NOT NULL"
    if c.hasDefault: p.add " DEFAULT " & litSql(c.defaultVal)
    if c.coll == colNocase: p.add " COLLATE NOCASE"
    # Column-level CHECK lives on the column, not in `tableChecks`, so it has to
    # be printed here or the reloaded table accepts rows the original refused.
    if c.checkExpr != nil: p.add " CHECK (" & toSql(c.checkExpr) & ")"
    # REFERENCES is recorded and reported (`PRAGMA foreign_key_list`) but not
    # enforced by this engine; it is printed so the catalog keeps saying what
    # the user wrote. See docs/db/*/divergences.md.
    if c.refTable.len > 0:
      p.add " REFERENCES " & quoteIdent(c.refTable)
      if c.refCol.len > 0: p.add "(" & quoteIdent(c.refCol) & ")"
    parts.add p
  if t.pkCols.len > 0:
    var pk = "PRIMARY KEY ("
    for i, c in t.pkCols:
      if i > 0: pk.add ", "
      pk.add quoteIdent(t.cols[c].name)
    parts.add pk & ")"
  # CHECK constraints are part of the schema, so they are part of the stored
  # schema. Leaving them out would reload a table that accepts rows the user
  # forbade — data integrity lost silently, discovered much later.
  for chk in t.tableChecks:
    parts.add "CHECK (" & toSql(chk.expr) & ")"
  result.add parts.join(", ") & ")"
  if t.strict: result.add " STRICT"

proc catalogText*(cat: Catalog): string =
  result = SchemaMagic & "\n"
  for name in cat.order:
    let t = cat.findTable(name)
    if t == nil or t.isView: continue
    result.add "TABLE " & $t.tid & " " & $t.nextRowid & " " & t.name & "\n"
    result.add ddlFor(t) & ";\n"
    for ix in t.indexes:
      if ix.isPkIndex: continue
      result.add "CREATE "
      if ix.unique: result.add "UNIQUE "
      result.add "INDEX " & quoteIdent(ix.name) & " ON " & quoteIdent(t.name) & " ("
      for i, c in ix.cols:
        if i > 0: result.add ", "
        result.add quoteIdent(t.cols[c].name)
      result.add ")"
      if ix.partial != nil: result.add " WHERE " & toSql(ix.partial)
      result.add ";\n"
  # Views are deliberately absent: the catalog keeps a parsed SELECT, not the
  # text the user typed, and re-printing a parsed statement is exactly the
  # "stored statement drifts from schema" problem this design avoids. Storing
  # the AST would work, but it needs a stable serialisation of every expression
  # node — a format decision that deserves its own issue rather than a rushed
  # half of one. `commitFile` refuses to write a catalog that has views, so the
  # limitation is loud instead of silent.

# ---------------------------------------------------------------------------
# Parsing the text back
# ---------------------------------------------------------------------------

func toIntOr0(s: string): int64 =
  ## `parseInt` raises; a schema line that does not parse must not take the
  ## process down while merely opening a database. A zero id is then rejected
  ## by the caller, which knows what a valid id is.
  try: int64(parseInt(s)) except ValueError: 0'i64

type
  SchemaLine* = object
    stmt*: string
    tid*: uint32
    nextRowid*: int64
    tableName*: string

proc schemaStatements*(text: string): seq[SchemaLine] =
  ## Splits the stored schema into executable statements, remembering the table
  ## id that belongs to each CREATE TABLE. `;` inside string literals is not
  ## special-cased because the writer above never emits one outside a literal it
  ## has quoted itself — and a mismatch here surfaces immediately, as an empty
  ## table list, which the tests would catch rather than a user.
  var pendingTid: uint32 = 0
  var pendingNext: int64 = 0
  var pendingName = ""
  var buf = ""
  for raw in text.splitLines():
    let line = raw.strip()
    if line.len == 0 or line.startsWith("--"): continue
    if line.startsWith(SchemaMagic): continue
    if line.startsWith("TABLE "):
      let parts = line.splitWhitespace()
      if parts.len >= 4:
        pendingTid = uint32(toIntOr0(parts[1]))
        pendingNext = toIntOr0(parts[2])
        pendingName = parts[3 .. ^1].join(" ")
      continue
    buf.add line
    if line.endsWith(";"):
      result.add SchemaLine(stmt: buf, tid: pendingTid, nextRowid: pendingNext,
                            tableName: pendingName)
      buf = ""
      pendingTid = 0
      pendingNext = 0
      pendingName = ""
  if buf.strip().len > 0:
    result.add SchemaLine(stmt: buf, tid: pendingTid, nextRowid: pendingNext,
                          tableName: pendingName)
