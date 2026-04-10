module Blake2bCrossCheckTest exposing (suite)

import Blake2b.Optimized as Optimized
import Blake2b.Positional as Positional
import Blake2b.Record as Record
import Blake2b.Tuple as Tuple
import Bytes exposing (Bytes)
import Bytes.Encode as Encode
import Expect
import Test exposing (Test, describe, test)
import TestHelpers exposing (bytesToHex)


emptyBytes : Bytes
emptyBytes =
    Encode.encode (Encode.sequence [])


sequentialBytes : Int -> Bytes
sequentialBytes n =
    Encode.encode (Encode.sequence (List.map Encode.unsignedInt8 (List.range 0 (n - 1))))


type alias Case =
    { label : String, digestLength : Int, key : Bytes, data : Bytes }


suite : Test
suite =
    describe "Cross-check: all three variants produce identical output"
        (List.concatMap crossCheckCase
            [ Case "empty unkeyed 512" 64 emptyBytes emptyBytes
            , Case "abc unkeyed 512" 64 emptyBytes (sequentialBytes 3)
            , Case "empty keyed 512" 64 (sequentialBytes 64) emptyBytes
            , Case "1-byte keyed 512" 64 (sequentialBytes 64) (sequentialBytes 1)
            , Case "128-byte keyed 512" 64 (sequentialBytes 64) (sequentialBytes 128)
            , Case "255-byte keyed 512" 64 (sequentialBytes 64) (sequentialBytes 255)
            , Case "1024-byte unkeyed 512" 64 emptyBytes (sequentialBytes 1024)
            , Case "empty unkeyed 256" 32 emptyBytes emptyBytes
            , Case "abc unkeyed 256" 32 emptyBytes (sequentialBytes 3)
            , Case "empty unkeyed 224" 28 emptyBytes emptyBytes
            , Case "129-byte keyed 224" 28 (sequentialBytes 32) (sequentialBytes 129)
            ]
        )


crossCheckCase : Case -> List Test
crossCheckCase c =
    let
        config =
            { digestLength = c.digestLength, key = c.key, data = c.data }

        recordResult =
            Record.hash config |> bytesToHex

        tupleResult =
            Tuple.hash config |> bytesToHex

        positionalResult =
            Positional.hash config |> bytesToHex

        optimizedResult =
            Optimized.hash config |> bytesToHex
    in
    [ test (c.label ++ ": Record == Tuple") <|
        \_ -> Expect.equal recordResult tupleResult
    , test (c.label ++ ": Record == Positional") <|
        \_ -> Expect.equal recordResult positionalResult
    , test (c.label ++ ": Record == Optimized") <|
        \_ -> Expect.equal recordResult optimizedResult
    ]
