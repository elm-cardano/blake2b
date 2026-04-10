# BLAKE2b Benchmark Results

Benchmarks run with [elm-bench](https://github.com/elm-menagerie/elm-bench) on Node.js.
All variants compute BLAKE2b-512 (64-byte digest) on inputs of varying size.

## Environment

- Tool: elm-bench (CLI, `-f` mode)
- Compiler: `elm make` (no `--optimize`, no elm-optimize-level-2)
- Runtime: Node.js
- Platform: macOS (Apple Silicon)

## Results

### Early variants (Record, Tuple, Positional, Optimized)

These variants were explored early on and later deleted. Results are kept for reference.

#### 64 bytes (1 block)

| Variant    | ns/run | vs Record |
|------------|-------:|-----------|
| Record     | 16,815 | baseline  |
| Tuple      | 16,953 | 1% slower |
| Positional | 20,206 | 20% slower |
| Optimized  | 16,222 | 4% faster |

#### 256 bytes (2 blocks)

| Variant    | ns/run | vs Record |
|------------|-------:|-----------|
| Record     | 29,664 | baseline  |
| Tuple      | 30,063 | 1% slower |
| Positional | 36,590 | 23% slower |
| Optimized  | 28,564 | 4% faster |

#### 1024 bytes (8 blocks)

| Variant    |  ns/run | vs Record |
|------------|--------:|-----------|
| Record     | 115,328 | baseline  |
| Tuple      | 114,661 | 1% faster |
| Positional | 141,238 | 22% slower |
| Optimized  | 109,032 | 5% faster |

#### 4096 bytes (32 blocks)

| Variant    |  ns/run | vs Record |
|------------|--------:|-----------|
| Record     | 499,628 | baseline  |
| Tuple      | 500,884 | same speed |
| Positional | 578,575 | 16% slower |
| Optimized  | 468,422 | 6% faster |

### Current variants (V1 through V4)

V1 is the Optimized variant renamed. V2-V4 build incrementally on V1.

#### 64 bytes (1 block)

| Variant | ns/run | vs V1     |
|---------|-------:|-----------|
| V1      | 10,389 | baseline  |
| V2      |  4,858 | 53% faster |
| V3      |  5,009 | 52% faster |
| V4      |  4,311 | 59% faster |

#### 1024 bytes (8 blocks)

| Variant |  ns/run | vs V1     |
|---------|--------:|-----------|
| V1      | 71,179 | baseline  |
| V2      | 28,835 | 59% faster |
| V3      | 29,346 | 59% faster |
| V4      | 27,453 | 61% faster |

### JS output size

Compiled JS output size (single module + Elm runtime, via `elm make --output`):

| Variant | JS bytes | JS lines |
|---------|----------|----------|
| V1      | 112,811  | 4,215    |
| V2      | 249,264  | 6,824    |
| V3      | 119,163  | 4,361    |
| V4      | ~119,000 | ~4,400   |

V2's 10 inlined round functions cause a 2.2x JS bloat. V3 consolidates to one
round function, bringing size back near V1 with only ~3% perf cost vs V2. V4
adds flat fields with negligible size impact.

## Variant Descriptions

### Record (`Blake2b.Record`) -- deleted

Baseline implementation. Uses `{ hi : Int, lo : Int }` records for 64-bit words.
The `round` function takes 17 arguments (16 U64 message words + WorkingVector),
exceeding Elm's 9-argument fast path (F2..F9). This means each round call goes
through `A9(round, ...)` plus 8 curried applications, creating ~96 closure
allocations per block across 12 rounds.

### Tuple (`Blake2b.Tuple`) -- deleted

Same structure as Record but uses `( Int, Int )` tuples instead of records.
Tuples compile to `{ $: '#2', a: hi, b: lo }` in JS -- 3 fields instead of 2.
Performance is nearly identical to Record, slightly slower from the extra `$` tag field.

### Positional (`Blake2b.Positional`) -- deleted

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

### V1 (`Blake2b.V1`) -- formerly Optimized

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

4. **Bitwise carry detection** -- Replaces `lo < (a.lo >>> 0)` comparison in `add64`
   (which compiles to Elm's polymorphic `_Utils_cmp` with a `typeof` type guard) with a
   pure bitwise formula: `((aLo AND bLo) OR ((aLo OR bLo) AND (NOT sumLo))) >>> 31`.
   Eliminates ~768 `_Utils_cmp` calls per block (8 adds/G x 8 G calls x 12 rounds).

### V2 (`Blake2b.V2`)

**Inlines G mixing function** into each of 10 specialized round functions as raw hi/lo
Int `let` bindings. This eliminates ~2,000 intermediate U64 record allocations per block
(each G call previously created ~21 U64 records for `add64`/`xor64`/`rotr` results;
now all intermediates become JS `var` statements with zero allocation).

- ~272 let bindings per round function (8 G calls x ~34 bindings each)
- Only the output WorkingVector (16 U64 records) is allocated per round
- Per-block allocations drop from ~2,100 to ~250
- **53-59% faster than V1**
- Downside: 10 copies of the inlined round body cause **2.2x JS output bloat** (249 KB vs 113 KB)

### V3 (`Blake2b.V3`)

**Consolidates 10 round functions into one.** All 10 round functions have identical
structure -- only the sigma permutation (which message words feed each G call) differs.
V3 uses a single `round` function; the caller applies the sigma permutation by constructing
a permuted `U64MessageBlock` at each call site (just reordering U64 references, no new
U64 allocations).

- 12 extra 16-field record allocations per `compress` call (permuted message blocks)
- JS output drops back to ~119 KB (near V1 levels)
- **~3% slower than V2** -- a good tradeoff for 10x less round code
- **52% faster than V1**

### V4 (`Blake2b.V4`)

**Flattens all state types to raw hi/lo Int fields.** Eliminates the `U64` record
wrapper entirely:

- `WorkingVector`: 16 U64 fields -> 32 Int fields (`v0Hi`, `v0Lo`, ..., `v15Hi`, `v15Lo`)
- `HashState`: 8 U64 fields -> 16 Int fields (`h0Hi`, `h0Lo`, ..., `h7Hi`, `h7Lo`)
- `U64MessageBlock` eliminated -- `round` takes `MessageBlock` directly (already 32 Int
  fields from `Internal.Decode`)
- Sigma permutation constructs permuted `MessageBlock` with 32 Int fields (copying Ints)

This removes ~192 U64 record allocations per block (16 per round x 12 rounds) and
eliminates nested field access (`v.v0Hi` instead of `v.v0.hi` -- one property lookup
instead of two). Per-block allocations drop from ~250 to ~25.

- **59-61% faster than V1** (7-14% faster than V3)
- Negligible JS size impact vs V3
- `xor64` helper removed (finalization uses inline `Bitwise.xor`)

## Throughput Estimates

Based on 1024-byte benchmarks:

| Variant |  ns/run | KB/s  |
|---------|--------:|------:|
| V1      | 71,179  |  14.4 |
| V2      | 28,835  |  35.5 |
| V3      | 29,346  |  34.9 |
| V4      | 27,453  |  37.3 |

## Allocation Estimates Per Block

| Variant    | JS objects/block | Main source |
|------------|----------------:|-------------|
| Record     |          ~2,100 | U64 records from add64/xor64/rotr in G |
| Positional |            ~108 | G8 returns + WorkingVector |
| V1         |          ~2,100 | Same as Record (G not inlined) |
| V2         |            ~250 | WorkingVector U64 fields (16/round x 12) + message blocks |
| V3         |            ~250 | Same as V2 + permuted message blocks |
| V4         |             ~25 | Flat WorkingVectors (1/round) + permuted MessageBlocks |

## Key Takeaways

1. **Inlining G is the single biggest win.** Turning ~2,000 intermediate U64 record
   allocations into JS `var` statements yields >2x speedup. This dominates all other
   optimizations combined.

2. **One generic round function is nearly as fast as 10 specialized ones.** Sigma
   permutation via reordered message block references costs only ~3% but saves 10x
   code size. V8's monomorphic inline caches handle the single-function pattern well.

3. **Flattening nested records helps.** Eliminating the `{hi, lo}` wrapper removes ~192
   allocations per block and turns nested property access (`v.v0.hi`) into flat access
   (`v.v0Hi`). Worth ~7-14% on top of G inlining.

4. **Small monomorphic records beat raw arguments.** V8's bump-pointer allocation (~3ns),
   escape analysis, and monomorphic inline caches make `{hi, lo}` records nearly free.
   High-arity functions (Positional variant) pay more in register spilling and lost
   inlining than they save in allocation avoidance.

5. **Stay within Elm's 9-argument fast path.** Functions with >9 arguments compile to
   curried chains with no `A10+` helper. Each call creates intermediate closures.

6. **Hoist constants to module level.** Elm's compiler does not lift `let` bindings
   out of functions, even when they don't depend on function arguments.

7. **Bitwise carry detection avoids polymorphic overhead.** Elm's `<` on Ints compiles
   to `_Utils_cmp` which includes a `typeof` type guard. Pure bitwise carry detection
   eliminates this, saving ~768 polymorphic calls per block (~3-4% improvement).

8. **Code size matters for maintainability, less so for V8.** V2's 2.2x JS bloat from
   10 inlined round copies had no measurable perf benefit over V3's single copy.
   V8 optimizes the single function body just as well.
