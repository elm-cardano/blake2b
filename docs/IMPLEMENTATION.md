# Pure Elm BLAKE2b: Implementation & Performance

A pure Elm implementation of BLAKE2b (RFC 7693). No kernel JS or ports.
The core challenge: Elm only has 32-bit integers, so all 64-bit arithmetic
is emulated with hi/lo Int pairs.

## Architecture

```
src/
├── Blake2b.elm                    -- Public facade (re-exports V1)
├── Blake2b/
│   ├── V1.elm                     -- Current best implementation
│   ├── V2.elm                     -- Experimental variant for A/B benchmarking
│   └── Internal/
│       ├── Constants.elm           -- 16 IV constants as top-level Ints
│       ├── Decode.elm              -- Block decoder, digest encoder (for V1)
│       └── DecodeV2.elm            -- Same decoder (for V2 isolation)
src/Bench.elm                      -- elm-bench functions for V1 and V2
```

### Public API

```elm
hash : { digestLength : Int, key : Bytes, data : Bytes } -> Bytes
hash512 : Bytes -> Bytes
hash256 : Bytes -> Bytes
```

### Algorithm Flow

1. Init `h[0..7] = IV[0..7] XOR parameter_block`
2. If keyed: prepend key padded to 128 bytes
3. Pre-pad input to 128-byte boundary (avoids re-encoding partial last block)
4. Process blocks via `Bytes.Decode.loop`:
   - Full blocks: counter += 128, no final flag
   - Last block: counter = total bytes consumed, final flag set
5. Extract first `digestLength` bytes from `h[0..7]` in little-endian

### Data Representation (Flat Fields)

All state types use flat hi/lo Int fields — no nested `{hi, lo}` wrapper records:

- **WorkingVector**: 32 Int fields (`v0Hi`, `v0Lo`, ..., `v15Hi`, `v15Lo`)
- **HashState**: 16 Int fields (`h0Hi`, `h0Lo`, ..., `h7Hi`, `h7Lo`)
- **MessageBlock**: 32 Int fields (`m0Hi`, `m0Lo`, ..., `m15Hi`, `m15Lo`)

### Key Implementation Details

**add64 carry detection** uses a pure bitwise formula:
`((aLo AND bLo) OR ((aLo OR bLo) AND (NOT sumLo))) >>> 31`.
This avoids Elm's polymorphic `_Utils_cmp` (which includes a `typeof` guard),
eliminating ~768 polymorphic calls per block.

**Rotation formulas** (all using `shiftRightZfBy` for unsigned shifts):

| Rotation | resultHi                    | resultLo                    |
| -------- | --------------------------- | --------------------------- |
| rotr 32  | `lo`                        | `hi`                        |
| rotr 24  | `(hi >>> 24) \| (lo << 8)`  | `(lo >>> 24) \| (hi << 8)`  |
| rotr 16  | `(hi >>> 16) \| (lo << 16)` | `(lo >>> 16) \| (hi << 16)` |
| rotr 63  | `(hi << 1) \| (lo >>> 31)`  | `(lo << 1) \| (hi >>> 31)`  |

**Finalization**: `v[14] = complement(IV[6])` on last block (XOR with all-ones).

**Edge cases**: Empty input (no key) processes one zero block with counter=0.
Exactly 128 bytes is one block with counter=128.

### Block Decoder

Uses quarter-block sub-decoders (4 words = 8 u32s each) to stay within Elm's
F2..F9 fast path. Four `QuarterBlock` records are combined into the final
`MessageBlock`. No function exceeds 8 arguments.

### Round Function

A single `round` function with the G mixing function fully inlined as ~272
`let` bindings. Sigma permutation is handled by constructing a permuted
`MessageBlock` at each of the 12 call sites (just reordering Int references).

## Optimization History

All variants compute BLAKE2b-512 (64-byte digest). Benchmarks run with
[elm-bench](https://github.com/elm-menagerie/elm-bench) on Node.js (macOS,
Apple Silicon). Compiled with `elm make` (no `--optimize`, no elm-optimize-level-2).

### Early Exploration (deleted variants)

| Variant    | 64B ns/run | 1024B ns/run | Notes                                                            |
| ---------- | ---------: | -----------: | ---------------------------------------------------------------- |
| Record     |     16,815 |      115,328 | Baseline. `{hi, lo}` records for U64s                            |
| Tuple      |     16,953 |      114,661 | `(hi, lo)` tuples — same speed, slightly larger JS objects       |
| Positional |     20,206 |      141,238 | Raw Int pairs as args — 20% slower despite 20x fewer allocations |
| Optimized  |     16,222 |      109,032 | Hoisted IVs + specialized rounds — became V1                     |

**Why Positional was slower**: Its 12-arg `g` function exceeded Elm's 9-arg
fast path, caused register spilling (~35 locals), and defeated V8's inlining
heuristics. Without inlining, V8 couldn't escape-analyze the callers' `{hi,lo}`
records. Meanwhile, V8's bump-pointer allocator makes small records nearly free
(~3ns), and escape analysis can eliminate them entirely when inlined.

### Current Optimization Progression

#### V1 (Optimized baseline)

- Module-level IV constants (Elm never hoists `let` bindings)
- 10 specialized 2-arg round functions (stay within F2..F9)
- `U64MessageBlock` type shared across rounds
- Bitwise carry detection (avoids `_Utils_cmp`)

#### V2: Inline G mixing function (53-59% faster than V1)

Inlines G into each round function as raw hi/lo `let` bindings. Eliminates
~2,000 intermediate U64 record allocations per block — all intermediates
become JS `var` statements. Per-block allocations: ~2,100 → ~250.

Downside: 10 copies of inlined G cause 2.2x JS bloat (249 KB vs 113 KB).

#### V3: Single round function (52% faster than V1)

Consolidates 10 round functions into one. Sigma permutation via reordered
message block references. Only ~3% slower than V2 but 10x less round code.
JS output back to ~119 KB.

#### V4: Flat hi/lo Int fields (59-61% faster than V1)

Eliminates the `{hi, lo}` wrapper entirely. WorkingVector: 16 U64 fields →
32 Int fields. Removes ~192 U64 allocations per block and eliminates nested
property access. Per-block allocations: ~250 → ~25.

#### V5: Fix decoder arities (64% faster than V1)

Block decoder previously used chained helpers with up to 28 arguments (~55
curried closures per block). Restructured into `decodeQuarter` (8 args each).
Also changed `encodeDigest` from 17 args to 2. **14% faster than V4.**

#### V6: Pre-padded input (additional 9% on partial blocks)

Pre-pads input to 128-byte boundary before entering the decode loop, so the
loop always reads full blocks. Eliminates O(padLen) `List.repeat` + encode +
re-decode per partial last block. Uses `unsignedInt32 LE 0` padding (4x fewer
list allocations than per-byte). Also hoists `zeroMessageBlock` constant for
empty-input path. Simplifies blockLoop from 3 branches to 2.

### Benchmark Summary

| Input | V1 ns/run | Best ns/run | Speedup  |
| ----- | --------: | ----------: | -------- |
| 64B   |    10,389 |  3,708 (V5) | 64%      |
| 129B  |         — |  6,162 (V6) | 9% vs V5 |
| 1024B |    71,179 | 27,453 (V4) | 61%      |

### JS Output Size

| Variant | JS bytes | JS lines |
| ------- | -------- | -------- |
| V1      | 112,811  | 4,215    |
| V2      | 249,264  | 6,824    |
| V3-V6   | ~119,000 | ~4,400   |

### Allocation Estimates Per Block

| Stage      | JS objects/block | Main source                                  |
| ---------- | ---------------: | -------------------------------------------- |
| Record/V1  |           ~2,100 | U64 records from add64/xor64/rotr in G       |
| Positional |             ~108 | G8 returns + WorkingVector                   |
| V2/V3      |             ~250 | WorkingVector U64 fields (16/round × 12)     |
| V4-V6      |              ~25 | Flat WorkingVectors + permuted MessageBlocks |

### Throughput (1024B benchmarks)

| Variant | ns/run | KB/s |
| ------- | -----: | ---: |
| V1      | 71,179 | 14.4 |
| V4      | 27,453 | 37.3 |

## Elm/V8 Performance Lessons

### What works

1. **Inlining G is the single biggest win.** Turning ~2,000 intermediate U64
   allocations into JS `var` statements yields >2x speedup.

2. **One generic round function ≈ 10 specialized ones.** Sigma permutation via
   reordered references costs ~3% but saves 10x code. V8's monomorphic inline
   caches handle it well.

3. **Flattening nested records helps.** Eliminating `{hi, lo}` wrappers removes
   ~192 allocations/block and turns `v.v0.hi` into `v.v0Hi`. Worth ~7-14%.

4. **Small monomorphic records beat raw arguments.** V8's bump-pointer allocation
   (~3ns), escape analysis, and monomorphic inline caches make `{hi, lo}` nearly
   free. High-arity functions pay more in register spilling and lost inlining.

5. **Stay within Elm's 9-argument fast path.** No `A10+` helper exists —
   functions with >9 args create intermediate closures via curried chains.

6. **Hoist constants to module level.** Elm's compiler never lifts `let` bindings
   out of functions, even for constant expressions.

7. **Bitwise carry > polymorphic comparison.** Elm's `<` on Ints compiles to
   `_Utils_cmp` with a `typeof` guard. Bitwise carry eliminates ~768 calls/block.

8. **Avoid encode+decode round-trips.** Pre-padding input once is cheaper than
   encoding zero-padded bytes then re-decoding per partial block.

### Elm compilation patterns

- **Records** compile to plain JS objects. Same-shape records share a HiddenClass
  (monomorphic = fastest V8 path).
- **Tuples** compile to `{$: '#2', a, b}` — 3 fields, slightly larger.
- **Let bindings** compile to `var` statements — zero closure/IIFE overhead,
  but never hoisted out of functions.
- **Record update syntax** (`{ r | field = val }`) uses `_Utils_update` which
  creates a new object with a different HiddenClass. Manual construction is 6-9x
  faster.
- **elm-optimize-level-2** transforms: direct function calls (up to 261% faster),
  variant shape padding, inline equality, direct HOF calls, fast record updates.

## Testing

30 tests covering:

- RFC 7693 vectors (empty string, "abc")
- Self-test digest (Appendix E) — exercises all digest lengths, keyed + unkeyed,
  input lengths 0-255
- KAT vectors (subset: 0, 1, 2, 63, 64, 127, 128, 129, 255 byte inputs)
- Convenience functions (hash512, hash256)
- Edge cases (0, 1, 127, 128, 129 bytes)
- V2 cross-check (V1 and V2 produce identical output)

## References

- [Improving Elm's compiler output](https://dev.to/robinheghan/improving-elm-s-compiler-output-5e1h) — Robin Heggelund Hansen
- [Successes and failures in optimizing Elm's runtime performance](https://blogg.bekk.no/successes-and-failures-in-optimizing-elms-runtime-performance-c8dc88f4e623)
- [elm-optimize-level-2 transformations](https://github.com/mdgriffith/elm-optimize-level-2/blob/master/notes/transformations.md)
- [What's up with monomorphism?](https://mrale.ph/blog/2015/01/11/whats-up-with-monomorphism.html) — Vyacheslav Egorov (V8)
- [Escape Analysis in V8](https://www.jfokus.se/jfokus18/preso/Escape-Analysis-in-V8.pdf) — Tobias Tebbi (V8)
- [Fast properties in V8](https://v8.dev/blog/fast-properties)
- [Tail-call optimization in Elm](https://jfmengels.net/tail-call-optimization/) — Jeroen Engels
