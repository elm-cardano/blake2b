# Writing Performant Elm Code

Research notes on Elm compilation, V8 optimization, and lessons learned
from benchmarking three BLAKE2b variants (Record, Tuple, Positional).

## How Elm Compiles to JavaScript

**Records** (`{hi, lo}`) compile to plain JS objects. With `--optimize`, field names are shortened. All records with the same fields share a single V8 HiddenClass — monomorphic access, the fastest path.

**Tuples** compile to `{$: '#2', a: x, b: y}` — 3 fields instead of 2, slightly larger. All 2-tuples share one shape, which is good.

**Custom types** compile to `{$: tag, a: ..., b: ...}`. Different variants of the same type can have **different shapes** (e.g., `Just` has `{$, a}`, `Nothing` has `{$}`), creating polymorphic inline caches. elm-optimize-level-2 pads these to match.

**Let bindings** compile to flat `var` declarations — **no closure or IIFE overhead**. However, constants in `let` blocks are **never hoisted** out of functions ([elm/compiler#1857](https://github.com/elm/compiler/issues/1857)), so they recompute on every call.

**Function application** uses `F2`..`F9` wrappers with `A2`..`A9` callers that do a runtime arity check. Functions with **>9 arguments have no fast path** — they become pure curried chains. elm-optimize-level-2 bypasses `A2` entirely with direct calls.

## Why the Positional Variant Was Slower

The Positional variant was designed to minimize allocations by passing raw `Int` pairs instead of `{hi, lo}` records. It uses ~108 JS object allocations per block vs ~2100 for Record/Tuple. Yet it benchmarked **13-17% slower**. Here's why:

1. **Monomorphic property access is extremely fast.** `{hi, lo}` records all share one HiddenClass. Every `.hi` and `.lo` access compiles to a single memory load at a known offset. This is V8's absolute fastest path.

2. **Bump-pointer allocation is ~3ns.** Creating a small object is just incrementing a pointer. Short-lived objects that die young cost essentially nothing to GC (the generational scavenger only pays for *surviving* objects).

3. **V8's escape analysis can eliminate the allocations entirely.** If TurboFan inlines the small functions that create/consume `{hi, lo}` objects, it can scalar-replace them into register values — the "allocation" becomes purely virtual.

4. **12 arguments cause register spilling at every call.** x86-64 has ~16 GP registers. Pushing 12 args onto the stack + loading them back is 12+ memory round-trips per call.

5. **~35 local variables guarantee heavy register spilling.** At least ~19 values must live on the stack at all times, generating constant spill/reload traffic.

6. **Large functions defeat TurboFan inlining.** TurboFan has a bytecode budget (~460 bytes) for inlining. A function with 12 params and 35 locals likely exceeds it. Without inlining, escape analysis, constant propagation, and dead code elimination across function boundaries are all lost.

7. **>9 args in Elm = no fast path.** The 12-argument `g` function compiles to a curried chain with no `A12` helper. Each invocation creates intermediate closures.

**Bottom line:** The "fewer allocations" approach traded nearly-free allocation costs for register pressure, stack spilling, lost inlining, and lost escape analysis — all far more expensive.

## elm-optimize-level-2 Transformations

The biggest wins:

| Transform | What it does | Impact |
|---|---|---|
| **Direct function calls** | Bypasses `A2`/`F2` wrapper, calls raw function | Up to 261% in Chrome, 164% Firefox |
| **Variant shapes** | Pads custom type variants to same shape | ~20-30% for custom-type-heavy code |
| **Inline equality** | `_Utils_eq(a, 1)` to `a === 1` | ~30% for comparison-heavy code |
| **Pass unwrapped functions** | HOFs like `List.map` call raw functions directly | Significant for pipeline-heavy code |
| **O3 record updates** | Constructor+clone instead of `_Utils_update` | 6-9x faster record updates |

`_Utils_update` (record update syntax `{ r | field = val }`) is especially bad — it creates a new empty object and iterates all properties, producing an object with a **different HiddenClass** from the original. Manual field-by-field construction is 6-9x faster.

## Actionable Patterns

### Do

- **Use records with consistent fields** for hot-path data — they're monomorphic in V8
- **Construct records manually** (`{x = r.x, y = newY}`) instead of update syntax (`{ r | y = newY }`)
- **Keep hot functions small** — small bytecode = TurboFan inlines them = escape analysis eliminates intermediate objects
- **Use `case` on literals** instead of `==` for dispatch (`case c of 'a' -> ...` is `===` in JS; `c == 'a'` goes through `_Utils_eq`)
- **Hoist constants to module level** — `let` bindings recompute every call
- **Compile with elm-optimize-level-2** for compute-heavy code — the direct-call transform alone can double throughput
- **Use direct application** for tail recursion (`foo (n-1)` not `n-1 |> foo`) — pipes break TCO
- **Benchmark on both Chrome and Firefox** — they optimize differently

### Don't

- Don't use functions with >9 arguments (no `A10+` fast path exists)
- Don't assume fewer allocations = faster (V8's bump allocator + escape analysis can make small objects free)
- Don't use record update syntax in hot loops
- Don't rely on `let` for caching — it doesn't hoist

## V8 Inline Cache States

- **Monomorphic** (1 shape): Fastest. V8 can specialize and inline.
- **Polymorphic** (2-4 shapes): ~40% slower. V8 uses a linear search.
- **Megamorphic** (>4 shapes): 3.5-60x slower. Falls back to global hash table.

All `{hi, lo}` records share one shape = monomorphic. This is the ideal case.

## BLAKE2b-Specific Takeaways

- The **Record variant** benefits from small monomorphic objects that V8 can escape-analyze away
- The **Tuple variant** is ~4% faster than Record (reason unclear — possibly the `$` tag helps V8's shape tracking)
- The **Positional variant** loses due to high arity, register pressure, and lost inlining
- The `G8` custom type (`G8 Int Int Int Int Int Int Int Int`) compiles to a 9-field object — not much better than 8 separate `{hi, lo}` records that might get escape-analyzed away
- **elm-optimize-level-2** should help all variants, but especially Positional if it can flatten the curried >9-arg calls

## References

- [Improving Elm's compiler output](https://dev.to/robinheghan/improving-elm-s-compiler-output-5e1h) — Robin Heggelund Hansen
- [Successes and failures in optimizing Elm's runtime performance](https://blogg.bekk.no/successes-and-failures-in-optimizing-elms-runtime-performance-c8dc88f4e623) — Robin Heggelund Hansen
- [Improving the performance of record updates](https://blogg.bekk.no/improving-the-performance-of-record-updates-cb34cb6d4451) — Robin Heggelund Hansen
- [How Elm functions work](https://blogg.bekk.no/how-elm-functions-work-71cab7426a2f) — Robin Heggelund Hansen
- [elm-optimize-level-2 transformations](https://github.com/mdgriffith/elm-optimize-level-2/blob/master/notes/transformations.md)
- [What's up with monomorphism?](https://mrale.ph/blog/2015/01/11/whats-up-with-monomorphism.html) — Vyacheslav Egorov (V8 team)
- [Escape Analysis in V8](https://www.jfokus.se/jfokus18/preso/Escape-Analysis-in-V8.pdf) — Tobias Tebbi (V8 team)
- [Trash talk: the Orinoco garbage collector](https://v8.dev/blog/trash-talk) — V8 team
- [Fast properties in V8](https://v8.dev/blog/fast-properties) — V8 team
- [Faster JavaScript calls](https://v8.dev/blog/adaptor-frame) — V8 team (adaptor frame removal)
- [Tail-call optimization in Elm](https://jfmengels.net/tail-call-optimization/) — Jeroen Engels
- [Tail recursion, but modulo cons](https://jfmengels.net/modulo-cons/) — Jeroen Engels
- [Elm Radio: Optimizing Performance with Robin Hansen](https://elm-radio.com/episode/optimizing-elm/)
- [Elm Radio: Performance in Elm](https://elm-radio.com/episode/performance/)
- [Understanding Monomorphism — 60x performance](https://www.builder.io/blog/monomorphic-javascript)
