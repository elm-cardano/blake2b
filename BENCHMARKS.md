# BLAKE2b Benchmark Results

Benchmarks run with [elm-bench](https://github.com/elm-menagerie/elm-bench) on Node.js.
All variants compute BLAKE2b-512 (64-byte digest) on inputs of varying size.

## Environment

- Tool: elm-bench (CLI, `-f` mode)
- Compiler: `elm make` (no `--optimize`, no elm-optimize-level-2)
- Runtime: Node.js
- Platform: macOS (Apple Silicon)

## Results

### 64 bytes (1 block)

| Variant    | ns/run | vs Record |
|------------|-------:|-----------|
| Record     | 16,815 | baseline  |
| Tuple      | 16,953 | 1% slower |
| Positional | 20,206 | 20% slower |
| Optimized  | 16,222 | 4% faster |

### 256 bytes (2 blocks)

| Variant    | ns/run | vs Record |
|------------|-------:|-----------|
| Record     | 29,664 | baseline  |
| Tuple      | 30,063 | 1% slower |
| Positional | 36,590 | 23% slower |
| Optimized  | 28,564 | 4% faster |

### 1024 bytes (8 blocks)

| Variant    |  ns/run | vs Record |
|------------|--------:|-----------|
| Record     | 115,328 | baseline  |
| Tuple      | 114,661 | 1% faster |
| Positional | 141,238 | 22% slower |
| Optimized  | 109,032 | 5% faster |

### 4096 bytes (32 blocks)

| Variant    |  ns/run  | vs Record |
|------------|--------:|-----------|
| Record     | 499,628 | baseline  |
| Tuple      | 500,884 | same speed |
| Positional | 578,575 | 16% slower |
| Optimized  | 468,422 | 6% faster |

## Variant Descriptions

### Record (`Blake2b.Record`)

Baseline implementation. Uses `{ hi : Int, lo : Int }` records for 64-bit words.
The `round` function takes 17 arguments (16 U64 message words + WorkingVector),
exceeding Elm's 9-argument fast path (F2..F9). This means each round call goes
through `A9(round, ...)` plus 8 curried applications, creating ~96 closure
allocations per block across 12 rounds.

### Tuple (`Blake2b.Tuple`)

Same structure as Record but uses `( Int, Int )` tuples instead of records.
Tuples compile to `{ $: '#2', a: hi, b: lo }` in JS -- 3 fields instead of 2.
Performance is nearly identical to Record, slightly slower from the extra `$` tag field.

### Positional (`Blake2b.Positional`)

Designed to minimize allocations by passing raw Int pairs as separate function arguments
instead of wrapping them in records. The `g` function takes 12 Int arguments and uses
~35 let bindings with only 1 allocation (the G8 return value) vs ~21 per G call in Record.

Despite ~20x fewer allocations per block (~108 vs ~2,100), it is consistently **20-23% slower**:

- 12-argument `g` function exceeds Elm's 9-arg fast path, compiling to curried chains
- ~35 local variables exceed x86-64's ~16 registers, causing heavy stack spilling
- Large function bytecode defeats TurboFan's inlining heuristics (~460 byte budget)
- Without inlining, V8 cannot perform escape analysis on callers' objects
- Meanwhile, V8's bump-pointer allocator makes small `{hi, lo}` records nearly free (~3ns)
- V8's escape analysis can eliminate `{hi, lo}` allocations entirely when functions are inlined

### Optimized (`Blake2b.Optimized`)

Applies three targeted optimizations based on V8 performance research:

1. **Module-level IV U64 records** -- 8 initialization vector records (`iv0U`..`iv7U`) are
   hoisted to module scope, evaluated once at load time instead of being reconstructed
   in every `compress` call. Exploits the fact that Elm `let` bindings are never hoisted
   by the compiler ([elm/compiler#1857](https://github.com/elm/compiler/issues/1857)).

2. **10 specialized 2-arg round functions** -- Instead of one 17-arg `round` function,
   there are 10 functions (`round0`..`round9`) each taking `(U64MessageBlock, WorkingVector)`.
   Rounds 10 and 11 reuse `round0` and `round1` (BLAKE2b sigma repeats after 10 rounds).
   All arities stay within Elm's F2..F9 fast path, eliminating ~96 closure allocations
   per block from curried overflow arguments.

3. **U64MessageBlock type** -- A 16-field record of `{hi, lo}` U64 records, constructed once
   in `compress` and shared across all 12 rounds. Avoids reconstructing 16 U64s per round.

## Throughput Estimates

Based on 4096-byte benchmarks (most representative for sustained throughput):

| Variant    |  ns/run | KB/s |
|------------|--------:|-----:|
| Record     | 499,628 |  8.2 |
| Tuple      | 500,884 |  8.2 |
| Positional | 578,575 |  7.1 |
| Optimized  | 468,422 |  8.7 |

## Key Takeaways

1. **Small monomorphic records beat raw arguments.** V8's bump-pointer allocation (~3ns),
   escape analysis, and monomorphic inline caches make `{hi, lo}` records nearly free.
   High-arity functions pay more in register spilling and lost inlining than they save
   in allocation avoidance.

2. **Stay within Elm's 9-argument fast path.** Functions with >9 arguments compile to
   curried chains with no `A10+` helper. Each call creates intermediate closures.

3. **Hoist constants to module level.** Elm's compiler does not lift `let` bindings
   out of functions, even when they don't depend on function arguments.

4. **Record and Tuple are nearly equivalent.** The extra `$` tag field on tuples has
   minimal impact. Record is marginally better due to smaller JS objects.

5. **The Optimized variant's 4-5% improvement is consistent** across all input sizes,
   confirming the bottleneck is per-block overhead (round function calls) rather than
   per-byte processing.
