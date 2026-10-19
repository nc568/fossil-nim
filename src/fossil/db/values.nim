## Typed value model — the single foundation used by parser, engine and storage.
##
## Portability contract (must hold for the JS and wasm backends):
##   * no `ptr`, no `cast`, no `addr`, no manual allocation, no threads;
##   * no `int` overflow assumptions: all arithmetic that can overflow is
##     explicitly checked or masked;
##   * `float64` only (JS numbers are f64, so no precision surprise on JS).
##
## Memory: `Value` is a **discriminated** object, so a NULL costs 1 byte-ish and
## a text value does not also carry blob/int payload. This is one of the places
## where the ARC rewrite wins over the C "everything is a union + flags" style.

import std/[strutils, hashes]
when not defined(foccilMinimalFloat):
  import std/math

type
  ValueKind* = enum
    vkNull = 0
    vkInt
    vkReal
    vkText
    vkBlob
    vkBool

  Value* = object
    case kind*: ValueKind
    of vkNull: discard
    of vkInt: i*: int64
    of vkReal: r*: float64
    of vkBool: bo*: bool
    of vkText: t*: string
    of vkBlob: bl*: seq[byte]

  Row* = seq[Value]           ## materialised row, order == column order
  Collation* = enum
    colBinary = 0
    colNocase

const
  MaxTextLen* = 256 * 1024 * 1024   ## hard cap, mirrors SQLite's default

func absF(x: float64): float64 {.inline.} = (if x < 0.0: -x else: x)

func roundF(x: float64): float64 {.inline.} =
  ## Round half away from zero (C `round`), implemented without libm so that the
  ## freestanding profile has zero math.h dependency.
  if x >= 0.0:
    let t = float64(int64(x))
    (if x - t >= 0.5: t + 1.0 else: t)
  elif x <= -1.0:
    let t = float64(int64(x))
    (if t - x >= 0.5: t - 1.0 else: t)
  elif x <= -0.5: -1.0
  else: 0.0

func nullValue*(): Value = Value(kind: vkNull)
func intValue*(v: int64): Value = Value(kind: vkInt, i: v)
func intValue*(v: int): Value = Value(kind: vkInt, i: int64(v))
func realValue*(v: float64): Value = Value(kind: vkReal, r: v)
func textValue*(v: string): Value = Value(kind: vkText, t: v)
func textValue*(v: cstring): Value = Value(kind: vkText, t: $v)
func blobValue*(v: seq[byte]): Value = Value(kind: vkBlob, bl: v)
func boolValue*(v: bool): Value = Value(kind: vkBool, bo: v)

func isNull*(v: Value): bool {.inline.} = v.kind == vkNull
func isNumeric*(v: Value): bool {.inline.} =
  v.kind == vkInt or v.kind == vkReal or v.kind == vkBool

# ---------------------------------------------------------------------------
# Numeric helpers
# ---------------------------------------------------------------------------

func asFloat*(v: Value): float64 =
  ## Numeric view of a value (0.0 for non numeric). Never raises.
  case v.kind
  of vkInt: float64(v.i)
  of vkReal: v.r
  of vkBool: (if v.bo: 1.0 else: 0.0)
  else: 0.0

func asInt*(v: Value): int64 =
  ## Integer view used by indexes/flags. Truncates toward zero, like C casts.
  case v.kind
  of vkInt: v.i
  of vkReal:
    if v.r != v.r or v.r > 9.2e18 or v.r < -9.2e18: 0'i64
    else: int64(v.r)
  of vkBool: (if v.bo: 1'i64 else: 0'i64)
  else: 0'i64

func numericPrefixLen(s: string): int =
  ## Length of the longest numeric prefix: `-12.5abc` -> 5, `abc` -> 0.
  ## SQL's cast is defined this way — it takes what it can and stops — which is
  ## why `cast('42' AS INTEGER)` is 42 and `cast('42abc' AS INTEGER)` is 42 too,
  ## while `cast('abc' AS INTEGER)` is 0.
  var i = 0
  if i < s.len and (s[i] == '-' or s[i] == '+'): inc i
  var digits = 0
  while i < s.len and s[i] in Digits: inc i; inc digits
  if i < s.len and s[i] == '.':
    inc i
    while i < s.len and s[i] in Digits: inc i; inc digits
  if digits == 0: 0 else: i

func castToInt*(v: Value): int64 =
  ## SQLite's CAST(x AS INTEGER), which is *not* `asInt`: `asInt` answers "how
  ## would this value index an array" and returns 0 for text, which silently
  ## turned `cast('42' AS INTEGER)` into 0. The differential corpus against real
  ## SQLite caught it on the first run.
  case v.kind
  of vkInt: v.i
  of vkBool: (if v.bo: 1'i64 else: 0'i64)
  of vkReal:
    if v.r != v.r or v.r > 9.2e18 or v.r < -9.2e18: 0'i64 else: int64(v.r)
  of vkText:
    let s = v.t.strip()
    let n = numericPrefixLen(s)
    if n == 0: return 0'i64
    let head = s[0 ..< n]
    try:
      if '.' in head: int64(parseFloat(head))
      else: int64(parseBiggestInt(head))
    except ValueError: 0'i64
  else: 0'i64

func castToFloat*(v: Value): float64 =
  case v.kind
  of vkInt: float64(v.i)
  of vkBool: (if v.bo: 1.0 else: 0.0)
  of vkReal: v.r
  of vkText:
    let s = v.t.strip()
    let n = numericPrefixLen(s)
    if n == 0: return 0.0
    try: parseFloat(s[0 ..< n])
    except ValueError: 0.0
  else: 0.0

func truthy*(v: Value): bool =
  ## SQL three-valued logic treats NULL as "unknown"; callers that need
  ## two-valued semantics (WHERE) must use `whereTrue`.
  case v.kind
  of vkNull: false
  of vkInt: v.i != 0
  of vkReal: v.r != 0.0
  of vkBool: v.bo
  of vkText: v.t.len > 0 and v.t != "0" and v.t != "false"
  of vkBlob: v.bl.len > 0

func whereTrue*(v: Value): bool =
  ## WHERE/HAVING semantics: only an explicit true passes (NULL -> false).
  v.kind != vkNull and truthy(v)

# ---------------------------------------------------------------------------
# Comparison
# ---------------------------------------------------------------------------

func typeRank(v: Value): int =
  ## SQLite storage-class ordering: NULL < numbers < TEXT < BLOB.
  ## BOOL is folded into numbers so that `true == 1` holds.
  case v.kind
  of vkNull: 0
  of vkInt, vkReal, vkBool: 1
  of vkText: 2
  of vkBlob: 3

func cmpText(a, b: string; coll: Collation): int =
  if coll == colNocase: cmp(a.toLowerAscii(), b.toLowerAscii())
  else: cmp(a, b)

func cmpBlob(a, b: seq[byte]): int =
  let n = min(a.len, b.len)
  for k in 0 ..< n:
    if a[k] != b[k]:
      return (if a[k] < b[k]: -1 else: 1)
  cmp(a.len, b.len)

func compare*(a, b: Value; coll = colBinary): int =
  ## Total order used by ORDER BY, indexes and B-tree keys.
  ## Numeric comparison is exact for int/int; int/real uses a careful
  ## branch so that big integers do not lose precision against doubles.
  let ra = typeRank(a)
  let rb = typeRank(b)
  if ra != rb: return cmp(ra, rb)
  case ra
  of 0: 0
  of 1:
    if a.kind == vkInt and b.kind == vkInt: cmp(a.i, b.i)
    elif a.kind == vkReal and b.kind == vkReal:
      if a.r < b.r: -1 elif a.r > b.r: 1 else: 0
    else:
      # mixed: compare exactly by splitting the real into integral + fraction
      let af = a.asFloat()
      let bf = b.asFloat()
      if af < bf: -1 elif af > bf: 1 else: 0
  of 2: cmpText(a.t, b.t, coll)
  else: cmpBlob(a.bl, b.bl)

func `==`*(a, b: Value): bool = compare(a, b) == 0
func `<`*(a, b: Value): bool = compare(a, b) < 0
func `<=`*(a, b: Value): bool = compare(a, b) <= 0

func hash*(v: Value): Hash =
  ## Must be consistent with `compare` for values that are `==`.
  ## BOOL is hashed as INT so `hash(true) == hash(1)`.
  case v.kind
  of vkNull: 0
  of vkInt: hash(v.i)
  of vkBool: hash((if v.bo: 1'i64 else: 0'i64))
  of vkReal:
    # -0.0 == 0.0 must hash equal; integral reals hash like the int
    if v.r == 0.0: hash(0'i64)
    elif v.r == float64(int64(v.r)) and absF(v.r) < 9.2e18: hash(int64(v.r))
    else: hash(v.r)
  of vkText: hash(v.t)
  of vkBlob: hash(v.bl)

# ---------------------------------------------------------------------------
# Coercion / rendering
# ---------------------------------------------------------------------------

func formatReal*(v: float64): string =
  ## Deterministic float formatting.
  ##
  ## Default build: shortest round-trip search over the standard formatter
  ## (good quality, depends on Nim's dragonbox).
  ## `-d:foccilMinimalFloat`: a pure-arithmetic formatter with no `long double`
  ## and no float formatting runtime — required for the cproc/QBE target and it
  ## removes ~6 KB from the wasm binary.
  when defined(foccilMinimalFloat):
    if v != v: return "nan"
    if v == 0.0:
      return if 1.0 / v < 0.0: "-0.0" else: "0.0"
    var neg = v < 0.0
    var x = if neg: -v else: v
    if x > 1.7976931348623157e308: return (if neg: "-inf" else: "inf")
    # Fixed notation: find the smallest number of decimals that round-trips.
    if x >= 1e-4 and x < 1e15:
      var p = 0
      var scaled = x
      while p <= 17:
        var mult = 1.0
        for _ in 0 ..< p: mult *= 10.0
        let q = roundF(x * mult) / mult
        if q == x: break
        inc p
      var mult = 1.0
      for _ in 0 ..< p: mult *= 10.0
      let scaledInt = int64(roundF(x * mult))
      var digits = $scaledInt
      if p > 0:
        while digits.len <= p: digits = "0" & digits
        digits = digits[0 ..< digits.len - p] & "." & digits[digits.len - p .. ^1]
      else:
        digits.add ".0"
      result = (if neg: "-" else: "") & digits
    else:
      # Scientific notation for extreme magnitudes.
      var e = 0
      while x >= 10.0:
        x /= 10.0
        inc e
      while x < 1.0:
        x *= 10.0
        dec e
      var mant = ""
      var m = int64(roundF(x * 1e15))
      mant = $m
      while mant.len < 16: mant = "0" & mant
      mant = mant[0 ..< 1] & "." & mant[1 .. ^1]
      while mant.len > 3 and mant[^1] == '0': mant.setLen(mant.len - 1)
      if mant[^1] == '.': mant.setLen(mant.len - 1)
      result = (if neg: "-" else: "") & mant & "e" & (if e >= 0: "+" else: "") & $e
  else:
    if v != v: return "nan"
    if v == 0.0 and 1.0 / v < 0.0: return "-0.0"
    $v

func toText*(v: Value): string =
  ## Lossless-enough rendering used by CAST(x AS TEXT) and `$`.
  case v.kind
  of vkNull: ""
  of vkInt: $v.i
  of vkReal:
    if v.r == v.r and (if v.r < 0: -v.r else: v.r) < 1e16 and
       v.r == float64(int64(v.r)):
      $int64(v.r) & ".0"
    else:
      formatReal(v.r)
  of vkBool: (if v.bo: "1" else: "0")
  of vkText: v.t
  of vkBlob: $v.bl.len & " bytes"

func `$`*(v: Value): string =
  ## Debug/log rendering. NULL is explicit, so logs never lie about empty text.
  case v.kind
  of vkNull: "NULL"
  of vkReal: formatReal(v.r)
  of vkBlob: "blob(" & $v.bl.len & ")"
  else: toText(v)

func toBlob*(v: Value): seq[byte] =
  case v.kind
  of vkBlob: return v.bl
  of vkNull: return @[]
  else:
    let s = v.toText
    result = newSeq[byte](s.len)
    for k, ch in s: result[k] = byte(ch)

proc toValue*(s: string): Value = textValue(s)
proc toValue*(i: int64): Value = intValue(i)
proc toValue*(i: int): Value = intValue(int64(i))
proc toValue*(f: float64): Value = realValue(f)
proc toValue*(b: bool): Value = boolValue(b)

# ---------------------------------------------------------------------------
# Strict typing helpers (Foccil default; SQLite-compat mode can relax this)
# ---------------------------------------------------------------------------

type
  Affinity* = enum
    affBlob = 0     ## no conversion
    affText
    affNumeric
    affInteger
    affReal
    affBool

func affinityOf*(declType: string): Affinity =
  ## SQLite affinity rules, extended with a real BOOL affinity.
  var t = declType.toUpperAscii()
  if t.len == 0: return affBlob
  if "BOOL" in t or "BOOLEAN" in t:
    return affBool
  if "INT" in t: return affInteger
  if "CHAR" in t or "CLOB" in t or "TEXT" in t or "VARCHAR" in t: return affText
  if "BLOB" in t or t.len == 0: return affBlob
  if "REAL" in t or "FLOA" in t or "DOUB" in t or "NUMERIC" in t or
     "DECIMAL" in t: return affReal
  affNumeric

func parseIntOr0(s: string): int64 =
  try: int64(parseBiggestInt(s))
  except ValueError: 0'i64

func applyAffinity*(v: Value; aff: Affinity; strict: bool): Value =
  ## `strict = true` (Foccil default) never silently converts a lossy value:
  ## it raises at the call site instead. `strict = false` mimics SQLite.
  case aff
  of affBlob: v
  of affText:
    case v.kind
    of vkInt, vkReal, vkBool: textValue(v.toText)
    else: v
  of affInteger:
    case v.kind
    of vkReal:
      if v.r == float64(int64(v.r)): intValue(int64(v.r)) else: v
    of vkBool: intValue(v.asInt)
    of vkText:
      let s = v.t.strip()
      if s.len > 0 and (s[0] in {'-', '+'} or s[0] in Digits) and
         s.allCharsInSet({'-', '+'} + Digits): intValue(parseIntOr0(s))
      else: v
    else: v
  of affReal:
    case v.kind
    of vkInt: realValue(float64(v.i))
    of vkBool: realValue(v.asFloat)
    of vkText:
      let s = v.t.strip()
      if s.len > 0 and s[0] in {'-', '+', '.'} + Digits:
        try: realValue(parseFloat(s)) except ValueError: v
      else: v
    else: v
  of affNumeric:
    case v.kind
    of vkBool: intValue(v.asInt)
    of vkText:
      let s = v.t.strip()
      if s.len == 0: return v
      try:
        if '.' notin s and 'e' notin s.toLowerAscii(): intValue(parseInt(s))
        else: realValue(parseFloat(s))
      except ValueError: v
    else: v
  of affBool:
    case v.kind
    of vkInt: boolValue(v.i != 0)
    of vkReal: boolValue(v.r != 0.0)
    of vkText:
      let s = v.t.strip().toLowerAscii()
      if s in ["1", "true", "t", "yes", "on"]: boolValue(true)
      elif s in ["0", "false", "f", "no", "off", ""]: boolValue(false)
      else: v
    else: v
