# BLAKE2b Algorithm Report

## 1. Specification

### Origin

BLAKE2b is a cryptographic hash function published in 2012 by Jean-Philippe Aumasson, Samuel Neves, Zooko Wilcox-O'Hearn, and Christian Winnerlein. It descends from **BLAKE** (a SHA-3 competition finalist), which itself is based on Daniel J. Bernstein's **ChaCha** stream cipher. BLAKE2 simplifies BLAKE by removing round-constant additions, reducing the number of rounds, and adding a parameter block for keying, salting, and personalization. It is specified in **RFC 7693**.

BLAKE2b is an **ARX** (Addition, Rotation, XOR) design: it uses only 64-bit modular additions, bitwise rotations, and XOR operations. There are no S-boxes, lookup tables, or data-dependent branches.

### Parameters

| Parameter           | BLAKE2b      | BLAKE2s      |
|---------------------|--------------|--------------|
| Word size           | 64-bit       | 32-bit       |
| Block size          | 128 bytes    | 64 bytes     |
| Rounds              | 12           | 10           |
| Max digest size     | 1--64 bytes  | 1--32 bytes  |
| Max key size        | 0--64 bytes  | 0--32 bytes  |
| Salt size           | 16 bytes     | 8 bytes      |
| Personalization     | 16 bytes     | 8 bytes      |
| Rotation constants  | 32, 24, 16, 63 | 16, 12, 8, 7 |

BLAKE2b is optimized for 64-bit platforms; BLAKE2s targets 8- to 32-bit platforms.

### Initialization

The initialization vectors are the first 64 bits of the fractional parts of the square roots of the first eight primes (identical to SHA-512):

```
IV[0] = 0x6A09E667F3BCC908    IV[1] = 0xBB67AE8584CAA73B
IV[2] = 0x3C6EF372FE94F82B    IV[3] = 0xA54FF53A5F1D36F1
IV[4] = 0x510E527FADE682D1    IV[5] = 0x9B05688C2B3E6C1F
IV[6] = 0x1F83D9ABFB41BD6B    IV[7] = 0x5BE0CD19137E2179
```

The hash state `h[0..7]` is initialized by XORing the IVs with a parameter block. For simple (unkeyed, no salt/personalization) hashing:

```
h[0] = IV[0] XOR 0x01010000 XOR (keyLength << 8) XOR digestLength
h[1..7] = IV[1..7]
```

When salt and personalization are used, `h[4..5]` and `h[6..7]` are also XORed with those values respectively.

### Compression Function

The compression function operates on a 4x4 matrix of 64-bit words (16 words total):

```
v[ 0]  v[ 1]  v[ 2]  v[ 3]      <- h[0..3] (chaining value)
v[ 4]  v[ 5]  v[ 6]  v[ 7]      <- h[4..7] (chaining value)
v[ 8]  v[ 9]  v[10]  v[11]      <- IV[0..3]
v[12]  v[13]  v[14]  v[15]      <- IV[4..7] XORed with counter/flags
```

Specifically:
- `v[12] = IV[4] XOR t[0]` (low 64 bits of byte counter)
- `v[13] = IV[5] XOR t[1]` (high 64 bits of byte counter)
- `v[14] = IV[6] XOR f[0]` (all-ones on the last block, zero otherwise)
- `v[15] = IV[7] XOR f[1]` (reserved, always zero for BLAKE2b)

### G Mixing Function

```
FUNCTION G(v, a, b, c, d, x, y):
    v[a] := (v[a] + v[b] + x) mod 2^64
    v[d] := (v[d] ^ v[a]) >>> 32
    v[c] := (v[c] + v[d]) mod 2^64
    v[b] := (v[b] ^ v[c]) >>> 24
    v[a] := (v[a] + v[b] + y) mod 2^64
    v[d] := (v[d] ^ v[a]) >>> 16
    v[c] := (v[c] + v[d]) mod 2^64
    v[b] := (v[b] ^ v[c]) >>> 63
```

Each G call takes two message words (`x`, `y`) selected by the SIGMA permutation table.

### Round Structure

Each of the 12 rounds performs 8 G function calls in two phases:

**Column step** (4 parallel G calls on columns):
```
G(v, 0, 4,  8, 12, m[sigma[r][ 0]], m[sigma[r][ 1]])
G(v, 1, 5,  9, 13, m[sigma[r][ 2]], m[sigma[r][ 3]])
G(v, 2, 6, 10, 14, m[sigma[r][ 4]], m[sigma[r][ 5]])
G(v, 3, 7, 11, 15, m[sigma[r][ 6]], m[sigma[r][ 7]])
```

**Diagonal step** (4 parallel G calls on diagonals):
```
G(v, 0, 5, 10, 15, m[sigma[r][ 8]], m[sigma[r][ 9]])
G(v, 1, 6, 11, 12, m[sigma[r][10]], m[sigma[r][11]])
G(v, 2, 7,  8, 13, m[sigma[r][12]], m[sigma[r][13]])
G(v, 3, 4,  9, 14, m[sigma[r][14]], m[sigma[r][15]])
```

After all 12 rounds: `h[i] = h[i] XOR v[i] XOR v[i+8]` for i = 0..7.

### SIGMA Permutation Table

The message schedule uses 10 permutations; rounds 10--11 wrap to `sigma[0]` and `sigma[1]`:

| Round | Permutation |
|-------|-------------|
| 0  | 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 |
| 1  | 14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3 |
| 2  | 11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4 |
| 3  | 7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8 |
| 4  | 9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13 |
| 5  | 2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9 |
| 6  | 12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11 |
| 7  | 13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10 |
| 8  | 6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5 |
| 9  | 10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0 |

### Keyed Hashing (MAC Mode)

BLAKE2b has built-in keying -- no HMAC construction is needed. When a key is provided, it is zero-padded to a full 128-byte block and prepended to the message as the first block. The key length is encoded in the parameter block.

---

## 2. Test Vectors and Implementation Validation

### RFC 7693 Test Vectors

RFC 7693 (Appendix A) provides a computational trace for **BLAKE2b-512("abc")**:

```
BA80A53F981C4D0D 6A2797B69F12F6E9 4C212F14685AC4B7 4B12BB6FDBFFA2D1
7D87C5392AAB792D C252D5DE4533CC95 18D38AA8DBF1925A B92386EDD4009923
```

**BLAKE2b-512("")** (empty string):

```
786A02F742015903 C6C6FD852552D272 912F4740E1584761 8A86E217F71F5419
D25E1031AFEE5853 13896444934EB04B 903A685B1448B755 D56F701AFE9BE2CE
```

Appendix A also includes a full state-after-each-round trace, invaluable for debugging implementations.

### RFC 7693 Self-Test (Appendix E)

The RFC specifies a self-test procedure in C that generates and validates keyed and unkeyed hashes of varying digest lengths, producing a final 32-byte digest:

```
C23A7800D98123BD 10F506C61E29DA56 03D763B8BBAD2E73 7F5E765A7BCCD475
```

This is the single most important validation check for a new implementation.

### Official BLAKE2 Repository Vectors

The reference repository at [github.com/BLAKE2/BLAKE2](https://github.com/BLAKE2/BLAKE2) provides exhaustive KAT (Known Answer Test) files under `/testvectors/`:

- **`blake2b-kat.txt`**: 256 test vectors for keyed BLAKE2b. Messages are sequential bytes (0x00, then 0x00 0x01, ..., up to 0x00..0xFF) with a fixed 64-byte key (0x00..0x3F), each producing a 512-bit digest.
- **`blake2-kat.json`**: JSON-formatted vectors covering all BLAKE2 variants.

This systematic methodology catches off-by-one errors, padding bugs, and counter-related issues.

### Additional Test Vector Sources

- **OpenSSL**: BLAKE2 vectors in `test/evptests.txt`.
- **Python hashlib** (pyblake2): Tests against reference vectors for keyed hashing, salt, and personalization.
- **libsodium**: Internal test suite validates `crypto_generichash` (BLAKE2b) against reference vectors.

### Common Implementation Pitfalls

1. **Endianness**: All multi-byte values are **little-endian**. The parameter block must be serialized in little-endian. Big-endian platforms require byte-swapping.

2. **Counter semantics**: The counter `t` counts **bytes** (not bits, unlike SHA-2). It is 128 bits split across `t[0]` (low) and `t[1]` (high). Carry from `t[0]` to `t[1]` must be handled for messages exceeding 2^64 bytes.

3. **Last-block flag**: `v[14]` must be inverted (`XOR 0xFFFFFFFFFFFFFFFF`) only on the final block. This is the single most commonly reported bug in new implementations.

4. **Padding**: The last block is zero-padded to 128 bytes. Unlike SHA-family, there is no length-encoding padding.

5. **Keyed mode**: The key block must be counted in the byte counter. Forgetting this is a common error.

6. **SIGMA wrap-around**: 12 rounds but only 10 permutations. Rounds 10 and 11 reuse `sigma[0]` and `sigma[1]`. Hardcoding 10 rounds or failing to wrap produces incorrect output.

---

## 3. Performance of Single-Threaded Implementations

### Why BLAKE2b Is Fast

- **ARX construction**: Only 64-bit additions, XORs, and rotations -- single-cycle operations on modern CPUs. No S-boxes or table lookups eliminates cache-timing side channels.
- **Instruction-level parallelism**: The 4 column/diagonal G calls are independent, letting superscalar CPUs execute multiple G operations per cycle.
- **64-bit word size**: Native-width operations on 64-bit platforms give a 2x advantage over 32-bit designs like SHA-256.
- **Fewer rounds than SHA-3**: 12 rounds vs. 24 for Keccak.
- **SIMD-friendly**: The column/diagonal structure maps naturally to AVX2 registers.

### Cycles Per Byte (Long Messages, x86-64)

| Hash Function  | Approx. cpb | Notes |
|----------------|-------------|-------|
| **BLAKE2b**    | **2.8 -- 3.5** | 2.81 cpb (Kaby Lake, AVX2); 3.5 cpb (Ivy Bridge) |
| MD5            | ~5.0        | Broken; BLAKE2b is faster on modern 64-bit CPUs |
| SHA-1          | ~3.5 -- 4.0 | Broken; ~3.51 cpb (Kaby Lake, OpenSSL) |
| SHA-256        | ~12 -- 15   | Software only; ~3.5 cpb with SHA-NI extensions |
| SHA-512        | ~5 -- 8     | ~5.11 cpb (Kaby Lake, OpenSSL) |
| SHA-3-256      | ~8          | |
| SHA-3-512      | ~10 -- 12   | |
| BLAKE3         | ~0.95       | Reduced rounds (7) + wide tree structure |

### Throughput (MB/s)

**Intel i5-8250U (Kaby Lake Refresh), single-threaded:**

| Implementation               | Throughput   | cpb  |
|------------------------------|-------------|------|
| BLAKE2b (blake2b_simd, AVX2) | 1005 MB/s  | 2.81 |
| BLAKE2b (libsodium, AVX2)    | 939 MB/s   | 3.07 |
| BLAKE2bp (4-way parallel)     | ~1900 MB/s | 1.44 |
| SHA-1 (OpenSSL)              | ~800 MB/s  | 3.51 |
| SHA-512 (OpenSSL)            | ~550 MB/s  | 5.11 |

**Key observations:**
- BLAKE2b at ~3 cpb is faster than software SHA-256 (~12-15 cpb) and SHA-512 (~5-8 cpb), and comparable to or faster than MD5 on 64-bit platforms.
- SHA-256 with Intel SHA-NI instructions (Goldmont/Ice Lake+) drops to ~3.5 cpb, reversing the advantage.
- BLAKE3 is ~3x faster than BLAKE2b single-threaded (~0.95 cpb) due to fewer rounds and a tree structure enabling SIMD parallelism.
- On ARM (e.g. Cortex-A72), BLAKE2b is the fastest available hash since ARM lacks SHA-NI-equivalent acceleration for SHA-256.

### Notable Implementations

| Implementation | Language | Notes |
|----------------|----------|-------|
| [BLAKE2 reference](https://github.com/BLAKE2/BLAKE2) | C | Portable + SSE/AVX variants. CC0 licensed. |
| libsodium | C | Default `crypto_generichash`. AVX2-optimized by Samuel Neves. |
| OpenSSL (1.1.0+) | C | `BLAKE2b512` via EVP interface. |
| [blake2b_simd](https://github.com/oconnor663/blake2_simd) | Rust | Dynamic SIMD detection. Faster than libsodium. |
| blake2 (RustCrypto) | Rust | Part of RustCrypto hashes. Uses `digest` trait. |
| Go `x/crypto/blake2b` | Go | AVX2 on amd64. |
| Crypto++ | C++ | SSE and NEON optimizations. |
| Botan | C++ | Full parameter support (salt, personalization). |

The Samuel Neves AVX2 implementation (used by libsodium and blake2b_simd) is the gold standard, mapping the 4 column/diagonal G calls onto 256-bit AVX2 registers to achieve ~2.8-3.1 cpb.

---

## References

- [RFC 7693 -- The BLAKE2 Cryptographic Hash and Message Authentication Code](https://www.rfc-editor.org/rfc/rfc7693)
- [BLAKE2 Official Website](https://www.blake2.net/)
- [BLAKE2 Paper: "BLAKE2: simpler, smaller, fast as MD5"](https://eprint.iacr.org/2013/322.pdf)
- [BLAKE2 Reference Implementation (GitHub)](https://github.com/BLAKE2/BLAKE2)
- [blake2_simd Benchmarks](https://github.com/oconnor663/blake2_simd)
