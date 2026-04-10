module Blake2b.DecodeV2 exposing
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


{-| Four 64-bit words decoded as hi/lo Int pairs (8 fields).
Used as an intermediate step to keep all decoder helper arities within
Elm's F2..F9 fast path (no function exceeds 9 arguments).
-}
type alias QuarterBlock =
    { w0Hi : Int
    , w0Lo : Int
    , w1Hi : Int
    , w1Lo : Int
    , w2Hi : Int
    , w2Lo : Int
    , w3Hi : Int
    , w3Lo : Int
    }


{-| Decode 4 little-endian 64-bit words (8 × u32) into a QuarterBlock.
-}
decodeQuarter : Decode.Decoder QuarterBlock
decodeQuarter =
    Decode.unsignedInt32 LE
        |> Decode.andThen
            (\w0Lo ->
                Decode.unsignedInt32 LE
                    |> Decode.andThen
                        (\w0Hi ->
                            Decode.unsignedInt32 LE
                                |> Decode.andThen
                                    (\w1Lo ->
                                        Decode.unsignedInt32 LE
                                            |> Decode.andThen
                                                (\w1Hi ->
                                                    Decode.unsignedInt32 LE
                                                        |> Decode.andThen
                                                            (\w2Lo ->
                                                                Decode.unsignedInt32 LE
                                                                    |> Decode.andThen
                                                                        (\w2Hi ->
                                                                            Decode.unsignedInt32 LE
                                                                                |> Decode.andThen
                                                                                    (\w3Lo ->
                                                                                        Decode.unsignedInt32 LE
                                                                                            |> Decode.map
                                                                                                (\w3Hi ->
                                                                                                    { w0Hi = w0Hi
                                                                                                    , w0Lo = w0Lo
                                                                                                    , w1Hi = w1Hi
                                                                                                    , w1Lo = w1Lo
                                                                                                    , w2Hi = w2Hi
                                                                                                    , w2Lo = w2Lo
                                                                                                    , w3Hi = w3Hi
                                                                                                    , w3Lo = w3Lo
                                                                                                    }
                                                                                                )
                                                                                    )
                                                                        )
                                                            )
                                                )
                                    )
                        )
            )


{-| Decode a 128-byte block into 16 little-endian 64-bit words (as hi/lo Int pairs).
Each 64-bit word is stored as lo 32 bits first, then hi 32 bits (little-endian byte order).

Uses 4 × decodeQuarter (8 args each) to stay within Elm's 9-argument fast path.
The previous implementation used chained helper functions with up to 28 arguments,
causing ~55 intermediate closure allocations per block from curried overflow.

-}
blockDecoder : Decode.Decoder MessageBlock
blockDecoder =
    decodeQuarter
        |> Decode.andThen
            (\q0 ->
                decodeQuarter
                    |> Decode.andThen
                        (\q1 ->
                            decodeQuarter
                                |> Decode.andThen
                                    (\q2 ->
                                        decodeQuarter
                                            |> Decode.map
                                                (\q3 ->
                                                    { m0Hi = q0.w0Hi
                                                    , m0Lo = q0.w0Lo
                                                    , m1Hi = q0.w1Hi
                                                    , m1Lo = q0.w1Lo
                                                    , m2Hi = q0.w2Hi
                                                    , m2Lo = q0.w2Lo
                                                    , m3Hi = q0.w3Hi
                                                    , m3Lo = q0.w3Lo
                                                    , m4Hi = q1.w0Hi
                                                    , m4Lo = q1.w0Lo
                                                    , m5Hi = q1.w1Hi
                                                    , m5Lo = q1.w1Lo
                                                    , m6Hi = q1.w2Hi
                                                    , m6Lo = q1.w2Lo
                                                    , m7Hi = q1.w3Hi
                                                    , m7Lo = q1.w3Lo
                                                    , m8Hi = q2.w0Hi
                                                    , m8Lo = q2.w0Lo
                                                    , m9Hi = q2.w1Hi
                                                    , m9Lo = q2.w1Lo
                                                    , m10Hi = q2.w2Hi
                                                    , m10Lo = q2.w2Lo
                                                    , m11Hi = q2.w3Hi
                                                    , m11Lo = q2.w3Lo
                                                    , m12Hi = q3.w0Hi
                                                    , m12Lo = q3.w0Lo
                                                    , m13Hi = q3.w1Hi
                                                    , m13Lo = q3.w1Lo
                                                    , m14Hi = q3.w2Hi
                                                    , m14Lo = q3.w2Lo
                                                    , m15Hi = q3.w3Hi
                                                    , m15Lo = q3.w3Lo
                                                    }
                                                )
                                    )
                        )
            )


{-| Encode the hash state (8 x 64-bit words as hi/lo pairs) into the first
digestLength bytes. Each word is encoded as lo then hi in little-endian order,
producing 64 bytes total, then the first digestLength bytes are extracted.
-}
encodeDigest : Int -> { h0Hi : Int, h0Lo : Int, h1Hi : Int, h1Lo : Int, h2Hi : Int, h2Lo : Int, h3Hi : Int, h3Lo : Int, h4Hi : Int, h4Lo : Int, h5Hi : Int, h5Lo : Int, h6Hi : Int, h6Lo : Int, h7Hi : Int, h7Lo : Int } -> Bytes
encodeDigest digestLength h =
    let
        full =
            Encode.encode
                (Encode.sequence
                    [ Encode.unsignedInt32 LE h.h0Lo
                    , Encode.unsignedInt32 LE h.h0Hi
                    , Encode.unsignedInt32 LE h.h1Lo
                    , Encode.unsignedInt32 LE h.h1Hi
                    , Encode.unsignedInt32 LE h.h2Lo
                    , Encode.unsignedInt32 LE h.h2Hi
                    , Encode.unsignedInt32 LE h.h3Lo
                    , Encode.unsignedInt32 LE h.h3Hi
                    , Encode.unsignedInt32 LE h.h4Lo
                    , Encode.unsignedInt32 LE h.h4Hi
                    , Encode.unsignedInt32 LE h.h5Lo
                    , Encode.unsignedInt32 LE h.h5Hi
                    , Encode.unsignedInt32 LE h.h6Lo
                    , Encode.unsignedInt32 LE h.h6Hi
                    , Encode.unsignedInt32 LE h.h7Lo
                    , Encode.unsignedInt32 LE h.h7Hi
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
