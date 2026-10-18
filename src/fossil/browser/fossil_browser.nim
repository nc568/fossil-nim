## Fossil-Nim Browser Core Engine
## Compiles directly to JavaScript with `nim js -d:release`
## Exposes high-performance VCS, diff, delta, markdown and CDB storage to browser

import ../types
import ../delta/delta as fossilDelta
import ../vcs/diff as fossilDiff
import ../markdown/parser as mdParser
import ../storage/cdb_backend as cdb
import std/[strutils, tables]

var gCdbHandles: Table[int, cdb.CdbBackend]
var gNextHandle = 1

proc diffUnified*(textA, textB, fileName: cstring): cstring {.exportc: "fossilDiffUnified".} =
  let bA = newBlob($textA)
  let bB = newBlob($textB)
  let res = fossilDiff.diffBlobs(bA, bB, $fileName)
  cstring(fossilDiff.diffToUnified(res))

proc diffJson*(textA, textB, fileName: cstring): cstring {.exportc: "fossilDiffJson".} =
  let bA = newBlob($textA)
  let bB = newBlob($textB)
  let res = fossilDiff.diffBlobs(bA, bB, $fileName)
  cstring(fossilDiff.diffToJson(res))

proc deltaCreate*(src, target: cstring): cstring {.exportc: "fossilDeltaCreate".} =
  let bSrc = newBlob($src)
  let bTgt = newBlob($target)
  let res = fossilDelta.deltaCreate(bSrc, bTgt)
  if res.isOk:
    let enc = fossilDelta.deltaEncode(res.value)
    return cstring(enc.data)
  return cstring("")

proc deltaApply*(src, deltaStr: cstring): cstring {.exportc: "fossilDeltaApply".} =
  let bSrc = newBlob($src)
  let dec = fossilDelta.deltaDecode(newBlob($deltaStr))
  if dec.isOk:
    let res = fossilDelta.deltaApply(bSrc, dec.value)
    if res.isOk:
      return cstring(res.value.data)
  return cstring("")

proc markdownToHtml*(markdown: cstring): cstring {.exportc: "fossilMarkdownToHtml".} =
  cstring(mdParser.markdownToHtml($markdown))

# Pure-Nim In-Memory CDB in JS
proc cdbCreate*(): int {.exportc: "fossilCdbCreate".} =
  var b: cdb.CdbBackend
  discard b.openMemory()
  let handle = gNextHandle
  inc gNextHandle
  gCdbHandles[handle] = b
  return handle

proc cdbLoad*(data: cstring): int {.exportc: "fossilCdbLoad".} =
  var b: cdb.CdbBackend
  let res = b.openMemory($data)
  if res.isOk:
    let handle = gNextHandle
    inc gNextHandle
    gCdbHandles[handle] = b
    return handle
  return 0

proc cdbPut*(handle: int, key, value: cstring): bool {.exportc: "fossilCdbPut".} =
  if gCdbHandles.hasKey(handle):
    let res = gCdbHandles[handle].setMeta($key, $value)
    return res.isOk
  return false

proc cdbGet*(handle: int, key: cstring): cstring {.exportc: "fossilCdbGet".} =
  if gCdbHandles.hasKey(handle):
    let res = gCdbHandles[handle].getMeta($key)
    if res.isOk:
      return cstring(res.value)
  return nil

proc cdbSerialize*(handle: int): cstring {.exportc: "fossilCdbSerialize".} =
  if gCdbHandles.hasKey(handle):
    return cstring(gCdbHandles[handle].serializeMemory())
  return cstring("")

echo "🦖 Fossil-Nim Web Engine initialized!"

{.emit: """
var _fc = {
  diffUnified: fossilDiffUnified,
  diffJson: fossilDiffJson,
  deltaCreate: fossilDeltaCreate,
  deltaApply: fossilDeltaApply,
  markdownToHtml: fossilMarkdownToHtml,
  cdbCreate: fossilCdbCreate,
  cdbLoad: fossilCdbLoad,
  cdbPut: fossilCdbPut,
  cdbGet: fossilCdbGet,
  cdbSerialize: fossilCdbSerialize
};
if (typeof window !== 'undefined') {
  window.FossilCore = _fc;
}
if (typeof globalThis !== 'undefined') {
  globalThis.FossilCore = _fc;
}
""".}
