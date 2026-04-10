module TestHelpers exposing (bytesToHex, hexToBytes)

import Bytes exposing (Bytes)
import Bytes.Decode as Decode
import Bytes.Encode as Encode


{-| Convert a hex string to Bytes. Assumes even-length, lowercase or uppercase hex.
-}
hexToBytes : String -> Bytes
hexToBytes hexStr =
    let
        chars =
            String.toList hexStr

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


{-| Convert Bytes to a lowercase hex string.
-}
bytesToHex : Bytes -> String
bytesToHex bytes =
    case Decode.decode (bytesToHexDecoder (Bytes.width bytes)) bytes of
        Just hex ->
            hex

        Nothing ->
            ""


bytesToHexDecoder : Int -> Decode.Decoder String
bytesToHexDecoder len =
    Decode.loop ( len, "" ) bytesToHexStep


bytesToHexStep : ( Int, String ) -> Decode.Decoder (Decode.Step ( Int, String ) String)
bytesToHexStep ( remaining, acc ) =
    if remaining <= 0 then
        Decode.succeed (Decode.Done acc)

    else
        Decode.unsignedInt8
            |> Decode.map
                (\byte ->
                    Decode.Loop ( remaining - 1, acc ++ byteToHex byte )
                )


byteToHex : Int -> String
byteToHex byte =
    let
        hi =
            nibbleToChar (byte // 16)

        lo =
            nibbleToChar (modBy 16 byte)
    in
    String.fromChar hi ++ String.fromChar lo


nibbleToChar : Int -> Char
nibbleToChar n =
    if n < 10 then
        Char.fromCode (0x30 + n)

    else
        Char.fromCode (0x61 + n - 10)
