## Big-endian field access on raw byte strings.
##
## One place for the byte order, because a format bug that lives in two files is
## a bug that gets fixed in one of them. Big-endian is chosen so that a hex dump
## of a page reads left to right, the way a human checks it.

proc getU16*(s: string; at: int): int =
  (int(uint8(s[at])) shl 8) or int(uint8(s[at + 1]))

proc putU16*(s: var string; at: int; v: int) =
  s[at] = char((v shr 8) and 0xFF)
  s[at + 1] = char(v and 0xFF)

proc getI32*(s: string; at: int): int =
  ## Signed on purpose: page ids are never negative, but lengths and markers are
  ## read back through the same call and a stray sign flip is how the WAL commit
  ## marker once became 4294967295.
  var u: uint32
  for i in 0 .. 3:
    u = (u shl 8) or uint32(uint8(s[at + i]))
  when sizeof(int) == 8:
    if (u and 0x8000_0000'u32) != 0: int(u) - (1 shl 32) else: int(u)
  else:
    cast[int32](u).int

proc putI32*(s: var string; at: int; v: int) =
  let u = uint32(v)
  s[at] = char((u shr 24) and 0xFF)
  s[at + 1] = char((u shr 16) and 0xFF)
  s[at + 2] = char((u shr 8) and 0xFF)
  s[at + 3] = char(u and 0xFF)
