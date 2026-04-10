module Blake2b.Internal.Decode exposing
    ( MessageBlock
    , blockDecoder
    , encodeDigest
    , padBlock
    )

import Bytes exposing (Bytes, Endianness(..))
import Bytes.Decode as Decode
import Bytes.Encode as Encode


type alias MessageBlock =
    { m0Hi : Int
    , m0Lo : Int
    , m1Hi : Int
    , m1Lo : Int
    , m2Hi : Int
    , m2Lo : Int
    , m3Hi : Int
    , m3Lo : Int
    , m4Hi : Int
    , m4Lo : Int
    , m5Hi : Int
    , m5Lo : Int
    , m6Hi : Int
    , m6Lo : Int
    , m7Hi : Int
    , m7Lo : Int
    , m8Hi : Int
    , m8Lo : Int
    , m9Hi : Int
    , m9Lo : Int
    , m10Hi : Int
    , m10Lo : Int
    , m11Hi : Int
    , m11Lo : Int
    , m12Hi : Int
    , m12Lo : Int
    , m13Hi : Int
    , m13Lo : Int
    , m14Hi : Int
    , m14Lo : Int
    , m15Hi : Int
    , m15Lo : Int
    }


{-| Decode a 128-byte block into 16 little-endian 64-bit words (as hi/lo Int pairs).
Each 64-bit word is stored as lo 32 bits first, then hi 32 bits (little-endian byte order).
-}
blockDecoder : Decode.Decoder MessageBlock
blockDecoder =
    Decode.unsignedInt32 LE
        |> Decode.andThen
            (\m0Lo ->
                Decode.unsignedInt32 LE
                    |> Decode.andThen
                        (\m0Hi ->
                            Decode.unsignedInt32 LE
                                |> Decode.andThen
                                    (\m1Lo ->
                                        Decode.unsignedInt32 LE
                                            |> Decode.andThen
                                                (\m1Hi ->
                                                    decodeFrom2 m0Hi m0Lo m1Hi m1Lo
                                                )
                                    )
                        )
            )


decodeFrom2 : Int -> Int -> Int -> Int -> Decode.Decoder MessageBlock
decodeFrom2 m0Hi m0Lo m1Hi m1Lo =
    Decode.unsignedInt32 LE
        |> Decode.andThen
            (\m2Lo ->
                Decode.unsignedInt32 LE
                    |> Decode.andThen
                        (\m2Hi ->
                            Decode.unsignedInt32 LE
                                |> Decode.andThen
                                    (\m3Lo ->
                                        Decode.unsignedInt32 LE
                                            |> Decode.andThen
                                                (\m3Hi ->
                                                    decodeFrom4 m0Hi m0Lo m1Hi m1Lo m2Hi m2Lo m3Hi m3Lo
                                                )
                                    )
                        )
            )


decodeFrom4 : Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Decode.Decoder MessageBlock
decodeFrom4 m0Hi m0Lo m1Hi m1Lo m2Hi m2Lo m3Hi m3Lo =
    Decode.unsignedInt32 LE
        |> Decode.andThen
            (\m4Lo ->
                Decode.unsignedInt32 LE
                    |> Decode.andThen
                        (\m4Hi ->
                            Decode.unsignedInt32 LE
                                |> Decode.andThen
                                    (\m5Lo ->
                                        Decode.unsignedInt32 LE
                                            |> Decode.andThen
                                                (\m5Hi ->
                                                    decodeFrom6 m0Hi m0Lo m1Hi m1Lo m2Hi m2Lo m3Hi m3Lo m4Hi m4Lo m5Hi m5Lo
                                                )
                                    )
                        )
            )


decodeFrom6 : Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Decode.Decoder MessageBlock
decodeFrom6 m0Hi m0Lo m1Hi m1Lo m2Hi m2Lo m3Hi m3Lo m4Hi m4Lo m5Hi m5Lo =
    Decode.unsignedInt32 LE
        |> Decode.andThen
            (\m6Lo ->
                Decode.unsignedInt32 LE
                    |> Decode.andThen
                        (\m6Hi ->
                            Decode.unsignedInt32 LE
                                |> Decode.andThen
                                    (\m7Lo ->
                                        Decode.unsignedInt32 LE
                                            |> Decode.andThen
                                                (\m7Hi ->
                                                    decodeFrom8 m0Hi m0Lo m1Hi m1Lo m2Hi m2Lo m3Hi m3Lo m4Hi m4Lo m5Hi m5Lo m6Hi m6Lo m7Hi m7Lo
                                                )
                                    )
                        )
            )


decodeFrom8 : Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Decode.Decoder MessageBlock
decodeFrom8 m0Hi m0Lo m1Hi m1Lo m2Hi m2Lo m3Hi m3Lo m4Hi m4Lo m5Hi m5Lo m6Hi m6Lo m7Hi m7Lo =
    Decode.unsignedInt32 LE
        |> Decode.andThen
            (\m8Lo ->
                Decode.unsignedInt32 LE
                    |> Decode.andThen
                        (\m8Hi ->
                            Decode.unsignedInt32 LE
                                |> Decode.andThen
                                    (\m9Lo ->
                                        Decode.unsignedInt32 LE
                                            |> Decode.andThen
                                                (\m9Hi ->
                                                    decodeFrom10 m0Hi m0Lo m1Hi m1Lo m2Hi m2Lo m3Hi m3Lo m4Hi m4Lo m5Hi m5Lo m6Hi m6Lo m7Hi m7Lo m8Hi m8Lo m9Hi m9Lo
                                                )
                                    )
                        )
            )


decodeFrom10 : Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Decode.Decoder MessageBlock
decodeFrom10 m0Hi m0Lo m1Hi m1Lo m2Hi m2Lo m3Hi m3Lo m4Hi m4Lo m5Hi m5Lo m6Hi m6Lo m7Hi m7Lo m8Hi m8Lo m9Hi m9Lo =
    Decode.unsignedInt32 LE
        |> Decode.andThen
            (\m10Lo ->
                Decode.unsignedInt32 LE
                    |> Decode.andThen
                        (\m10Hi ->
                            Decode.unsignedInt32 LE
                                |> Decode.andThen
                                    (\m11Lo ->
                                        Decode.unsignedInt32 LE
                                            |> Decode.andThen
                                                (\m11Hi ->
                                                    decodeFrom12 m0Hi m0Lo m1Hi m1Lo m2Hi m2Lo m3Hi m3Lo m4Hi m4Lo m5Hi m5Lo m6Hi m6Lo m7Hi m7Lo m8Hi m8Lo m9Hi m9Lo m10Hi m10Lo m11Hi m11Lo
                                                )
                                    )
                        )
            )


decodeFrom12 : Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Decode.Decoder MessageBlock
decodeFrom12 m0Hi m0Lo m1Hi m1Lo m2Hi m2Lo m3Hi m3Lo m4Hi m4Lo m5Hi m5Lo m6Hi m6Lo m7Hi m7Lo m8Hi m8Lo m9Hi m9Lo m10Hi m10Lo m11Hi m11Lo =
    Decode.unsignedInt32 LE
        |> Decode.andThen
            (\m12Lo ->
                Decode.unsignedInt32 LE
                    |> Decode.andThen
                        (\m12Hi ->
                            Decode.unsignedInt32 LE
                                |> Decode.andThen
                                    (\m13Lo ->
                                        Decode.unsignedInt32 LE
                                            |> Decode.andThen
                                                (\m13Hi ->
                                                    decodeFrom14 m0Hi m0Lo m1Hi m1Lo m2Hi m2Lo m3Hi m3Lo m4Hi m4Lo m5Hi m5Lo m6Hi m6Lo m7Hi m7Lo m8Hi m8Lo m9Hi m9Lo m10Hi m10Lo m11Hi m11Lo m12Hi m12Lo m13Hi m13Lo
                                                )
                                    )
                        )
            )


decodeFrom14 : Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Decode.Decoder MessageBlock
decodeFrom14 m0Hi m0Lo m1Hi m1Lo m2Hi m2Lo m3Hi m3Lo m4Hi m4Lo m5Hi m5Lo m6Hi m6Lo m7Hi m7Lo m8Hi m8Lo m9Hi m9Lo m10Hi m10Lo m11Hi m11Lo m12Hi m12Lo m13Hi m13Lo =
    Decode.unsignedInt32 LE
        |> Decode.andThen
            (\m14Lo ->
                Decode.unsignedInt32 LE
                    |> Decode.andThen
                        (\m14Hi ->
                            Decode.unsignedInt32 LE
                                |> Decode.andThen
                                    (\m15Lo ->
                                        Decode.unsignedInt32 LE
                                            |> Decode.andThen
                                                (\m15Hi ->
                                                    Decode.succeed
                                                        { m0Hi = m0Hi
                                                        , m0Lo = m0Lo
                                                        , m1Hi = m1Hi
                                                        , m1Lo = m1Lo
                                                        , m2Hi = m2Hi
                                                        , m2Lo = m2Lo
                                                        , m3Hi = m3Hi
                                                        , m3Lo = m3Lo
                                                        , m4Hi = m4Hi
                                                        , m4Lo = m4Lo
                                                        , m5Hi = m5Hi
                                                        , m5Lo = m5Lo
                                                        , m6Hi = m6Hi
                                                        , m6Lo = m6Lo
                                                        , m7Hi = m7Hi
                                                        , m7Lo = m7Lo
                                                        , m8Hi = m8Hi
                                                        , m8Lo = m8Lo
                                                        , m9Hi = m9Hi
                                                        , m9Lo = m9Lo
                                                        , m10Hi = m10Hi
                                                        , m10Lo = m10Lo
                                                        , m11Hi = m11Hi
                                                        , m11Lo = m11Lo
                                                        , m12Hi = m12Hi
                                                        , m12Lo = m12Lo
                                                        , m13Hi = m13Hi
                                                        , m13Lo = m13Lo
                                                        , m14Hi = m14Hi
                                                        , m14Lo = m14Lo
                                                        , m15Hi = m15Hi
                                                        , m15Lo = m15Lo
                                                        }
                                                )
                                    )
                        )
            )


{-| Encode the hash state (8 x 64-bit words as hi/lo pairs) into the first
digestLength bytes. Each word is encoded as lo then hi in little-endian order,
producing 64 bytes total, then the first digestLength bytes are extracted.
-}
encodeDigest : Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Bytes
encodeDigest digestLength h0Hi h0Lo h1Hi h1Lo h2Hi h2Lo h3Hi h3Lo h4Hi h4Lo h5Hi h5Lo h6Hi h6Lo h7Hi h7Lo =
    let
        full =
            Encode.encode
                (Encode.sequence
                    [ Encode.unsignedInt32 LE h0Lo
                    , Encode.unsignedInt32 LE h0Hi
                    , Encode.unsignedInt32 LE h1Lo
                    , Encode.unsignedInt32 LE h1Hi
                    , Encode.unsignedInt32 LE h2Lo
                    , Encode.unsignedInt32 LE h2Hi
                    , Encode.unsignedInt32 LE h3Lo
                    , Encode.unsignedInt32 LE h3Hi
                    , Encode.unsignedInt32 LE h4Lo
                    , Encode.unsignedInt32 LE h4Hi
                    , Encode.unsignedInt32 LE h5Lo
                    , Encode.unsignedInt32 LE h5Hi
                    , Encode.unsignedInt32 LE h6Lo
                    , Encode.unsignedInt32 LE h6Hi
                    , Encode.unsignedInt32 LE h7Lo
                    , Encode.unsignedInt32 LE h7Hi
                    ]
                )
    in
    case Decode.decode (Decode.bytes digestLength) full of
        Just b ->
            b

        Nothing ->
            full


{-| Pad a partial block (0-127 bytes) with zeros to make a full 128-byte block.
-}
padBlock : Bytes -> Bytes
padBlock partial =
    let
        len =
            Bytes.width partial

        padLen =
            128 - len
    in
    Encode.encode
        (Encode.sequence
            [ Encode.bytes partial
            , Encode.sequence (List.repeat padLen (Encode.unsignedInt8 0))
            ]
        )
