## B+tree over the pager.
##
## Shape, and why this shape:
##
##   * keys always live on the page. A key that needs an overflow page means a
##     comparison cost a random read, and a comparison happens at every level
##     of descent — the worst possible place to pay for I/O. Keys are therefore
##     capped at `MaxKeySize` and rejected beyond it, loudly.
##   * values spill to an overflow chain past `InlineValueMax`. A 1 KiB ceiling
##     is four keys' worth of space; below it the value rides along with the
##     page we already had to read, above it we pay one extra hop only for the
##     rows that actually need it.
##   * those two constants bound a cell to 1 544 bytes, so any page holds at
##     least two cells. That is the invariant that makes every split terminate:
##     no node can be "too full to split".
##   * leaves are linked both ways. Range scans need `next`; deleting a leaf
##     needs `prev`, and finding it by descending from the root would turn a
##     page removal into a tree walk.
##   * underfull nodes are *not* merged. SQLite does not merge either, and the
##     reason holds here: a page that is half empty is a page that will be
##     filled again, and a merge costs writes on a workload that is usually
##     delete-then-reinsert. Only empty nodes are collapsed, so space is
##     reclaimed in units the freelist can actually reuse.

import std/[algorithm, strutils]
import fossil/db/[bytes, errors, pager]

const
  NodeHeader* = 16
  KindLeaf* = 1
  KindInternal* = 2
  CellHdr* = 8
  MaxKeySize* = 512
  InlineValueMax* = 1024
  MaxLeafCell* = CellHdr + MaxKeySize + InlineValueMax
  MaxIntCell* = CellHdr + MaxKeySize
  OverflowHdr* = 8
  OverflowUsable* = PageSize - OverflowHdr
  ValInline = 0
  ValOverflow = 1

type
  Node = object
    kind: int
    left, right: int          ## right = next sibling leaf; internal: unused
    keys: seq[string]         ## separators: keys[i] is the min key of child i+1
    cells: seq[string]        ## raw cell bytes, parallel to keys

  Btree* = ref object
    p*: Pager
    root*: int
    height*: int

  TreeStats* = object
    depth*: int
    leaves*: int
    keys*: int
    nodes*: int

# ---------------------------------------------------------------------------
# cells
# ---------------------------------------------------------------------------

proc leafCell(key, val: string; overflowPage = 0; totalLen = -1): string =
  ## `[keyLen u16][kind u8][pad][valLen i32][key][value | firstOverflowPage]`
  ## `totalLen` matters for overflow cells: the payload is not on the page, and
  ## storing `val.len` there wrote 0 — every overflow value came back empty.
  let kind = if overflowPage != 0: ValOverflow else: ValInline
  let tail = if kind == ValInline: val.len else: 4
  result = newString(CellHdr + key.len + tail)
  result.putU16(0, key.len)
  result[2] = char(kind)
  result.putI32(4, if totalLen >= 0: totalLen else: val.len)
  for i in 0 ..< key.len: result[CellHdr + i] = key[i]
  if kind == ValInline:
    for i in 0 ..< val.len: result[CellHdr + key.len + i] = val[i]
  else:
    result.putI32(CellHdr + key.len, overflowPage)

proc intCell(child: int; key: string): string =
  ## `[child i32][keyLen u16][pad][key]`, where the key is the *minimum* key of
  ## that child's subtree.
  result = newString(CellHdr + key.len)
  result.putI32(0, child)
  result.putU16(4, key.len)
  for i in 0 ..< key.len: result[CellHdr + i] = key[i]

proc cellKey(cell: string; kind: int): string =
  let klen = if kind == KindLeaf: cell.getU16(0) else: cell.getU16(4)
  cell[CellHdr ..< CellHdr + klen]

proc cellChild(cell: string): int = cell.getI32(0)
proc cellValLen(cell: string): int = cell.getI32(4)
proc cellValKind(cell: string): int = int(uint8(cell[2]))
proc cellInlineVal(cell: string): string =
  let klen = cell.getU16(0)
  cell[CellHdr + klen ..< CellHdr + klen + cell.cellValLen]
proc cellOverflowPage(cell: string): int =
  cell.getI32(CellHdr + cell.getU16(0))

# ---------------------------------------------------------------------------
# node <-> page
# ---------------------------------------------------------------------------

proc emptyNode(kind: int): Node = Node(kind: kind)

proc usedBytes(n: Node): int =
  result = NodeHeader + 2 * n.cells.len
  for c in n.cells: result += c.len

proc fits(n: Node): bool = usedBytes(n) <= PageSize

doAssert 2 * MaxLeafCell + NodeHeader + 4 <= PageSize, "a leaf must hold two full cells"
doAssert 2 * MaxIntCell + NodeHeader + 4 <= PageSize, "an internal node must hold two cells"

proc parseNode(page: string): Node =
  result.kind = int(uint8(page[0]))
  result.left = page.getI32(8)
  result.right = page.getI32(4)
  let n = page.getU16(2)
  for i in 0 ..< n:
    # cells are packed end to end, so the next cell's offset is our end
    let off = page.getU16(NodeHeader + 2 * i)
    let endOff = if i + 1 < n: page.getU16(NodeHeader + 2 * (i + 1)) else: PageSize
    let cell = page[off ..< endOff]
    result.cells.add cell
    result.keys.add cellKey(cell, result.kind)

proc buildPage(n: Node): string =
  result = newString(PageSize)
  result[0] = char(n.kind)
  result.putU16(2, n.cells.len)
  result.putI32(4, n.right)
  result.putI32(8, n.left)
  var total = 0
  for c in n.cells: total += c.len
  var off = PageSize - total
  result.putU16(12, off)
  for i, c in n.cells:
    result.putU16(NodeHeader + 2 * i, off)
    for j in 0 ..< c.len: result[off + j] = c[j]
    off += c.len

# ---------------------------------------------------------------------------
# overflow values
# ---------------------------------------------------------------------------

proc writeOverflow(b: Btree; val: string): int =
  var pos = 0
  var prev = 0
  while pos < val.len:
    let pid = b.p.allocPage()
    let take = min(OverflowUsable, val.len - pos)
    var page = newString(PageSize)
    page.putI32(0, 0)
    page.putU16(4, take)
    for i in 0 ..< take: page[OverflowHdr + i] = val[pos + i]
    b.p.writePage(pid, page)
    if prev == 0: result = pid
    else:
      var p = b.p.readPage(prev)       # patch the previous link now that we know it
      p.putI32(0, pid)
      b.p.writePage(prev, p)
    prev = pid
    pos += take

proc readOverflow(b: Btree; first, total: int): string =
  result = newString(total)
  var pid = first
  var pos = 0
  while pid != 0 and pos < total:
    let page = b.p.readPage(pid)
    let take = min(page.getU16(4), total - pos)
    for i in 0 ..< take: result[pos + i] = page[OverflowHdr + i]
    pos += take
    pid = page.getI32(0)

proc freeOverflow(b: Btree; first: int) =
  var pid = first
  while pid != 0:
    let next = b.p.readPage(pid).getI32(0)
    b.p.freePage(pid)
    pid = next

# ---------------------------------------------------------------------------
# tree
# ---------------------------------------------------------------------------
#
# Internal node invariant: every cell carries the *minimum* key of its own
# child's subtree. The first version stored only the separator between two
# children, so the minimum of child 0 was nowhere — and when an insert pushed a
# leaf's minimum downwards, the parent never learned, descent took the wrong
# branch, and a duplicate key appeared in a second leaf. The tree answered
# lookups correctly often enough to look healthy. It was the reference-model
# test that caught it.
#
# With a minimum per child there is no key to "promote and drop" on a split:
# the parent simply learns the new node's minimum, which the node already knows.

proc childIndex(n: Node; key: string): int =
  var i = 0
  while i + 1 < n.cells.len and cmp(key, n.keys[i + 1]) >= 0: inc i
  i

proc descend(b: Btree; key: string): int =
  result = b.root
  var depth = 0
  while true:
    let n = parseNode(b.p.readPage(result))
    if n.kind == KindLeaf: break
    result = n.cells[childIndex(n, key)].cellChild
    inc depth
    if depth > 64: failf(corrupt, "B+tree deeper than 64 levels — cycle in the page graph")

proc leftmost(b: Btree): int =
  result = b.root
  var depth = 0
  while true:
    let n = parseNode(b.p.readPage(result))
    if n.kind == KindLeaf: break
    result = n.cells[0].cellChild
    inc depth
    if depth > 64: failf(corrupt, "B+tree deeper than 64 levels — cycle in the page graph")

proc measure(b: Btree) =
  var d = 0
  var pid = b.root
  while true:
    let n = parseNode(b.p.readPage(pid))
    if n.kind == KindLeaf: break
    pid = n.cells[0].cellChild
    inc d
    if d > 64: break
  b.height = d

proc openBtree*(p: Pager): Btree =
  result = Btree(p: p)
  if p.root == 0:
    let pid = p.allocPage()
    p.writePage(pid, buildPage(emptyNode(KindLeaf)))
    p.root = pid
  result.root = p.root
  result.measure()

proc get*(b: Btree; key: string): tuple[found: bool, val: string] =
  let n = parseNode(b.p.readPage(b.descend(key)))
  var lo = 0
  var hi = n.keys.len - 1
  while lo <= hi:
    let mid = (lo + hi) div 2
    let c = cmp(n.keys[mid], key)
    if c == 0:
      let cell = n.cells[mid]
      if cell.cellValKind == ValInline: return (true, cell.cellInlineVal)
      return (true, b.readOverflow(cell.cellOverflowPage, cell.cellValLen))
    elif c < 0: lo = mid + 1
    else: hi = mid - 1
  (false, "")

proc makeLeafCell(b: Btree; key, val: string): string =
  if key.len > MaxKeySize:
    failf(range, "key of $1 bytes exceeds the $2-byte limit", key.len, MaxKeySize)
  if val.len <= InlineValueMax: leafCell(key, val)
  else:
    let first = b.writeOverflow(val)
    leafCell(key, "", first, val.len)

proc freeCellValue(b: Btree; cell: string; kind: int) =
  if kind == KindLeaf and cell.cellValKind == ValOverflow:
    b.freeOverflow(cell.cellOverflowPage)

proc splitOff(n: var Node): Node =
  ## Cuts `n` in half; returns the right half. Both halves are non-empty and
  ## each knows its own minimum, which is all the parent needs.
  if n.kind == KindLeaf:
    let mid = n.keys.len div 2
    if mid == 0: failf(corrupt, "cannot split a leaf with $1 keys", n.keys.len)
    result = emptyNode(KindLeaf)
    result.right = n.right
    for i in mid ..< n.keys.len:
      result.cells.add n.cells[i]
      result.keys.add n.keys[i]
    n.cells.setLen(mid)
    n.keys.setLen(mid)
    n.right = 0
  else:
    let mid = n.cells.len div 2
    if mid == 0: failf(corrupt, "cannot split an internal node with $1 cells", n.cells.len)
    result = emptyNode(KindInternal)
    for i in mid ..< n.cells.len:
      result.cells.add n.cells[i]
      result.keys.add n.keys[i]
    n.cells.setLen(mid)
    n.keys.setLen(mid)

proc insertRec(b: Btree; pid: int; key, val: string):
    tuple[split: bool, sep: string, right: int, minKey: string] =
  var n = parseNode(b.p.readPage(pid))

  if n.kind == KindLeaf:
    var pos = 0
    while pos < n.keys.len and cmp(n.keys[pos], key) < 0: inc pos
    if pos < n.keys.len and n.keys[pos] == key:
      b.freeCellValue(n.cells[pos], KindLeaf)
      n.cells[pos] = b.makeLeafCell(key, val)
      b.p.writePage(pid, buildPage(n))
      return (false, "", 0, n.keys[0])
    n.cells.insert(b.makeLeafCell(key, val), pos)
    n.keys.insert(key, pos)
    if fits(n):
      b.p.writePage(pid, buildPage(n))
      return (false, "", 0, n.keys[0])

    let sep = n.keys[n.keys.len div 2]
    var rhs = splitOff(n)
    let newPid = b.p.allocPage()
    rhs.left = pid          # splitOff already carried the old `right` across;
    n.right = newPid        # re-reading it from `n` here would find zero and
                            # silently cut the leaf chain in half
    if rhs.right != 0:
      var sib = parseNode(b.p.readPage(rhs.right))
      sib.left = newPid
      b.p.writePage(rhs.right, buildPage(sib))
    b.p.writePage(pid, buildPage(n))
    b.p.writePage(newPid, buildPage(rhs))
    return (true, sep, newPid, n.keys[0])

  let i = childIndex(n, key)
  let r = b.insertRec(n.cells[i].cellChild, key, val)
  # The child's minimum may have moved. `n.keys` is a parsed view; the page is
  # built from `n.cells`, so the *cell* has to be rebuilt — assigning to the
  # parsed array updated nothing on disk and the tree slowly drifted out of
  # range. Two hours of my life, honestly.
  n.cells[i] = intCell(n.cells[i].cellChild, r.minKey)
  n.keys[i] = r.minKey
  if not r.split:
    b.p.writePage(pid, buildPage(n))
    return (false, "", 0, n.keys[0])

  n.cells.insert(intCell(r.right, r.sep), i + 1)
  n.keys.insert(r.sep, i + 1)
  if fits(n):
    b.p.writePage(pid, buildPage(n))
    return (false, "", 0, n.keys[0])

  let sep = n.keys[n.cells.len div 2]
  var rhs = splitOff(n)
  let newPid = b.p.allocPage()
  b.p.writePage(pid, buildPage(n))
  b.p.writePage(newPid, buildPage(rhs))
  (true, sep, newPid, n.keys[0])

proc put*(b: Btree; key, val: string) =
  let r = b.insertRec(b.root, key, val)
  if not r.split: return
  var root = emptyNode(KindInternal)
  root.cells.add intCell(b.root, r.minKey)
  root.cells.add intCell(r.right, r.sep)
  root.keys.add r.minKey
  root.keys.add r.sep
  let newRoot = b.p.allocPage()
  b.p.writePage(newRoot, buildPage(root))
  b.root = newRoot
  b.p.root = newRoot
  b.measure()

proc unlinkLeaf(b: Btree; n: Node) =
  if n.left != 0:
    var prev = parseNode(b.p.readPage(n.left))
    prev.right = n.right
    b.p.writePage(n.left, buildPage(prev))
  if n.right != 0:
    var nxt = parseNode(b.p.readPage(n.right))
    nxt.left = n.left
    b.p.writePage(n.right, buildPage(nxt))

proc deleteRec(b: Btree; pid: int; key: string): tuple[removed: bool, minKey: string] =
  var n = parseNode(b.p.readPage(pid))

  if n.kind == KindLeaf:
    var lo = 0
    var hi = n.keys.len - 1
    while lo <= hi:
      let mid = (lo + hi) div 2
      let c = cmp(n.keys[mid], key)
      if c == 0:
        b.freeCellValue(n.cells[mid], KindLeaf)
        n.cells.delete(mid)
        n.keys.delete(mid)
        if n.keys.len == 0:
          if pid != b.root: b.unlinkLeaf(n)
          b.p.freePage(pid)
          return (true, "")
        b.p.writePage(pid, buildPage(n))
        return (true, n.keys[0])
      elif c < 0: lo = mid + 1
      else: hi = mid - 1
    return (false, if n.keys.len > 0: n.keys[0] else: "")

  let i = childIndex(n, key)
  let r = b.deleteRec(n.cells[i].cellChild, key)
  if not r.removed: return (false, n.keys[0])

  if r.minKey.len == 0:
    n.cells.delete(i)                    # empty child, and it freed itself
    n.keys.delete(i)
    if n.cells.len == 0:
      b.p.freePage(pid)
      return (true, "")
  else:
    n.cells[i] = intCell(n.cells[i].cellChild, r.minKey)
    n.keys[i] = r.minKey
  b.p.writePage(pid, buildPage(n))
  (true, n.keys[0])

proc del*(b: Btree; key: string): bool =
  if b.root == 0: return false
  let r = b.deleteRec(b.root, key)
  if not r.removed: return false
  if r.minKey.len == 0:
    # the root emptied itself and freed its page; give the tree a fresh leaf
    b.root = b.p.allocPage()
    b.p.writePage(b.root, buildPage(emptyNode(KindLeaf)))
    b.p.root = b.root
    b.height = 0
    return true
  let n = parseNode(b.p.readPage(b.root))
  if n.kind == KindInternal and n.cells.len <= 1:
    # a root with one child is a level nobody needs
    let heir = if n.cells.len == 1: n.cells[0].cellChild else: 0
    b.p.freePage(b.root)
    if heir != 0:
      b.root = heir
    else:
      b.root = b.p.allocPage()
      b.p.writePage(b.root, buildPage(emptyNode(KindLeaf)))
    b.p.root = b.root
    b.measure()
  true

proc clear*(b: Btree) =
  ## Drops every page reachable from the root and starts a fresh empty leaf.
  proc drop(pid: int) =
    let n = parseNode(b.p.readPage(pid))
    if n.kind == KindInternal:
      for c in n.cells: drop(c.cellChild)
    else:
      for c in n.cells: b.freeCellValue(c, KindLeaf)
    b.p.freePage(pid)
  drop(b.root)
  let pid = b.p.allocPage()
  b.p.writePage(pid, buildPage(emptyNode(KindLeaf)))
  b.root = pid
  b.p.root = pid
  b.height = 0

# ---------------------------------------------------------------------------
# scans
# ---------------------------------------------------------------------------

iterator scanFrom*(b: Btree; start: string): tuple[key, val: string] =
  ## Ordered scan from `start` (inclusive) to the end of the tree.
  var pid = b.descend(start)
  var started = false
  while pid != 0:
    let n = parseNode(b.p.readPage(pid))
    for i in 0 ..< n.keys.len:
      if not started and cmp(n.keys[i], start) < 0: continue
      started = true
      let cell = n.cells[i]
      let val = if cell.cellValKind == ValInline: cell.cellInlineVal
                else: b.readOverflow(cell.cellOverflowPage, cell.cellValLen)
      yield (n.keys[i], val)
    pid = n.right

iterator pairs*(b: Btree): tuple[key, val: string] =
  var pid = b.leftmost()
  while pid != 0:
    let n = parseNode(b.p.readPage(pid))
    for i in 0 ..< n.keys.len:
      let cell = n.cells[i]
      let val = if cell.cellValKind == ValInline: cell.cellInlineVal
                else: b.readOverflow(cell.cellOverflowPage, cell.cellValLen)
      yield (n.keys[i], val)
    pid = n.right

iterator range*(b: Btree; lo, hi: string): tuple[key, val: string] =
  ## `lo` inclusive, `hi` exclusive.
  var pid = b.descend(lo)
  block outer:
    while pid != 0:
      let n = parseNode(b.p.readPage(pid))
      for i in 0 ..< n.keys.len:
        if cmp(n.keys[i], lo) < 0: continue
        if cmp(n.keys[i], hi) >= 0: break outer
        let cell = n.cells[i]
        let val = if cell.cellValKind == ValInline: cell.cellInlineVal
                  else: b.readOverflow(cell.cellOverflowPage, cell.cellValLen)
        yield (n.keys[i], val)
      pid = n.right

# ---------------------------------------------------------------------------
# verification
# ---------------------------------------------------------------------------

proc verify*(b: Btree): TreeStats =
  ## Full walk. Throws on any structural violation, so a green test that calls
  ## this means the tree is *actually* a B+tree, not merely one that answers.
  var stats: TreeStats
  var leafDepth = -1

  proc walk(pid: int; depth: int; lo, hi: string; hasLo, hasHi: bool) =
    inc stats.nodes
    let n = parseNode(b.p.readPage(pid))
    if not fits(n): failf(corrupt, "node $1 overflows its page", pid)
    for i in 1 ..< n.keys.len:
      if cmp(n.keys[i - 1], n.keys[i]) >= 0:
        failf(corrupt, "node $1 has keys out of order", pid)

    if n.kind == KindLeaf:
      if leafDepth < 0: leafDepth = depth
      elif leafDepth != depth: failf(corrupt, "leaves sit at different depths")
      inc stats.leaves
      stats.keys += n.keys.len
      for i in 0 ..< n.keys.len:
        if hasLo and cmp(n.keys[i], lo) < 0:
          failf(corrupt, "key $1 below its subtree range (lo=$2) in page $3", n.keys[i], lo, pid)
        if hasHi and cmp(n.keys[i], hi) >= 0:
          failf(corrupt, "key $1 above its subtree range (hi=$2) in page $3", n.keys[i], hi, pid)
      for c in n.cells:
        if c.cellValKind == ValOverflow and c.cellOverflowPage == 0:
          failf(corrupt, "overflow value without a chain")
      if n.right != 0:
        let sib = parseNode(b.p.readPage(n.right))
        if sib.left != pid: failf(corrupt, "leaf chain is not doubly linked")
      return

    if n.cells.len == 0: failf(corrupt, "internal node with no children")
    if hasLo and cmp(n.keys[0], lo) != 0:
      failf(corrupt, "child minimum $1 disagrees with the range start $2", n.keys[0], lo)
    for i in 0 ..< n.cells.len:
      let childLo = n.keys[i]
      let childHi = if i + 1 < n.keys.len: n.keys[i + 1] else: hi
      let childHasHi = if i + 1 < n.keys.len: true else: hasHi
      walk(n.cells[i].cellChild, depth + 1, childLo, childHi, true, childHasHi)

  stats.depth = b.height
  walk(b.root, 0, "", "", false, false)
  stats

proc dump*(b: Btree): string =
  ## Indented picture of the tree. Cheap to write, and the alternative when a
  ## structural test fails is guessing from page numbers.
  var acc = ""
  proc walk(pid, depth: int) =
    let n = parseNode(b.p.readPage(pid))
    var line = "  ".repeat(depth) & "page " & $pid & " " &
               (if n.kind == KindLeaf: "leaf" else: "node") & " [" & $n.cells.len & "] "
    for i in 0 ..< n.keys.len:
      if i > 0: line.add " | "
      if n.kind == KindLeaf:
        line.add n.keys[i] & "=" & (if n.cells[i].cellValKind == ValInline: n.cells[i].cellInlineVal else: "<ovf>")
      else:
        line.add $n.keys[i] & "->" & $n.cells[i].cellChild
    if n.kind == KindLeaf and n.right != 0: line.add "  next=" & $n.right
    acc.add line & "\n"
    if n.kind == KindInternal:
      for c in n.cells: walk(c.cellChild, depth + 1)
  walk(b.root, 0)
  acc
