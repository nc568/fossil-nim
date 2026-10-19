## Crypto tests: published vectors, then the attacks that matter.
##
## A home-grown primitive is only worth having if it reproduces the standard
## vectors byte for byte. Everything here is checked against the RFCs first and
## against itself second — self-consistency would pass on a broken cipher that
## is broken identically everywhere.

import std/[strutils, unittest]
import fossil/db/[crypto, errors]

proc hex(s: string): string =
  result = newString(s.len * 2)
  const digits = "0123456789abcdef"
  for i in 0 ..< s.len:
    result[i * 2] = digits[int(uint8(s[i])) shr 4]
    result[i * 2 + 1] = digits[int(uint8(s[i])) and 0x0F]

proc unhex(s: string): string =
  result = newString(s.len div 2)
  for i in 0 ..< result.len:
    result[i] = char(parseHexInt(s[i * 2 .. i * 2 + 1]))

suite "sha256 (FIPS 180-4)":
  test "empty string":
    check hex(sha256("")) ==
      "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

  test "abc":
    check hex(sha256("abc")) ==
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"

  test "448-bit message (two blocks, exercises padding)":
    check hex(sha256("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")) ==
      "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"

  test "one million 'a' (the long-message vector)":
    var s = newString(1_000_000)
    for i in 0 ..< s.len: s[i] = 'a'
    check hex(sha256(s)) ==
      "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0"

  test "input is not mutated":
    var msg = "the caller still owns this string"
    let before = msg
    discard sha256(msg)
    check msg == before

suite "hmac-sha256 (RFC 4231)":
  test "case 1: 20-byte key of 0x0b":
    let key = repeat('\x0b', 20)
    check hex(hmacSha256(key, "Hi There")) ==
      "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7"

  test "case 2: key shorter than the block":
    check hex(hmacSha256("Jefe", "what do ya want for nothing?")) ==
      "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"

  test "case 6: key longer than the block is hashed first":
    let key = repeat('\xaa', 131)
    check hex(hmacSha256(key, "Test Using Larger Than Block-Size Key - Hash Key First")) ==
      "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54"

suite "chacha20 (RFC 8439 §2.3.2)":
  test "the published block":
    # The nonce here is 00:00:00:09:00:00:00:4a:00:00:00:00 — section 2.3.2 and
    # section 2.4.2 use *different* nonces, and pairing the 2.3.2 output with the
    # 2.4.2 nonce is a mistake this test made first. Encrypting 64 zero bytes
    # yields the keystream, which is the block function output.
    let key = unhex("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
    let nonce = unhex("000000090000004a00000000")
    let zeros = repeat('\0', 64)
    let ks = chacha20Xor(key, nonce, zeros, 1)
    check hex(ks) ==
      "10f1e7e4d13b5915500fdd1fa32071c4c7d1f4c733c068030422aa9ac3d46c4e" &
      "d2826446079faa0914c2d705d98b02a2b5129cd1de164eb9cbd083e8a2503c4e"

  test "encrypting then decrypting returns the original":
    let key = unhex("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
    let nonce = unhex("00000000000000000000004a")
    var data = newString(1000)
    for i in 0 ..< data.len: data[i] = char(i mod 256)
    let ct = chacha20Xor(key, nonce, data)
    check ct != data
    check chacha20Xor(key, nonce, ct) == data

  test "different counter gives a different keystream":
    let key = unhex("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
    let nonce = unhex("00000000000000000000004a")
    let zeros = repeat('\0', 64)
    check chacha20Xor(key, nonce, zeros, 1) != chacha20Xor(key, nonce, zeros, 2)

  test "wrong key length is refused, not silently stretched":
    expect DbError:
      discard chacha20Xor("short", repeat('\0', 12), "data")

suite "page sealing":
  test "seal then open returns the page":
    let keys = deriveKeys(repeat('k', 32))
    var page = newString(4096)
    for i in 0 ..< page.len: page[i] = char(i mod 251)
    let sealed = sealPage(keys, 7, 1, page)
    check sealed.len == page.len + TagLen
    check sealed[0 ..< 32] != page[0 ..< 32]     # actually encrypted
    check openPage(keys, 7, 1, sealed) == page

  test "a flipped bit anywhere in the ciphertext is caught":
    let keys = deriveKeys(repeat('k', 32))
    let page = repeat('A', 4096)
    let sealed = sealPage(keys, 7, 1, page)
    for pos in [0, 1, 100, 2048, 4095, 4100, 4120]:
      var bad = sealed
      bad[pos] = char(uint8(bad[pos]) xor 1)
      expect DbError:
        discard openPage(keys, 7, 1, bad)

  test "a flipped bit in the tag is caught":
    let keys = deriveKeys(repeat('k', 32))
    let sealed = sealPage(keys, 7, 1, repeat('A', 4096))
    var bad = sealed
    bad[sealed.len - 1] = char(uint8(bad[sealed.len - 1]) xor 0x80)
    expect DbError:
      discard openPage(keys, 7, 1, bad)

  test "a page moved to another slot fails to open":
    ## The attack this prevents: swapping two pages in the file. Both are
    ## authentic ciphertext; only the nonce binds them to their slot.
    let keys = deriveKeys(repeat('k', 32))
    let sealed = sealPage(keys, 7, 1, repeat('A', 4096))
    expect DbError:
      discard openPage(keys, 8, 1, sealed)

  test "a page from another generation fails to open":
    ## And this one: replaying last checkpoint's page over this one.
    let keys = deriveKeys(repeat('k', 32))
    let sealed = sealPage(keys, 7, 1, repeat('A', 4096))
    expect DbError:
      discard openPage(keys, 7, 2, sealed)

  test "a wrong key fails, and tells you nothing about how wrong":
    let good = deriveKeys(repeat('k', 32))
    let bad = deriveKeys(repeat('K', 32))
    let sealed = sealPage(good, 7, 1, repeat('A', 4096))
    var messages: seq[string]
    for attempt in 0 ..< 3:
      try:
        discard openPage(bad, 7, 1, sealed)
        check false
      except DbError as e:
        messages.add e.msg
    check messages.len == 3
    check messages[0] == messages[1] and messages[1] == messages[2]

  test "truncated sealed data is refused before decrypting":
    let keys = deriveKeys(repeat('k', 32))
    expect DbError:
      discard openPage(keys, 1, 1, "short")
    expect DbError:
      discard openPage(keys, 1, 1, repeat('\0', TagLen - 1))

  test "keys are domain-separated":
    let k = deriveKeys(repeat('k', 32))
    check k.enc != k.mac
    check k.enc.len == 32 and k.mac.len == 32

  test "the master key length is enforced":
    expect DbError:
      discard deriveKeys(repeat('k', 16))

  test "nonces differ per page and per generation":
    check pageNonce(1, 1) != pageNonce(2, 1)
    check pageNonce(1, 1) != pageNonce(1, 2)
    check pageNonce(1, 1).len == 12

  test "constant-time comparison agrees with ==":
    check constantTimeEq("abc", "abc")
    check not constantTimeEq("abc", "abd")
    check not constantTimeEq("abc", "ab")
    check constantTimeEq("", "")
