## Foccil SQL functions.
##
## Rules that matter for the portability targets:
##  * no locale-dependent formatting (`formatFloat` with fixed precision only);
##  * no `TIMESTAMP_NOW` dependence inside evaluation: `now()` is read once per
##    statement from `Db.clock`, which keeps a query deterministic and is what
##    you want for `CURRENT_TIMESTAMP` inside a long-running SELECT;
##  * every function is total: it returns NULL rather than raising, except for
##    arity errors, which are detected at prepare time.

import std/strutils
when not defined(foccilMinimalFloat):
  # libm is avoided in the freestanding profile: cproc/QBE cannot parse musl's
  # math.h (it declares `long double` prototypes), and wasm gains nothing from
  # linking libm for the handful of functions used here.
  import std/math
when not defined(foccilNoClock):
  import std/times

# --- arithmetic helpers that replace libm in the minimal profile ------------
func absF(x: float64): float64 {.inline.} = (if x < 0.0: -x else: x)
func roundF(x: float64): float64 {.inline.} =
  ## Round half away from zero, exactly like C `round`.
  if x >= 0.0: (if x - float64(int64(x)) >= 0.5: float64(int64(x) + 1) else: float64(int64(x)))
  elif x <= -1.0:
    let t = float64(int64(x))
    (if t - x >= 0.5: t - 1.0 else: t)
  elif x <= -0.5: -1.0
  else: 0.0
func pow10F(n: int): float64 =
  result = 1.0
  if n >= 0:
    for _ in 0 ..< n: result *= 10.0
  else:
    for _ in 0 ..< -n: result /= 10.0
import ./values, ./errors

type
  FuncSig* = object
    name*: string
    minArgs*: int
    maxArgs*: int          ## -1 = variadic
    isAggregate*: bool
    isDeterministic*: bool

const FunctionTable* = [
  FuncSig(name: "count", minArgs: 0, maxArgs: 1, isAggregate: true, isDeterministic: true),
  FuncSig(name: "sum", minArgs: 1, maxArgs: 1, isAggregate: true, isDeterministic: true),
  FuncSig(name: "total", minArgs: 1, maxArgs: 1, isAggregate: true, isDeterministic: true),
  FuncSig(name: "avg", minArgs: 1, maxArgs: 1, isAggregate: true, isDeterministic: true),
  FuncSig(name: "min", minArgs: 1, maxArgs: 1, isAggregate: true, isDeterministic: true),
  FuncSig(name: "max", minArgs: 1, maxArgs: 1, isAggregate: true, isDeterministic: true),
  FuncSig(name: "group_concat", minArgs: 1, maxArgs: 2, isAggregate: true, isDeterministic: true),
  FuncSig(name: "abs", minArgs: 1, maxArgs: 1, isAggregate: false, isDeterministic: true),
  FuncSig(name: "length", minArgs: 1, maxArgs: 1, isAggregate: false, isDeterministic: true),
  FuncSig(name: "lower", minArgs: 1, maxArgs: 1, isAggregate: false, isDeterministic: true),
  FuncSig(name: "upper", minArgs: 1, maxArgs: 1, isAggregate: false, isDeterministic: true),
  FuncSig(name: "substr", minArgs: 2, maxArgs: 3, isAggregate: false, isDeterministic: true),
  FuncSig(name: "replace", minArgs: 3, maxArgs: 3, isAggregate: false, isDeterministic: true),
  FuncSig(name: "trim", minArgs: 1, maxArgs: 2, isAggregate: false, isDeterministic: true),
  FuncSig(name: "ltrim", minArgs: 1, maxArgs: 2, isAggregate: false, isDeterministic: true),
  FuncSig(name: "rtrim", minArgs: 1, maxArgs: 2, isAggregate: false, isDeterministic: true),
  FuncSig(name: "round", minArgs: 1, maxArgs: 2, isAggregate: false, isDeterministic: true),
  FuncSig(name: "coalesce", minArgs: 1, maxArgs: -1, isAggregate: false, isDeterministic: true),
  FuncSig(name: "ifnull", minArgs: 2, maxArgs: 2, isAggregate: false, isDeterministic: true),
  FuncSig(name: "nullif", minArgs: 2, maxArgs: 2, isAggregate: false, isDeterministic: true),
  FuncSig(name: "typeof", minArgs: 1, maxArgs: 1, isAggregate: false, isDeterministic: true),
  FuncSig(name: "hex", minArgs: 1, maxArgs: 1, isAggregate: false, isDeterministic: true),
  FuncSig(name: "instr", minArgs: 2, maxArgs: 2, isAggregate: false, isDeterministic: true),
  FuncSig(name: "printf", minArgs: 1, maxArgs: -1, isAggregate: false, isDeterministic: true),
  FuncSig(name: "quote", minArgs: 1, maxArgs: 1, isAggregate: false, isDeterministic: true),
  FuncSig(name: "now", minArgs: 0, maxArgs: 0, isAggregate: false, isDeterministic: false),
  FuncSig(name: "date_now", minArgs: 0, maxArgs: 0, isAggregate: false, isDeterministic: false),
  FuncSig(name: "time_now", minArgs: 0, maxArgs: 0, isAggregate: false, isDeterministic: false),
  FuncSig(name: "unixepoch", minArgs: 0, maxArgs: 0, isAggregate: false, isDeterministic: false),
  FuncSig(name: "random", minArgs: 0, maxArgs: 0, isAggregate: false, isDeterministic: false),
  FuncSig(name: "rowid", minArgs: 0, maxArgs: 0, isAggregate: false, isDeterministic: true),
]

proc findFunc*(name: string): (bool, FuncSig) =
  let n = name.toLowerAscii()
  for f in FunctionTable:
    if f.name == n: return (true, f)
  (false, FuncSig())

proc isAggregateName*(name: string): bool =
  let (ok, f) = findFunc(name)
  ok and f.isAggregate

# ---------------------------------------------------------------------------
# Scalar functions
# ---------------------------------------------------------------------------

func likeMatch(s, pat: string; esc: char): bool =
  ## Iterative LIKE matcher with backtracking on `%` only — O(n·m) worst case,
  ## O(n) typical, no regex engine (regex is a DoS surface and costs code size).
  var si = 0
  var pi = 0
  var starP = -1
  var starS = 0
  while si < s.len:
    if pi < pat.len:
      let pc = pat[pi]
      if pc == esc and pi + 1 < pat.len:
        if s[si] == pat[pi + 1]:
          inc si
          pi += 2
          continue
      elif pc == '%':
        starP = pi
        starS = si
        inc pi
        continue
      elif pc == '_' or (pc != '%' and pc != '_' and s[si] == pc):
        inc si
        inc pi
        continue
      elif s[si].toLowerAscii() == pc.toLowerAscii():
        inc si
        inc pi
        continue
    if starP >= 0:
      pi = starP + 1
      inc starS
      si = starS
    else:
      return false
  while pi < pat.len and pat[pi] == '%': inc pi
  pi == pat.len

func globMatch(s, pat: string): bool =
  var si = 0
  var pi = 0
  var starP = -1
  var starS = 0
  while si < s.len:
    var advance = false
    if pi < pat.len:
      let pc = pat[pi]
      if pc == '*':
        starP = pi
        starS = si
        inc pi
        continue
      elif pc == '?':
        inc si
        inc pi
        continue
      elif pc == '[':
        var k = pi + 1
        var neg = false
        if k < pat.len and (pat[k] == '^' or pat[k] == '!'):
          neg = true
          inc k
        var hit = false
        while k < pat.len and pat[k] != ']':
          if k + 2 < pat.len and pat[k + 1] == '-' and pat[k + 2] != ']':
            if s[si] >= pat[k] and s[si] <= pat[k + 2]: hit = true
            k += 3
          else:
            if s[si] == pat[k]: hit = true
            inc k
        if k < pat.len: inc k
        if hit != neg:
          inc si
          pi = k
          continue
        elif starP >= 0:
          pi = starP + 1
          inc starS
          si = starS
          continue
        else:
          return false
      elif s[si] == pc:
        inc si
        inc pi
        continue
    if starP >= 0:
      pi = starP + 1
      inc starS
      si = starS
    else:
      return false
  while pi < pat.len and pat[pi] == '*': inc pi
  pi == pat.len

func sqlLike*(s, pat: string; esc = '\\'): bool = likeMatch(s, pat, esc)
func sqlGlob*(s, pat: string): bool = globMatch(s, pat)

func hexOf*(s: string): string =
  const hexDigits = "0123456789ABCDEF"
  result = newStringOfCap(s.len * 2)
  for ch in s:
    result.add hexDigits[ord(ch) shr 4]
    result.add hexDigits[ord(ch) and 15]

func unhexOf*(s: string): string =
  if s.len mod 2 != 0: return ""
  result = newStringOfCap(s.len div 2)
  var i = 0
  while i + 1 < s.len:
    proc hv(c: char): int =
      if c in Digits: ord(c) - ord('0')
      elif c in {'a'..'f'}: ord(c) - ord('a') + 10
      elif c in {'A'..'F'}: ord(c) - ord('A') + 10
      else: -1
    let a = hv(s[i])
    let b = hv(s[i + 1])
    if a < 0 or b < 0: return ""
    result.add char((a shl 4) or b)
    i += 2

func trimSet(s, chars: string; left, right: bool): string =
  var a = 0
  var b = s.len
  if left:
    while a < b and s[a] in chars: inc a
  if right:
    while b > a and s[b - 1] in chars: dec b
  s[a ..< b]

func fmtFloat(v: float64; prec: int): string =
  ## Locale-independent fixed formatting.
  when defined(foccilMinimalFloat):
    # Pure arithmetic: no libm dependency on the freestanding targets.
    if v != v: return "NULL"
    var neg = v < 0.0
    var x = if neg: -v else: v
    let mult = pow10F(prec)
    let scaledInt = int64(roundF(x * mult))
    var digits = $scaledInt
    if prec > 0:
      while digits.len <= prec: digits = "0" & digits
      digits = digits[0 ..< digits.len - prec] & "." & digits[digits.len - prec .. ^1]
      while digits.len > 1 and digits[^1] == '0' and digits[^2] != '.': digits.setLen(digits.len - 1)
    return (if neg: "-" else: "") & digits
  if v != v: return "NULL"
  if prec <= 0: return $int64(roundF(v))
  var scale = 1.0
  for _ in 0 ..< prec: scale *= 10.0
  let scaled = roundF(v * scale) / scale
  var s = formatFloat(scaled, ffDecimal, prec)
  # trim trailing zeros but keep at least one decimal digit
  while s.len > 1 and s[^1] == '0' and s[^2] != '.': s.setLen(s.len - 1)
  s

proc callScalar*(name: string; args: openArray[Value]; nowIso: string;
                 randState: var uint64): Value

proc xorshift(state: var uint64): uint64 =
  ## Deterministic, allocation-free PRNG. Not for crypto (documented);
  ## crypto-grade randomness is provided by the OS entropy source at the API
  ## layer, never by SQL itself — SQL must not be able to weaken a key.
  var x = state
  x = x xor (x shl 13)
  x = x xor (x shr 7)
  x = x xor (x shl 17)
  state = x
  x

proc callScalar*(name: string; args: openArray[Value]; nowIso: string;
                 randState: var uint64): Value =
  template a(i: int): Value = args[i]
  case name
  of "abs":
    if a(0).kind == vkNull: return nullValue()
    case a(0).kind
    of vkInt:
      if a(0).i == low(int64): return realValue(9.2233720368547758e18)
      intValue(abs(a(0).i))
    of vkReal: realValue(abs(a(0).r))
    else: realValue(abs(a(0).asFloat))
  of "length":
    case a(0).kind
    of vkNull: nullValue()
    of vkText: intValue(int64(a(0).t.len))
    of vkBlob: intValue(int64(a(0).bl.len))
    else: intValue(int64(a(0).toText.len))
  of "lower":
    if a(0).kind == vkNull: nullValue()
    else: textValue(a(0).toText.toLowerAscii())
  of "upper":
    if a(0).kind == vkNull: nullValue()
    else: textValue(a(0).toText.toUpperAscii())
  of "substr":
    if a(0).kind == vkNull: return nullValue()
    let s = a(0).toText
    var start = int(a(1).asInt)
    var cnt = if args.len > 2: int(a(2).asInt) else: high(int)
    if start < 0: start = s.len + start + 1
    if start < 1: start = 1
    var lo = start - 1
    if lo > s.len: lo = s.len
    if cnt < 0: cnt = 0
    let hi = min(s.len, lo + cnt)
    textValue(s[lo ..< hi])
  of "replace":
    if a(0).kind == vkNull or a(1).kind == vkNull or a(2).kind == vkNull:
      nullValue()
    else: textValue(a(0).toText.replace(a(1).toText, a(2).toText))
  of "trim", "ltrim", "rtrim":
    if a(0).kind == vkNull: return nullValue()
    let chars = if args.len > 1: a(1).toText else: " "
    textValue(trimSet(a(0).toText, chars, name != "rtrim", name != "ltrim"))
  of "round":
    if a(0).kind == vkNull: return nullValue()
    let prec = if args.len > 1: int(a(1).asInt) else: 0
    if a(0).kind == vkInt and prec == 0: intValue(a(0).i)
    else:
      let m = pow10F(prec)
      realValue(roundF(a(0).asFloat * m) / m)
  of "coalesce":
    for v in args:
      if v.kind != vkNull: return v
    nullValue()
  of "ifnull":
    if a(0).kind != vkNull: a(0)
    else: a(1)
  of "nullif":
    if a(0).kind == vkNull or a(1).kind == vkNull: a(0)
    elif compare(a(0), a(1)) == 0: nullValue()
    else: a(0)
  of "typeof":
    case a(0).kind
    of vkNull: textValue("null")
    of vkInt: textValue("integer")
    of vkReal: textValue("real")
    of vkBool: textValue("boolean")
    of vkText: textValue("text")
    of vkBlob: textValue("blob")
  of "hex":
    case a(0).kind
    of vkNull: textValue("")
    of vkBlob:
      var s = newString(a(0).bl.len)
      for i, b in a(0).bl: s[i] = char(b)
      textValue(hexOf(s))
    else: textValue(hexOf(a(0).toText))
  of "instr":
    if a(0).kind == vkNull or a(1).kind == vkNull: nullValue()
    else:
      let idx = a(0).toText.find(a(1).toText)
      intValue(if idx < 0: 0'i64 else: int64(idx + 1))
  of "printf":
    if a(0).kind == vkNull: return nullValue()
    var fmt = a(0).toText
    var argi = 1
    var res = ""
    var i = 0
    while i < fmt.len:
      if fmt[i] == '%' and i + 1 < fmt.len:
        inc i
        case fmt[i]
        of '%': res.add '%'
        of 'd', 'i':
          if argi < args.len: res.add $args[argi].asInt
          inc argi
        of 's':
          if argi < args.len: res.add args[argi].toText
          inc argi
        of 'f':
          if argi < args.len: res.add fmtFloat(args[argi].asFloat, 6)
          inc argi
        else:
          res.add '%'
          res.add fmt[i]
        inc i
      else:
        res.add fmt[i]
        inc i
    textValue(res)
  of "quote":
    case a(0).kind
    of vkNull: textValue("NULL")
    of vkText: textValue("'" & a(0).t.replace("'", "''") & "'")
    of vkBlob:
      var s = newString(a(0).bl.len)
      for i, b in a(0).bl: s[i] = char(b)
      textValue("X'" & hexOf(s) & "'")
    else: textValue(a(0).toText)
  of "now": textValue(nowIso)
  of "date_now": textValue(if nowIso.len >= 10: nowIso[0 ..< 10] else: nowIso)
  of "time_now": textValue(if nowIso.len >= 19: nowIso[11 ..< 19] else: nowIso)
  of "unixepoch":
    when defined(foccilNoClock):
      intValue(0)
    else:
      try: intValue(int64(parse(nowIso, "yyyy-MM-dd'T'HH:mm:ss'Z'", utc()).toTime.toUnix))
      except CatchableError: intValue(0)
  of "random":
    let r = xorshift(randState)
    intValue(int64(r and 0x7FFF_FFFF_FFFF_FFFF'u64))
  else:
    nullValue()
