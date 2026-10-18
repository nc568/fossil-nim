## Fuzz test for delta - 100 random cases

import std/[random, strutils]
import ../src/fossil/types
import ../src/fossil/delta/delta

proc randomString(rnd: var Rand, maxLen: int): string =
  let len = rnd.rand(maxLen)
  result = newString(len)
  for i in 0..<len:
    result[i] = char(rnd.rand(255))

proc testDeltaFuzz() =
  var rnd = initRand(42)
  var passed = 0
  var failed = 0
  for i in 0..<100:
    let baseLen = rnd.rand(5000) + 10
    let base = randomString(rnd, baseLen)
    # Create modified version: 70% same, 30% random changes
    var target = base
    let numEdits = rnd.rand(20) + 1
    for _ in 0..<numEdits:
      let op = rnd.rand(2)
      if op==0 and target.len>0:
        # Delete
        let pos = rnd.rand(target.len-1)
        let delLen = min(rnd.rand(10)+1, target.len-pos)
        target = target[0..<pos] & target[pos+delLen..^1]
      elif op==1:
        # Insert
        let pos = if target.len>0: rnd.rand(target.len) else: 0
        let ins = randomString(rnd, rnd.rand(20)+1)
        target = target[0..<pos] & ins & target[pos..^1]
      else:
        # Change
        if target.len>0:
          let pos = rnd.rand(target.len-1)
          target[pos] = char(rnd.rand(255))
    let baseBlob = newBlob(base)
    let targetBlob = newBlob(target)
    let deltaRes = deltaCreate(baseBlob, targetBlob, true)
    if deltaRes.isErr:
      echo "Delta create failed at iteration ", i, ": ", deltaRes.error.msg
      inc failed
      continue
    let delta = deltaRes.value
    let appliedRes = deltaApply(baseBlob, delta)
    if appliedRes.isErr:
      echo "Delta apply failed at iteration ", i, ": ", appliedRes.error.msg
      inc failed
      continue
    if appliedRes.value.data != target:
      echo "Delta roundtrip mismatch at iteration ", i, " base len=", base.len, " target len=", target.len, " delta len=", deltaOutputSize(delta)
      inc failed
    else:
      inc passed
  echo "fuzz_delta: passed=", passed, " failed=", failed, " total=100"
  assert failed==0, "fuzz_delta failed: " & $failed
  echo "fuzz_delta OK"

when isMainModule:
  testDeltaFuzz()
