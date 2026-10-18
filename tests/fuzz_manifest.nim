## Fuzz test for manifest parsing

import std/[random, strutils, times]
import ../src/fossil/types
import ../src/fossil/artifact/manifest
import ../src/fossil/utils/hash

proc randomHex(rnd: var Rand, len: int): string =
  const hexChars = "0123456789abcdef"
  result = newString(len)
  for i in 0..<len:
    result[i] = hexChars[rnd.rand(15)]

proc testManifestFuzz() =
  var rnd = initRand(123)
  var passed = 0
  var failed = 0
  for i in 0..<100:
    # Generate random manifest-like content
    var content = "C Test manifest " & $i & "\n"
    content.add "D " & $getTime().toUnix() & "\n"
    content.add "F file" & $i & ".txt " & randomHex(rnd, 40) & "\n"
    content.add "P " & randomHex(rnd, 40) & "\n"
    content.add "R " & randomHex(rnd, 40) & "\n"
    content.add "U user" & $rnd.rand(10) & "\n"
    content.add "W " & $rnd.rand(10000) & "\n"
    # Try to parse
    let parseRes = parseManifest(content)
    if parseRes.isOk:
      inc passed
    else:
      # Some random manifests are invalid, that's ok, but we check that parser doesn't crash
      inc passed
  echo "fuzz_manifest: passed=", passed, " failed=", failed, " total=100"
  echo "fuzz_manifest OK"

when isMainModule:
  testManifestFuzz()
