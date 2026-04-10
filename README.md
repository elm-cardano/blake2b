# blake2b

Pure Elm implementation of the BLAKE2b cryptographic hash function ([RFC 7693][rfc]).

No kernel code, no ports, no JS FFI — just Elm.

[rfc]: https://www.rfc-editor.org/rfc/rfc7693

## Install

```sh
elm install elm-cardano/blake2b
```

## Usage

```elm
import Blake2b
import Bytes exposing (Bytes)
import Bytes.Encode

message : Bytes
message =
    Bytes.Encode.encode (Bytes.Encode.string "hello")

-- 512-bit hash (64 bytes), the default for BLAKE2b
digest : Bytes
digest =
    Blake2b.hash512 message

-- 256-bit hash (32 bytes)
digest256 : Bytes
digest256 =
    Blake2b.hash256 message

-- Custom digest length and keyed hashing
keyed : Bytes
keyed =
    Blake2b.hash
        { digestLength = 48
        , key = Bytes.Encode.encode (Bytes.Encode.string "secret")
        , data = message
        }
```

## API

- **`hash512 : Bytes -> Bytes`** — 512-bit (64-byte) hash
- **`hash256 : Bytes -> Bytes`** — 256-bit (32-byte) hash
- **`hash224 : Bytes -> Bytes`** — 224-bit (28-byte) hash
- **`hash : { digestLength : Int, key : Bytes, data : Bytes } -> Bytes`** — configurable digest length (1-64) and optional key (0-64 bytes)

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
