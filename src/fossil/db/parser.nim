## Recursive-descent SQL parser with precedence climbing.
##
## Design notes
##  * single pass, no intermediate token vector: the tokenizer's lookahead is
##    one token deep, which is all a recursive-descent parser needs;
##  * every construct that Foccil refuses (ATTACH, load_extension, VACUUM INTO,
##    PRAGMA that touches files) fails with `unsupported`/`auth` *here*, at
##    parse time, so nothing reachable from user SQL can touch the filesystem;
##  * statements are immutable after parsing → safe to reuse/share.

import std/strutils
import ./errors, ./values, ./tokenizer, ./ast, ./funcs

type
  Parser* = object
    t*: Tokenizer
    depth*: int              ## recursion guard (DoS protection)
    paramCount*: int

const MaxParseDepth* = 64    ## stops `((((((…` stack exhaustion

# --- forward declarations (mutual recursion without a second module) --------
proc parseExpr(p: var Parser; minPrec = 0): Expr
proc parseSelectStmt(p: var Parser): SelectStmt
proc parseSelectCore(p: var Parser): SelectStmt
proc parseFromItem(p: var Parser): TableSource
proc parseTableSource(p: var Parser; first: var TableSource; joins: var seq[Join])
proc parseStmt(p: var Parser): Stmt

proc err(p: Parser; msg: string) {.noreturn.} =
  raise dbErr(syntax, msg & " (at offset " & $p.t.pos & ")")

proc enter(p: var Parser) =
  inc p.depth
  if p.depth > MaxParseDepth:
    raise dbErr(limit, "statement nesting too deep")

proc leave(p: var Parser) {.inline.} = dec p.depth

# ---------------------------------------------------------------------------
# Token helpers
# ---------------------------------------------------------------------------

func isKw(p: Parser; tok: Token; kw: string): bool = p.t.isKeyword(tok, kw)

proc acceptKw(p: var Parser; kw: string): bool =
  let tk = p.t.peek()
  if p.t.isKeyword(tk, kw):
    discard p.t.advance()
    return true
  false

proc expectKw(p: var Parser; kw: string) =
  if not p.acceptKw(kw): p.err("expected '" & kw & "'")

proc acceptPunct(p: var Parser; s: string): bool =
  let tk = p.t.peek()
  if tk.kind == tkPunct and p.t.slice(tk) == s:
    discard p.t.advance()
    return true
  false

proc expectPunct(p: var Parser; s: string) =
  if not p.acceptPunct(s): p.err("expected '" & s & "'")

proc acceptOp(p: var Parser; s: string): bool =
  let tk = p.t.peek()
  if tk.kind == tkOp and p.t.slice(tk) == s:
    discard p.t.advance()
    return true
  false

proc peekIsKw(p: var Parser; kw: string): bool =
  p.t.isKeyword(p.t.peek(), kw)

proc peekIsPunct(p: var Parser; s: string): bool =
  let tk = p.t.peek()
  tk.kind == tkPunct and p.t.slice(tk) == s

proc peekIsStar(p: var Parser): bool =
  ## `*` is lexed as an operator (it is also multiplication), so the star needs
  ## its own matcher instead of the punctuation helper.
  let tk = p.t.peek()
  tk.kind in {tkPunct, tkOp} and p.t.slice(tk) == "*"

proc acceptStar(p: var Parser): bool =
  if p.peekIsStar():
    discard p.t.advance()
    return true
  false

proc takeIdent(p: var Parser): string =
  let tk = p.t.peek()
  case tk.kind
  of tkIdent:
    discard p.t.advance()
    p.t.slice(tk)
  of tkQuotedIdent:
    discard p.t.advance()
    tk.paramName
  else:
    p.err("expected identifier")

proc peekIsAnyKw(p: var Parser; kws: openArray[string]): bool =
  ## Allocation-free "peek in set of keywords" (replaces sequtils.anyIt,
  ## which captures `p` and defeats the JS backend's inlining).
  let tk = p.t.peek()
  if tk.kind notin {tkIdent, tkQuotedIdent}: return false
  for kw in kws:
    if p.t.isKeyword(tk, kw): return true
  false

proc peekIdentIs(p: var Parser; s: string): bool =
  let tk = p.t.peek()
  (tk.kind == tkIdent and p.t.isKeyword(tk, s))

# ---------------------------------------------------------------------------
# Expressions
# ---------------------------------------------------------------------------

const
  # precedence, higher binds tighter
  PrecOr = 1
  PrecAnd = 2
  PrecNot = 3
  PrecCompare = 4
  PrecBit = 5
  PrecAdd = 6
  PrecMul = 7
  PrecConcat = 8
  PrecUnary = 9
  PrecCollate = 10

proc binPrec(op: string): int =
  case op
  of "or": PrecOr
  of "and": PrecAnd
  of "=", "==", "!=", "<>", "<", "<=", ">", ">=", "is": PrecCompare
  of "&", "|", "<<", ">>": PrecBit
  of "+", "-": PrecAdd
  of "*", "/", "%": PrecMul
  of "||": PrecConcat
  else: 0

proc parseCase(p: var Parser): Expr =
  result = newExpr(exCase)
  result.pIdx = -1
  if not p.peekIsKw("WHEN"):
    result.args.add p.parseExpr(PrecOr)
  while p.acceptKw("WHEN"):
    let w = p.parseExpr(PrecOr)
    p.expectKw("THEN")
    let th = p.parseExpr(PrecOr)
    result.pairs.add (w, th)
  if p.acceptKw("ELSE"):
    result.e1 = p.parseExpr(PrecOr)
  p.expectKw("END")
  if result.pairs.len == 0: p.err("CASE without WHEN")

proc parseTypeName(p: var Parser): string =
  ## `INTEGER`, `VARCHAR(40)`, `DECIMAL(10,2)`, `NUMERIC`, `TEXT`, `BOOL`…
  var parts: seq[string]
  if p.peekIsKw("UNSIGNED"): discard p.t.advance()
  parts.add p.takeIdent()
  while true:
    if p.peekIsPunct("("):
      discard p.t.advance()
      var dims: seq[string]
      while true:
        let tk = p.t.peek()
        if tk.kind != tkNumber: p.err("expected type size")
        discard p.t.advance()
        dims.add p.t.slice(tk)
        if p.acceptPunct(","): continue
        break
      p.expectPunct(")")
      parts.add "(" & dims.join(",") & ")"
      break
    elif p.peekIdentIs("CHARACTER") or p.peekIdentIs("VARYING") or
         p.peekIdentIs("PRECISION") or p.peekIdentIs("UNSIGNED"):
      parts.add p.takeIdent()
    else:
      break
  parts.join(" ")

proc parsePrimary(p: var Parser): Expr =
  p.enter()
  defer: p.leave()
  let tk = p.t.peek()
  case tk.kind
  of tkNumber:
    discard p.t.advance()
    result = lit(tk.num)
  of tkString:
    discard p.t.advance()
    result = lit(tk.num)
  of tkBlob:
    discard p.t.advance()
    result = lit(tk.num)
  of tkParam:
    discard p.t.advance()
    inc p.paramCount
    result = newExpr(exParam)
    if tk.paramIdx == -2:
      result.pName = tk.paramName
      result.pIdx = 0
    else:
      result.pIdx = if tk.paramIdx > 0: tk.paramIdx else: p.paramCount
  of tkPunct:
    let s = p.t.slice(tk)
    if s == "(":
      discard p.t.advance()
      if p.peekIsKw("SELECT") or p.peekIsKw("WITH") or p.peekIsKw("VALUES"):
        let sub = p.parseSelectStmt()
        p.expectPunct(")")
        result = newExpr(exScalarSub)
        result.sub = sub
        return
      var first = p.parseExpr(PrecOr)
      if p.acceptPunct(","):
        var items = @[first]
        while true:
          items.add p.parseExpr(PrecOr)
          if not p.acceptPunct(","): break
        p.expectPunct(")")
        result = newExpr(exTuple)
        result.args = items
        return
      p.expectPunct(")")
      result = first
    elif s == "*":
      discard p.t.advance()
      result = newExpr(exStar)
    else:
      p.err("unexpected '" & s & "'")
  of tkIdent, tkQuotedIdent:
    let isQuoted = tk.kind == tkQuotedIdent
    if not isQuoted:
      # keyword-led primary expressions
      if p.acceptKw("CASE"):
        return p.parseCase()
      if p.acceptKw("CAST"):
        p.expectPunct("(")
        let e = p.parseExpr(PrecOr)
        p.expectKw("AS")
        let tn = p.parseTypeName()
        p.expectPunct(")")
        result = newExpr(exCast)
        result.args = @[e]
        result.typeName = tn
        return
      if p.acceptKw("NOT"):
        if p.acceptKw("EXISTS"):
          p.expectPunct("(")
          let sub = p.parseSelectStmt()
          p.expectPunct(")")
          result = newExpr(exExists)
          result.sub = sub
          result.negated = true
          return
        let a = p.parseExpr(PrecUnary)
        return unop("not", a)
      if p.acceptKw("EXISTS"):
        p.expectPunct("(")
        let sub = p.parseSelectStmt()
        p.expectPunct(")")
        result = newExpr(exExists)
        result.sub = sub
        return
      if p.acceptKw("NULL"):
        return lit(nullValue())
      if p.acceptKw("TRUE"):
        return lit(boolValue(true))
      if p.acceptKw("FALSE"):
        return lit(boolValue(false))
      if p.acceptKw("CURRENT_TIMESTAMP"):
        return call("now", @[])
      if p.acceptKw("CURRENT_DATE"):
        return call("date_now", @[])
      if p.acceptKw("CURRENT_TIME"):
        return call("time_now", @[])
    var name = p.takeIdent()
    var tbl = ""
    if p.peekIsPunct("."):
      discard p.t.advance()
      if p.peekIsStar():
        discard p.t.advance()
        result = newExpr(exStar)
        result.tbl = name
        return
      tbl = name
      name = p.takeIdent()
    if p.peekIsPunct("("):
      discard p.t.advance()
      result = newExpr(exCall)
      result.name = name.toLowerAscii()
      if p.acceptKw("DISTINCT"):
        result.isDistinctArg = true
      if p.acceptStar():
        result.star = true
        p.expectPunct(")")
        if not findFunc(result.name)[0]:
          p.err("no such function: " & result.name)
        return
      if not p.peekIsPunct(")"):
        while true:
          result.args.add p.parseExpr(PrecOr)
          if not p.acceptPunct(","): break
        if result.isDistinctArg:
          # DISTINCT(a, b) prefix form is also accepted
          discard
      p.expectPunct(")")
      # Unknown functions are rejected at *prepare* time. Deferring them to
      # execution would let a misspelled security-relevant call (e.g.
      # `load_extension`) resolve to NULL and silently do nothing.
      if not findFunc(result.name)[0]:
        p.err("no such function: " & result.name)
      return
    result = colRef(tbl, name)
  else:
    p.err("unexpected end of statement")

proc parsePostfix(p: var Parser; base: Expr): Expr =
  var e = base
  while true:
    if p.peekIsKw("COLLATE"):
      let tk = p.t.advance()
      let nm = p.takeIdent().toLowerAscii()
      var c = newExpr(exCollate)
      c.args = @[e]
      c.name = nm
      e = c
    elif p.peekIsKw("ISNULL"):
      discard p.t.advance()
      e = Expr(kind: exIsNull, args: @[e], pIdx: -1)
    elif p.peekIsKw("NOTNULL"):
      discard p.t.advance()
      e = Expr(kind: exIsNull, args: @[e], negated: true, pIdx: -1)
    elif p.peekIsKw("IS"):
      discard p.t.advance()
      let neg = p.acceptKw("NOT")
      if p.acceptKw("NULL"):
        e = Expr(kind: exIsNull, args: @[e], negated: neg, pIdx: -1)
      elif p.acceptKw("DISTINCT"):
        p.expectKw("FROM")
        let r = p.parseExpr(PrecCompare + 1)
        e = Expr(kind: exBinary, op: (if neg: "isnotdistinct" else: "isdistinct"),
                 args: @[e, r], pIdx: -1)
      else:
        let r = p.parseExpr(PrecCompare + 1)
        e = Expr(kind: exBinary, op: (if neg: "isnot" else: "is"),
                 args: @[e, r], pIdx: -1)
    elif p.peekIsKw("NOT") or p.peekIsKw("IN") or p.peekIsKw("LIKE") or
         p.peekIsKw("GLOB") or p.peekIsKw("BETWEEN"):
      let save = p.t.pos
      let savePeek = p.t.peeked
      let saveTok = p.t.peekTok
      var neg = false
      if p.acceptKw("NOT"): neg = true
      if p.acceptKw("IN"):
        p.expectPunct("(")
        if p.peekIsKw("SELECT") or p.peekIsKw("WITH"):
          let sub = p.parseSelectStmt()
          p.expectPunct(")")
          e = Expr(kind: exIn, args: @[e], sub: sub, negated: neg, pIdx: -1)
        else:
          var items: seq[Expr]
          if not p.peekIsPunct(")"):
            while true:
              items.add p.parseExpr(PrecOr)
              if not p.acceptPunct(","): break
          p.expectPunct(")")
          e = Expr(kind: exIn, args: @[e] & items, negated: neg, pIdx: -1)
      elif p.acceptKw("BETWEEN"):
        let lo = p.parseExpr(PrecCompare + 1)
        p.expectKw("AND")
        let hi = p.parseExpr(PrecCompare + 1)
        e = Expr(kind: exBetween, args: @[e, lo, hi], negated: neg, pIdx: -1)
      elif p.acceptKw("LIKE"):
        let pat = p.parseExpr(PrecCompare + 1)
        var esc: Expr = nil
        if p.acceptKw("ESCAPE"):
          esc = p.parseExpr(PrecCompare + 1)
        e = Expr(kind: exLike, op: "like",
                 args: (if esc == nil: @[e, pat] else: @[e, pat, esc]),
                 negated: neg, pIdx: -1)
      elif p.acceptKw("GLOB"):
        let pat = p.parseExpr(PrecCompare + 1)
        e = Expr(kind: exLike, op: "glob", args: @[e, pat], negated: neg, pIdx: -1)
      else:
        # not an infix operator form: rewind
        p.t.pos = save
        p.t.peeked = savePeek
        p.t.peekTok = saveTok
        break
    else:
      break
  e

proc parseUnary(p: var Parser): Expr =
  p.enter()
  defer: p.leave()
  let tk = p.t.peek()
  if tk.kind == tkOp:
    let s = p.t.slice(tk)
    if s in ["-", "+", "~"]:
      discard p.t.advance()
      let a = p.parseUnary()
      if s == "+": return a
      return unop(s, a)
  if tk.kind == tkIdent and p.t.isKeyword(tk, "NOT"):
    discard p.t.advance()
    return unop("not", p.parseUnary())
  p.parsePostfix(p.parsePrimary())

proc parseExpr(p: var Parser; minPrec = 0): Expr =
  var left = p.parseUnary()
  while true:
    let tk = p.t.peek()
    var op = ""
    var prec = 0
    if tk.kind == tkOp:
      op = p.t.slice(tk)
      if op == "!": break
      prec = binPrec(op)
    elif tk.kind == tkIdent:
      for kw in ["OR", "AND"]:
        if p.t.isKeyword(tk, kw):
          op = kw.toLowerAscii()
          prec = binPrec(op)
          break
    if prec == 0 or prec <= minPrec: break
    discard p.t.advance()
    let right = p.parseExpr(prec)
    left = binop(op, left, right)
  left

# ---------------------------------------------------------------------------
# SELECT
# ---------------------------------------------------------------------------

proc parseFromItem(p: var Parser): TableSource =
  if p.peekIsPunct("("):
    discard p.t.advance()
    if p.peekIsKw("SELECT") or p.peekIsKw("WITH"):
      let sub = p.parseSelectStmt()
      p.expectPunct(")")
      result = TableSource(sub: sub)
    else:
      # parenthesised join
      let inner = p.parseFromItem()
      p.expectPunct(")")
      result = inner
  else:
    result = TableSource(name: p.takeIdent())
    if p.peekIsPunct("."):
      discard p.t.advance()
      result.name = result.name & "." & p.takeIdent()
  if p.acceptKw("AS"):
    result.alias = p.takeIdent()
  else:
    let tk = p.t.peek()
    const reserved = ["WHERE","GROUP","ORDER","LIMIT","JOIN","INNER","LEFT",
      "CROSS","ON","USING","HAVING","UNION","EXCEPT","INTERSECT","OFFSET","AS"]
    if tk.kind in {tkIdent, tkQuotedIdent} and
       not (tk.kind == tkIdent and p.peekIsAnyKw(reserved)):
      result.alias = p.takeIdent()

proc parseTableSource(p: var Parser; first: var TableSource;
                      joins: var seq[Join]) =
  ## Left-deep join chain: `a JOIN b ON .. JOIN c ON ..` becomes
  ## first=a, joins=[b, c]. Flat representation => executor is a simple loop,
  ## not a recursive tree walk.
  first = p.parseFromItem()
  while true:
    var kind = jkInner
    if p.acceptKw("JOIN"):
      kind = jkInner
    elif p.acceptKw("INNER"):
      p.expectKw("JOIN")
    elif p.acceptKw("CROSS"):
      p.expectKw("JOIN")
      kind = jkCross
    elif p.acceptKw("LEFT"):
      discard p.acceptKw("OUTER")
      p.expectKw("JOIN")
      kind = jkLeft
    elif p.acceptKw("RIGHT") or p.acceptKw("FULL"):
      p.err("RIGHT/FULL JOIN is not supported; rewrite with a LEFT JOIN")
    elif p.peekIsPunct(","):
      discard p.t.advance()
      kind = jkCross
    else:
      break
    var j: Join
    j.kind = kind
    j.table = p.parseFromItem()
    if p.acceptKw("ON"):
      j.on = p.parseExpr(PrecOr)
    elif p.acceptKw("USING"):
      p.expectPunct("(")
      while true:
        j.usingCols.add p.takeIdent()
        if not p.acceptPunct(","): break
      p.expectPunct(")")
    joins.add j

proc parseOrderBy(p: var Parser; terms: var seq[OrderTerm]) =
  p.expectKw("ORDER")
  p.expectKw("BY")
  while true:
    var t: OrderTerm
    t.expr = p.parseExpr(PrecOr)
    if p.acceptKw("DESC"): t.desc = true
    else: discard p.acceptKw("ASC")
    t.nullsFirst = -1
    if p.acceptKw("NULLS"):
      if p.acceptKw("FIRST"): t.nullsFirst = 1
      else:
        p.expectKw("LAST")
        t.nullsFirst = 0
    if p.acceptKw("COLLATE"):
      let c = p.takeIdent().toLowerAscii()
      t.coll = if c == "nocase": colNocase else: colBinary
    terms.add t
    if not p.acceptPunct(","): break

proc parseSelectCore(p: var Parser): SelectStmt =
  result = SelectStmt(ctes: @[])
  if p.acceptKw("DISTINCT"): result.isDistinct = true
  else: discard p.acceptKw("ALL")
  if p.peekIsKw("FROM"):
    # SELECT * style without column list is invalid; columns come first
    discard
  while true:
    var rc: ResultCol
    if p.peekIsStar():
      discard p.t.advance()
      rc.e = newExpr(exStar)
    else:
      rc.e = p.parseExpr(PrecOr)
    rc.text = exprName(rc.e)
    if p.acceptKw("AS"):
      rc.alias = p.takeIdent()
    else:
      let tk = p.t.peek()
      if tk.kind == tkQuotedIdent:
        rc.alias = p.takeIdent()
      else:
        const colStop = ["FROM","WHERE","GROUP","ORDER","LIMIT","HAVING",
                         "UNION","EXCEPT","INTERSECT","OFFSET"]
        if tk.kind == tkIdent and not p.peekIsAnyKw(colStop):
          rc.alias = p.takeIdent()
    if rc.text.len > 0:
      rc.text = rc.text.strip()
    result.cols.add rc
    if not p.acceptPunct(","): break
  if p.acceptKw("FROM"):
    p.parseTableSource(result.fromFirst, result.joins)
  if p.acceptKw("WHERE"):
    result.where = p.parseExpr(PrecOr)
  if p.peekIsKw("GROUP"):
    discard p.t.advance()
    p.expectKw("BY")
    while true:
      result.groupBy.add p.parseExpr(PrecOr)
      if not p.acceptPunct(","): break
  if p.acceptKw("HAVING"):
    result.having = p.parseExpr(PrecOr)

proc parseSelectStmt(p: var Parser): SelectStmt =
  p.enter()
  defer: p.leave()
  var ctes: seq[tuple[name: string, cols: seq[string], q: SelectStmt]]
  if p.acceptKw("WITH"):
    discard p.acceptKw("RECURSIVE")
    while true:
      var name = p.takeIdent()
      var cols: seq[string]
      if p.peekIsPunct("("):
        discard p.t.advance()
        while true:
          cols.add p.takeIdent()
          if not p.acceptPunct(","): break
        p.expectPunct(")")
      p.expectKw("AS")
      p.expectPunct("(")
      let q = p.parseSelectStmt()
      p.expectPunct(")")
      ctes.add (name, cols, q)
      if not p.acceptPunct(","): break
  p.expectKw("SELECT")
  result = p.parseSelectCore()
  result.ctes = ctes
  if p.peekIsKw("UNION") or p.peekIsKw("EXCEPT") or p.peekIsKw("INTERSECT"):
    let opTok = p.t.advance()
    var op = p.t.slice(opTok).toLowerAscii()
    if p.acceptKw("ALL"): op.add " all"
    elif p.acceptKw("DISTINCT"): discard
    let rhs = p.parseSelectStmt()
    result.isCompound = true
    result.compoundOp = op
    result.compoundRhs = rhs
    return
  if p.peekIsKw("ORDER"):
    p.parseOrderBy(result.orderBy)
  if p.acceptKw("LIMIT"):
    result.limit = p.parseExpr(PrecOr)
    if p.acceptKw("OFFSET"):
      result.offset = p.parseExpr(PrecOr)
    elif p.acceptPunct(","):
      result.offset = result.limit
      result.limit = p.parseExpr(PrecOr)
  elif p.acceptKw("OFFSET"):
    result.offset = p.parseExpr(PrecOr)

# ---------------------------------------------------------------------------
# DML / DDL
# ---------------------------------------------------------------------------

proc parseReturning(p: var Parser): seq[ResultCol] =
  if not p.acceptKw("RETURNING"): return @[]
  while true:
    var rc: ResultCol
    if p.peekIsStar():
      discard p.t.advance()
      rc.e = newExpr(exStar)
    else:
      rc.e = p.parseExpr(PrecOr)
    rc.text = exprName(rc.e)
    if p.acceptKw("AS"): rc.alias = p.takeIdent()
    result.add rc
    if not p.acceptPunct(","): break

proc parseColumnDef(p: var Parser): ColumnDef =
  result.name = p.takeIdent()
  if not (p.peekIsKw("CONSTRAINT") or p.peekIsKw("PRIMARY") or
          p.peekIsKw("NOT") or p.peekIsKw("UNIQUE") or p.peekIsKw("CHECK") or
          p.peekIsKw("DEFAULT") or p.peekIsKw("REFERENCES") or
          p.peekIsKw("COLLATE") or p.peekIsKw("GENERATED") or
          p.peekIsKw("NULL") or p.peekIsKw("AUTOINCREMENT") or
          p.peekIsKw("AS")):
    result.typeName = p.parseTypeName()
  while true:
    if p.acceptKw("CONSTRAINT"):
      discard p.takeIdent()
    elif p.acceptKw("PRIMARY"):
      p.expectKw("KEY")
      result.isPrimaryKey = true
      if p.acceptKw("DESC"): discard
      elif p.acceptKw("ASC"): discard
      if p.acceptKw("AUTOINCREMENT"): result.autoIncrement = true
    elif p.acceptKw("AUTOINCREMENT"):
      result.autoIncrement = true
    elif p.acceptKw("NOT"):
      p.expectKw("NULL")
      result.notNull = true
    elif p.acceptKw("NULL"):
      discard
    elif p.acceptKw("UNIQUE"):
      result.isUnique = true
    elif p.acceptKw("DEFAULT"):
      if p.peekIsPunct("("):
        discard p.t.advance()
        result.defaultExpr = p.parseExpr(PrecOr)
        p.expectPunct(")")
      else:
        result.defaultExpr = p.parseUnary()
    elif p.acceptKw("CHECK"):
      p.expectPunct("(")
      result.checkExpr = p.parseExpr(PrecOr)
      p.expectPunct(")")
    elif p.acceptKw("REFERENCES"):
      result.refTable = p.takeIdent()
      if p.peekIsPunct("("):
        discard p.t.advance()
        result.refCol = p.takeIdent()
        p.expectPunct(")")
      if p.acceptKw("ON"):
        if p.acceptKw("DELETE"):
          if p.acceptKw("CASCADE"): result.onDelete = "cascade"
          elif p.acceptKw("RESTRICT"): result.onDelete = "restrict"
          elif p.acceptKw("SET"): discard p.takeIdent(); result.onDelete = "setnull"
          else: discard p.t.advance()
    elif p.acceptKw("COLLATE"):
      let c = p.takeIdent().toLowerAscii()
      result.collate = if c == "nocase": colNocase else: colBinary
    elif p.acceptKw("GENERATED"):
      p.err("GENERATED columns are not supported yet")
    else:
      break

proc parseCreate(p: var Parser): Stmt =
  var temporary = false
  if p.acceptKw("TEMP") or p.acceptKw("TEMPORARY"): temporary = true
  if p.acceptKw("TABLE"):
    result = Stmt(kind: stCreateTable, temporary: temporary)
    if p.acceptKw("IF"):
      p.expectKw("NOT")
      p.expectKw("EXISTS")
      result.ifNotExists = true
    result.table = p.takeIdent()
    if p.peekIsPunct("."):
      discard p.t.advance()
      result.table = result.table & "." & p.takeIdent()
    p.expectPunct("(")
    while true:
      if p.peekIsKw("PRIMARY") or p.peekIsKw("UNIQUE") or p.peekIsKw("CHECK") or
         p.peekIsKw("FOREIGN") or p.peekIsKw("CONSTRAINT"):
        if p.acceptKw("CONSTRAINT"): discard p.takeIdent()
        var tc: TableConstraint
        if p.acceptKw("PRIMARY"):
          p.expectKw("KEY")
          tc.kind = tcPrimaryKey
          p.expectPunct("(")
          while true:
            tc.cols.add p.takeIdent()
            if p.acceptKw("ASC") or p.acceptKw("DESC"): discard
            if not p.acceptPunct(","): break
          p.expectPunct(")")
        elif p.acceptKw("UNIQUE"):
          tc.kind = tcUnique
          p.expectPunct("(")
          while true:
            tc.cols.add p.takeIdent()
            if p.acceptKw("ASC") or p.acceptKw("DESC"): discard
            if not p.acceptPunct(","): break
          p.expectPunct(")")
        elif p.acceptKw("CHECK"):
          tc.kind = tcCheck
          p.expectPunct("(")
          tc.checkExpr = p.parseExpr(PrecOr)
          p.expectPunct(")")
        elif p.acceptKw("FOREIGN"):
          tc.kind = tcForeignKey
          p.expectKw("KEY")
          p.expectPunct("(")
          while true:
            tc.cols.add p.takeIdent()
            if not p.acceptPunct(","): break
          p.expectPunct(")")
          p.expectKw("REFERENCES")
          tc.refTable = p.takeIdent()
          if p.peekIsPunct("("):
            discard p.t.advance()
            while true:
              tc.refCols.add p.takeIdent()
              if not p.acceptPunct(","): break
            p.expectPunct(")")
          if p.acceptKw("ON"):
            p.expectKw("DELETE")
            if p.acceptKw("CASCADE"): tc.onDelete = "cascade"
            elif p.acceptKw("RESTRICT"): tc.onDelete = "restrict"
        else:
          p.err("unsupported table constraint")
        result.constraints.add tc
      else:
        result.cols.add p.parseColumnDef()
      if not p.acceptPunct(","): break
    p.expectPunct(")")
    while true:
      if p.acceptKw("WITHOUT"):
        p.expectKw("ROWID")
        result.withoutRowid = true
      elif p.acceptKw("STRICT"):
        result.strict = true
      else:
        break
    return
  if p.acceptKw("UNIQUE"):
    p.expectKw("INDEX")
    result = Stmt(kind: stCreateIndex, isUnique: true)
  elif p.acceptKw("INDEX"):
    result = Stmt(kind: stCreateIndex)
  elif p.acceptKw("VIEW"):
    result = Stmt(kind: stCreateView)
    if p.acceptKw("IF"):
      p.expectKw("NOT")
      p.expectKw("EXISTS")
      result.ifNotExists = true
    result.viewName = p.takeIdent()
    if p.peekIsPunct("("):
      discard p.t.advance()
      while true:
        result.viewCols.add p.takeIdent()
        if not p.acceptPunct(","): break
      p.expectPunct(")")
    p.expectKw("AS")
    result.viewSelect = p.parseSelectStmt()
    return
  elif p.peekIsKw("TRIGGER"):
    p.err("TRIGGER is not supported (planned for v0.4)")
  else:
    p.err("unsupported CREATE statement")
  if p.acceptKw("IF"):
    p.expectKw("NOT")
    p.expectKw("EXISTS")
    result.ifNotExists = true
  result.indexName = p.takeIdent()
  p.expectKw("ON")
  result.table = p.takeIdent()
  p.expectPunct("(")
  while true:
    var t: tuple[expr: Expr, desc: bool, coll: Collation]
    t.expr = p.parseExpr(PrecOr)
    if p.acceptKw("DESC"): t.desc = true
    else: discard p.acceptKw("ASC")
    t.coll = colBinary
    if p.acceptKw("COLLATE"):
      let c = p.takeIdent().toLowerAscii()
      t.coll = if c == "nocase": colNocase else: colBinary
    result.indexCols.add t
    if not p.acceptPunct(","): break
  p.expectPunct(")")
  if p.acceptKw("WHERE"):
    result.where = p.parseExpr(PrecOr)

proc parseStmt(p: var Parser): Stmt =
  p.enter()
  defer: p.leave()
  let tk = p.t.peek()
  if tk.kind == tkEof: p.err("empty statement")

  if p.acceptKw("EXPLAIN"):
    let inner = p.parseStmt()
    return Stmt(kind: stExplain, inner: inner)

  if p.acceptKw("SELECT"):
    var st = p.parseSelectCore()
    if p.peekIsKw("UNION") or p.peekIsKw("EXCEPT") or p.peekIsKw("INTERSECT"):
      let opTok = p.t.advance()
      var op = p.t.slice(opTok).toLowerAscii()
      if p.acceptKw("ALL"): op.add " all"
      let rhs = p.parseSelectStmt()
      st.isCompound = true
      st.compoundOp = op
      st.compoundRhs = rhs
    else:
      if p.peekIsKw("ORDER"): p.parseOrderBy(st.orderBy)
      if p.acceptKw("LIMIT"):
        st.limit = p.parseExpr(PrecOr)
        if p.acceptKw("OFFSET"): st.offset = p.parseExpr(PrecOr)
    return Stmt(kind: stSelect, select: st)

  if p.peekIsKw("WITH"):
    return Stmt(kind: stSelect, select: p.parseSelectStmt())

  if p.acceptKw("INSERT"):
    result = Stmt(kind: stInsert)
    p.expectKw("INTO")
    result.table = p.takeIdent()
    if p.peekIsPunct("(") and not p.peekIsKw("SELECT"):
      discard p.t.advance()
      while true:
        result.columns.add p.takeIdent()
        if not p.acceptPunct(","): break
      p.expectPunct(")")
    if p.acceptKw("DEFAULT"):
      p.expectKw("VALUES")
      result.defaultValues = true
    elif p.acceptKw("VALUES"):
      while true:
        p.expectPunct("(")
        var row: seq[Expr]
        if not p.peekIsPunct(")"):
          while true:
            row.add p.parseExpr(PrecOr)
            if not p.acceptPunct(","): break
        p.expectPunct(")")
        result.values.add row
        if not p.acceptPunct(","): break
    elif p.peekIsKw("SELECT") or p.peekIsKw("WITH"):
      result.sourceSelect = p.parseSelectStmt()
    else:
      p.err("expected VALUES or SELECT")
    if p.acceptKw("ON"):
      p.expectKw("CONFLICT")
      if p.acceptKw("IGNORE"): result.onConflict = "ignore"
      elif p.acceptKw("REPLACE"): result.onConflict = "replace"
      elif p.acceptKw("ABORT"): result.onConflict = "abort"
      elif p.acceptKw("FAIL"): result.onConflict = "fail"
      else: p.err("bad ON CONFLICT action")
    result.returning = p.parseReturning()
    return

  if p.acceptKw("REPLACE"):
    p.expectKw("INTO")
    result = Stmt(kind: stInsert, table: p.takeIdent(), onConflict: "replace")
    if p.peekIsPunct("("):
      discard p.t.advance()
      while true:
        result.columns.add p.takeIdent()
        if not p.acceptPunct(","): break
      p.expectPunct(")")
    p.expectKw("VALUES")
    while true:
      p.expectPunct("(")
      var row: seq[Expr]
      while true:
        row.add p.parseExpr(PrecOr)
        if not p.acceptPunct(","): break
      p.expectPunct(")")
      result.values.add row
      if not p.acceptPunct(","): break
    return

  if p.acceptKw("UPDATE"):
    result = Stmt(kind: stUpdate)
    result.table = p.takeIdent()
    p.expectKw("SET")
    while true:
      var a: Assign
      a.col = p.takeIdent()
      if not p.acceptOp("="): p.err("expected '=' in SET")
      a.e = p.parseExpr(PrecOr)
      result.assigns.add a
      if not p.acceptPunct(","): break
    if p.acceptKw("WHERE"): result.where = p.parseExpr(PrecOr)
    result.returning = p.parseReturning()
    return

  if p.acceptKw("DELETE"):
    p.expectKw("FROM")
    result = Stmt(kind: stDelete, table: p.takeIdent())
    if p.acceptKw("WHERE"): result.where = p.parseExpr(PrecOr)
    result.returning = p.parseReturning()
    return

  if p.peekIsKw("CREATE"):
    discard p.t.advance()
    return p.parseCreate()

  if p.acceptKw("DROP"):
    if p.acceptKw("TABLE"):
      result = Stmt(kind: stDropTable)
      if p.acceptKw("IF"): p.expectKw("EXISTS"); result.ifExists = true
      result.table = p.takeIdent()
      return
    if p.acceptKw("INDEX"):
      result = Stmt(kind: stDropIndex)
      if p.acceptKw("IF"): p.expectKw("EXISTS"); result.ifExists = true
      result.indexName = p.takeIdent()
      return
    if p.acceptKw("VIEW"):
      result = Stmt(kind: stDropView)
      if p.acceptKw("IF"): p.expectKw("EXISTS"); result.ifExists = true
      result.viewName = p.takeIdent()
      return
    p.err("unsupported DROP")

  if p.acceptKw("ALTER"):
    p.expectKw("TABLE")
    result = Stmt(kind: stAlterTable, table: p.takeIdent())
    if p.acceptKw("RENAME"):
      if p.acceptKw("TO"):
        result.alterAction = "rename_table"
        result.newName = p.takeIdent()
      elif p.acceptKw("COLUMN"):
        result.alterAction = "rename_column"
        result.oldCol = p.takeIdent()
        p.expectKw("TO")
        result.newCol = p.takeIdent()
      else:
        result.alterAction = "rename_table"
        p.expectKw("TO")
        result.newName = p.takeIdent()
    elif p.acceptKw("RENAME") :
      discard
    elif p.acceptKw("ADD"):
      discard p.acceptKw("COLUMN")
      result.alterAction = "add_column"
      result.addCol = p.parseColumnDef()
    elif p.acceptKw("DROP"):
      discard p.acceptKw("COLUMN")
      result.alterAction = "drop_column"
      result.oldCol = p.takeIdent()
    else:
      p.err("unsupported ALTER TABLE action")
    return

  if p.acceptKw("BEGIN"):
    discard p.acceptKw("DEFERRED")
    discard p.acceptKw("IMMEDIATE")
    discard p.acceptKw("EXCLUSIVE")
    discard p.acceptKw("TRANSACTION")
    return Stmt(kind: stBegin)
  if p.acceptKw("COMMIT") or p.acceptKw("END"):
    discard p.acceptKw("TRANSACTION")
    return Stmt(kind: stCommit)
  if p.acceptKw("ROLLBACK"):
    discard p.acceptKw("TRANSACTION")
    if p.acceptKw("TO"):
      discard p.acceptKw("SAVEPOINT")
      return Stmt(kind: stRollback, savepointName: p.takeIdent())
    return Stmt(kind: stRollback)
  if p.acceptKw("SAVEPOINT"):
    return Stmt(kind: stSavepoint, savepointName: p.takeIdent())
  if p.acceptKw("RELEASE"):
    discard p.acceptKw("SAVEPOINT")
    return Stmt(kind: stRelease, savepointName: p.takeIdent())

  if p.acceptKw("PRAGMA"):
    result = Stmt(kind: stPragma)
    result.pragmaName = p.takeIdent().toLowerAscii()
    if p.peekIsPunct("."):
      discard p.t.advance()
      result.pragmaName.add "." & p.takeIdent().toLowerAscii()
    if p.acceptOp("="):
      result.pragmaValue = p.parseUnary()
    elif p.acceptPunct("("):
      if not p.peekIsPunct(")"):
        result.pragmaValue = p.parseExpr(PrecOr)
      p.expectPunct(")")
    return

  if p.acceptKw("ATTACH") or p.acceptKw("DETACH"):
    # There is no ATTACH in this engine, by design: a second database file in
    # the same connection is how data escapes an authorization boundary.
    raise dbErr(auth, "ATTACH/DETACH is not supported by design")

  if p.acceptKw("ANALYZE"):
    return Stmt(kind: stAnalyze)
  if p.acceptKw("VACUUM"):
    discard p.acceptKw("INTO")   # rejected below: VACUUM INTO writes files
    if p.t.peek().kind != tkEof:
      raise dbErr(auth, "VACUUM INTO is not supported by design")
    return Stmt(kind: stVacuum)

  p.err("unrecognized statement")

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

proc parseOne*(src: string): tuple[stmt: Stmt, params: int] =
  ## Parses exactly one statement; trailing `;` allowed, trailing garbage is not.
  var p = Parser(t: initTokenizer(src), depth: 0)
  let st = p.parseStmt()
  discard p.acceptPunct(";")
  if p.t.peek().kind != tkEof:
    p.err("unexpected trailing input")
  (st, p.paramCount)

proc parseScript*(src: string): seq[Stmt] =
  ## Splits and parses a multi-statement script. `;` inside strings/comments is
  ## handled by the tokenizer, so naive string splitting is never used.
  result = @[]
  var p = Parser(t: initTokenizer(src), depth: 0)
  while true:
    while p.acceptPunct(";"): discard
    if p.t.peek().kind == tkEof: break
    result.add p.parseStmt()
    if not p.acceptPunct(";") and p.t.peek().kind != tkEof:
      p.err("expected ';' between statements")
