# Plan: Three Pure Elm BLAKE2b Implementations

## Context

We need a pure Elm implementation of BLAKE2b (RFC 7693). Kernel JS, ports, and BLAKE2s are off-limits. We'll build three variants that differ in how they represent 64-bit words, to compare their performance characteristics. The core challenge: Elm only has 32-bit integers and bitwise ops, so all 64-bit arithmetic must be emulated with hi/lo Int pairs.

## Project Structure

```
blake2b/
├── elm.json                              -- package
├── src/
│   ├── Blake2b.elm                       -- Public facade (re-exports Record as default)
│   ├── Blake2b/
│   │   ├── Record.elm                    -- Variant 1: { hi, lo } records
│   │   ├── Tuple.elm                     -- Variant 2: ( hi, lo ) tuples
│   │   ├── Positional.elm                -- Variant 3: raw Int pairs, no wrapper
│   │   └── Internal/
│   │       ├── Constants.elm             -- IVs as 16 top-level Ints, shared
│   │       └── Decode.elm                -- Block decoding & digest encoding helpers
├── tests/
│   ├── TestHelpers.elm                   -- hexToBytes, bytesToHex
│   ├── KatVectors.elm                    -- Shared test vector data
│   ├── Blake2bRecordTest.elm
│   ├── Blake2bTupleTest.elm
│   ├── Blake2bPositionalTest.elm
│   └── Blake2bCrossCheckTest.elm         -- All three must match
├── benchmarks/
│   ├── elm.json                          -- application, with elm-explorations/benchmark
│   └── src/
│       └── Main.elm                      -- Benchmark runner
```

## Shared Foundation (`Blake2b.Internal.*`)

### Constants.elm

16 top-level `Int` constants for the 8 IVs (no data structures):

```elm
iv0Hi = 0x6A09E667
iv0Lo = 0xF3BCC908  -- runtime: JS number 4089235720, works fine
-- ... through iv7Hi, iv7Lo
```

**SIGMA table**: Not stored as a data structure. Each of the 12 rounds inlines its sigma permutation at the call site in `compress`. The `compress` function calls a generic `round` function 12 times, each time passing the 16 message words in sigma-permuted order. Zero lookup overhead.

### Decode.elm

**Block decoding** (128 bytes → 32 Ints, little-endian):

Chain 32 `Bytes.Decode.unsignedInt32 LE` calls via `andThen`. Little-endian means bytes `[b0,b1,b2,b3,b4,b5,b6,b7]` decode as `m0Lo = u32LE(b0..b3)`, `m0Hi = u32LE(b4..b7)`. Returns a 32-field record `{ m0Hi, m0Lo, ..., m15Hi, m15Lo }`. This runs once per block — the closure overhead is negligible.

**Digest encoding** (hash state → first N bytes):

Encode all 8 hash words as 16 × `unsignedInt32 LE` (lo first, then hi for each word), producing 64 bytes. Then use `Bytes.Decode.bytes digestLength` to extract the prefix. One allocation, clean.

**Padding**: Zero-pad partial last block to 128 bytes using `Bytes.Encode.sequence` with `List.repeat padLen (unsignedInt8 0)`. Runs once per hash — cost irrelevant.

## The Three Variants

### Common API (all three expose the same interface)

```elm
hash : { digestLength : Int, key : Bytes, data : Bytes } -> Bytes
hash512 : Bytes -> Bytes
hash256 : Bytes -> Bytes
hash224 : Bytes -> Bytes
```

### Common Algorithm Flow

```
hash config =
  1. Init h[0..7] = IV[0..7] XOR parameter block
  2. If keyed: prepend key padded to 128 bytes
  3. Process full 128-byte blocks (counter += 128 each, no final flag)
  4. Pad + process last block (counter = total bytes consumed, final flag set)
  5. Extract first digestLength bytes from h[0..7] in LE
```

Block iteration uses `Bytes.Decode.loop` with an accumulator carrying (hash state, byte counter, remaining byte count).

Counter is 4 Ints (t0Hi, t0Lo, t1Hi, t1Lo) for 128-bit total. Practically only t0Lo changes.

### Variant 1: Record (`Blake2b.Record`)

**U64 type**: `type alias U64 = { hi : Int, lo : Int }`

**Primitive ops** (each returns a new U64 record):
```elm
add64 : U64 -> U64 -> U64    -- carry via shiftRightZfBy 0 unsigned comparison
xor64 : U64 -> U64 -> U64    -- XOR each half
rotr64by32 : U64 -> U64      -- swap hi/lo (1 record alloc)
rotr64by24 : U64 -> U64      -- shift-and-or: (hi>>>24)|(lo<<8) per half
rotr64by16 : U64 -> U64      -- shift-and-or: (hi>>>16)|(lo<<16) per half
rotr64by63 : U64 -> U64      -- = rotl by 1: (hi<<1)|(lo>>>31) per half
```

Four specialized rotation functions (no branching on rotation amount).

**G function**: Takes 6 U64 args (a, b, c, d, x, y), returns `{ a : U64, b : U64, c : U64, d : U64 }`.
~21 intermediate U64 allocations per G call (8 adds + 4 xors + 4 rotations + some xor-before-rotate).

**State types**:
- `HashState`: 8-field record of U64 (`{ h0 : U64, ..., h7 : U64 }`)
- `WorkingVector`: 16-field record of U64 (`{ v0 : U64, ..., v15 : U64 }`)
- `MessageBlock`: 16-field record of U64 (`{ m0 : U64, ..., m15 : U64 }`)

**Round function**: Generic `round` taking 16 U64 message-word args + WorkingVector → WorkingVector. Column step (4 G calls on independent columns), then diagonal step (4 G calls using column outputs). Returns a new WorkingVector built from the 8 G results.

**compress**: Calls `round` 12 times, each with sigma-permuted message words inlined at the call site. Then `h'[i] = xor64 (xor64 h[i] v[i]) v[i+8]`.

**Allocation estimate per block**: 12 rounds × (8 G calls × ~21 U64 + 8 G-return records + 1 WorkingVector) ≈ **~2100 JS objects**.

### Variant 2: Tuple (`Blake2b.Tuple`)

**U64 type**: `type alias U64 = ( Int, Int )` — hi first by convention.

**Primitives**: Same logic, tuple construction/destructuring:
```elm
add64 : U64 -> U64 -> U64
add64 ( aHi, aLo ) ( bHi, bLo ) = ...  -- returns ( hi, lo )
```

Tuples compile to `{ $: '#2', a: hi, b: lo }` (3-field JS object vs 2-field for records). Marginally heavier per allocation.

**G return type**: Cannot use a 4-tuple (Elm max is 3-tuple). Use a custom type:
```elm
type GResult = GResult U64 U64 U64 U64
```

**State types**: Same structure as Record (WorkingVector is still a record *of tuples*).

**Allocation estimate per block**: Similar to Record, ~2100 JS objects, each slightly larger due to tuple tag field.

### Variant 3: Positional (`Blake2b.Positional`)

**No U64 type**. All 64-bit values are raw `(Int, Int)` pairs passed as separate function arguments or `let` bindings.

**Key insight**: Inside the G function, all intermediate 64-bit ops become `let` bindings on raw Ints — these compile to JS `var` statements with **zero allocation**. The only allocation is the return value.

**G function**:
```elm
type G8 = G8 Int Int Int Int Int Int Int Int

g : Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> G8
g aHi aLo bHi bLo cHi cLo dHi dLo xHi xLo yHi yLo =
    let
        -- add64(a, b): 3 let bindings
        abLo = Bitwise.shiftRightZfBy 0 (aLo + bLo)
        abCarry = if abLo < Bitwise.shiftRightZfBy 0 aLo then 1 else 0
        abHi = Bitwise.shiftRightZfBy 0 (aHi + bHi + abCarry)
        -- add64(ab, x): 3 more let bindings
        a1Lo = Bitwise.shiftRightZfBy 0 (abLo + xLo)
        a1Carry = if a1Lo < Bitwise.shiftRightZfBy 0 abLo then 1 else 0
        a1Hi = Bitwise.shiftRightZfBy 0 (abHi + xHi + a1Carry)
        -- xor64(d, a1) then rotr32 (= swap): 2 let bindings
        d1Hi = Bitwise.xor dLo a1Lo   -- swapped!
        d1Lo = Bitwise.xor dHi a1Hi   -- swapped!
        -- ... ~30 more let bindings for remaining steps
    in
    G8 a2Hi a2Lo b2Hi b2Lo c2Hi c2Lo d2Hi d2Lo
```

~35 let bindings (JS vars), **1 allocation** (the G8 return). Compare to ~21 allocations in Record variant.

**State types**: 32-field records of raw Ints:
```elm
type alias WorkingVector =
    { v0Hi : Int, v0Lo : Int, ..., v15Hi : Int, v15Lo : Int }

type alias HashState =
    { h0Hi : Int, h0Lo : Int, ..., h7Hi : Int, h7Lo : Int }

type alias MessageBlock =
    { m0Hi : Int, m0Lo : Int, ..., m15Hi : Int, m15Lo : Int }
```

**Round function**: Calls `g` 8 times, destructures each G8 to extract the 8 output Ints, wires column outputs into diagonal inputs, builds next WorkingVector.

**Allocation estimate per block**: 12 rounds × (8 G8 returns + 1 WorkingVector) ≈ **~108 JS objects**. That's ~20x fewer than Record/Tuple.

## Critical Implementation Details

### add64 carry detection

```elm
-- Force unsigned 32-bit via shiftRightZfBy 0, then compare as JS numbers
lo = Bitwise.shiftRightZfBy 0 (aLo + bLo)
carry = if lo < Bitwise.shiftRightZfBy 0 aLo then 1 else 0
```

Values from `shiftRightZfBy 0` are non-negative JS numbers (0 to 4294967295). The `<` comparison works correctly because all 32-bit unsigned values are exactly representable as IEEE 754 doubles.

### Rotation formulas

| Rotation | resultHi | resultLo |
|----------|----------|----------|
| rotr 32 | `lo` | `hi` |
| rotr 24 | `(hi >>> 24) \| (lo << 8)` | `(lo >>> 24) \| (hi << 8)` |
| rotr 16 | `(hi >>> 16) \| (lo << 16)` | `(lo >>> 16) \| (hi << 16)` |
| rotr 63 | `(hi << 1) \| (lo >>> 31)` | `(lo << 1) \| (hi >>> 31)` |

All shifts use `shiftRightZfBy` (logical/unsigned) and `shiftLeftBy`.

### Finalization

`v[14] = IV[6] XOR f0` where `f0 = 0xFFFFFFFF_FFFFFFFF` on last block (else 0).
In hi/lo form: `v14Hi = complement iv6Hi`, `v14Lo = complement iv6Lo` for last block.

### Edge cases

- **Empty input, no key**: process one block of 128 zero bytes, counter = 0, final flag set
- **Empty input, keyed**: key block (128 bytes) is the only block, counter = 128, final flag set
- **Exactly 128 bytes**: one full block, counter = 128, final flag set
- **129 bytes**: first block (128 bytes, counter = 128, no flag), second block (1 byte + 127 zeros, counter = 129, final flag)

## Implementation Order

### Phase 1: Foundation
1. Create `elm.json`
2. `Blake2b.Internal.Constants` — 16 IV constants
3. `Blake2b.Internal.Decode` — block decoder, digest encoder, padding

### Phase 2: Record variant (reference implementation)
4. `Blake2b.Record` — U64 type, primitives, G, round, compress, hash API
5. `tests/TestHelpers.elm` — hex conversion
6. `tests/KatVectors.elm` — test vector data
7. `tests/Blake2bRecordTest.elm` — RFC vectors, self-test, KAT subset, edge cases
8. Debug until all tests pass

### Phase 3: Tuple variant
9. `Blake2b.Tuple` — same structure, tuple U64, GResult custom type
10. `tests/Blake2bTupleTest.elm` — same test suite

### Phase 4: Positional variant
11. `Blake2b.Positional` — G8 type, inlined G, 32-field state records
12. `tests/Blake2bPositionalTest.elm` — same test suite

### Phase 5: Cross-check and benchmarks
13. `tests/Blake2bCrossCheckTest.elm` — all three produce identical output
14. `benchmarks/` — elm-explorations/benchmark app, test 64/256/1024/4096 byte inputs

## Testing Plan

| Test Category | Source | What It Catches |
|--------------|--------|-----------------|
| BLAKE2b-512("") | RFC 7693 | Basic init + single-block compression |
| BLAKE2b-512("abc") | RFC 7693 | 3-byte input, padding |
| Self-test digest | RFC 7693 App. E | Comprehensive: all digest lengths, keyed + unkeyed, 0-255 byte inputs |
| KAT vectors (subset: 0,1,2,63,64,127,128,129,255) | BLAKE2 repo | Keyed hashing, boundary lengths, multi-block |
| Edge cases (0,1,127,128,129 bytes) | Custom | Block boundary handling |
| Cross-check | Custom | All three variants agree on diverse inputs |

The self-test from Appendix E is the single most valuable test — it exercises all digest lengths, keyed and unkeyed hashing, and input lengths 0-255 in a single check.

## Expected Performance Characteristics

| Variant | JS objects per block | Relative speed (est.) | Why |
|---------|--------------------:|----------------------:|-----|
| Record | ~2100 | 1x (baseline) | Every U64 op allocates a `{ hi, lo }` |
| Tuple | ~2100 | ~0.9-1.0x | Same count, slightly larger objects (tag field) |
| Positional | ~108 | ~2-5x | Intermediates are let bindings; only G8 returns + WorkingVector allocate |

All variants: estimated ~50-500 KB/s depending on JS engine optimization. The Positional variant's 20x reduction in allocations should show a meaningful speedup, though the exact factor depends on how well V8/SpiderMonkey handle the many-argument functions and large let-binding blocks.
