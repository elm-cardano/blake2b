module Blake2bTest exposing (suite)

import Bitwise
import Blake2b
import Blake2b224
import Blake2b256
import Blake2b512
import Bytes exposing (Bytes)
import Bytes.Encode as Encode
import Expect
import Test exposing (Test, describe, test)
import TestHelpers exposing (hexToBytes)


emptyBytes : Bytes
emptyBytes =
    Encode.encode (Encode.sequence [])


{-| Build a Bytes value from a list of integers (each 0-255).
-}
bytesFromList : List Int -> Bytes
bytesFromList ints =
    Encode.encode (Encode.sequence (List.map Encode.unsignedInt8 ints))


{-| Generate sequential bytes 0x00, 0x01, ..., 0x(n-1).
-}
sequentialBytes : Int -> Bytes
sequentialBytes n =
    bytesFromList (List.range 0 (n - 1))


{-| The standard KAT key: 64 bytes 0x00 0x01 ... 0x3F.
-}
katKey : Bytes
katKey =
    sequentialBytes 64


keyedHex : Int -> Bytes -> Bytes -> String
keyedHex digestLength key data =
    Blake2b.fromBytes { digestLength = digestLength, key = key } data
        |> Blake2b.toHex


suite : Test
suite =
    describe "Blake2b"
        [ rfcVectors
        , katVectors
        , convenienceFunctions
        , selfTest
        , edgeCases
        ]



-- RFC 7693 Appendix A test vectors


rfcVectors : Test
rfcVectors =
    describe "RFC 7693 test vectors"
        [ test "BLAKE2b-512 of empty string (unkeyed)" <|
            \_ ->
                keyedHex 64 emptyBytes emptyBytes
                    |> Expect.equal
                        "786a02f742015903c6c6fd852552d272912f4740e15847618a86e217f71f5419d25e1031afee585313896444934eb04b903a685b1448b755d56f701afe9be2ce"
        , test "BLAKE2b-512 of \"abc\" (unkeyed)" <|
            \_ ->
                keyedHex 64 emptyBytes (hexToBytes "616263")
                    |> Expect.equal
                        "ba80a53f981c4d0d6a2797b69f12f6e94c212f14685ac4b74b12bb6fdbffa2d17d87c5392aab792dc252d5de4533cc9518d38aa8dbf1925ab92386edd4009923"
        ]



-- BLAKE2 KAT (Known Answer Test) keyed vectors


katVectors : Test
katVectors =
    describe "BLAKE2b KAT keyed vectors (64-byte key, 512-bit digest)"
        [ test "message length 0" <|
            \_ ->
                keyedHex 64 katKey emptyBytes
                    |> Expect.equal
                        "10ebb67700b1868efb4417987acf4690ae9d972fb7a590c2f02871799aaa4786b5e996e8f0f4eb981fc214b005f42d2ff4233499391653df7aefcbc13fc51568"
        , test "message length 1 (0x00)" <|
            \_ ->
                keyedHex 64 katKey (sequentialBytes 1)
                    |> Expect.equal
                        "961f6dd1e4dd30f63901690c512e78e4b45e4742ed197c3c5e45c549fd25f2e4187b0bc9fe30492b16b0d0bc4ef9b0f34c7003fac09a5ef1532e69430234cebd"
        , test "message length 2 (0x00 0x01)" <|
            \_ ->
                keyedHex 64 katKey (sequentialBytes 2)
                    |> Expect.equal
                        "da2cfbe2d8409a0f38026113884f84b50156371ae304c4430173d08a99d9fb1b983164a3770706d537f49e0c916d9f32b95cc37a95b99d857436f0232c88a965"
        , test "message length 3 (0x00 0x01 0x02)" <|
            \_ ->
                keyedHex 64 katKey (sequentialBytes 3)
                    |> Expect.equal
                        "33d0825dddf7ada99b0e7e307104ad07ca9cfd9692214f1561356315e784f3e5a17e364ae9dbb14cb2036df932b77f4b292761365fb328de7afdc6d8998f5fc1"
        , test "message length 64" <|
            \_ ->
                keyedHex 64 katKey (sequentialBytes 64)
                    |> Expect.equal
                        "65676d800617972fbd87e4b9514e1c67402b7a331096d3bfac22f1abb95374abc942f16e9ab0ead33b87c91968a6e509e119ff07787b3ef483e1dcdccf6e3022"
        , test "message length 128" <|
            \_ ->
                keyedHex 64 katKey (sequentialBytes 128)
                    |> Expect.equal
                        "72065ee4dd91c2d8509fa1fc28a37c7fc9fa7d5b3f8ad3d0d7a25626b57b1b44788d4caf806290425f9890a3a2a35a905ab4b37acfd0da6e4517b2525c9651e4"
        , test "message length 255" <|
            \_ ->
                keyedHex 64 katKey (sequentialBytes 255)
                    |> Expect.equal
                        "142709d62e28fcccd0af97fad0f8465b971e82201dc51070faa0372aa43e92484be1c1e73ba10906d5d1853db6a4106e0a7bf9800d373d6dee2d46d62ef2a461"
        ]



-- Convenience function tests


convenienceFunctions : Test
convenienceFunctions =
    describe "Fixed-size modules"
        [ test "Blake2b512 of empty string matches generic with digestLength=64" <|
            \_ ->
                Blake2b512.fromBytes emptyBytes
                    |> Blake2b512.toHex
                    |> Expect.equal (keyedHex 64 emptyBytes emptyBytes)
        , test "Blake2b512 of \"abc\"" <|
            \_ ->
                Blake2b512.fromBytes (hexToBytes "616263")
                    |> Blake2b512.toHex
                    |> Expect.equal
                        "ba80a53f981c4d0d6a2797b69f12f6e94c212f14685ac4b74b12bb6fdbffa2d17d87c5392aab792dc252d5de4533cc9518d38aa8dbf1925ab92386edd4009923"
        , test "Blake2b256 of empty string matches reference vector" <|
            \_ ->
                Blake2b256.fromBytes emptyBytes
                    |> Blake2b256.toHex
                    |> Expect.equal
                        "0e5751c026e543b2e8ab2eb06099daa1d1e5df47778f7787faab45cdf12fe3a8"
        , test "Blake2b256 of \"abc\" matches reference vector" <|
            \_ ->
                Blake2b256.fromBytes (hexToBytes "616263")
                    |> Blake2b256.toHex
                    |> Expect.equal
                        "bddd813c634239723171ef3fee98579b94964e3bb1cb3e427262c8c068d52319"
        , test "Blake2b224 of empty string matches reference vector" <|
            \_ ->
                Blake2b224.fromBytes emptyBytes
                    |> Blake2b224.toHex
                    |> Expect.equal
                        "836cc68931c2e4e3e838602eca1902591d216837bafddfe6f0c8cb07"
        , test "Blake2b224 of \"abc\" matches reference vector" <|
            \_ ->
                Blake2b224.fromBytes (hexToBytes "616263")
                    |> Blake2b224.toHex
                    |> Expect.equal
                        "9bd237b02a29e43bdd6738afa5b53ff0eee178d6210b618e4511aec8"
        , test "fromString matches fromBytes for the same content" <|
            \_ ->
                Blake2b256.fromString "abc"
                    |> Blake2b256.toHex
                    |> Expect.equal
                        (Blake2b256.fromBytes (hexToBytes "616263") |> Blake2b256.toHex)
        , test "fromByteValues matches fromBytes" <|
            \_ ->
                Blake2b256.fromByteValues [ 0x61, 0x62, 0x63 ]
                    |> Blake2b256.toHex
                    |> Expect.equal
                        (Blake2b256.fromBytes (hexToBytes "616263") |> Blake2b256.toHex)
        , test "toByteValues round-trips through fromByteValues" <|
            \_ ->
                let
                    digest : Blake2b256.Digest
                    digest =
                        Blake2b256.fromBytes (hexToBytes "616263")
                in
                Blake2b256.toByteValues digest
                    |> List.length
                    |> Expect.equal 32
        , test "toBase64 produces a non-empty string" <|
            \_ ->
                Blake2b256.fromBytes emptyBytes
                    |> Blake2b256.toBase64
                    |> String.isEmpty
                    |> Expect.equal False
        ]



-- RFC 7693 Appendix E Self-Test


{-| Pseudorandom sequence generator from RFC 7693 Appendix E.
-}
selftestSeq : Int -> Int -> Bytes
selftestSeq len seed =
    let
        a0 : Int
        a0 =
            Bitwise.shiftRightZfBy 0 (0xDEAD4BAD * seed)

        generate : Int -> ( Int, Int, List Encode.Encoder ) -> ( Int, Int, List Encode.Encoder )
        generate _ ( a, b, acc ) =
            let
                t : Int
                t =
                    Bitwise.shiftRightZfBy 0 (a + b)
            in
            ( b, t, Encode.unsignedInt8 (Bitwise.and (Bitwise.shiftRightZfBy 24 t) 0xFF) :: acc )

        ( _, _, reversedEncoders ) =
            List.foldl generate ( a0, 1, [] ) (List.range 0 (len - 1))
    in
    Encode.encode (Encode.sequence (List.reverse reversedEncoders))


appendBytes : Bytes -> Bytes -> Bytes
appendBytes a b =
    Encode.encode
        (Encode.sequence
            [ Encode.bytes a
            , Encode.bytes b
            ]
        )


selfTest : Test
selfTest =
    describe "RFC 7693 Appendix E self-test"
        [ test "grand hash of all test outputs equals expected BLAKE2b-256 digest" <|
            \_ ->
                let
                    mdLens : List Int
                    mdLens =
                        [ 20, 32, 48, 64 ]

                    inLens : List Int
                    inLens =
                        [ 0, 3, 128, 129, 255, 1024 ]

                    allOutputs : Bytes
                    allOutputs =
                        List.foldl
                            (\outlen outerAcc ->
                                List.foldl
                                    (\inlen innerAcc ->
                                        let
                                            inputData : Bytes
                                            inputData =
                                                selftestSeq inlen inlen

                                            key : Bytes
                                            key =
                                                selftestSeq outlen outlen

                                            unkeyed : Bytes
                                            unkeyed =
                                                Blake2b.fromBytes
                                                    { digestLength = outlen, key = emptyBytes }
                                                    inputData
                                                    |> Blake2b.toBytes

                                            keyed : Bytes
                                            keyed =
                                                Blake2b.fromBytes
                                                    { digestLength = outlen, key = key }
                                                    inputData
                                                    |> Blake2b.toBytes
                                        in
                                        appendBytes (appendBytes innerAcc unkeyed) keyed
                                    )
                                    outerAcc
                                    inLens
                            )
                            emptyBytes
                            mdLens
                in
                Blake2b256.fromBytes allOutputs
                    |> Blake2b256.toHex
                    |> Expect.equal
                        "c23a7800d98123bd10f506c61e29da5603d763b8bbad2e737f5e765a7bccd475"
        ]



-- Edge cases around block boundaries (128 bytes per block)


edgeCases : Test
edgeCases =
    describe "Edge cases around block boundaries"
        [ test "127 bytes (one byte short of a full block)" <|
            \_ ->
                keyedHex 64 katKey (sequentialBytes 127)
                    |> String.length
                    |> Expect.equal 128
        , test "128 bytes (exactly one block)" <|
            \_ ->
                keyedHex 64 katKey (sequentialBytes 128)
                    |> Expect.equal
                        "72065ee4dd91c2d8509fa1fc28a37c7fc9fa7d5b3f8ad3d0d7a25626b57b1b44788d4caf806290425f9890a3a2a35a905ab4b37acfd0da6e4517b2525c9651e4"
        , test "129 bytes (one byte past a full block)" <|
            \_ ->
                keyedHex 64 katKey (sequentialBytes 129)
                    |> String.length
                    |> Expect.equal 128
        , test "keyed hash with 127-byte message produces correct length" <|
            \_ ->
                Blake2b.fromBytes { digestLength = 64, key = katKey } (sequentialBytes 127)
                    |> Blake2b.toBytes
                    |> Bytes.width
                    |> Expect.equal 64
        , test "unkeyed hash with 128-byte message" <|
            \_ ->
                keyedHex 64 emptyBytes (sequentialBytes 128)
                    |> String.length
                    |> Expect.equal 128
        , test "unkeyed hash with 129-byte message" <|
            \_ ->
                keyedHex 64 emptyBytes (sequentialBytes 129)
                    |> String.length
                    |> Expect.equal 128
        , test "different digest lengths produce different results" <|
            \_ ->
                let
                    d32 : String
                    d32 =
                        keyedHex 32 emptyBytes (hexToBytes "616263")

                    d64 : String
                    d64 =
                        keyedHex 64 emptyBytes (hexToBytes "616263")
                in
                Expect.notEqual d32 (String.left 64 d64)
        ]
