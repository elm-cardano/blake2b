module Bench exposing
    ( record64, tuple64, positional64, optimized64
    , record256, tuple256, positional256, optimized256
    , record1024, tuple1024, positional1024, optimized1024
    , record4096, tuple4096, positional4096, optimized4096
    )

{-| Wrapper functions for benchmarking the three BLAKE2b variants with elm-bench.

Each function takes `()` and hashes a pre-built `Bytes` input of a fixed size
using one of the three variants (Record, Tuple, Positional).

Run from the project root with:

    elm-bench -f Bench.record64 -f Bench.tuple64 -f Bench.positional64 -f Bench.optimized64 "()"
    elm-bench -f Bench.record256 -f Bench.tuple256 -f Bench.positional256 -f Bench.optimized256 "()"
    elm-bench -f Bench.record1024 -f Bench.tuple1024 -f Bench.positional1024 -f Bench.optimized1024 "()"
    elm-bench -f Bench.record4096 -f Bench.tuple4096 -f Bench.positional4096 -f Bench.optimized4096 "()"

-}

import Blake2b.Optimized as Optimized
import Blake2b.Positional as Positional
import Blake2b.Record as Record
import Blake2b.Tuple as Tuple
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



-- 64 bytes


record64 : () -> Bytes
record64 () =
    Record.hash512 bytes64


tuple64 : () -> Bytes
tuple64 () =
    Tuple.hash512 bytes64


positional64 : () -> Bytes
positional64 () =
    Positional.hash512 bytes64


optimized64 : () -> Bytes
optimized64 () =
    Optimized.hash512 bytes64



-- 256 bytes


record256 : () -> Bytes
record256 () =
    Record.hash512 bytes256


tuple256 : () -> Bytes
tuple256 () =
    Tuple.hash512 bytes256


positional256 : () -> Bytes
positional256 () =
    Positional.hash512 bytes256


optimized256 : () -> Bytes
optimized256 () =
    Optimized.hash512 bytes256



-- 1024 bytes


record1024 : () -> Bytes
record1024 () =
    Record.hash512 bytes1024


tuple1024 : () -> Bytes
tuple1024 () =
    Tuple.hash512 bytes1024


positional1024 : () -> Bytes
positional1024 () =
    Positional.hash512 bytes1024


optimized1024 : () -> Bytes
optimized1024 () =
    Optimized.hash512 bytes1024



-- 4096 bytes


record4096 : () -> Bytes
record4096 () =
    Record.hash512 bytes4096


tuple4096 : () -> Bytes
tuple4096 () =
    Tuple.hash512 bytes4096


positional4096 : () -> Bytes
positional4096 () =
    Positional.hash512 bytes4096


optimized4096 : () -> Bytes
optimized4096 () =
    Optimized.hash512 bytes4096
