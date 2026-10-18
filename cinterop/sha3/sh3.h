#ifndef _SH3_H_
#define _SH3_H_

#include <stddef.h>
#include <stdint.h>

// Fossil-compatible SHA3Context wrapper around tiny_sha3
typedef struct {
    // tiny_sha3 context
    union {
        uint8_t b[200];
        uint64_t q[25];
    } st;
    int pt, rsiz, mdlen;
} SHA3Context;

int SHA3Init(SHA3Context *ctx, int bits);
int SHA3Update(SHA3Context *ctx, const unsigned char *data, size_t n);
int SHA3Final(SHA3Context *ctx, unsigned char *outHash);

// SHA1 compat for QBE
typedef struct {
    uint32_t state[5];
    uint32_t count[2];
    unsigned char buffer[64];
} SHA1Context;

void SHA1Init(SHA1Context *ctx);
void SHA1Update(SHA1Context *ctx, const unsigned char *data, unsigned int len);
void SHA1Final(SHA1Context *ctx, unsigned char *outHash);

#endif
