module Blake2b.DecodeV1 exposing
    ( HashState
    , MessageBlock
    , blockDecoder
    , encodeDigest
    )

import Bytes exposing (Bytes, Endianness(..))
import Bytes.Decode as Decode
import Bytes.Encode as Encode


type alias HashState =
    { h0Hi : Int
    , h0Lo : Int
    , h1Hi : Int
    , h1Lo : Int
    , h2Hi : Int
    , h2Lo : Int
    , h3Hi : Int
    , h3Lo : Int
    , h4Hi : Int
    , h4Lo : Int
    , h5Hi : Int
    , h5Lo : Int
    , h6Hi : Int
    , h6Lo : Int
    , h7Hi : Int
    , h7Lo : Int
    }


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


type alias U64 =
    { hi : Int, lo : Int }


decodeU64LE : Decode.Decoder U64
decodeU64LE =
    Decode.map2 (\lo hi -> { hi = hi, lo = lo })
        (Decode.unsignedInt32 LE)
        (Decode.unsignedInt32 LE)


decodeQuarter : Decode.Decoder QuarterBlock
decodeQuarter =
    Decode.map4
        (\w0 w1 w2 w3 ->
            { w0Hi = w0.hi
            , w0Lo = w0.lo
            , w1Hi = w1.hi
            , w1Lo = w1.lo
            , w2Hi = w2.hi
            , w2Lo = w2.lo
            , w3Hi = w3.hi
            , w3Lo = w3.lo
            }
        )
        decodeU64LE
        decodeU64LE
        decodeU64LE
        decodeU64LE


blockDecoder : Decode.Decoder MessageBlock
blockDecoder =
    Decode.map4
        (\q0 q1 q2 q3 ->
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
        decodeQuarter
        decodeQuarter
        decodeQuarter
        decodeQuarter


{-| Encode the hash state (8 x 64-bit words as hi/lo pairs) into the first
digestLength bytes. Each word is encoded as lo then hi in little-endian order,
producing 64 bytes total, then the first digestLength bytes are extracted.
-}
encodeDigest : Int -> HashState -> Bytes
encodeDigest digestLength h =
    let
        full : Bytes
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
