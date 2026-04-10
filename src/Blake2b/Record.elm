module Blake2b.Record exposing (hash, hash512, hash256, hash224)

{-| Pure Elm BLAKE2b implementation (RFC 7693) using record-based U64 type.
-}

import Bitwise
import Blake2b.Internal.Constants exposing (..)
import Blake2b.Internal.Decode exposing (MessageBlock, blockDecoder, encodeDigest, padBlock)
import Bytes exposing (Bytes, Endianness(..))
import Bytes.Decode as Decode
import Bytes.Encode as Encode



-- U64 TYPE


type alias U64 =
    { hi : Int, lo : Int }



-- PRIMITIVE OPERATIONS


add64 : U64 -> U64 -> U64
add64 a b =
    let
        lo =
            Bitwise.shiftRightZfBy 0 (a.lo + b.lo)

        carry =
            if lo < Bitwise.shiftRightZfBy 0 a.lo then
                1

            else
                0

        hi =
            Bitwise.shiftRightZfBy 0 (a.hi + b.hi + carry)
    in
    { hi = hi, lo = lo }


xor64 : U64 -> U64 -> U64
xor64 a b =
    { hi = Bitwise.xor a.hi b.hi, lo = Bitwise.xor a.lo b.lo }


rotr32 : U64 -> U64
rotr32 w =
    { hi = w.lo, lo = w.hi }


rotr24 : U64 -> U64
rotr24 w =
    { hi = Bitwise.or (Bitwise.shiftRightZfBy 24 w.hi) (Bitwise.shiftLeftBy 8 w.lo)
    , lo = Bitwise.or (Bitwise.shiftRightZfBy 24 w.lo) (Bitwise.shiftLeftBy 8 w.hi)
    }


rotr16 : U64 -> U64
rotr16 w =
    { hi = Bitwise.or (Bitwise.shiftRightZfBy 16 w.hi) (Bitwise.shiftLeftBy 16 w.lo)
    , lo = Bitwise.or (Bitwise.shiftRightZfBy 16 w.lo) (Bitwise.shiftLeftBy 16 w.hi)
    }


rotr63 : U64 -> U64
rotr63 w =
    { hi = Bitwise.or (Bitwise.shiftLeftBy 1 w.hi) (Bitwise.shiftRightZfBy 31 w.lo)
    , lo = Bitwise.or (Bitwise.shiftLeftBy 1 w.lo) (Bitwise.shiftRightZfBy 31 w.hi)
    }



-- G MIXING FUNCTION


g : U64 -> U64 -> U64 -> U64 -> U64 -> U64 -> { a : U64, b : U64, c : U64, d : U64 }
g a b c d x y =
    let
        a1 =
            add64 (add64 a b) x

        d1 =
            rotr32 (xor64 d a1)

        c1 =
            add64 c d1

        b1 =
            rotr24 (xor64 b c1)

        a2 =
            add64 (add64 a1 b1) y

        d2 =
            rotr16 (xor64 d1 a2)

        c2 =
            add64 c1 d2

        b2 =
            rotr63 (xor64 b1 c2)
    in
    { a = a2, b = b2, c = c2, d = d2 }



-- STATE TYPES


type alias WorkingVector =
    { v0 : U64
    , v1 : U64
    , v2 : U64
    , v3 : U64
    , v4 : U64
    , v5 : U64
    , v6 : U64
    , v7 : U64
    , v8 : U64
    , v9 : U64
    , v10 : U64
    , v11 : U64
    , v12 : U64
    , v13 : U64
    , v14 : U64
    , v15 : U64
    }


type alias HashState =
    { h0 : U64
    , h1 : U64
    , h2 : U64
    , h3 : U64
    , h4 : U64
    , h5 : U64
    , h6 : U64
    , h7 : U64
    }



-- ROUND FUNCTION


round : U64 -> U64 -> U64 -> U64 -> U64 -> U64 -> U64 -> U64 -> U64 -> U64 -> U64 -> U64 -> U64 -> U64 -> U64 -> U64 -> WorkingVector -> WorkingVector
round s0 s1 s2 s3 s4 s5 s6 s7 s8 s9 s10 s11 s12 s13 s14 s15 v =
    let
        -- Column step
        g0 =
            g v.v0 v.v4 v.v8 v.v12 s0 s1

        g1 =
            g v.v1 v.v5 v.v9 v.v13 s2 s3

        g2 =
            g v.v2 v.v6 v.v10 v.v14 s4 s5

        g3 =
            g v.v3 v.v7 v.v11 v.v15 s6 s7

        -- Diagonal step
        g4 =
            g g0.a g1.b g2.c g3.d s8 s9

        g5 =
            g g1.a g2.b g3.c g0.d s10 s11

        g6 =
            g g2.a g3.b g0.c g1.d s12 s13

        g7 =
            g g3.a g0.b g1.c g2.d s14 s15
    in
    { v0 = g4.a
    , v1 = g5.a
    , v2 = g6.a
    , v3 = g7.a
    , v4 = g7.b
    , v5 = g4.b
    , v6 = g5.b
    , v7 = g6.b
    , v8 = g6.c
    , v9 = g7.c
    , v10 = g4.c
    , v11 = g5.c
    , v12 = g5.d
    , v13 = g6.d
    , v14 = g7.d
    , v15 = g4.d
    }



-- COMPRESS FUNCTION


compress : HashState -> Int -> Int -> Int -> Int -> Bool -> MessageBlock -> HashState
compress h t0Hi t0Lo t1Hi t1Lo isLastBlock mb =
    let
        -- Pre-construct 16 U64 message words
        m0 =
            { hi = mb.m0Hi, lo = mb.m0Lo }

        m1 =
            { hi = mb.m1Hi, lo = mb.m1Lo }

        m2 =
            { hi = mb.m2Hi, lo = mb.m2Lo }

        m3 =
            { hi = mb.m3Hi, lo = mb.m3Lo }

        m4 =
            { hi = mb.m4Hi, lo = mb.m4Lo }

        m5 =
            { hi = mb.m5Hi, lo = mb.m5Lo }

        m6 =
            { hi = mb.m6Hi, lo = mb.m6Lo }

        m7 =
            { hi = mb.m7Hi, lo = mb.m7Lo }

        m8 =
            { hi = mb.m8Hi, lo = mb.m8Lo }

        m9 =
            { hi = mb.m9Hi, lo = mb.m9Lo }

        m10 =
            { hi = mb.m10Hi, lo = mb.m10Lo }

        m11 =
            { hi = mb.m11Hi, lo = mb.m11Lo }

        m12 =
            { hi = mb.m12Hi, lo = mb.m12Lo }

        m13 =
            { hi = mb.m13Hi, lo = mb.m13Lo }

        m14 =
            { hi = mb.m14Hi, lo = mb.m14Lo }

        m15 =
            { hi = mb.m15Hi, lo = mb.m15Lo }

        -- Initialize working vector
        iv4 =
            { hi = iv4Hi, lo = iv4Lo }

        iv5 =
            { hi = iv5Hi, lo = iv5Lo }

        iv6 =
            { hi = iv6Hi, lo = iv6Lo }

        iv7 =
            { hi = iv7Hi, lo = iv7Lo }

        initV =
            { v0 = h.h0
            , v1 = h.h1
            , v2 = h.h2
            , v3 = h.h3
            , v4 = h.h4
            , v5 = h.h5
            , v6 = h.h6
            , v7 = h.h7
            , v8 = { hi = iv0Hi, lo = iv0Lo }
            , v9 = { hi = iv1Hi, lo = iv1Lo }
            , v10 = { hi = iv2Hi, lo = iv2Lo }
            , v11 = { hi = iv3Hi, lo = iv3Lo }
            , v12 = xor64 iv4 { hi = t0Hi, lo = t0Lo }
            , v13 = xor64 iv5 { hi = t1Hi, lo = t1Lo }
            , v14 =
                if isLastBlock then
                    { hi = Bitwise.xor iv6.hi 0xFFFFFFFF, lo = Bitwise.xor iv6.lo 0xFFFFFFFF }

                else
                    iv6
            , v15 = iv7
            }

        -- 12 rounds with inlined sigma permutations
        -- Round 0: 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15
        vR0 =
            round m0 m1 m2 m3 m4 m5 m6 m7 m8 m9 m10 m11 m12 m13 m14 m15 initV

        -- Round 1: 14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3
        vR1 =
            round m14 m10 m4 m8 m9 m15 m13 m6 m1 m12 m0 m2 m11 m7 m5 m3 vR0

        -- Round 2: 11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4
        vR2 =
            round m11 m8 m12 m0 m5 m2 m15 m13 m10 m14 m3 m6 m7 m1 m9 m4 vR1

        -- Round 3: 7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8
        vR3 =
            round m7 m9 m3 m1 m13 m12 m11 m14 m2 m6 m5 m10 m4 m0 m15 m8 vR2

        -- Round 4: 9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13
        vR4 =
            round m9 m0 m5 m7 m2 m4 m10 m15 m14 m1 m11 m12 m6 m8 m3 m13 vR3

        -- Round 5: 2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9
        vR5 =
            round m2 m12 m6 m10 m0 m11 m8 m3 m4 m13 m7 m5 m15 m14 m1 m9 vR4

        -- Round 6: 12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11
        vR6 =
            round m12 m5 m1 m15 m14 m13 m4 m10 m0 m7 m6 m3 m9 m2 m8 m11 vR5

        -- Round 7: 13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10
        vR7 =
            round m13 m11 m7 m14 m12 m1 m3 m9 m5 m0 m15 m4 m8 m6 m2 m10 vR6

        -- Round 8: 6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5
        vR8 =
            round m6 m15 m14 m9 m11 m3 m0 m8 m12 m2 m13 m7 m1 m4 m10 m5 vR7

        -- Round 9: 10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0
        vR9 =
            round m10 m2 m8 m4 m7 m6 m1 m5 m15 m11 m9 m14 m3 m12 m13 m0 vR8

        -- Round 10: same as round 0
        vR10 =
            round m0 m1 m2 m3 m4 m5 m6 m7 m8 m9 m10 m11 m12 m13 m14 m15 vR9

        -- Round 11: same as round 1
        vR11 =
            round m14 m10 m4 m8 m9 m15 m13 m6 m1 m12 m0 m2 m11 m7 m5 m3 vR10
    in
    -- Finalize: h'[i] = h[i] XOR v[i] XOR v[i+8]
    { h0 = xor64 (xor64 h.h0 vR11.v0) vR11.v8
    , h1 = xor64 (xor64 h.h1 vR11.v1) vR11.v9
    , h2 = xor64 (xor64 h.h2 vR11.v2) vR11.v10
    , h3 = xor64 (xor64 h.h3 vR11.v3) vR11.v11
    , h4 = xor64 (xor64 h.h4 vR11.v4) vR11.v12
    , h5 = xor64 (xor64 h.h5 vR11.v5) vR11.v13
    , h6 = xor64 (xor64 h.h6 vR11.v6) vR11.v14
    , h7 = xor64 (xor64 h.h7 vR11.v7) vR11.v15
    }



-- BLOCK PROCESSING LOOP


type alias LoopAcc =
    { h : HashState
    , t0Lo : Int
    , t0Hi : Int
    , remaining : Int
    }


blockLoop : LoopAcc -> Decode.Decoder (Decode.Step LoopAcc HashState)
blockLoop acc =
    if acc.remaining > 128 then
        -- Full block, not the last
        Decode.map
            (\mb ->
                let
                    newT0Lo =
                        Bitwise.shiftRightZfBy 0 (acc.t0Lo + 128)

                    newT0Hi =
                        if newT0Lo < Bitwise.shiftRightZfBy 0 acc.t0Lo then
                            acc.t0Hi + 1

                        else
                            acc.t0Hi

                    newH =
                        compress acc.h newT0Hi newT0Lo 0 0 False mb
                in
                Decode.Loop
                    { h = newH
                    , t0Lo = newT0Lo
                    , t0Hi = newT0Hi
                    , remaining = acc.remaining - 128
                    }
            )
            blockDecoder

    else if acc.remaining == 128 then
        -- Last block, exactly full
        Decode.map
            (\mb ->
                let
                    newT0Lo =
                        Bitwise.shiftRightZfBy 0 (acc.t0Lo + 128)

                    newT0Hi =
                        if newT0Lo < Bitwise.shiftRightZfBy 0 acc.t0Lo then
                            acc.t0Hi + 1

                        else
                            acc.t0Hi
                in
                Decode.Done (compress acc.h newT0Hi newT0Lo 0 0 True mb)
            )
            blockDecoder

    else
        -- Last block, partial (1 to 127 bytes)
        Decode.map
            (\partialBytes ->
                let
                    lastSize =
                        acc.remaining

                    newT0Lo =
                        Bitwise.shiftRightZfBy 0 (acc.t0Lo + lastSize)

                    newT0Hi =
                        if newT0Lo < Bitwise.shiftRightZfBy 0 acc.t0Lo then
                            acc.t0Hi + 1

                        else
                            acc.t0Hi

                    padded =
                        padBlock partialBytes
                in
                case Decode.decode blockDecoder padded of
                    Just mb ->
                        Decode.Done (compress acc.h newT0Hi newT0Lo 0 0 True mb)

                    Nothing ->
                        Decode.Done acc.h
            )
            (Decode.bytes acc.remaining)



-- HASH FUNCTIONS


emptyBytes : Bytes
emptyBytes =
    Encode.encode (Encode.sequence [])


{-| Compute a BLAKE2b hash with the given digest length, key, and data.

    - digestLength: 1 to 64 (number of output bytes)
    - key: 0 to 64 bytes (use empty Bytes for unkeyed hashing)
    - data: the message to hash

-}
hash : { digestLength : Int, key : Bytes, data : Bytes } -> Bytes
hash config =
    let
        keyLen =
            Bytes.width config.key

        dataLen =
            Bytes.width config.data

        -- Build full input data (key block prepended if keyed)
        fullData =
            if keyLen > 0 then
                Encode.encode
                    (Encode.sequence
                        [ Encode.bytes config.key
                        , Encode.sequence (List.repeat (128 - keyLen) (Encode.unsignedInt8 0))
                        , Encode.bytes config.data
                        ]
                    )

            else
                config.data

        totalLen =
            if keyLen > 0 then
                128 + dataLen

            else
                dataLen

        -- Initialize hash state
        paramWord =
            Bitwise.or (Bitwise.or 0x01010000 (Bitwise.shiftLeftBy 8 keyLen)) config.digestLength

        initState =
            { h0 = { hi = iv0Hi, lo = Bitwise.xor iv0Lo paramWord }
            , h1 = { hi = iv1Hi, lo = iv1Lo }
            , h2 = { hi = iv2Hi, lo = iv2Lo }
            , h3 = { hi = iv3Hi, lo = iv3Lo }
            , h4 = { hi = iv4Hi, lo = iv4Lo }
            , h5 = { hi = iv5Hi, lo = iv5Lo }
            , h6 = { hi = iv6Hi, lo = iv6Lo }
            , h7 = { hi = iv7Hi, lo = iv7Lo }
            }

        finalState =
            if totalLen == 0 then
                -- Empty unkeyed: compress one zero block with counter=0, final
                let
                    zeroBytes =
                        Encode.encode (Encode.sequence (List.repeat 128 (Encode.unsignedInt8 0)))
                in
                case Decode.decode blockDecoder zeroBytes of
                    Just mb ->
                        compress initState 0 0 0 0 True mb

                    Nothing ->
                        initState

            else
                case Decode.decode (Decode.loop { h = initState, t0Lo = 0, t0Hi = 0, remaining = totalLen } blockLoop) fullData of
                    Just hs ->
                        hs

                    Nothing ->
                        initState
    in
    encodeDigest config.digestLength
        finalState.h0.hi
        finalState.h0.lo
        finalState.h1.hi
        finalState.h1.lo
        finalState.h2.hi
        finalState.h2.lo
        finalState.h3.hi
        finalState.h3.lo
        finalState.h4.hi
        finalState.h4.lo
        finalState.h5.hi
        finalState.h5.lo
        finalState.h6.hi
        finalState.h6.lo
        finalState.h7.hi
        finalState.h7.lo


{-| Compute a 512-bit (64-byte) BLAKE2b hash of the given data.
-}
hash512 : Bytes -> Bytes
hash512 data =
    hash { digestLength = 64, key = emptyBytes, data = data }


{-| Compute a 256-bit (32-byte) BLAKE2b hash of the given data.
-}
hash256 : Bytes -> Bytes
hash256 data =
    hash { digestLength = 32, key = emptyBytes, data = data }


{-| Compute a 224-bit (28-byte) BLAKE2b hash of the given data.
-}
hash224 : Bytes -> Bytes
hash224 data =
    hash { digestLength = 28, key = emptyBytes, data = data }
