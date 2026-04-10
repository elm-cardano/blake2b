module Bench exposing (v1_1024, v1_256, v1_4096, v1_64)

{-| Benchmark functions for BLAKE2b.

Each function takes `()` and computes BLAKE2b-512 on a pre-built input of the given size.
Useful with elm-bench:

    elm - bench -f Bench.v1_64 -f Bench.v1_256 -f Bench.v1_1024 -f Bench.v1_4096 "()"

-}

import Blake2b.V1
import Bytes exposing (Bytes)
import Bytes.Encode as Encode


makeBytes : Int -> Bytes
makeBytes n =
    Encode.encode
        (Encode.sequence
            (List.map (\i -> Encode.unsignedInt8 (modBy 256 i)) (List.range 0 (n - 1)))
        )


bytes64 : Bytes
bytes64 =
    makeBytes 64


bytes256 : Bytes
bytes256 =
    makeBytes 256


bytes1024 : Bytes
bytes1024 =
    makeBytes 1024


bytes4096 : Bytes
bytes4096 =
    makeBytes 4096


v1_64 : () -> Bytes
v1_64 () =
    Blake2b.V1.hash512 bytes64


v1_256 : () -> Bytes
v1_256 () =
    Blake2b.V1.hash512 bytes256


v1_1024 : () -> Bytes
v1_1024 () =
    Blake2b.V1.hash512 bytes1024


v1_4096 : () -> Bytes
v1_4096 () =
    Blake2b.V1.hash512 bytes4096
