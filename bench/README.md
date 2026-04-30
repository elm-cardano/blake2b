# bench/

Benchmarking and A/B testing infrastructure for the BLAKE2b implementation.

## Structure

```
bench/
├── elm.json              -- Elm application (imports ../src as source)
├── src/
│   ├── Bench.elm         -- Benchmark functions for elm-bench
│   └── Blake2b/
│       ├── V2.elm        -- Experimental variant (copy of V1 to modify)
│       └── DecodeV2.elm  -- Decoder for V2
└── tests/
    ├── CrossCheckTest.elm -- Verifies V2 matches V1 output
    └── TestHelpers.elm    -- Hex conversion utilities
```

## How it works

- **V1** is the package implementation in `../src/Blake2b/V1.elm`, imported directly.
- **V2** starts as an exact copy of V1. To experiment with an optimization, modify V2 and benchmark it against V1.
- **CrossCheckTest** ensures V2 produces identical outputs to V1 (RFC vectors, self-test, keyed hashing).

## Running benchmarks

Using [elm-bench](https://github.com/miniBill/elm-bench):

```sh
cd bench
elm-bench -f Bench.v1_1024 -f Bench.v2_1024 "()"
```

Available functions: `v1_64`, `v1_129`, `v1_256`, `v1_1024`, `v1_4096` and their `v2_` counterparts.

## Running cross-check tests

```sh
cd bench
elm-test
```

## History of performance optimizations

Changes in V6 (from V5):

- Pre-pads input to a 128-byte boundary before entering the decode loop,
  so the loop always reads full blocks with blockDecoder. Eliminates the
  partial-block path that did padBlock (O(n) List.repeat) + Decode.decode
  (full re-decode). Uses u32-sized zero padding where possible (4x fewer
  list cons cells). ~9% faster on inputs with partial last blocks.
- Hoists zero MessageBlock to module level for the empty-input path.

Changes in V5 (from V4):

- Restructures blockDecoder into quarter-block sub-decoders (8 args each)
  to stay within Elm's F2..F9 fast path. Previous chained helpers had up
  to 28 arguments, creating ~55 curried closures per block decode.
- Changes encodeDigest from 17 args to 2 (record-based). ~14% faster.

Changes in V4 (from V3):

- Flattens all state types to raw hi/lo Int fields. WorkingVector goes from
  16 U64 record fields to 32 Int fields; HashState from 8 U64 to 16 Int.
  Eliminates U64MessageBlock entirely — round takes the raw MessageBlock
  (already 32 Int fields from Internal.Decode). This removes ~192 U64 record
  allocations per block (16 per round × 12 rounds) and eliminates nested
  field access (v.v0Hi instead of v.v0.hi). Sigma permutation constructs
  permuted MessageBlocks with 32 Int fields (just copying Int values).

Changes in V3 (from V2):

- Consolidates 10 specialized round functions into a single round function.
  Sigma permutations applied at call site via permuted message blocks.

Changes in V2 (from V1):

- Inlines G mixing function as raw hi/lo Int let-bindings (~55% faster).

Base (V1):

- Bitwise carry detection in add64 (avoids polymorphic \_Utils_cmp)
- Hoists IV constructions to module level
