## sharks_crosscheck.nim -- the judge of the "does it look the same everywhere"
## question for examples/sharks.nim.
##
## `tools/sharks_run.sh <backend> <outdir>` builds and runs the app on one
## backend and writes `<outdir>/<backend>.digest`, a single `SHARKS_DIGEST`
## line. This tool reads every digest in a directory, compares all of them
## against each other and against `tests/sharks_digest_golden.txt`, and fails
## loudly -- with a GitHub annotation, which is the only part of a CI log this
## project can actually read back -- when anything disagrees.
##
##   nim c --mm:arc -r tools/sharks_crosscheck.nim \
##       --dir=/tmp/sharks --require=native,html,canvas,jsdom
##
## Which fields are gated and which are only reported, and why, is documented
## at the top of the golden file.

import std/[algorithm, os, strutils, tables]

const
  GatedKeys = ["frames", "w", "h", "rects", "lines", "texts", "blits",
               "cells", "bakeRects", "blitOk", "geom", "bake", "txt", "sc"]
  ReportedKeys = ["pos"]
  ## The order the report prints digests in, so two runs of CI are readable
  ## side by side instead of in whatever order the filesystem listed them.
  PreferredOrder = ["native", "x11", "cocoa", "winapi", "gtk4", "sdl2", "sdl3",
                    "html", "canvas", "jsdom"]

type Digest = object
  backend: string   ## the file name the run was filed under
  reported: string  ## what the app itself said it was compiled for
  source: string
  fields: Table[string, string]

proc argValue(flag: string; default: string): string =
  ## `paramStrs()` does not exist in Nim 2.2, so walk `paramStr` by hand.
  let prefix = "--" & flag & "="
  for i in 1 .. paramCount():
    let a = paramStr(i)
    if a.startsWith(prefix): return a[prefix.len .. ^1]
  default

proc digestRank(d: Digest): int =
  let i = PreferredOrder.find(d.backend)
  if i >= 0: i else: PreferredOrder.len

proc cmpDigest(a, b: Digest): int =
  let r = cmp(digestRank(a), digestRank(b))
  if r != 0: r else: cmp(a.backend, b.backend)

proc parseDigestLine(line, source: string): Digest =
  result.fields = initTable[string, string]()
  result.source = source
  result.backend = "?"
  let parts = line.split(' ')
  for p in parts:
    let eq = p.find('=')
    if eq <= 0: continue
    let k = p[0 ..< eq]
    let v = p[eq + 1 .. ^1]
    result.fields[k] = v
    if k == "backend": result.backend = v

proc expectedSelfReport(stem: string): seq[string] =
  ## What the app's own `backend=` field must say for a digest file with this
  ## name. `native` is whatever the OS picks by itself, and `jsdom` is the
  ## html backend compiled to JavaScript, so neither maps to its own name.
  case stem
  of "native": @["x11", "cocoa", "winapi"]
  of "jsdom": @["html"]
  else: @[stem]

proc loadGolden(path: string): Table[string, string] =
  result = initTable[string, string]()
  if not fileExists(path):
    quit "sharks_crosscheck: golden digest not found: " & path, 1
  # `readLines(n)` raises EOFError on a file shorter than n, and the golden
  # file is a page, not a log.
  for raw in splitLines(readFile(path)):
    let line = raw.strip
    if line.len == 0 or line.startsWith("#"): continue
    let eq = line.find('=')
    if eq <= 0: continue
    result[line[0 ..< eq]] = line[eq + 1 .. ^1]

proc main() =
  let dir = argValue("dir", "")
  let goldenPath = argValue("golden", "tests/sharks_digest_golden.txt")
  let requireRaw = argValue("require", "")
  let inGithub = getEnv("GITHUB_ACTIONS", "") == "true"

  if dir.len == 0 or not dirExists(dir):
    quit "usage: sharks_crosscheck --dir=<digest dir> [--golden=PATH] " &
         "[--require=a,b,c]", 2

  let golden = loadGolden(goldenPath)

  var digests: seq[Digest] = @[]
  for kind, path in walkDir(dir):
    if kind != pcFile or not path.endsWith(".digest"): continue
    let body = readFile(path).strip
    if body.len == 0:
      echo "  EMPTY  ", path, " (a backend that printed nothing is not a pass)"
      continue
    var found = false
    for line in body.splitLines:
      if line.startsWith("SHARKS_DIGEST "):
        var d = parseDigestLine(line, path)
        # The file name is the identity: `sharks_run.sh jsdom` produces a page
        # whose app honestly reports `backend=html`, because that is the
        # backend it was compiled with. What the app reports is a claim about
        # the file name, and the two are checked against each other below.
        d.reported = d.backend
        d.backend = splitFile(path).name
        digests.add d
        found = true
        break
    if not found:
      echo "  NODIGEST  ", path
      digests.add Digest(backend: splitFile(path).name, source: path,
                         fields: initTable[string, string]())

  # Stable, readable order.
  digests.sort(cmpDigest)

  echo ""
  echo "======================================================================"
  echo " sharks.nim -- one scene, every backend on this machine"
  echo "======================================================================"
  echo " golden: ", goldenPath
  echo ""

  # Header
  proc pad(s: string; n: int): string =
    if s.len >= n: s[0 ..< n] else: s & repeat(' ', n - s.len)
  echo "  ", pad("run as", 10), pad("app says", 9), pad("frames", 7), pad("rects", 8),
       pad("geom", 10), pad("bake", 10), pad("sc", 10), pad("txt", 10),
       pad("pos", 10), " verdict"
  echo "  ", repeat('-', 105)

  var failures: seq[string] = @[]
  var ok = 0
  for d in digests:
    if d.fields.len == 0:
      echo "  ", pad(d.backend, 10), pad("-", 9), "NO DIGEST"
      failures.add d.backend & ": produced no SHARKS_DIGEST line"
      continue
    var bad: seq[string] = @[]
    let allowed = expectedSelfReport(d.backend)
    if d.reported.len > 0 and d.reported notin allowed:
      bad.add "reports backend=" & d.reported & " but was run as " & d.backend &
        " (expected one of " & allowed.join(", ") & ")"
    for k in GatedKeys:
      let got = d.fields.getOrDefault(k, "<missing>")
      let want = golden.getOrDefault(k, "<not in golden>")
      if got != want:
        bad.add k & "=" & got & " (golden " & want & ")"
    let verdict = if bad.len == 0: "MATCH" else: "DIFFERS"
    echo "  ", pad(d.backend, 10),
         pad(d.reported, 9),
         pad(d.fields.getOrDefault("frames", "-"), 7),
         pad(d.fields.getOrDefault("rects", "-"), 8),
         pad(d.fields.getOrDefault("geom", "-"), 10),
         pad(d.fields.getOrDefault("bake", "-"), 10),
         pad(d.fields.getOrDefault("sc", "-"), 10),
         pad(d.fields.getOrDefault("txt", "-"), 10),
         pad(d.fields.getOrDefault("pos", "-"), 10),
         " ", verdict
    if bad.len == 0:
      inc ok
    else:
      for b in bad:
        failures.add d.backend & ": " & b
        if inGithub:
          echo "::error file=examples/sharks.nim,title=sharks digest differs on " &
            d.backend & "::" & d.backend & " " & b & " -- see " &
            goldenPath & "; every backend must draw the same scene"
  echo ""

  # Reported-only fields, side by side: two backends on one machine that
  # disagree here have a real problem, two machines that disagree do not.
  echo "  reported, not gated (font metrics differ per platform by design):"
  for d in digests:
    if d.fields.len == 0: continue
    var line = "    " & pad(d.backend, 10)
    for k in ReportedKeys:
      line.add k & "=" & d.fields.getOrDefault(k, "-") & "  "
    echo line
  echo ""

  # A backend that was supposed to run and did not is a failure, not a skip:
  # silently dropping one is exactly how a whole platform stops being tested.
  if requireRaw.len > 0:
    let required = requireRaw.split(',')
    for r in required:
      let name = r.strip
      if name.len == 0: continue
      var present = false
      for d in digests:
        if d.backend == name and d.fields.len > 0: present = true
      if not present:
        failures.add "required backend produced no digest: " & name
        if inGithub:
          echo "::error title=sharks backend missing::" & name &
            " was required but produced no digest"

  echo "  ", $ok, " of ", $digests.len, " backends match the golden digest"
  if failures.len > 0:
    echo ""
    for f in failures:
      echo "  FAIL  ", f
    quit 1
  echo "  OK    every backend on this machine drew the same scene"

main()
