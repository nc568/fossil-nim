# Page integrity in the plain (unencrypted) file

Decision record. Written before any code, so that K9L-83 (encryption) inherits a
format instead of defining one, and so that an unencrypted database is not
defenceless against bit rot.

## 1. The block

```
block 4096 = [ payload 4032 ][ trailer 64 ]
```

| offset | bytes | plain mode | encrypted mode |
|---|---|---|---|
| 0 | 4032 | page image (page header, cells, overflow) | ciphertext of the same |
| 4032 | 4 | CRC32 of bytes `0..4031`, little-endian | nonce[0..3] |
| 4036 | 60 | zero | nonce[4..23] (24 total at 4032..4055), gen 8 (4056), tag 32 (4064) |

The stride and the payload size are identical in both modes. Turning encryption
on is a re-encryption pass, not a migration: the file keeps its page count, its
B+tree structure and its offsets.

## 2. CRC parameters

CRC-32/ISO-HDLC — the zlib one, not CRC32C:

* poly `0xEDB88320` (reflected), init `0xFFFFFFFF`, refin/refout, xorout `0xFFFFFFFF`
* check value: `crc32("123456789") == 0xCBF43926`
* stored little-endian at offset 4032
* computed over the **payload only** (4032 bytes), never over the trailer —
  a checksum that covers its own storage explains itself away

CRC32 rather than CRC32C because the WAL already computes CRC32 over every frame
and has tested code for it; one implementation exercised in two places beats two
implementations where one is exercised. CRC32C's hardware acceleration does not
exist on wasm or JS, and those targets cannot be allowed to disagree with native.

## 3. Reserved bytes are not free

In plain mode bytes 4036..4095 **must be zero**. Anything else is `CORRUPT`, not
"ignore unknown trailing bytes". This is what makes an encrypted page read by
mistake as a plain one fail loudly instead of being parsed as garbage that
happens to have a plausible page header.

## 4. When the check runs

* `readPage`: verified before any parsing, on every read. Not lazily, not once
  per open — a check you can skip is a check that will be skipped.
* WAL replay: verified per frame, before the frame is applied.
* Checkpoint: pages are copied **verbatim**, the CRC is not recomputed. A
  checkpoint that recomputed would launder corruption into a clean-looking file.
* Write path: computed when the page is serialised, before the write.

## 5. Mismatch behaviour

`DbError` with code `CORRUPT`, carrying the page id. Never a `Defect` — a defect
escapes every handler in the program (see `audit-lessons.md`). The statement
fails, the process lives, and the pager then does what it does for a torn write:
if the log holds a newer image of that page, replay it. Nothing is ever
"repaired" silently.

## 6. Cost, measured rather than guessed

4032-byte page, Nim 2.2.12, gcc `-d:danger`, x86-64 sandbox, 20 000 iterations:

| implementation | µs/page | MB/s |
|---|---|---|
| bitwise (what the WAL does today) | 28.1 | 144 |
| nibble table, 16 entries | 18.0 | 224 |
| table of 256, **generated at init** | 9.9 | 408 |

All three produce identical values (checked against `0xCBF43926`). The current
bitwise version was chosen to keep 1 KiB of tables out of the wasm artifact — a
real constraint. The resolution keeps both properties: build the 256-entry table
**at startup, in RAM**. Zero bytes in the artifact, ~2.8× faster.

At 10 µs per 4 KiB page read, verifying every read costs about one core-second
per 100 000 pages — the honest price of the only corruption defence that exists
without a key. Slice-by-8 (8 KiB of tables, ~2–3 GB/s) is written down as the
next step if profiling ever shows the CRC dominating; not now, because it would
be an optimisation for a cost nobody has measured yet.

## 7. What it does not do

Without a key there is no authentication. Someone who rewrites a page *and* its
CRC is not detected. Integrity without a key defends against accident, not
against intent; the MAC in `encryption.md` is the answer to intent.

## 8. Tests this format must come with

These are acceptance criteria for the pager change, not optional extras:

1. flip every bit of a page (sampled), expect `CORRUPT`, never `Defect`
2. one non-zero reserved byte → `CORRUPT`
3. a page written in encrypted mode, read in plain mode → `CORRUPT` (rule of §3)
4. the stored CRC is the CRC of the payload, not of payload+trailer
5. WAL frame with a bad CRC is rejected and the good image is not lost
6. checkpoint output is byte-identical to the source pages (no recomputation)
7. native and JS compute the same CRC for the same bytes
