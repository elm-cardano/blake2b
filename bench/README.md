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
