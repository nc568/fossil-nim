## Test sync protocol

import std/[strutils]
import ../src/fossil/sync/protocol as proto
import ../src/fossil/types

echo "=== test_sync_protocol ==="

# Test file card with multiline content (critical bug fixed)
let content = "line1\nline2\nline3 with spaces\nlast line"
let uuid = Uuid("a".repeat(64))
let blob = newBlob(content)
let card = XferCard(kind: ckFile, uuid: uuid, data: blob)
let encoded = encodeCard(card)
echo "Encoded file card len=", encoded.len
let cards = parseCards(encoded)
assert cards.len==1, "parseCards count should be 1, got " & $cards.len
assert cards[0].data.data == content, "content mismatch"
echo "file card multiline OK Match true"

# Test gimme/igot/cookie/error cards
let gimmeCard = XferCard(kind: ckGimme, uuid: uuid)
let encGimme = encodeCard(gimmeCard)
let parsedGimme = parseCards(encGimme)
assert parsedGimme.len==1
assert parsedGimme[0].kind==ckGimme
echo "gimme card OK"

let igotCard = XferCard(kind: ckIgot, uuid: uuid)
let encIgot = encodeCard(igotCard)
let parsedIgot = parseCards(encIgot)
assert parsedIgot.len==1
assert parsedIgot[0].kind==ckIgot
echo "igot card OK"

# Test bundle
var bundle = ""
bundle.add encodeCard(card)
bundle.add encodeCard(gimmeCard)
bundle.add encodeCard(igotCard)
let parsedBundle = parseCards(bundle)
assert parsedBundle.len==3
echo "bundle parse OK count=", parsedBundle.len

echo "All sync tests passed!"
