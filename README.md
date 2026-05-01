# blake2b

Pure Elm implementation of the BLAKE2b cryptographic hash function ([RFC 7693][rfc]).

No kernel code, no ports, no JS FFI — just Elm.

[rfc]: https://www.rfc-editor.org/rfc/rfc7693

## Install

```sh
elm install elm-cardano/blake2b
```

## Development

```sh
pnpm install
pnpm test          # run tests
pnpm review        # run elm-review
pnpm format:check  # check formatting
pnpm format        # auto-format
```

## API

```elm
import Blake2b512

Blake2b512.fromString "hello"             -- Digest
Blake2b512.fromBytes bytes                -- Digest
Blake2b512.fromByteValues [0x68, 0x69]    -- Digest

Blake2b512.toHex digest                   -- String
Blake2b512.toBase64 digest                -- String
Blake2b512.toBytes digest                 -- Bytes
Blake2b512.toByteValues digest            -- List Int
```

The same API is exposed by `Blake2b224` and `Blake2b256`.

For custom digest lengths or keyed hashing, use the `Blake2b` module:

```elm
import Blake2b
import Bytes.Encode as Encode

Blake2b.fromString
    { digestLength = 48
    , key = Encode.encode (Encode.string "secret")
    }
    "hello"
    |> Blake2b.toHex
```

## Performance

64-bit arithmetic is emulated using pairs of 32-bit integers.
All intermediate values in the compression function are `let` bindings on raw `Int` pairs, which compile to plain JS variables with zero allocation.
This keeps garbage collection pressure low and makes the implementation practical for real use.

For details on the optimization journey, see [docs/IMPLEMENTATION.md](https://github.com/elm-cardano/blake2b/blob/main/docs/IMPLEMENTATION.md).
Benchmarking infrastructure lives in the [bench/](https://github.com/elm-cardano/blake2b/tree/main/bench) folder.

## Correctness

Tested against:

- RFC 7693 test vectors (`BLAKE2b-512("")`, `BLAKE2b-512("abc")`)
- RFC 7693 Appendix E self-test (all digest lengths, keyed and unkeyed, input lengths 0-255)
- BLAKE2 KAT vectors (keyed hashing at boundary lengths)

## License

BSD-3-Clause
