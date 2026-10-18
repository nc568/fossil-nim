## AST for the Foccil SQL dialect.
##
## The tree is deliberately *flat* (one object with optional fields instead of a
## deep variant hierarchy). Rationale:
##   * fewer lines of code for the same expressive power (no per-node visitors);
##   * node allocation is uniform, so allocation size never varies in a plan;
##   * pattern matching is a single `case` on `kind`, which the JS backend turns
##     into a jump table — cheap on V8 and on wasm.
## A prepared statement is built once and executed many times, so AST footprint
## is not on the hot path; evaluation is.

import ./values, ./errors

type
  ExprKind* = enum
    exLit = 0      ## literal (val)
    exParam        ## ? / :name (pIdx, pName)
    exCol          ## column reference (tbl, name)
    exStar         ## `*`
    exUnary        ## op, args[0]
    exBinary       ## op, args[0], args[1]
    exCall         ## name, args, distinct, star
    exCase         ## args = [operand?], pairs = branches, e1 = else
    exCast         ## typeName, args[0]
    exIn           ## args[0] IN (list) | IN (subquery), negated
    exExists       ## sub, negated
    exScalarSub    ## sub
    exBetween      ## args[0] BETWEEN args[1] AND args[2], negated
    exIsNull       ## args[0] IS [NOT] NULL, negated
    exLike         ## args[0] LIKE args[1] [ESCAPE args[2]], negated
    exTuple        ## (a, b, …)
    exCollate      ## args[0] COLLATE name
    exRowValue     ## row value used in comparisons

  Expr* = ref object
    kind*: ExprKind
    val*: Value
    pIdx*: int
    pName*: string
    tbl*: string
    name*: string
    op*: string
    args*: seq[Expr]
    pairs*: seq[tuple[whenE, thenE: Expr]]
    e1*: Expr
    negated*: bool
    isDistinctArg*: bool
    star*: bool
    typeName*: string
    sub*: SelectStmt
    aggIdx*: int             ## >= 0 when this call is an aggregate in the plan
    span*: string            ## original source slice, for error messages & EXPLAIN

  OrderTerm* = object
    expr*: Expr
    desc*: bool
    nullsFirst*: int         ## -1 = default, 0 = NULLS LAST, 1 = NULLS FIRST
    coll*: Collation

  ResultCol* = object
    e*: Expr
    alias*: string
    text*: string            ## output name before alias resolution

  JoinKind* = enum
    jkInner = 0
    jkLeft
    jkCross

  Join* = object
    kind*: JoinKind
    table*: TableSource
    on*: Expr
    usingCols*: seq[string]

  TableSource* = ref object
    name*: string
    alias*: string
    sub*: SelectStmt         ## derived table / view / CTE body
    isView*: bool
    cteName*: string         ## set when this source refers to a CTE

  SelectStmt* = ref object
    isDistinct*: bool
    cols*: seq[ResultCol]
    fromFirst*: TableSource  ## left-most FROM item
    joins*: seq[Join]        ## left-deep join chain
    where*: Expr
    groupBy*: seq[Expr]
    having*: Expr
    orderBy*: seq[OrderTerm]
    limit*: Expr
    offset*: Expr
    ctes*: seq[tuple[name: string, cols: seq[string], q: SelectStmt]]
    isCompound*: bool
    compoundOp*: string      ## "union" | "union all" | "intersect" | "except"
    compoundRhs*: SelectStmt

  ColumnDef* = object
    name*: string
    typeName*: string
    notNull*: bool
    isPrimaryKey*: bool
    autoIncrement*: bool
    isUnique*: bool
    defaultExpr*: Expr
    checkExpr*: Expr
    refTable*: string
    refCol*: string
    onDelete*: string
    collate*: Collation

  TableConstraintKind* = enum
    tcPrimaryKey = 0
    tcUnique
    tcCheck
    tcForeignKey

  TableConstraint* = object
    kind*: TableConstraintKind
    name*: string
    cols*: seq[string]
    checkExpr*: Expr
    refTable*: string
    refCols*: seq[string]
    onDelete*: string

  Assign* = object
    col*: string
    e*: Expr

  StmtKind* = enum
    stSelect = 0
    stInsert
    stUpdate
    stDelete
    stCreateTable
    stDropTable
    stAlterTable
    stCreateIndex
    stDropIndex
    stCreateView
    stDropView
    stBegin
    stCommit
    stRollback
    stSavepoint
    stRelease
    stPragma
    stExplain
    stAnalyze
    stVacuum

  Stmt* = ref object
    kind*: StmtKind
    select*: SelectStmt
    # INSERT
    table*: string
    columns*: seq[string]
    values*: seq[seq[Expr]]
    sourceSelect*: SelectStmt
    returning*: seq[ResultCol]
    onConflict*: string          ## "", "ignore", "replace", "abort", "fail"
    defaultValues*: bool
    # UPDATE
    assigns*: seq[Assign]
    where*: Expr
    # DELETE  (uses table + where)
    # CREATE TABLE
    cols*: seq[ColumnDef]
    constraints*: seq[TableConstraint]
    ifNotExists*: bool
    ifExists*: bool
    withoutRowid*: bool
    strict*: bool
    temporary*: bool
    # ALTER
    alterAction*: string         ## "rename_table" | "add_column" | "rename_column" | "drop_column"
    newName*: string
    oldCol*: string
    newCol*: string
    addCol*: ColumnDef
    # CREATE INDEX
    indexName*: string
    indexCols*: seq[tuple[expr: Expr, desc: bool, coll: Collation]]
    isUnique*: bool
    # transactions
    savepointName*: string
    # PRAGMA
    pragmaName*: string
    pragmaValue*: Expr
    # EXPLAIN
    inner*: Stmt
    # VIEW
    viewName*: string
    viewSelect*: SelectStmt
    viewCols*: seq[string]

## All constructors set `aggIdx = -1` explicitly. Nim zero-initialises object
## fields, so a forgotten field would silently look like "aggregate slot 0" and
## every scalar function would return NULL — the kind of bug a type system
## cannot catch but a single shared constructor can avoid.
func newExpr*(k: ExprKind): Expr = Expr(kind: k, pIdx: -1, aggIdx: -1)
func lit*(v: Value): Expr = Expr(kind: exLit, val: v, pIdx: -1, aggIdx: -1)
func colRef*(tbl, name: string): Expr =
  Expr(kind: exCol, tbl: tbl, name: name, pIdx: -1, aggIdx: -1)
func binop*(op: string; a, b: Expr): Expr =
  Expr(kind: exBinary, op: op, args: @[a, b], pIdx: -1, aggIdx: -1)
func unop*(op: string; a: Expr): Expr =
  Expr(kind: exUnary, op: op, args: @[a], pIdx: -1, aggIdx: -1)
func call*(fn: string; args: seq[Expr]): Expr =
  Expr(kind: exCall, name: fn, args: args, pIdx: -1, aggIdx: -1)

func exprName*(e: Expr): string =
  ## Structural output-column name. Deriving the name from the tree instead of
  ## slicing the source text keeps names independent of tokenizer lookahead
  ## (a slice-based name silently swallows the following token).
  case e.kind
  of exCol: e.name
  of exStar: "*"
  of exLit:
    case e.val.kind
    of vkText: e.val.t
    of vkNull: "NULL"
    else: e.val.toText
  of exCall: e.name
  of exParam: "?"
  of exCast: "cast"
  of exUnary: e.op & " " & exprName(e.args[0])
  of exBinary: exprName(e.args[0]) & " " & e.op & " " & exprName(e.args[1])
  of exCollate: exprName(e.args[0])
  of exIsNull: exprName(e.args[0]) & " ISNULL"
  else: "expr"

func isLiteral*(e: Expr): bool {.inline.} = e.kind == exLit
func isConstExpr*(e: Expr): bool =
  ## A constant expression can be folded at prepare time.
  case e.kind
  of exLit: true
  of exParam, exCol, exStar, exScalarSub, exExists: false
  else:
    var ok = true
    for a in e.args: ok = ok and a.isConstExpr
    for p in e.pairs:
      ok = ok and p.whenE.isConstExpr and p.thenE.isConstExpr
    ok and (e.e1 == nil or e.e1.isConstExpr) and e.sub == nil
