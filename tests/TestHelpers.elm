module TestHelpers exposing (hexToBytes)

import Bytes exposing (Bytes)
import Bytes.Encode as Encode


{-| Convert a hex string to Bytes. Assumes even-length, lowercase or uppercase hex.
-}
hexToBytes : String -> Bytes
hexToBytes hexStr =
    let
        chars : List Char
        chars =
            String.toList hexStr

        pairs : List Int
        pairs =
            toPairs chars []
    in
    Encode.encode (Encode.sequence (List.map (\b -> Encode.unsignedInt8 b) pairs))


toPairs : List Char -> List Int -> List Int
toPairs chars acc =
    case chars of
        hi :: lo :: rest ->
            toPairs rest (acc ++ [ hexCharToInt hi * 16 + hexCharToInt lo ])

        _ ->
            acc


hexCharToInt : Char -> Int
hexCharToInt c =
    let
        code : Int
        code =
            Char.toCode c
    in
    if code >= 0x30 && code <= 0x39 then
        code - 0x30

    else if code >= 0x41 && code <= 0x46 then
        code - 0x41 + 10

    else if code >= 0x61 && code <= 0x66 then
        code - 0x61 + 10

    else
        0
