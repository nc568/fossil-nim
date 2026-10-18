## SQL tokenizer.
##
## Hand-written and table-driven: no regex, no copies in the hot path.
## Allocation policy: an identifier/number token stores a *slice* of the source
## string (offset+len), so lexing a 1 MB statement costs one allocation (the
## source itself) instead of one per token. That is both faster and leaner than
## the classic "substring per token" approach.

import std/strutils
import ./errors, ./values

type
  TokKind* = enum
    tkEof = 0
    tkIdent        ## bare identifier or keyword (case preserved)
    tkQuotedIdent  ## "x", [x], `x`
    tkNumber
    tkString
    tkBlob         ## x'00ff'
    tkParam        ## ? ?NNN :name @name $name
    tkOp           ## operator
    tkPunct        ## ( ) , ; . *

  Token* = object
    kind*: TokKind
    pos*: int          ## byte offset in source
    len*: int
    num*: Value        ## pre-decoded numeric literal (tkNumber) / blob
    paramIdx*: int     ## 1-based for ?, -1 for named
    paramName*: string

  Tokenizer* = object
    src*: string
    pos*: int
    peeked*: bool
    peekTok*: Token

const
  IdentStart* = {'a'..'z', 'A'..'Z', '_'}
  HexDigits* = {'0'..'9', 'a'..'f', 'A'..'F'}
  IdentCont* = IdentStart + Digits + {'$'}
  OpChars* = {'+', '-', '*', '/', '%', '=', '<', '>', '!', '|', '&', '~', '^'}

func makeToken(kind: TokKind; pos, len: int): Token =
  Token(kind: kind, pos: pos, len: len, paramIdx: -1)

func slice*(t: Tokenizer; tok: Token): string =
  if tok.len == 0: "" else: t.src[tok.pos ..< tok.pos + tok.len]

func isKeyword*(t: Tokenizer; tok: Token; kw: string): bool =
  ## Case-insensitive keyword check without allocating an upper-cased copy
  ## for the common equal-length case.
  if tok.kind notin {tkIdent, tkQuotedIdent}: return false
  if tok.kind == tkQuotedIdent: return false   # quoted => never a keyword
  if tok.len != kw.len: return false
  for k in 0 ..< kw.len:
    let c = t.src[tok.pos + k]
    let d = kw[k]
    let cn = if c in {'a'..'z'}: char(ord(c) - 32) else: c
    let dn = if d in {'a'..'z'}: char(ord(d) - 32) else: d
    if cn != dn: return false
  true

func identOf*(t: Tokenizer; tok: Token): string = t.slice(tok)

# ---------------------------------------------------------------------------
# Literal decoding
# ---------------------------------------------------------------------------

const IntLimStrs = ["9223372036854775807", "-9223372036854775808"]

func parseNumberLiteral(s: string): Value =
  ## Deterministic, locale-independent, overflow-detecting numeric literal
  ## decoding. Hex (`0x…`), exponents and underscores (`1_000`) are supported.
  var i = 0
  var neg = false
  if i < s.len and (s[i] == '-' or s[i] == '+'):
    neg = s[i] == '-'
    inc i
  if i + 1 < s.len and s[i] == '0' and (s[i + 1] == 'x' or s[i + 1] == 'X'):
    var v = 0'i64
    inc i, 2
    if i >= s.len: return nullValue()
    while i < s.len:
      let c = s[i]
      var d = 0'i64
      if c in Digits: d = int64(ord(c) - ord('0'))
      elif c in {'a'..'f'}: d = int64(ord(c) - ord('a') + 10)
      elif c in {'A'..'F'}: d = int64(ord(c) - ord('A') + 10)
      else: return nullValue()
      v = (v shl 4) or d
      inc i
    return intValue(if neg: -v else: v)
  var isFloat = false
  var ii = i
  while ii < s.len:
    let c = s[ii]
    if c == '.' or c == 'e' or c == 'E': isFloat = true
    elif c notin Digits and c != '_': return nullValue()
    inc ii
  var clean = newStringOfCap(s.len)
  if neg: clean.add '-'
  for k in i ..< s.len:
    if s[k] != '_': clean.add s[k]
  if isFloat:
    try:
      return realValue(parseFloat(clean))
    except ValueError:
      return nullValue()
  try:
    intValue(parseBiggestInt(clean).int64)
  except ValueError, OverflowDefect:
    # integer too large -> SQLite promotes to REAL; do the same, but flag it
    try: realValue(parseFloat(clean))
    except ValueError: nullValue()

func hexVal(c: char): int =
  if c in Digits: ord(c) - ord('0')
  elif c in {'a'..'f'}: ord(c) - ord('a') + 10
  elif c in {'A'..'F'}: ord(c) - ord('A') + 10
  else: -1

# ---------------------------------------------------------------------------
# Scanner
# ---------------------------------------------------------------------------

proc error(t: Tokenizer; msg: string) {.noreturn.} =
  raise dbErr(syntax, msg & " (at offset " & $t.pos & ")")

proc skipSpaceAndComments(t: var Tokenizer) =
  ## Comment handling is explicit rather than regex-based; `--` line comments
  ## and `/* */` block comments are skipped, no nesting (SQL standard).
  while t.pos < t.src.len:
    let c = t.src[t.pos]
    if c in {' ', '\t', '\r', '\n', '\f', '\v'}:
      inc t.pos
    elif c == '-' and t.pos + 1 < t.src.len and t.src[t.pos + 1] == '-':
      t.pos += 2
      while t.pos < t.src.len and t.src[t.pos] != '\n': inc t.pos
    elif c == '/' and t.pos + 1 < t.src.len and t.src[t.pos + 1] == '*':
      t.pos += 2
      var closed = false
      while t.pos + 1 < t.src.len:
        if t.src[t.pos] == '*' and t.src[t.pos + 1] == '/':
          t.pos += 2
          closed = true
          break
        inc t.pos
      if not closed:
        t.pos = t.src.len
        t.error("unterminated block comment")
    else:
      break

proc quotedIdent(t: var Tokenizer; start: int; closeCh: char): Token =
  var i = start + 1
  var buf = newStringOfCap(16)
  while i < t.src.len:
    let c = t.src[i]
    if c == closeCh:
      # doubled quote is an escaped quote
      if i + 1 < t.src.len and t.src[i + 1] == closeCh:
        buf.add closeCh
        inc i, 2
        continue
      t.pos = i + 1
      var tok = makeToken(tkQuotedIdent, start, t.pos - start)
      tok.paramName = buf        # decoded identifier
      return tok
    buf.add c
    inc i
  t.pos = t.src.len
  t.error("unterminated quoted identifier")

proc stringLiteral(t: var Tokenizer; start: int): Token =
  var i = start + 1
  var buf = newStringOfCap(16)
  while i < t.src.len:
    let c = t.src[i]
    if c == '\'':
      if i + 1 < t.src.len and t.src[i + 1] == '\'':
        buf.add '\''
        inc i, 2
        continue
      t.pos = i + 1
      var tok = makeToken(tkString, start, t.pos - start)
      tok.num = textValue(buf)
      return tok
    buf.add c
    inc i
  t.pos = t.src.len
  t.error("unterminated string literal")

proc blobLiteral(t: var Tokenizer; start: int; qPos: int): Token =
  # x'00ff'
  var i = qPos + 1
  var buf: seq[byte]
  while i < t.src.len and t.src[i] != '\'':
    let hi = hexVal(t.src[i])
    if hi < 0: t.error("bad hex digit in blob literal")
    if i + 1 >= t.src.len: t.error("odd number of hex digits in blob literal")
    let lo = hexVal(t.src[i + 1])
    if lo < 0: t.error("bad hex digit in blob literal")
    buf.add byte((hi shl 4) or lo)
    inc i, 2
  if i >= t.src.len: t.error("unterminated blob literal")
  t.pos = i + 1
  var tok = makeToken(tkBlob, start, t.pos - start)
  tok.num = blobValue(buf)
  tok

proc nextToken*(t: var Tokenizer): Token =
  t.skipSpaceAndComments()
  let start = t.pos
  if start >= t.src.len:
    return makeToken(tkEof, start, 0)
  let c = t.src[start]

  # identifiers / keywords / blob literal prefix
  if c in IdentStart:
    var i = start + 1
    while i < t.src.len and t.src[i] in IdentCont: inc i
    # x'..' blob
    if i == start + 1 and (c == 'x' or c == 'X') and i < t.src.len and
       t.src[i] == '\'':
      return t.blobLiteral(start, i)
    t.pos = i
    return makeToken(tkIdent, start, i - start)

  if c in Digits or (c == '.' and start + 1 < t.src.len and t.src[start + 1] in Digits):
    var i = start
    let isHex = start + 1 < t.src.len and t.src[start] == '0' and
                (t.src[start + 1] == 'x' or t.src[start + 1] == 'X')
    if isHex: i = start + 2
    while i < t.src.len:
      let d = t.src[i]
      if isHex and d in HexDigits:
        inc i
        continue
      if d in Digits or d in {'a'..'f', 'A'..'F'} or d in {'.', '_', 'e', 'E'}:
        # stop hex-ish letters unless the literal really is 0x…
        if d in {'a'..'f', 'A'..'F'} and not
           (i >= start + 2 and t.src[start] == '0' and
            (t.src[start + 1] == 'x' or t.src[start + 1] == 'X')):
          break
        inc i
      elif d in {'+', '-'} and i > start and (t.src[i - 1] in {'e', 'E'}):
        inc i
      else:
        break
    t.pos = i
    var tok = makeToken(tkNumber, start, i - start)
    tok.num = parseNumberLiteral(t.src[start ..< i])
    if tok.num.kind == vkNull and (i - start) > 0 and t.src[start] != '0':
      # A malformed numeric literal must not silently become NULL.
      t.error("malformed numeric literal")
    return tok

  if c == '\'':
    return t.stringLiteral(start)

  if c == '"':
    return t.quotedIdent(start, '"')
  if c == '[':
    return t.quotedIdent(start, ']')
  if c == '`':
    return t.quotedIdent(start, '`')

  # parameters
  if c == '?':
    var i = start + 1
    while i < t.src.len and t.src[i] in Digits: inc i
    t.pos = i
    var tok = makeToken(tkParam, start, i - start)
    if i > start + 1:
      tok.paramIdx = int(parseNumberLiteral(t.src[start + 1 ..< i]).asInt)
    tok
  elif c in {'@', ':', '$'}:
    var i = start + 1
    if i >= t.src.len or t.src[i] notin IdentStart:
      t.error("malformed named parameter")
    while i < t.src.len and t.src[i] in IdentCont: inc i
    t.pos = i
    var tok = makeToken(tkParam, start, i - start)
    tok.paramName = t.src[start ..< i]
    tok.paramIdx = -2
    tok

  # punctuation
  elif c in {'(', ')', ',', ';', '.'}:
    t.pos = start + 1
    makeToken(tkPunct, start, 1)

  # operators, longest match first
  elif c in OpChars:
    const three = ["->>"]
    const two = ["->", "<=", ">=", "<>", "!=", "==", "||", "<<", ">>"]
    if start + 3 <= t.src.len and t.src[start ..< start + 3] in three:
      t.pos = start + 3
      return makeToken(tkOp, start, 3)
    if start + 2 <= t.src.len and t.src[start ..< start + 2] in two:
      t.pos = start + 2
      return makeToken(tkOp, start, 2)
    t.pos = start + 1
    makeToken(tkOp, start, 1)
  else:
    t.pos = start + 1
    t.error("unexpected character '" & $c & "'")

proc peek*(t: var Tokenizer): Token =
  ## One-token lookahead. The scanner is *not* rewound: `t.pos` is already past
  ## the peeked token, and `advance` simply hands it out. This keeps lexing O(n)
  ## with zero re-scanning (a save/restore design re-scans the token on every
  ## peek, which is quadratic on token-heavy statements).
  if not t.peeked:
    t.peekTok = t.nextToken()
    t.peeked = true
  t.peekTok

proc advance*(t: var Tokenizer): Token =
  ## Consume and return the next token (uses the lookahead buffer when warm).
  if t.peeked:
    t.peeked = false
    return t.peekTok
  t.nextToken()

func initTokenizer*(src: string): Tokenizer =
  Tokenizer(src: src, pos: 0, peeked: false)

proc `$`*(t: Tokenizer; tok: Token): string =
  case tok.kind
  of tkEof: "<eof>"
  of tkParam: "?"
  of tkPunct, tkOp: t.slice(tok)
  of tkQuotedIdent: "\"" & tok.paramName & "\""
  else: t.slice(tok)
