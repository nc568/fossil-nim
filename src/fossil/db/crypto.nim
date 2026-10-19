## Page encryption: ChaCha20 + HMAC-SHA256, encrypt-then-MAC.
##
## Why not AES: this code has to run byte-identically in C, in JavaScript and in
## wasm. AES needs either tables (a cache-timing side channel, and 1 KiB of
## constants in the wasm artifact) or careful bitslicing. ChaCha20 is add-xor-
## rotate: constant time by construction, no tables, and it produces the same
## bytes in every backend because JavaScript's bitwise ops are already 32-bit.
##
## Why not Poly1305: it needs 130-bit arithmetic, which means either 64-bit
## integers (Nim emulates them in JS, slowly and with edge cases) or the 26-bit
## limb trick with floating point. HMAC-SHA256 is plain 32-bit arithmetic and
## has test vectors older than most of the people who will read this file. On a
## 4 KiB page the cost difference is noise.
##
## Construction: encrypt-then-MAC, the composition with the simplest security
## argument — the MAC covers the ciphertext and the header, so a flipped bit
## anywhere in the stored page is detected before a single byte is decrypted.
##
## Everything here is verified against published vectors in t_crypto.nim. If a
## backend ever disagrees with C, those tests fail loudly instead of producing a
## database that one runtime can read and another cannot.

import fossil/db/errors

const
  KeyLen* = 32
  NonceLen* = 12
  TagLen* = 32
  PageNonceLen* = 12

# ---------------------------------------------------------------------------
# SHA-256 (FIPS 180-4)
# ---------------------------------------------------------------------------

const K256 = [
  0x428a2f98'u32, 0x71374491'u32, 0xb5c0fbcf'u32, 0xe9b5dba5'u32,
  0x3956c25b'u32, 0x59f111f1'u32, 0x923f82a4'u32, 0xab1c5ed5'u32,
  0xd807aa98'u32, 0x12835b01'u32, 0x243185be'u32, 0x550c7dc3'u32,
  0x72be5d74'u32, 0x80deb1fe'u32, 0x9bdc06a7'u32, 0xc19bf174'u32,
  0xe49b69c1'u32, 0xefbe4786'u32, 0x0fc19dc6'u32, 0x240ca1cc'u32,
  0x2de92c6f'u32, 0x4a7484aa'u32, 0x5cb0a9dc'u32, 0x76f988da'u32,
  0x983e5152'u32, 0xa831c66d'u32, 0xb00327c8'u32, 0xbf597fc7'u32,
  0xc6e00bf3'u32, 0xd5a79147'u32, 0x06ca6351'u32, 0x14292967'u32,
  0x27b70a85'u32, 0x2e1b2138'u32, 0x4d2c6dfc'u32, 0x53380d13'u32,
  0x650a7354'u32, 0x766a0abb'u32, 0x81c2c92e'u32, 0x92722c85'u32,
  0xa2bfe8a1'u32, 0xa81a664b'u32, 0xc24b8b70'u32, 0xc76c51a3'u32,
  0xd192e819'u32, 0xd6990624'u32, 0xf40e3585'u32, 0x106aa070'u32,
  0x19a4c116'u32, 0x1e376c08'u32, 0x2748774c'u32, 0x34b0bcb5'u32,
  0x391c0cb3'u32, 0x4ed8aa4a'u32, 0x5b9cca4f'u32, 0x682e6ff3'u32,
  0x748f82ee'u32, 0x78a5636f'u32, 0x84c87814'u32, 0x8cc70208'u32,
  0x90befffa'u32, 0xa4506ceb'u32, 0xbef9a3f7'u32, 0xc67178f2'u32]

proc rotr(x: uint32; n: int): uint32 =
  (x shr n) or (x shl (32 - n))

proc sha256*(data: string): string =
  var h = [0x6a09e667'u32, 0xbb67ae85'u32, 0x3c6ef372'u32, 0xa54ff53a'u32,
           0x510e527f'u32, 0x9b05688c'u32, 0x1f83d9ab'u32, 0x5be0cd19'u32]

  # Padding happens on a copy of the length, not on the message: callers pass
  # the string they intend to store, and a hash function that mutates its
  # argument is a bug waiting to be blamed on the caller.
  let bitLen = uint64(data.len) * 8
  var msg = data
  msg.add '\x80'
  while msg.len mod 64 != 56: msg.add '\0'
  for i in countdown(7, 0):
    msg.add char((bitLen shr (i * 8)) and 0xFF)

  var w: array[64, uint32]
  var off = 0
  while off < msg.len:
    for i in 0 ..< 16:
      w[i] = (uint32(uint8(msg[off + i * 4])) shl 24) or
             (uint32(uint8(msg[off + i * 4 + 1])) shl 16) or
             (uint32(uint8(msg[off + i * 4 + 2])) shl 8) or
             uint32(uint8(msg[off + i * 4 + 3]))
    for i in 16 ..< 64:
      let s0 = rotr(w[i - 15], 7) xor rotr(w[i - 15], 18) xor (w[i - 15] shr 3)
      let s1 = rotr(w[i - 2], 17) xor rotr(w[i - 2], 19) xor (w[i - 2] shr 10)
      w[i] = w[i - 16] + s0 + w[i - 7] + s1

    var a = h[0]
    var b = h[1]
    var c = h[2]
    var d = h[3]
    var e = h[4]
    var f = h[5]
    var g = h[6]
    var hh = h[7]
    for i in 0 ..< 64:
      let S1 = rotr(e, 6) xor rotr(e, 11) xor rotr(e, 25)
      let ch = (e and f) xor ((not e) and g)
      let t1 = hh + S1 + ch + K256[i] + w[i]
      let S0 = rotr(a, 2) xor rotr(a, 13) xor rotr(a, 22)
      let maj = (a and b) xor (a and c) xor (b and c)
      let t2 = S0 + maj
      hh = g
      g = f
      f = e
      e = d + t1
      d = c
      c = b
      b = a
      a = t1 + t2
    h[0] += a; h[1] += b; h[2] += c; h[3] += d
    h[4] += e; h[5] += f; h[6] += g; h[7] += hh
    off += 64

  result = newString(32)
  for i in 0 ..< 8:
    result[i * 4] = char((h[i] shr 24) and 0xFF)
    result[i * 4 + 1] = char((h[i] shr 16) and 0xFF)
    result[i * 4 + 2] = char((h[i] shr 8) and 0xFF)
    result[i * 4 + 3] = char(h[i] and 0xFF)

proc hmacSha256*(key, msg: string): string =
  ## RFC 2104. Keys longer than the block are hashed first, as the RFC requires;
  ## silently truncating them would make two different keys authenticate the
  ## same data.
  var k = if key.len > 64: sha256(key) else: key
  while k.len < 64: k.add '\0'            # padded by hand: this file stays
  var ipad = newString(64)                # dependency-free on purpose
  var opad = newString(64)
  for i in 0 ..< 64:
    ipad[i] = char(uint8(k[i]) xor 0x36)
    opad[i] = char(uint8(k[i]) xor 0x5c)
  sha256(opad & sha256(ipad & msg))

# ---------------------------------------------------------------------------
# ChaCha20 (RFC 8439)
# ---------------------------------------------------------------------------

proc quarterRound(s: var array[16, uint32]; a, b, c, d: int) =
  # The RFC writes these as left rotations by 16, 12, 8 and 7. `rotr` is what we
  # have, so the amounts are 32 - n: 16, 20, 24, 25. Writing the left-rotation
  # amounts against `rotr` produces a cipher that is perfectly self-consistent
  # and produces the wrong bytes — which is exactly what the vector caught.
  s[a] += s[b]; s[d] = rotr(s[d] xor s[a], 16)
  s[c] += s[d]; s[b] = rotr(s[b] xor s[c], 20)
  s[a] += s[b]; s[d] = rotr(s[d] xor s[a], 24)
  s[c] += s[d]; s[b] = rotr(s[b] xor s[c], 25)

proc chachaBlock(key: string; counter: uint32; nonce: string): array[64, char] =
  if key.len != KeyLen: failf(cryptoErr, "ChaCha20 key must be $1 bytes", KeyLen)
  if nonce.len != NonceLen: failf(cryptoErr, "ChaCha20 nonce must be $1 bytes", NonceLen)
  var st: array[16, uint32]
  st[0] = 0x61707865'u32; st[1] = 0x3320646e'u32
  st[2] = 0x79622d32'u32; st[3] = 0x6b206574'u32
  # Little-endian, per RFC 8439: the key and the nonce are read as 32-bit
  # little-endian words. Building them big-endian gives a cipher that is
  # internally consistent and simply is not ChaCha20 — the vector is the only
  # thing that can tell you which one you wrote.
  for i in 0 ..< 8:
    st[4 + i] = uint32(uint8(key[i * 4])) or
                (uint32(uint8(key[i * 4 + 1])) shl 8) or
                (uint32(uint8(key[i * 4 + 2])) shl 16) or
                (uint32(uint8(key[i * 4 + 3])) shl 24)
  st[12] = counter
  for i in 0 ..< 3:
    st[13 + i] = uint32(uint8(nonce[i * 4])) or
                 (uint32(uint8(nonce[i * 4 + 1])) shl 8) or
                 (uint32(uint8(nonce[i * 4 + 2])) shl 16) or
                 (uint32(uint8(nonce[i * 4 + 3])) shl 24)
  var x = st
  for _ in 0 ..< 10:
    quarterRound(x, 0, 4, 8, 12)
    quarterRound(x, 1, 5, 9, 13)
    quarterRound(x, 2, 6, 10, 14)
    quarterRound(x, 3, 7, 11, 15)
    quarterRound(x, 0, 5, 10, 15)
    quarterRound(x, 1, 6, 11, 12)
    quarterRound(x, 2, 7, 8, 13)
    quarterRound(x, 3, 4, 9, 14)
  for i in 0 ..< 16: x[i] += st[i]
  for i in 0 ..< 16:                    # serialised little-endian as well
    result[i * 4] = char(x[i] and 0xFF)
    result[i * 4 + 1] = char((x[i] shr 8) and 0xFF)
    result[i * 4 + 2] = char((x[i] shr 16) and 0xFF)
    result[i * 4 + 3] = char((x[i] shr 24) and 0xFF)

proc chacha20Xor*(key, nonce, data: string; counter = 1'u32): string =
  ## Returns `data` XORed with the ChaCha20 keystream. Encryption and decryption
  ## are the same operation, which is why there is only one function.
  result = newString(data.len)
  var ctr = counter
  var pos = 0
  while pos < data.len:
    let ks = chachaBlock(key, ctr, nonce)
    let take = min(64, data.len - pos)
    for i in 0 ..< take:
      result[pos + i] = char(uint8(data[pos + i]) xor uint8(ks[i]))
    pos += take
    inc ctr

# ---------------------------------------------------------------------------
# key derivation and page sealing
# ---------------------------------------------------------------------------

type PageKeys* = object
  enc*: string          ## 32 bytes, ChaCha20 key
  mac*: string          ## 32 bytes, HMAC key

proc deriveKeys*(master: string): PageKeys =
  ## Domain separation by hashing a label with the master key: the two keys are
  ## independent as long as SHA-256 is, and there is no counter to get wrong.
  if master.len != KeyLen:
    failf(cryptoErr, "master key must be $1 bytes, got $2", KeyLen, master.len)
  result.enc = sha256("foccil/page-enc\x00" & master)
  result.mac = sha256("foccil/page-mac\x00" & master)

proc pageNonce*(pageId: int; generation: int): string =
  ## 12 bytes: generation in the first 8, page id in the last 4.
  ##
  ## The generation matters more than it looks. A page id alone repeats for the
  ## lifetime of the file, so a page rewritten after a checkpoint would reuse a
  ## keystream; mixing the generation in makes every (page, generation) pair a
  ## fresh nonce, and the counter inside ChaCha20 makes each block inside a page
  ## fresh as well.
  result = newString(12)
  for i in 0 ..< 8:
    result[i] = char((generation shr (i * 8)) and 0xFF)
  for i in 0 ..< 4:
    result[8 + i] = char((pageId shr (i * 8)) and 0xFF)

proc constantTimeEq*(a, b: string): bool =
  ## Compares every byte, always. Early exit turns a MAC check into an oracle
  ## that tells an attacker how many leading bytes they got right.
  if a.len != b.len: return false
  var diff = 0
  for i in 0 ..< a.len:
    diff = diff or (int(uint8(a[i])) xor int(uint8(b[i])))
  diff == 0

proc sealPage*(keys: PageKeys; pageId, generation: int; plain: string): string =
  ## Ciphertext followed by the 32-byte tag. The tag covers the nonce and the
  ## ciphertext, so a page moved to another slot, or from another generation,
  ## fails authentication instead of decrypting to rubbish that looks like data.
  let nonce = pageNonce(pageId, generation)
  let ct = chacha20Xor(keys.enc, nonce, plain)
  result = ct & hmacSha256(keys.mac, nonce & ct)

proc openPage*(keys: PageKeys; pageId, generation: int; sealed: string): string =
  if sealed.len < TagLen:
    failf(cryptoErr, "sealed page is too short to be one")
  let bodyLen = sealed.len - TagLen
  let ct = sealed[0 ..< bodyLen]
  let tag = sealed[bodyLen ..< sealed.len]
  let nonce = pageNonce(pageId, generation)
  if not constantTimeEq(hmacSha256(keys.mac, nonce & ct), tag):
    failf(cryptoErr, "page authentication failed: wrong key, wrong page, or a torn write")
  chacha20Xor(keys.enc, nonce, ct)
