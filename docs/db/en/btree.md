# B+tree: the storage format (v0.2, slice 3)

Status: **implemented and tested** (2026-10-19). `src/fossil/db/btree.nim`,
`tests/db/t_btree.nim` (24 tests), 5 of them model checks.

## Two decisions that shaped everything

**Keys live on the page, always.** A key stored in an overflow page would cost a
random read at every level of descent — the worst possible place to pay for I/O.
So keys are capped at `MaxKeySize = 512` and rejected above it, loudly, rather
than silently truncated.

**Values spill past 1 KiB.** Below that ceiling a value rides along with the page
we already had to read; above it we pay one extra hop, and only for the rows that
actually need it.

Together those cap a cell at 1 544 bytes, so **any page holds at least two cells**.
That is the invariant that makes every split terminate — no node can be "too full
to split". It is checked at compile time, not by hope:

```nim
doAssert 2 * MaxLeafCell + NodeHeader + 4 <= PageSize
```

## Page layout

```
0    u8   kind            1 = leaf, 2 = internal
2    u16  cell count
4    i32  next sibling     (leaf chain)
8    i32  previous sibling (leaf chain)
12   u16  first cell offset
16   u16  cell offsets[n]
       …    cells, packed from the end of the page backwards
```

Leaf cell: `[keyLen u16][kind u8][pad][valLen i32][key][value | overflowPage i32]`

Internal cell: `[child i32][keyLen u16][pad][key]`

## Internal nodes carry a minimum per child

Every internal cell stores **the minimum key of its own child's subtree**. The
first version stored only the separator between two children, so child 0's
minimum existed nowhere. Inserting a key that lowered a leaf's minimum left the
parent stale, descent then took the wrong branch, and the same key ended up in two
leaves. The tree still answered most lookups correctly — which is exactly why the
reference-model test, not the happy-path test, caught it.

With a minimum per child there is also nothing to "promote and drop" on a split:
the parent just learns the new node's minimum, which that node already knows.

## Delete

Only **empty** nodes are collapsed. Underfull nodes are left alone, exactly as
SQLite does: a half-empty page will be filled again, and merging costs writes on a
workload that is usually delete-then-reinsert. Space is still reclaimed in units
the freelist can reuse.

Leaves are doubly linked so removing one is O(1) — `prev.next = next`. Finding the
previous leaf by descending from the root would turn a page removal into a tree
walk.

## Verification is a first-class function

`verify()` walks the whole tree and throws on any violation: cells out of order,
keys outside their subtree range, leaves at unequal depths, a leaf chain that is
not doubly linked, a node whose cells overflow the page, an overflow value with no
chain. Every heavy test ends with it. A test that only checks `get` returns what
`put` stored would pass on a single-page array.

`dump()` prints the tree — cheap to write, and the alternative when a structural
test fails is guessing from page numbers.

## Two more bugs worth remembering

1. After a leaf split, `rhs.right = n.right` re-read the pointer that `splitOff`
   had already zeroed — the leaf chain was cut in half and scans stopped early.
2. `n.keys[i] = newMin` updated the **parsed** array, but pages are built from the
   raw cell bytes. The parent's minimum silently never reached disk.

Both were invisible in review and obvious to a test that reads back its own writes.

## Numbers

```
5 000 sequential inserts    depth 2, all leaves at one depth, verify clean
1 200 keys, every 3rd gone  800 remain, chain intact, ordered scan correct
40 KB value                 10 overflow pages, byte-identical round trip
JS build                    same tree, same depth, no os/File
```

## Not here yet

- a free-space map per page (SQLite's freelist is global and fragmented);
- prefix compression on keys (the obvious next space win);
- bulk load for `CREATE INDEX` — currently N inserts, not a sorted build;
- concurrency: one writer, same as the WAL.

## Run

```sh
nim c -r --skipParentCfg:on --path:src tests/db/t_btree.nim
```
