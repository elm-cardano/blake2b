module Main exposing (main)

import Benchmark exposing (Benchmark, describe)
import Benchmark.Runner exposing (BenchmarkProgram, program)
import Blake2b.Optimized as Optimized
import Blake2b.Positional as Positional
import Blake2b.Record as Record
import Blake2b.Tuple as Tuple
import Bytes exposing (Bytes)
import Bytes.Encode as Encode


main : BenchmarkProgram
main =
    program suite


emptyBytes : Bytes
emptyBytes =
    Encode.encode (Encode.sequence [])


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


suite : Benchmark
suite =
    describe "BLAKE2b-512"
        [ describe "64 bytes"
            [ Benchmark.benchmark "Record" (\_ -> Record.hash512 bytes64)
            , Benchmark.benchmark "Tuple" (\_ -> Tuple.hash512 bytes64)
            , Benchmark.benchmark "Positional" (\_ -> Positional.hash512 bytes64)
            , Benchmark.benchmark "Optimized" (\_ -> Optimized.hash512 bytes64)
            ]
        , describe "256 bytes"
            [ Benchmark.benchmark "Record" (\_ -> Record.hash512 bytes256)
            , Benchmark.benchmark "Tuple" (\_ -> Tuple.hash512 bytes256)
            , Benchmark.benchmark "Positional" (\_ -> Positional.hash512 bytes256)
            , Benchmark.benchmark "Optimized" (\_ -> Optimized.hash512 bytes256)
            ]
        , describe "1024 bytes"
            [ Benchmark.benchmark "Record" (\_ -> Record.hash512 bytes1024)
            , Benchmark.benchmark "Tuple" (\_ -> Tuple.hash512 bytes1024)
            , Benchmark.benchmark "Positional" (\_ -> Positional.hash512 bytes1024)
            , Benchmark.benchmark "Optimized" (\_ -> Optimized.hash512 bytes1024)
            ]
        ]
