## wasm32 bridge.
##
## The module is built with `--os:standalone --cpu:wasm32 --mm:arc` and links
## against wasi-libc (see tools/db/wasm/build.sh). It performs **no I/O**: the host
## drives it through three exports and copies the result immediately.
##
## Export surface (deliberately tiny — every export is attack surface):
##   foccil_version()             -> cstring
##   foccil_init()                -> void
##   foccil_exec(sql, params)     -> cstring (TSV payload, NUL terminated)
##   foccil_exec_n(sql, params, n)-> cstring (same, n = payload byte length)
##
## Wire format of a result payload (versioned by the leading field):
##   "1\tOK\t<cols joined by \t>\t<rows>\n<row>\n<row>…"
##   "1\tERR\t<CODE>\t<message>"
## Cells are escaped: \\ -> \\\\ , \t -> \\t , \n -> \\n.

import std/strutils
import ../db/api

var gDb: Db
var gOut: string

proc esc(s: string): string =
  ## Escaping is done once, on the way out, so the engine never has to know
  ## about the wire format.
  result = newStringOfCap(s.len + 8)
  for ch in s:
    case ch
    of '\\': result.add "\\\\"
    of '\t': result.add "\\t"
    of '\n': result.add "\\n"
    else: result.add ch

proc foccil_version*(): cstring {.exportc, cdecl.} =
  cstring("foccil-db/0.1.0-wasm")

proc foccil_init*() {.exportc, cdecl.} =
  gDb = openMemory()
  gOut = ""

proc foccil_exec*(sql: cstring; params: cstring): cstring {.exportc, cdecl.} =
  ## `params` is a `\t`-separated list of `type:value` cells (empty = none):
  ##   i:42  r:3.5  s:text  b:hexbytes  n:
  gOut = ""
  try:
    if gDb == nil: gDb = openMemory()
    var ps: Params = @[]
    let p = $params
    if p.len > 0:
      for cell in p.split('\t'):
        if cell.len < 2: continue
        let payload = cell[2 .. ^1]
        case cell[0]
        of 'i': ps.add intValue(int64(parseInt(payload)))
        of 'r': ps.add realValue(parseFloat(payload))
        of 's': ps.add textValue(payload)
        of 'b':
          var b: seq[byte] = @[]
          var i = 0
          while i + 1 < payload.len:
            b.add byte(parseHexInt(payload[i .. i + 1]))
            i += 2
          ps.add blobValue(b)
        else: ps.add nullValue()
    let rs = gDb.execute($sql, ps)
    var parts: seq[string] = @[]
    parts.add "1"
    parts.add "OK"
    var cols: seq[string] = @[]
    for c in rs.cols: cols.add esc(c)
    parts.add cols.join("\t")
    parts.add $rs.rows.len
    for r in rs.rows:
      var cells: seq[string] = @[]
      for v in r:
        case v.kind
        of vkNull: cells.add "n:"
        of vkInt: cells.add "i:" & $v.i
        of vkReal: cells.add "r:" & $v.r
        of vkBool: cells.add "i:" & (if v.bo: "1" else: "0")
        of vkText: cells.add "s:" & esc(v.t)
        of vkBlob: cells.add "b:" & $v.bl.len
      parts.add cells.join("\t")
    gOut = parts.join("\n")
  except DbError as e:
    gOut = "1\nERR\n" & e.code.codeName & "\n" & esc(e.msg)
  except CatchableError as e:
    # Never let an unexpected Nim exception escape into the host: an uncaught
    # exception in a wasm export traps the whole instance.
    gOut = "1\nERR\nINTERNAL\n" & esc(e.msg)
  result = gOut.cstring

proc foccil_exec_n*(sql: cstring; params: cstring): int32 {.exportc, cdecl.} =
  ## Same as `foccil_exec` but returns the payload length, so the host can copy
  ## exactly N bytes and does not need to scan for the NUL.
  discard foccil_exec(sql, params)
  int32(gOut.len)

proc foccil_last_len*(): int32 {.exportc, cdecl.} = int32(gOut.len)

proc foccil_last_ptr*(): cstring {.exportc, cdecl.} =
  ## Pointer to the last payload. The buffer is owned by the module and is
  ## valid until the next `foccil_exec` — the host must copy it out first.
  ## (Returning `cstring` exports as a raw i32 pointer without any `cast`.)
  gOut.cstring
