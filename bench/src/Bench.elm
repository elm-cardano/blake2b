module Bench exposing
    ( v1_64, v1_129, v1_256, v1_1024, v1_4096
    , v2_64, v2_129, v2_256, v2_1024, v2_4096
    )

{-| Benchmark functions for BLAKE2b.

Each function takes `()` and computes BLAKE2b-512 on a pre-built input of the given size.
Useful with elm-bench:

```sh
elm-bench -f Bench.v1_64 -f Bench.v2_64 "()"
elm-bench -f Bench.v1_1024 -f Bench.v2_1024 "()"
elm-bench -f Bench.v1_4096 -f Bench.v2_4096 "()"
```


## V1

@docs v1_64, v1_129, v1_256, v1_1024, v1_4096


## V2

@docs v2_64, v2_129, v2_256, v2_1024, v2_4096

-}

import Blake2b.V2
import Blake2b512
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


bytes129 : Bytes
bytes129 =
    makeBytes 129


bytes4096 : Bytes
bytes4096 =
    makeBytes 4096


v1Hash512 : Bytes -> Bytes
v1Hash512 data =
    Blake2b512.toBytes (Blake2b512.fromBytes data)


{-| V1 BLAKE2b-512 on 64 bytes.
-}
v1_64 : () -> Bytes
v1_64 () =
    v1Hash512 bytes64


{-| V1 BLAKE2b-512 on 129 bytes.
-}
v1_129 : () -> Bytes
v1_129 () =
    v1Hash512 bytes129


{-| V1 BLAKE2b-512 on 256 bytes.
-}
v1_256 : () -> Bytes
v1_256 () =
    v1Hash512 bytes256


{-| V1 BLAKE2b-512 on 1024 bytes.
-}
v1_1024 : () -> Bytes
v1_1024 () =
    v1Hash512 bytes1024


{-| V1 BLAKE2b-512 on 4096 bytes.
-}
v1_4096 : () -> Bytes
v1_4096 () =
    v1Hash512 bytes4096


{-| V2 BLAKE2b-512 on 64 bytes.
-}
v2_64 : () -> Bytes
v2_64 () =
    Blake2b.V2.hash512 bytes64


{-| V2 BLAKE2b-512 on 129 bytes.
-}
v2_129 : () -> Bytes
v2_129 () =
    Blake2b.V2.hash512 bytes129


{-| V2 BLAKE2b-512 on 256 bytes.
-}
v2_256 : () -> Bytes
v2_256 () =
    Blake2b.V2.hash512 bytes256


{-| V2 BLAKE2b-512 on 1024 bytes.
-}
v2_1024 : () -> Bytes
v2_1024 () =
    Blake2b.V2.hash512 bytes1024


{-| V2 BLAKE2b-512 on 4096 bytes.
-}
v2_4096 : () -> Bytes
v2_4096 () =
    Blake2b.V2.hash512 bytes4096
