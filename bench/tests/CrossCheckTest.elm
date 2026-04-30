module CrossCheckTest exposing (suite)

{-| Cross-check tests verifying V2 produces identical output to V1.
Run from the bench/ directory: elm-test
-}

import Bitwise
import Blake2b
import Blake2b.V2
import Blake2b256
import Blake2b512
import Bytes exposing (Bytes)
import Bytes.Encode as Encode
import Expect
import Test exposing (Test, describe, test)
import TestHelpers exposing (bytesToHex, hexToBytes)


v1Hash : { digestLength : Int, key : Bytes, data : Bytes } -> Bytes
v1Hash { digestLength, key, data } =
    Blake2b.fromBytes { digestLength = digestLength, key = key } data
        |> Blake2b.toBytes


v1Hash512 : Bytes -> Bytes
v1Hash512 data =
    Blake2b512.toBytes (Blake2b512.fromBytes data)


v1Hash256 : Bytes -> Bytes
v1Hash256 data =
    Blake2b256.toBytes (Blake2b256.fromBytes data)


emptyBytes : Bytes
emptyBytes =
    Encode.encode (Encode.sequence [])


sequentialBytes : Int -> Bytes
sequentialBytes n =
    Encode.encode
        (Encode.sequence
            (List.map (\i -> Encode.unsignedInt8 (modBy 256 i)) (List.range 0 (n - 1)))
        )


katKey : Bytes
katKey =
    sequentialBytes 64


suite : Test
suite =
    describe "V2 cross-check"
        [ describe "hash512"
            [ test "empty input" <|
                \_ ->
                    Blake2b.V2.hash512 emptyBytes
                        |> bytesToHex
                        |> Expect.equal (v1Hash512 emptyBytes |> bytesToHex)
            , test "abc" <|
                \_ ->
                    Blake2b.V2.hash512 (hexToBytes "616263")
                        |> bytesToHex
                        |> Expect.equal (v1Hash512 (hexToBytes "616263") |> bytesToHex)
            , test "128 bytes" <|
                \_ ->
                    Blake2b.V2.hash512 (sequentialBytes 128)
                        |> bytesToHex
                        |> Expect.equal (v1Hash512 (sequentialBytes 128) |> bytesToHex)
            , test "129 bytes" <|
                \_ ->
                    Blake2b.V2.hash512 (sequentialBytes 129)
                        |> bytesToHex
                        |> Expect.equal (v1Hash512 (sequentialBytes 129) |> bytesToHex)
            , test "255 bytes" <|
                \_ ->
                    Blake2b.V2.hash512 (sequentialBytes 255)
                        |> bytesToHex
                        |> Expect.equal (v1Hash512 (sequentialBytes 255) |> bytesToHex)
            , test "1024 bytes" <|
                \_ ->
                    Blake2b.V2.hash512 (sequentialBytes 1024)
                        |> bytesToHex
                        |> Expect.equal (v1Hash512 (sequentialBytes 1024) |> bytesToHex)
            ]
        , describe "keyed hash"
            [ test "64-byte keyed message" <|
                \_ ->
                    Blake2b.V2.hash { digestLength = 64, key = katKey, data = sequentialBytes 64 }
                        |> bytesToHex
                        |> Expect.equal (v1Hash { digestLength = 64, key = katKey, data = sequentialBytes 64 } |> bytesToHex)
            , test "128-byte keyed message" <|
                \_ ->
                    Blake2b.V2.hash { digestLength = 64, key = katKey, data = sequentialBytes 128 }
                        |> bytesToHex
                        |> Expect.equal (v1Hash { digestLength = 64, key = katKey, data = sequentialBytes 128 } |> bytesToHex)
            ]
        , describe "hash256"
            [ test "abc" <|
                \_ ->
                    Blake2b.V2.hash256 (hexToBytes "616263")
                        |> bytesToHex
                        |> Expect.equal (v1Hash256 (hexToBytes "616263") |> bytesToHex)
            ]
        , describe "self-test (Appendix E)"
            [ test "V2 grand hash matches V1 grand hash" <|
                \_ ->
                    let
                        grandHash impl =
                            let
                                mdLens =
                                    [ 20, 32, 48, 64 ]

                                inLens =
                                    [ 0, 3, 128, 129, 255, 1024 ]

                                allOutputs =
                                    List.foldl
                                        (\outlen outerAcc ->
                                            List.foldl
                                                (\inlen innerAcc ->
                                                    let
                                                        inputData =
                                                            selftestSeq inlen inlen

                                                        key =
                                                            selftestSeq outlen outlen

                                                        unkeyed =
                                                            impl.hash
                                                                { digestLength = outlen
                                                                , key = emptyBytes
                                                                , data = inputData
                                                                }

                                                        keyed =
                                                            impl.hash
                                                                { digestLength = outlen
                                                                , key = key
                                                                , data = inputData
                                                                }
                                                    in
                                                    appendBytes (appendBytes innerAcc unkeyed) keyed
                                                )
                                                outerAcc
                                                inLens
                                        )
                                        emptyBytes
                                        mdLens
                            in
                            impl.hash
                                { digestLength = 32
                                , key = emptyBytes
                                , data = allOutputs
                                }
                                |> bytesToHex
                    in
                    grandHash { hash = Blake2b.V2.hash }
                        |> Expect.equal (grandHash { hash = v1Hash })
            ]
        ]


selftestSeq : Int -> Int -> Bytes
selftestSeq len seed =
    let
        a0 =
            Bitwise.shiftRightZfBy 0 (0xDEAD4BAD * seed)

        generate _ ( a, b, acc ) =
            let
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
