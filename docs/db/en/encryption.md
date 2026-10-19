# Page encryption: the primitives (v0.2, slice 5a)

Status: **crypto core implemented and verified** (2026-10-19).
`src/fossil/db/crypto.nim`, `tests/db/t_crypto.nim` (23 tests, green in C **and**
in plain JS). Integration into the pager and the log is the next slice — see
"What is deliberately not done yet" at the bottom.

## The two decisions

**ChaCha20, not AES.** This code has to produce the same bytes in C, in
JavaScript and in wasm. AES needs either tables (a cache-timing side channel, and
1 KiB of constants in the wasm artifact) or careful bitslicing. ChaCha20 is
add-xor-rotate: constant time by construction, no tables, and JavaScript's
bitwise operators are already 32-bit, so the two backends agree without
negotiation.

**HMAC-SHA256, not Poly1305.** Poly1305 needs 130-bit arithmetic: either 64-bit
integers (emulated and slow in JS) or the 26-bit limb trick with floating point.
SHA-256 is plain 32-bit arithmetic with vectors older than most of the people who
will read the file. On a 4 KiB page the cost difference is noise.

**Encrypt-then-MAC**, because it is the composition with the simplest security
argument: the MAC covers the nonce and the ciphertext, so a flipped bit anywhere
is detected *before* a single byte is decrypted.

## What a stored page looks like

```
[ ciphertext : 4096 bytes ][ tag : 32 bytes ]
        nonce = f(pageId, generation), never stored
```

The nonce is derived, not stored: `pageId` in the low 4 bytes, the checkpoint
`generation` in the high 8. That closes two attacks that a plain page-id nonce
would leave open:

| Attack | Why it fails |
|---|---|
| swap page 7 and page 8 in the file | both authenticate against their own slot only |
| replay last checkpoint's page over this one | the generation is part of the nonce |

An unauthenticated stream cipher would happily "decrypt" either of those into
plausible-looking bytes, and the corruption would surface much later as a bug in
the B+tree.

## Verified against the standards, not against itself

Self-consistency proves nothing: a cipher with an inverted rotation order is
perfectly self-consistent and is not ChaCha20. Every primitive is checked against
its published vectors:

- SHA-256 — FIPS 180-4, including the one-million-`a` message;
- HMAC-SHA256 — RFC 4231 cases 1, 2 and 6 (the last with a key longer than the
  block, which must be hashed first);
- ChaCha20 — RFC 8439 §2.3.2 block output, byte for byte.

Two bugs were caught by those vectors, and both were invisible in review:

1. the quarter-round used the RFC's **left**-rotation amounts against `rotr`;
2. the key, nonce and output block were assembled **big**-endian, while ChaCha20
   specifies little-endian for all three.

Either one produces a cipher that works, round-trips, and is wrong.

## What the tests assert beyond the vectors

- a flipped bit anywhere — ciphertext, tag, first byte, last byte — is rejected;
- a page moved to another slot does not open;
- a page from another generation does not open;
- a wrong key fails, and the error text is **identical** every time: an error
  message that varies with how many bytes matched is an oracle;
- truncated input is refused before decryption, not after;
- the MAC comparison is constant time.

`constantTimeEq` exists because `==` on strings exits at the first differing
byte, which turns a MAC check into a byte-by-byte guessing game.

## Costs

| | |
|---|---|
| per page overhead | 32 bytes (0.78%) |
| ChaCha20 on 4 KiB | ~16 blocks, no branching |
| SHA-256 on 4 KiB | ~64 blocks |
| new wasm constants | 0 |

## What is deliberately not done yet

The primitive is done and tested; it is **not wired in**. Two pieces remain, and
neither is a formality:

1. **Stride.** A sealed page is 4128 bytes, not 4096. The pager must map
   `pid → pid * 4128` while still handing 4096-byte pages upward, and the header
   page has to stay readable before a key is available (so it carries the salt
   and the format version in the clear, and nothing else).
2. **The log.** Encrypting the main file while leaving the WAL in plaintext would
   be security theatre — after a crash, the log is exactly where the newest page
   images live. WAL frames need their payload sealed too, which changes the frame
   header from 12 to 12 bytes plus a tag.

Until both are done, `openStore` has no key parameter and no page is encrypted.
Saying so here is cheaper than a user assuming otherwise.
