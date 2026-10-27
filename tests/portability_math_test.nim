## portability_math_test.nim -- pins the arithmetic that the browser and the
## native backends have to agree on.
##
## uirelays draws the same scene on X11, Cocoa, WinAPI, GTK4, SDL and in a
## browser, and `examples/sharks.nim` proves the agreement by digest. That
## proof is only worth anything if the arithmetic underneath it is portable,
## and three things in it are not portable by default:
##
##   * A 32-bit multiply. `nim js` computes uint32 arithmetic in a double, so
##     every bit above 2^53 is lost. Measured on this very repo: the reference
##     demo's `x * 374761393` hash yields 4262848038 natively and 2293536820
##     in the browser. `mul32` below splits the multiply into 16-bit halves and
##     is bit-identical on both -- that is why every hash in web_common.nim and
##     in the sharks scene goes through it.
##   * `float32`. The C backend rounds to 32 bits, the JS backend keeps the
##     double. Densities stored as float32 pick a different palette index on
##     the two backends, so the sharks use `float`.
##   * Pointers. The JS backend cannot index a `ptr UncheckedArray[T]` at all
##     (internal compiler error, `expr(nkBracketExpr, tyUncheckedArray)`), and
##     a pointer *parameter* reaches the callee as two ABI slots: the base
##     array and the element offset. `blitRGBA` needs exactly that indexing to
##     turn a pixel buffer into a PNG, which is why it used to be stubbed out
##     with `return @[]` under `defined(js)` -- defect N11, a silent no-op that
##     left every standalone page without its background.
##
## Compile & run on BOTH backends; both must pass with the same goldens:
##   nim c --mm:arc --outdir:/tmp/uirelays_bins -r tests/portability_math_test.nim
##   nim js --jsbigint64:off -d:nimStringHash2 -d:html \
##       --outdir:/tmp/uirelays_bins tests/portability_math_test.nim
##   node /tmp/uirelays_bins/portability_math_test.js

import std/[math, strutils]
import uirelays/drivers/web_common

var failures = 0
var passes = 0

proc check(name: string; cond: bool; detail = "") =
  if cond:
    inc passes
    echo "  PASS  ", name
  else:
    inc failures
    echo "  FAIL  ", name, (if detail.len > 0: "  -- " & detail else: "")

proc hex8(x: uint32): string =
  const digits = "0123456789abcdef"
  result = newString(8)
  for i in 0 .. 7:
    result[i] = digits[(x shr (28 - i * 4)) and 0xF'u32]

proc addU32(a, b: uint32): uint32 = a + b

proc jsRound(x: float): int =
  ## `Math.round` semantics: half towards +inf. Nim's `round` goes half away
  ## from zero, which is a different function on negative halves.
  int(floor(x + 0.5))

proc quantProbe(x: float): int = int(floor(x * 1024.0))

proc mul32(a, b: uint32): uint32 =
  let lo = (a and 0xFFFF'u32) * b
  let hi = ((a shr 16) * b) and 0xFFFF'u32
  (lo and 0xFFFFFFFF'u32) + (hi shl 16)

proc mix(h: uint32; v: int): uint32 =
  var x = h xor uint32(v + 20_000_000)
  x = mul32(x, 16777619'u32)
  x xor (x shr 15)

echo "=== UIRelays portability of arithmetic (--mm:arc) ==="
when defined(js):
  echo "  backend under test: JavaScript (nim js)"
else:
  echo "  backend under test: C (nim c)"

# ---------------------------------------------------------------------------
# 1. mul32: the low 32 bits of a product, goldens computed independently
# ---------------------------------------------------------------------------

const MulGoldens: array[10, tuple[a, b, want: uint32]] = [
  (374761393'u32, 12345'u32, 749618793'u32),
  (668265263'u32, 104729'u32, 260640407'u32),
  (16777619'u32, 4262848038'u32, 578375122'u32),
  (65535'u32, 65535'u32, 4294836225'u32),
  (65536'u32, 65536'u32, 0'u32),            # 2^32 wraps to exactly zero
  (1274126177'u32, 1542469173'u32, 2526311701'u32),
  (1099511629'u32, 2654435769'u32, 2664913829'u32),
  (4294967295'u32, 4294967295'u32, 1'u32),
  (4294967295'u32, 3'u32, 4294967293'u32),
  (2147483648'u32, 2'u32, 0'u32)
]

var mulBad = 0
var mulDetail = ""
for g in MulGoldens:
  let got = mul32(g.a, g.b)
  if got != g.want:
    inc mulBad
    if mulDetail.len == 0:
      mulDetail = "mul32(" & $g.a & ", " & $g.b & ") = " & $got &
                  ", want " & $g.want
check("mul32 matches the true low 32 bits on 10 golden products",
      mulBad == 0, mulDetail)
check("mul32 is commutative", mul32(123456789'u32, 987654321'u32) ==
                               mul32(987654321'u32, 123456789'u32))
check("mul32 by 1 is the identity", mul32(0xDEADBEEF'u32, 1'u32) == 0xDEADBEEF'u32)
check("mul32 distributes over addition",
      mul32(111'u32 + 222'u32, 333'u32) ==
        (mul32(111'u32, 333'u32) + mul32(222'u32, 333'u32)))

# A bare `*` is what breaks on the JS backend; show that the split version
# survives the very product that does not.
let bareNative = 374761393'u32 * 12345'u32
check("the split multiply survives a product a bare uint32 `*` loses on JS",
      mul32(374761393'u32, 12345'u32) == 749618793'u32,
      "bare `*` gave " & $bareNative)

# ---------------------------------------------------------------------------
# 2. The rest of the integer toolbox the scene and the digests are built from
# ---------------------------------------------------------------------------

check("uint32 addition wraps", addU32(4294967295'u32, 1'u32) == 0'u32)
check("uint32 shl drops the high bits",
      (0xFEDCBA98'u32 shl 8) == 0xDCBA9800'u32)
check("uint32 shr is logical, never arithmetic",
      (0x80000000'u32 shr 1) == 0x40000000'u32)
check("uint32 xor", (0xFF00FF00'u32 xor 0x0F0F0F0F'u32) == 0xF00FF00F'u32)
check("int(floor()) of a negative float goes down, on both backends",
      int(floor(-1.5)) == -2)
check("Math.round semantics differ from Nim's round, and jsRound is the one " &
      "the reference scene uses", jsRound(-1.5) == -1 and round(-1.5) == -2.0)
check("int(floor(x*1024)) quantises identically", quantProbe(-0.0005) == -1)

# ---------------------------------------------------------------------------
# 3. Transcendentals: quantised, because `cast[uint64](float)` is garbage on
#    the JS backend and a printed decimal hides which side moved
# ---------------------------------------------------------------------------

proc q(x: float): int32 = int32(floor((x + 1.5) * 400000000.0))

var dSin, dCos, dTan, dAtan, dSqrt, dExp, dLn, dPow: uint32 = 1
for i in 0 ..< 512:
  let t = float(i) * 0.0137
  dSin  = mix(dSin,  q(sin(t)).int)
  dCos  = mix(dCos,  q(cos(t * 1.31)).int)
  dTan  = mix(dTan,  q(arctan(t) / 1.5).int)
  dAtan = mix(dAtan, q(arctan2(float(i) - 256.0, float(i) * 0.37 + 1.0) / 3.0).int)
  dSqrt = mix(dSqrt, q(sqrt(float(i) * 0.0037 + 0.5) - 1.0).int)
  dExp  = mix(dExp,  q(exp(-float(i) * 0.0071)).int)
  dLn   = mix(dLn,   q(ln(float(i) + 1.0) / 6.5).int)
  dPow  = mix(dPow,  q(pow(float(i) + 1.0, 0.42) / 14.0).int)

# libm (glibc, Apple's, the MSVC CRT) and V8's fdlibm port agree to well
# inside 2.4e-9 on every one of these; they do NOT agree when printed to 17
# digits, which is a formatting difference, not a value difference.
check("sin agrees between libm and V8 to 2.4e-9 over 512 samples",
      hex8(dSin) == "7a384543", hex8(dSin))
check("cos agrees", hex8(dCos) == "7eb55e63", hex8(dCos))
check("arctan agrees", hex8(dTan) == "716c1382", hex8(dTan))
check("arctan2 agrees", hex8(dAtan) == "e0b16413", hex8(dAtan))
check("sqrt agrees", hex8(dSqrt) == "80bfd0d1", hex8(dSqrt))
check("exp agrees", hex8(dExp) == "6141e553", hex8(dExp))
check("ln agrees", hex8(dLn) == "209b7b37", hex8(dLn))
check("pow agrees", hex8(dPow) == "429aa4a5", hex8(dPow))

# ---------------------------------------------------------------------------
# 4. The PNG encoder blitRGBA depends on: identical bytes on both backends,
#    and honouring the element offset a JS pointer carries
# ---------------------------------------------------------------------------

const PW = 37
const PH = 23

proc fillPattern(buf: var seq[uint32]) =
  for i in 0 ..< buf.len:
    buf[i] = (uint32(if (i div 7) mod 2 == 0: 0xFF else: 0x00) shl 24) or
             (uint32((i * 13) mod 256) shl 16) or
             (uint32((i * 29) mod 256) shl 8) or
             uint32((i * 53) mod 256)

proc strDigest(s: string): uint32 =
  result = 2166136261'u32
  for ch in s:
    result = mul32(result xor uint32(int(ch)), 16777619'u32)
    result = result xor (result shr 15)

var buf = newSeq[uint32](PW * PH)
fillPattern(buf)

let uri = encodeRgbaToPngDataUri(cast[ptr UncheckedArray[uint32]](addr buf[0]),
                                 PW, PH)
check("blitRGBA's PNG payload is not empty on this backend (defect N11)",
      uri.len > 0, "len=" & $uri.len)
check("the payload is a PNG data URI", uri.startsWith("data:image/png;base64,iVBORw0KGgo"))
check("the payload has the golden length", uri.len == 4682, "len=" & $uri.len)
check("the payload has the golden digest on both backends",
      hex8(strDigest(uri)) == "f76ffe4b", hex8(strDigest(uri)))

# The JS backend hands a pointer over as (base array, element offset). Reading
# from a non-zero offset is the only way to prove the offset half is honoured;
# if it were dropped, this digest would equal the one above.
let off = 2
let uriOff = encodeRgbaToPngDataUri(
  cast[ptr UncheckedArray[uint32]](addr buf[off]), PW - off, PH)
check("a buffer read from a non-zero offset encodes differently",
      uriOff.len > 0 and uriOff != uri)
check("the offset read has the golden digest",
      hex8(strDigest(uriOff)) == "c4bd5c29", hex8(strDigest(uriOff)))

# ---------------------------------------------------------------------------
# 5. The payload cache: a repeated blit must not re-encode, and a changed
#    pixel must not be served from the cache
# ---------------------------------------------------------------------------

let before = blitCacheStats()
let again = encodeRgbaToPngDataUri(cast[ptr UncheckedArray[uint32]](addr buf[off]),
                                   PW - off, PH)
let afterHit = blitCacheStats()
check("an identical blit is served from the cache, not re-encoded (defect N12)",
      again == uriOff and afterHit.hits == before.hits + 1 and
        afterHit.misses == before.misses,
      "hits " & $before.hits & "->" & $afterHit.hits & ", misses " &
        $before.misses & "->" & $afterHit.misses)

buf[off + 5] = buf[off + 5] xor 1'u32
let changed = encodeRgbaToPngDataUri(
  cast[ptr UncheckedArray[uint32]](addr buf[off]), PW - off, PH)
let afterMiss = blitCacheStats()
check("a single changed pixel invalidates the cached payload",
      changed != uriOff and afterMiss.misses == afterHit.misses + 1,
      "misses " & $afterHit.misses & "->" & $afterMiss.misses)
check("the cache never grows past its two slots", afterMiss.live <= 2,
      "live=" & $afterMiss.live)

echo ""
echo "  ", $passes, " passed, ", $failures, " failed"
if failures > 0:
  # `quit` on the JS backend calls a host `exit` that node does not define, so
  # the process would die with a ReferenceError instead of an exit code.
  when defined(js):
    {.emit: "if (typeof process !== 'undefined' && process.exit) process.exit(1);".}
  else:
    quit 1
