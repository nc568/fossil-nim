# Page encryption: the primitives (v0.2, slice 5b)

Status: **crypto core implemented and verified** (2026-10-19).
`src/fossil/db/crypto.nim`, `tests/db/t_crypto.nim` (34 tests, green in C **and**
in plain JS). Integration into the pager and the log is the next slice — see
"What is deliberately not done yet" at the bottom.

## Decisions, and what they cost

**ChaCha20 + HMAC-SHA256, encrypt-then-MAC.** The task asked for
XChaCha20-Poly1305. Poly1305 was rejected because it needs 130-bit arithmetic:
either 64-bit integers (emulated and slow in JS) or the 26-bit limb trick with
floating point. SHA-256 is plain 32-bit arithmetic with vectors older than most
of the people who will read the file, and on a 4 KiB page the cost difference is
noise. The MAC key and the encryption key are separate, both derived from the
master key by domain-separated SHA-256 (`foccil/page-enc\0`, `foccil/page-mac\0`),
so a break in one does not hand over the other.

**XChaCha20, not plain ChaCha20.** This is the part that changed after review,
and it changed for a reason worth writing down. The cheap design derives the
nonce from `(pageId, generation)` and stores nothing. It looks sufficient —
until you ask what happens when the file is *copied*:

| Scenario | Derived nonce | Random nonce |
|---|---|---|
| restore an old backup, then write | same `(pageId, generation)`, new plaintext → keystream reuse | new nonce, safe |
| fork the file (copy-a-clone workflow) | both branches write the same pairs → guaranteed reuse | safe |
| replay a WAL across a salt bump | same pair, different content | safe |

Keystream reuse does not merely leak; it XORs two plaintexts together and hands
the result to the attacker. No amount of care in three separate code paths
(page writes, checkpoints, recovery) makes a derived nonce safe against a
restore, because the restore happens *outside* the code. A 192-bit random nonce
turns a invariant that must never be violated into a 2^-96 event.

The price: 24 bytes per page, stored next to the ciphertext. That is 0.6%, and
it is the whole reason the format below is not the obvious one.

## What a stored page looks like

```
[ ciphertext : N bytes ][ tag : 32 bytes ]
        nonce = 24 random bytes, stored by the storage layer
```

`sealPage` returns `nonce || ciphertext || tag`; `SealedOverhead` is 56. The
crypto layer stays layout-agnostic — how the nonce is anchored in the file is
the pager's decision, and is specified in K9L-83.

The tag is `HMAC-SHA256(macKey, pageId || generation || nonce || ciphertext)`.
`pageId` and `generation` are 4- and 8-byte little-endian fields supplied by the
caller and persisted by the storage layer. Two deliberate details:

- **the nonce is inside the MAC.** It has to be: the nonce is attacker-visible
  and attacker-writable, and a flipped nonce bit corrupts the plaintext without
  touching the tag.
- **`pageId` is what stops a page swap**, not the nonce. Two pages of the same
  file are both authentic ciphertext; only their slot number tells them apart.

`generation` binds a page to the epoch it was written in. It is *not* the WAL
salt and must not be: a salt that changes on every checkpoint would orphan every
page that the checkpoint did not rewrite. The salt never enters key derivation
at all, which is why rotating it cannot make an old page unreadable — a
requirement, not an accident.

## Verified against the standards, not against itself

Self-consistency proves nothing: a cipher with an inverted rotation order is
perfectly self-consistent and is not ChaCha20. Every primitive is checked against
its published vectors:

- SHA-256 — FIPS 180-4, including the one-million-`a` message;
- HMAC-SHA256 — RFC 4231 cases 1, 2 and 6 (the last with a key longer than the
  block, which must be hashed first);
- ChaCha20 — RFC 8439 §2.3.2 block output, byte for byte;
- HChaCha20 — draft-irtf-cfrg-xchacha-03 §2.2.1 subkey;
- XChaCha20 — draft §A.2.2, counter 1, blocks 1 and 5 through 8 of the keystream.

Four bugs were caught by those vectors, and none was visible in review:

1. the quarter-round used the RFC's **left**-rotation amounts against `rotr`;
2. the key, nonce and output block were assembled **big**-endian, while ChaCha20
   specifies little-endian for all three;
3. HChaCha20 must *not* add the initial state back after the rounds — the
   ChaCha20 habit produces 32 self-consistent, wrong bytes;
4. the draft prints the post-rounds state as **word values** and the subkey as
   **little-endian bytes**, so the two disagree by a byte swap inside every word.
   The test asserted the state-table order first and failed against a correct
   implementation.

## What the tests assert beyond the vectors

- a flipped bit anywhere — nonce, ciphertext, tag, first byte, last byte — is
  rejected;
- a page moved to another slot does not open, including when the attacker
  transplants the nonce as well;
- a page from another generation does not open;
- **fork test**: the same `(pageId, generation)` sealed twice yields unrelated
  ciphertexts and both still open — the property a derived nonce cannot offer;
- **nonce property test**: 20 000 consecutive nonces are distinct (a collision is
  the one failure that silently destroys confidentiality, so this is a property
  test, not a smoke test);
- a wrong key fails, and the error text is **identical** every time: an error
  message that varies with how many bytes matched is an oracle;
- truncated input is refused before decryption, not after;
- the MAC comparison is constant time;
- the per-page overhead is pinned at 56 bytes, because the pager sizes its
  stride from it.

`randomNonce` raises if the OS cannot supply entropy. There is no fallback: a
predictable nonce is worse than a failed write.

## Costs

| | |
|---|---|
| per page overhead | 56 bytes (24 nonce + 32 tag) |
| XChaCha20 on 4 KiB | 1 HChaCha20 + ~16 ChaCha blocks, no branching |
| SHA-256 on 4 KiB | ~64 blocks for the tag, plus key derivation once per open |
| randomness | 24 bytes per sealed page from `std/sysrand` |
| new wasm constants | 0 |

## Page integrity without a key

Encryption must not be the only thing that detects bit rot. A database that is
never encrypted is exactly as exposed to a failing disk as an encrypted one, and
"you get corruption detection when you buy the encryption module" is not a
security posture, it is an upsell.

So the page layout is fixed **once**, now, in a way that both modes share:

```
block 4096 = [ payload 4032 ][ trailer 64 ]
```

| mode | trailer | check |
|---|---|---|
| plain | `[crc32 4][zeros 60]` | CRC32 of the 4032-byte payload |
| encrypted | `[nonce 24][gen 8][tag 32]` | HMAC-SHA256 over `pageId ‖ gen ‖ nonce ‖ ct` |

Both modes have the same payload size, the same stride, and the same page count,
which is the whole point: turning encryption on becomes a re-encryption pass, not
a format change, and a file never has to be migrated between layouts. The cost to
an unencrypted database is 64 bytes per page — 1.5% — paid once instead of paying
a format migration later.

A mismatch is a `DbError` with code `CORRUPT`, never a `Defect`: the difference
matters because a defect escapes every handler in the program (see
`audit-lessons.md`). The pager treats a page that fails its check the way it
treats a torn write — the log may still hold a good image of it.

CRC32 rather than CRC32C: the WAL already computes CRC32 over every frame and has
tested it, and one checksum implementation that is exercised in two places beats
two implementations where one is exercised.

What this does and does not buy:

- **buys**: a flipped bit anywhere in a page is refused instead of returned as
  data — the gap that `audit-lessons.md` calls the strongest non-confidentiality
  argument for this work;
- **does not buy**: any protection against an attacker who rewrites *both* the
  page and its CRC. That needs the MAC, which needs a key, which is the
  encryption story above. With no key there is no secret to authenticate with;
  integrity without a key is a defence against accident, not against intent.

## Known limitation: rollback of a single page

The MAC makes a page tamper-evident, but a page can still be replaced by an
*older, authentic* version of itself. Nothing inside a single file can detect
that: the attacker replays a value the file itself once produced. Detection needs
trusted state outside the file — a saved epoch, a manifest, a filesystem
snapshot chain. The plan is an optional `DbOptions.expectedGeneration`: pages
whose stored generation is older than the caller's expectation are refused.
Whole-file rollback (restoring a backup) is undetectable for the same reason, and
will be documented as out of scope rather than papered over.

## What is deliberately not done yet

The primitive is done and tested; it is **not wired in**. `openStore` has no key
parameter and no page is encrypted. Two pieces remain, both tracked as K9L-83:

1. **Layout.** A sealed page is 56 bytes larger than its payload. K9L-83 compares
   a 4128-byte stride against keeping the on-disk block at exactly 4096 and
   shrinking the payload, and the second option wins on sector alignment and
   write amplification:

### Stride: 4128 bytes, or 4096 with a smaller payload?

| | A: stride 4128 | B: block 4096, tag inline | C: block 4096, 16-byte tag |
|---|---|---|---|
| payload per page | 4096 | 4032 (24 nonce + 8 gen + 32 tag) | 4080 |
| sector alignment | **lost**: page k starts at 4128·k, so nearly every page straddles a 4 KiB boundary | kept: one page = one sector | kept |
| power loss mid-write | tail of one page and head of the next can be torn together; the MAC catches it, but two pages are now suspect | one page is torn, the MAC catches it, recovery falls back to the log | same |
| write amplification | a 1-page update dirties 2 sectors | 1 sector | 1 sector |
| `filesize / pagesize` | still exact, but non-power-of-two | exact and a power of two | exact |

B wins. The 8 leftover bytes are the per-page generation that the MAC binds (see
above); C saves 16 more bytes at the cost of a truncated tag, which is not worth
the extra rule. The cost of B is 64 bytes of payload per page — 1.5% — paid once
in fanout, against 2x write amplification on every small update.


2. **The log.** Encrypting the main file while leaving the WAL in plaintext would
   be security theatre: after a crash, the log is exactly where the newest page
   images live.

Until both are done, saying so is cheaper than a user assuming otherwise.
