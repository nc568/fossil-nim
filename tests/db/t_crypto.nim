## Crypto tests: published vectors, then the attacks that matter.
##
## A home-grown primitive is only worth having if it reproduces the standard
## vectors byte for byte. Everything here is checked against the RFCs first and
## against itself second — self-consistency would pass on a broken cipher that
## is broken identically everywhere.

import std/[strutils, tables, unittest]
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

suite "hchacha20 (draft-irtf-cfrg-xchacha-03 §2.2.1)":
  test "the published subkey":
    # The vector that catches the classic mistake: HChaCha20 does NOT add the
    # initial state back after the rounds. Adding it produces 32 bytes that are
    # self-consistent and wrong.
    #
    # Reading it is a trap of its own: the draft prints the post-rounds state as
    # *word values* ("423b4182 fe7bb227 ...") and the subkey as *little-endian
    # bytes*, so the two disagree by a byte swap inside every word. This test
    # asserted the state-table order first and failed against a correct
    # implementation.
    let key = unhex("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
    let nonce = unhex("000000090000004a0000000031415927")
    check hex(hchaCha20(key, nonce)) ==
      "82413b4227b27bfed30e42508a877d73" &
      "a0f9e4d58a74a853c12ec41326d3ecdc"

  test "wrong nonce length is refused":
    expect DbError:
      discard hchaCha20(repeat('k', 32), repeat('n', 12))

suite "xchacha20 (draft §A.2.2, block counter 1)":
  test "published keystream, blocks 1 and 5 to 8":
    let key = unhex("808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f")
    let iv = unhex("404142434445464748494a4b4c4d4e4f5051525354555658")
    let ks = xChaCha20Xor(key, iv, repeat('\0', 288), 1)
    # 0x00..0x3f and 0xe0..0x11f: block 1 and a slice four blocks later. A
    # counter or loop bug shows up in one of the two.
    check hex(ks[0x00 ..< 0x40]) ==
      "29624b4b1b140ace53740e405b216854" &
      "0fd7d630c1f536fecd722fc3cddba7f4" &
      "cca98cf9e47e5e64d115450f9b125b54" &
      "449ff76141ca620a1f9cfcab2a1a8a25"
    check hex(ks[0xe0 ..< 0x120]) ==
      "b3df507ca8c924f7017b7e712d15a2eb" &
      "5c50484451e54e1b4b995bd8fdd94597" &
      "bb94d7af0b2c04df10ba0890899ed929" &
      "3a0f55b8bafa999264035f1d4fbe7fe0"

  test "encrypting then decrypting returns the original":
    let key = unhex("808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f")
    let iv = unhex("404142434445464748494a4b4c4d4e4f5051525354555658")
    var data = newString(1000)
    for i in 0 ..< data.len: data[i] = char(i mod 256)
    let ct = xChaCha20Xor(key, iv, data)
    check ct != data
    check xChaCha20Xor(key, iv, ct) == data

  test "the 8-byte tail of the nonce alone changes everything":
    ## XChaCha's promise: sharing 16 nonce bytes is harmless, because the subkey
    ## changes. If this ever passes with equal ciphertexts, HChaCha20 is not
    ## being used at all.
    let key = unhex("808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f")
    let base = unhex("404142434445464748494a4b4c4d4e4f5051525354555658")
    var other = base
    other[23] = char(uint8(other[23]) xor 1)
    let z = repeat('\0', 64)
    check xChaCha20Xor(key, base, z) != xChaCha20Xor(key, other, z)

  test "wrong nonce length is refused":
    expect DbError:
      discard xChaCha20Xor(repeat('k', 32), repeat('n', 12), "data")

suite "random nonces":
  test "24 bytes, and 20000 in a row are distinct":
    ## A nonce collision under one key is the one failure that silently destroys
    ## confidentiality, so this is a property test, not a smoke test.
    var seen = initTable[string, bool]()
    for _ in 0 ..< 20_000:
      let n = randomNonce()
      check n.len == PageNonceLen
      check not seen.hasKeyOrPut(n, true)

  test "a fresh nonce never repeats the previous one":
    var last = randomNonce()
    for _ in 0 ..< 1_000:
      let n = randomNonce()
      check n != last
      last = n

suite "page sealing":
  test "seal then open returns the page":
    let keys = deriveKeys(repeat('k', 32))
    var page = newString(4040)
    for i in 0 ..< page.len: page[i] = char(i mod 251)
    let sealed = sealPage(keys, 7, 1, page)
    check sealed.len == page.len + SealedOverhead
    check sealed[0 ..< 32] != page[0 ..< 32]     # actually encrypted
    check openPage(keys, 7, 1, sealed) == page

  test "sealing the same page twice gives different bytes":
    ## The property a derived nonce cannot offer: two writers that both think
    ## they are at generation 1 still produce unrelated ciphertexts.
    let keys = deriveKeys(repeat('k', 32))
    let a = sealPage(keys, 7, 1, repeat('A', 4040))
    let b = sealPage(keys, 7, 1, repeat('A', 4040))
    check a != b
    check openPage(keys, 7, 1, a) == openPage(keys, 7, 1, b)

  test "a flipped bit anywhere in the ciphertext is caught":
    let keys = deriveKeys(repeat('k', 32))
    let page = repeat('A', 4040)
    let sealed = sealPage(keys, 7, 1, page)
    for pos in [0, 1, 23, 24, 100, 2048, 4040, 4060, sealed.len - 1]:
      var bad = sealed
      bad[pos] = char(uint8(bad[pos]) xor 1)
      expect DbError:
        discard openPage(keys, 7, 1, bad)

  test "a flipped bit in the stored nonce is caught":
    ## The nonce is attacker-visible and attacker-writable. It is inside the MAC
    ## for exactly this reason.
    let keys = deriveKeys(repeat('k', 32))
    let sealed = sealPage(keys, 7, 1, repeat('A', 4040))
    var bad = sealed
    bad[3] = char(uint8(bad[3]) xor 0x40)
    expect DbError:
      discard openPage(keys, 7, 1, bad)

  test "a page moved to another slot fails to open":
    ## The attack this prevents: swapping two pages in the file. Both are
    ## authentic ciphertext, so only the page id in the MAC tells them apart.
    let keys = deriveKeys(repeat('k', 32))
    let sealed = sealPage(keys, 7, 1, repeat('A', 4040))
    expect DbError:
      discard openPage(keys, 8, 1, sealed)

  test "a page from another generation fails to open":
    ## And this one: replaying last checkpoint's page over this one.
    let keys = deriveKeys(repeat('k', 32))
    let sealed = sealPage(keys, 7, 1, repeat('A', 4040))
    expect DbError:
      discard openPage(keys, 7, 2, sealed)

  test "a whole sealed page replayed into another slot fails":
    ## Same as the swap test but with the nonce transplanted as well, which is
    ## what an attacker who understands the format would try.
    let keys = deriveKeys(repeat('k', 32))
    let a = sealPage(keys, 7, 1, repeat('A', 4040))
    let b = sealPage(keys, 8, 1, repeat('B', 4040))
    var spliced = a[0 ..< PageNonceLen] & b[PageNonceLen ..< b.len]
    expect DbError:
      discard openPage(keys, 8, 1, spliced)

  test "fork: two copies of the file diverge without a nonce clash":
    ## A restored backup or a forked clone replays (pageId, generation) with new
    ## contents. Under a derived nonce that is keystream reuse; under a random
    ## nonce the two ciphertexts are independent and both authenticate.
    let keys = deriveKeys(repeat('k', 32))
    let original = sealPage(keys, 3, 1, repeat('O', 4040))
    let forked = sealPage(keys, 3, 1, repeat('F', 4040))
    check original[PageNonceLen ..< PageNonceLen + 64] !=
          forked[PageNonceLen ..< PageNonceLen + 64]
    check openPage(keys, 3, 1, original) == repeat('O', 4040)
    check openPage(keys, 3, 1, forked) == repeat('F', 4040)

  test "a wrong key fails, and tells you nothing about how wrong":
    let good = deriveKeys(repeat('k', 32))
    let bad = deriveKeys(repeat('K', 32))
    let sealed = sealPage(good, 7, 1, repeat('A', 4040))
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
      discard openPage(keys, 1, 1, repeat('\0', SealedOverhead - 1))

  test "keys are domain-separated":
    let k = deriveKeys(repeat('k', 32))
    check k.enc != k.mac
    check k.enc.len == 32 and k.mac.len == 32

  test "the master key length is enforced":
    expect DbError:
      discard deriveKeys(repeat('k', 16))

  test "constant-time comparison agrees with ==":
    check constantTimeEq("abc", "abc")
    check not constantTimeEq("abc", "abd")
    check not constantTimeEq("abc", "ab")
    check constantTimeEq("", "")

  test "the overhead is 56 bytes, whatever the payload":
    ## 24 nonce + 32 tag. Pinned because the pager sizes its stride from it.
    let keys = deriveKeys(repeat('k', 32))
    for n in [0, 1, 4040, 8192]:
      check sealPage(keys, 1, 1, repeat('x', n)).len == n + 56
