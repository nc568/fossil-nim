import ../src/fossil/delta/delta as fossilDelta
import ../src/fossil/vcs/diff as fossilDiff
import ../src/fossil/markdown/parser as mdParser
import ../src/fossil/types

echo "=== Fossil-Nim running on JS backend! ==="

let b1 = newBlob("hello\nworld\nversion 1\n")
let b2 = newBlob("hello\nbrowser\nversion 2\n")

# 1. Diff in JS
let diffRes = fossilDiff.diffBlobs(b1, b2, "file.txt")
let unified = fossilDiff.diffToUnified(diffRes)
echo "1. Unified Diff in JS:"
echo unified

# 2. Fossil Delta create and apply in JS
let deltaRes = fossilDelta.deltaCreate(b1, b2)
if deltaRes.isOk:
  let applied = fossilDelta.deltaApply(b1, deltaRes.value)
  if applied.isOk:
    echo "2. Delta roundtrip in JS successful: ", applied.value.data == b2.data

# 3. Markdown parsing in JS
let html = mdParser.markdownToHtml("# Hello from Fossil-Nim in JS!\n\n**Offline VCS** inside browser!")
echo "3. Markdown rendered in JS:"
echo html
