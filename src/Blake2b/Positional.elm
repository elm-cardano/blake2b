module Blake2b.Positional exposing (hash, hash512, hash256, hash224)

{-| Pure Elm BLAKE2b implementation (RFC 7693) using raw Int pairs as
positional function arguments. No U64 wrapper type — all 64-bit values
are passed as separate hi/lo Int arguments for maximum performance.
-}

import Bitwise
import Blake2b.Internal.Constants exposing (..)
import Blake2b.Internal.Decode exposing (MessageBlock, blockDecoder, encodeDigest, padBlock)
import Bytes exposing (Bytes, Endianness(..))
import Bytes.Decode as Decode
import Bytes.Encode as Encode



-- G MIXING FUNCTION


type G8
    = G8 Int Int Int Int Int Int Int Int


g : Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> G8
g aHi aLo bHi bLo cHi cLo dHi dLo xHi xLo yHi yLo =
    let
        -- Step 1: a1 = a + b + x (two add64 operations inlined)
        abLo =
            Bitwise.shiftRightZfBy 0 (aLo + bLo)

        abCarry =
            if abLo < Bitwise.shiftRightZfBy 0 aLo then
                1

            else
                0

        abHi =
            Bitwise.shiftRightZfBy 0 (aHi + bHi + abCarry)

        a1Lo =
            Bitwise.shiftRightZfBy 0 (abLo + xLo)

        a1Carry =
            if a1Lo < Bitwise.shiftRightZfBy 0 abLo then
                1

            else
                0

        a1Hi =
            Bitwise.shiftRightZfBy 0 (abHi + xHi + a1Carry)

        -- Step 2: d1 = rotr32(d XOR a1) — XOR then swap hi/lo
        d1Hi =
            Bitwise.xor dLo a1Lo

        d1Lo =
            Bitwise.xor dHi a1Hi

        -- Step 3: c1 = c + d1
        cd1Lo =
            Bitwise.shiftRightZfBy 0 (cLo + d1Lo)

        cd1Carry =
            if cd1Lo < Bitwise.shiftRightZfBy 0 cLo then
                1

            else
                0

        c1Hi =
            Bitwise.shiftRightZfBy 0 (cHi + d1Hi + cd1Carry)

        c1Lo =
            cd1Lo

        -- Step 4: b1 = rotr24(b XOR c1)
        bxc1Hi =
            Bitwise.xor bHi c1Hi

        bxc1Lo =
            Bitwise.xor bLo c1Lo

        b1Hi =
            Bitwise.or (Bitwise.shiftRightZfBy 24 bxc1Hi) (Bitwise.shiftLeftBy 8 bxc1Lo)

        b1Lo =
            Bitwise.or (Bitwise.shiftRightZfBy 24 bxc1Lo) (Bitwise.shiftLeftBy 8 bxc1Hi)

        -- Step 5: a2 = a1 + b1 + y
        ab1Lo =
            Bitwise.shiftRightZfBy 0 (a1Lo + b1Lo)

        ab1Carry =
            if ab1Lo < Bitwise.shiftRightZfBy 0 a1Lo then
                1

            else
                0

        ab1Hi =
            Bitwise.shiftRightZfBy 0 (a1Hi + b1Hi + ab1Carry)

        a2Lo =
            Bitwise.shiftRightZfBy 0 (ab1Lo + yLo)

        a2Carry =
            if a2Lo < Bitwise.shiftRightZfBy 0 ab1Lo then
                1

            else
                0

        a2Hi =
            Bitwise.shiftRightZfBy 0 (ab1Hi + yHi + a2Carry)

        -- Step 6: d2 = rotr16(d1 XOR a2)
        dxa2Hi =
            Bitwise.xor d1Hi a2Hi

        dxa2Lo =
            Bitwise.xor d1Lo a2Lo

        d2Hi =
            Bitwise.or (Bitwise.shiftRightZfBy 16 dxa2Hi) (Bitwise.shiftLeftBy 16 dxa2Lo)

        d2Lo =
            Bitwise.or (Bitwise.shiftRightZfBy 16 dxa2Lo) (Bitwise.shiftLeftBy 16 dxa2Hi)

        -- Step 7: c2 = c1 + d2
        cd2Lo =
            Bitwise.shiftRightZfBy 0 (c1Lo + d2Lo)

        cd2Carry =
            if cd2Lo < Bitwise.shiftRightZfBy 0 c1Lo then
                1

            else
                0

        c2Hi =
            Bitwise.shiftRightZfBy 0 (c1Hi + d2Hi + cd2Carry)

        c2Lo =
            cd2Lo

        -- Step 8: b2 = rotr63(b1 XOR c2) = rotl1(b1 XOR c2)
        bxc2Hi =
            Bitwise.xor b1Hi c2Hi

        bxc2Lo =
            Bitwise.xor b1Lo c2Lo

        b2Hi =
            Bitwise.or (Bitwise.shiftLeftBy 1 bxc2Hi) (Bitwise.shiftRightZfBy 31 bxc2Lo)

        b2Lo =
            Bitwise.or (Bitwise.shiftLeftBy 1 bxc2Lo) (Bitwise.shiftRightZfBy 31 bxc2Hi)
    in
    G8 a2Hi a2Lo b2Hi b2Lo c2Hi c2Lo d2Hi d2Lo



-- STATE TYPES


type alias WorkingVector =
    { v0Hi : Int
    , v0Lo : Int
    , v1Hi : Int
    , v1Lo : Int
    , v2Hi : Int
    , v2Lo : Int
    , v3Hi : Int
    , v3Lo : Int
    , v4Hi : Int
    , v4Lo : Int
    , v5Hi : Int
    , v5Lo : Int
    , v6Hi : Int
    , v6Lo : Int
    , v7Hi : Int
    , v7Lo : Int
    , v8Hi : Int
    , v8Lo : Int
    , v9Hi : Int
    , v9Lo : Int
    , v10Hi : Int
    , v10Lo : Int
    , v11Hi : Int
    , v11Lo : Int
    , v12Hi : Int
    , v12Lo : Int
    , v13Hi : Int
    , v13Lo : Int
    , v14Hi : Int
    , v14Lo : Int
    , v15Hi : Int
    , v15Lo : Int
    }


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



-- ROUND FUNCTION


round : Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> WorkingVector -> WorkingVector
round s0Hi s0Lo s1Hi s1Lo s2Hi s2Lo s3Hi s3Lo s4Hi s4Lo s5Hi s5Lo s6Hi s6Lo s7Hi s7Lo s8Hi s8Lo s9Hi s9Lo s10Hi s10Lo s11Hi s11Lo s12Hi s12Lo s13Hi s13Lo s14Hi s14Lo s15Hi s15Lo v =
    let
        -- Column step
        (G8 g0aHi g0aLo g0bHi g0bLo g0cHi g0cLo g0dHi g0dLo) =
            g v.v0Hi v.v0Lo v.v4Hi v.v4Lo v.v8Hi v.v8Lo v.v12Hi v.v12Lo s0Hi s0Lo s1Hi s1Lo

        (G8 g1aHi g1aLo g1bHi g1bLo g1cHi g1cLo g1dHi g1dLo) =
            g v.v1Hi v.v1Lo v.v5Hi v.v5Lo v.v9Hi v.v9Lo v.v13Hi v.v13Lo s2Hi s2Lo s3Hi s3Lo

        (G8 g2aHi g2aLo g2bHi g2bLo g2cHi g2cLo g2dHi g2dLo) =
            g v.v2Hi v.v2Lo v.v6Hi v.v6Lo v.v10Hi v.v10Lo v.v14Hi v.v14Lo s4Hi s4Lo s5Hi s5Lo

        (G8 g3aHi g3aLo g3bHi g3bLo g3cHi g3cLo g3dHi g3dLo) =
            g v.v3Hi v.v3Lo v.v7Hi v.v7Lo v.v11Hi v.v11Lo v.v15Hi v.v15Lo s6Hi s6Lo s7Hi s7Lo

        -- Diagonal step
        (G8 g4aHi g4aLo g4bHi g4bLo g4cHi g4cLo g4dHi g4dLo) =
            g g0aHi g0aLo g1bHi g1bLo g2cHi g2cLo g3dHi g3dLo s8Hi s8Lo s9Hi s9Lo

        (G8 g5aHi g5aLo g5bHi g5bLo g5cHi g5cLo g5dHi g5dLo) =
            g g1aHi g1aLo g2bHi g2bLo g3cHi g3cLo g0dHi g0dLo s10Hi s10Lo s11Hi s11Lo

        (G8 g6aHi g6aLo g6bHi g6bLo g6cHi g6cLo g6dHi g6dLo) =
            g g2aHi g2aLo g3bHi g3bLo g0cHi g0cLo g1dHi g1dLo s12Hi s12Lo s13Hi s13Lo

        (G8 g7aHi g7aLo g7bHi g7bLo g7cHi g7cLo g7dHi g7dLo) =
            g g3aHi g3aLo g0bHi g0bLo g1cHi g1cLo g2dHi g2dLo s14Hi s14Lo s15Hi s15Lo
    in
    { v0Hi = g4aHi
    , v0Lo = g4aLo
    , v1Hi = g5aHi
    , v1Lo = g5aLo
    , v2Hi = g6aHi
    , v2Lo = g6aLo
    , v3Hi = g7aHi
    , v3Lo = g7aLo
    , v4Hi = g7bHi
    , v4Lo = g7bLo
    , v5Hi = g4bHi
    , v5Lo = g4bLo
    , v6Hi = g5bHi
    , v6Lo = g5bLo
    , v7Hi = g6bHi
    , v7Lo = g6bLo
    , v8Hi = g6cHi
    , v8Lo = g6cLo
    , v9Hi = g7cHi
    , v9Lo = g7cLo
    , v10Hi = g4cHi
    , v10Lo = g4cLo
    , v11Hi = g5cHi
    , v11Lo = g5cLo
    , v12Hi = g5dHi
    , v12Lo = g5dLo
    , v13Hi = g6dHi
    , v13Lo = g6dLo
    , v14Hi = g7dHi
    , v14Lo = g7dLo
    , v15Hi = g4dHi
    , v15Lo = g4dLo
    }



-- COMPRESS FUNCTION


compress : HashState -> Int -> Int -> Int -> Int -> Bool -> MessageBlock -> HashState
compress h t0Hi t0Lo t1Hi t1Lo isLastBlock mb =
    let
        -- Initialize working vector v12 and v13 with XOR of IV and counter
        v12Hi =
            Bitwise.xor iv4Hi t0Hi

        v12Lo =
            Bitwise.xor iv4Lo t0Lo

        v13Hi =
            Bitwise.xor iv5Hi t1Hi

        v13Lo =
            Bitwise.xor iv5Lo t1Lo

        v14Hi =
            if isLastBlock then
                Bitwise.xor iv6Hi 0xFFFFFFFF

            else
                iv6Hi

        v14Lo =
            if isLastBlock then
                Bitwise.xor iv6Lo 0xFFFFFFFF

            else
                iv6Lo

        initV =
            { v0Hi = h.h0Hi
            , v0Lo = h.h0Lo
            , v1Hi = h.h1Hi
            , v1Lo = h.h1Lo
            , v2Hi = h.h2Hi
            , v2Lo = h.h2Lo
            , v3Hi = h.h3Hi
            , v3Lo = h.h3Lo
            , v4Hi = h.h4Hi
            , v4Lo = h.h4Lo
            , v5Hi = h.h5Hi
            , v5Lo = h.h5Lo
            , v6Hi = h.h6Hi
            , v6Lo = h.h6Lo
            , v7Hi = h.h7Hi
            , v7Lo = h.h7Lo
            , v8Hi = iv0Hi
            , v8Lo = iv0Lo
            , v9Hi = iv1Hi
            , v9Lo = iv1Lo
            , v10Hi = iv2Hi
            , v10Lo = iv2Lo
            , v11Hi = iv3Hi
            , v11Lo = iv3Lo
            , v12Hi = v12Hi
            , v12Lo = v12Lo
            , v13Hi = v13Hi
            , v13Lo = v13Lo
            , v14Hi = v14Hi
            , v14Lo = v14Lo
            , v15Hi = iv7Hi
            , v15Lo = iv7Lo
            }

        -- 12 rounds with inlined sigma permutations
        -- Round 0: 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15
        vR0 =
            round
                mb.m0Hi mb.m0Lo mb.m1Hi mb.m1Lo mb.m2Hi mb.m2Lo mb.m3Hi mb.m3Lo
                mb.m4Hi mb.m4Lo mb.m5Hi mb.m5Lo mb.m6Hi mb.m6Lo mb.m7Hi mb.m7Lo
                mb.m8Hi mb.m8Lo mb.m9Hi mb.m9Lo mb.m10Hi mb.m10Lo mb.m11Hi mb.m11Lo
                mb.m12Hi mb.m12Lo mb.m13Hi mb.m13Lo mb.m14Hi mb.m14Lo mb.m15Hi mb.m15Lo
                initV

        -- Round 1: 14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3
        vR1 =
            round
                mb.m14Hi mb.m14Lo mb.m10Hi mb.m10Lo mb.m4Hi mb.m4Lo mb.m8Hi mb.m8Lo
                mb.m9Hi mb.m9Lo mb.m15Hi mb.m15Lo mb.m13Hi mb.m13Lo mb.m6Hi mb.m6Lo
                mb.m1Hi mb.m1Lo mb.m12Hi mb.m12Lo mb.m0Hi mb.m0Lo mb.m2Hi mb.m2Lo
                mb.m11Hi mb.m11Lo mb.m7Hi mb.m7Lo mb.m5Hi mb.m5Lo mb.m3Hi mb.m3Lo
                vR0

        -- Round 2: 11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4
        vR2 =
            round
                mb.m11Hi mb.m11Lo mb.m8Hi mb.m8Lo mb.m12Hi mb.m12Lo mb.m0Hi mb.m0Lo
                mb.m5Hi mb.m5Lo mb.m2Hi mb.m2Lo mb.m15Hi mb.m15Lo mb.m13Hi mb.m13Lo
                mb.m10Hi mb.m10Lo mb.m14Hi mb.m14Lo mb.m3Hi mb.m3Lo mb.m6Hi mb.m6Lo
                mb.m7Hi mb.m7Lo mb.m1Hi mb.m1Lo mb.m9Hi mb.m9Lo mb.m4Hi mb.m4Lo
                vR1

        -- Round 3: 7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8
        vR3 =
            round
                mb.m7Hi mb.m7Lo mb.m9Hi mb.m9Lo mb.m3Hi mb.m3Lo mb.m1Hi mb.m1Lo
                mb.m13Hi mb.m13Lo mb.m12Hi mb.m12Lo mb.m11Hi mb.m11Lo mb.m14Hi mb.m14Lo
                mb.m2Hi mb.m2Lo mb.m6Hi mb.m6Lo mb.m5Hi mb.m5Lo mb.m10Hi mb.m10Lo
                mb.m4Hi mb.m4Lo mb.m0Hi mb.m0Lo mb.m15Hi mb.m15Lo mb.m8Hi mb.m8Lo
                vR2

        -- Round 4: 9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13
        vR4 =
            round
                mb.m9Hi mb.m9Lo mb.m0Hi mb.m0Lo mb.m5Hi mb.m5Lo mb.m7Hi mb.m7Lo
                mb.m2Hi mb.m2Lo mb.m4Hi mb.m4Lo mb.m10Hi mb.m10Lo mb.m15Hi mb.m15Lo
                mb.m14Hi mb.m14Lo mb.m1Hi mb.m1Lo mb.m11Hi mb.m11Lo mb.m12Hi mb.m12Lo
                mb.m6Hi mb.m6Lo mb.m8Hi mb.m8Lo mb.m3Hi mb.m3Lo mb.m13Hi mb.m13Lo
                vR3

        -- Round 5: 2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9
        vR5 =
            round
                mb.m2Hi mb.m2Lo mb.m12Hi mb.m12Lo mb.m6Hi mb.m6Lo mb.m10Hi mb.m10Lo
                mb.m0Hi mb.m0Lo mb.m11Hi mb.m11Lo mb.m8Hi mb.m8Lo mb.m3Hi mb.m3Lo
                mb.m4Hi mb.m4Lo mb.m13Hi mb.m13Lo mb.m7Hi mb.m7Lo mb.m5Hi mb.m5Lo
                mb.m15Hi mb.m15Lo mb.m14Hi mb.m14Lo mb.m1Hi mb.m1Lo mb.m9Hi mb.m9Lo
                vR4

        -- Round 6: 12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11
        vR6 =
            round
                mb.m12Hi mb.m12Lo mb.m5Hi mb.m5Lo mb.m1Hi mb.m1Lo mb.m15Hi mb.m15Lo
                mb.m14Hi mb.m14Lo mb.m13Hi mb.m13Lo mb.m4Hi mb.m4Lo mb.m10Hi mb.m10Lo
                mb.m0Hi mb.m0Lo mb.m7Hi mb.m7Lo mb.m6Hi mb.m6Lo mb.m3Hi mb.m3Lo
                mb.m9Hi mb.m9Lo mb.m2Hi mb.m2Lo mb.m8Hi mb.m8Lo mb.m11Hi mb.m11Lo
                vR5

        -- Round 7: 13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10
        vR7 =
            round
                mb.m13Hi mb.m13Lo mb.m11Hi mb.m11Lo mb.m7Hi mb.m7Lo mb.m14Hi mb.m14Lo
                mb.m12Hi mb.m12Lo mb.m1Hi mb.m1Lo mb.m3Hi mb.m3Lo mb.m9Hi mb.m9Lo
                mb.m5Hi mb.m5Lo mb.m0Hi mb.m0Lo mb.m15Hi mb.m15Lo mb.m4Hi mb.m4Lo
                mb.m8Hi mb.m8Lo mb.m6Hi mb.m6Lo mb.m2Hi mb.m2Lo mb.m10Hi mb.m10Lo
                vR6

        -- Round 8: 6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5
        vR8 =
            round
                mb.m6Hi mb.m6Lo mb.m15Hi mb.m15Lo mb.m14Hi mb.m14Lo mb.m9Hi mb.m9Lo
                mb.m11Hi mb.m11Lo mb.m3Hi mb.m3Lo mb.m0Hi mb.m0Lo mb.m8Hi mb.m8Lo
                mb.m12Hi mb.m12Lo mb.m2Hi mb.m2Lo mb.m13Hi mb.m13Lo mb.m7Hi mb.m7Lo
                mb.m1Hi mb.m1Lo mb.m4Hi mb.m4Lo mb.m10Hi mb.m10Lo mb.m5Hi mb.m5Lo
                vR7

        -- Round 9: 10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0
        vR9 =
            round
                mb.m10Hi mb.m10Lo mb.m2Hi mb.m2Lo mb.m8Hi mb.m8Lo mb.m4Hi mb.m4Lo
                mb.m7Hi mb.m7Lo mb.m6Hi mb.m6Lo mb.m1Hi mb.m1Lo mb.m5Hi mb.m5Lo
                mb.m15Hi mb.m15Lo mb.m11Hi mb.m11Lo mb.m9Hi mb.m9Lo mb.m14Hi mb.m14Lo
                mb.m3Hi mb.m3Lo mb.m12Hi mb.m12Lo mb.m13Hi mb.m13Lo mb.m0Hi mb.m0Lo
                vR8

        -- Round 10: same as round 0
        vR10 =
            round
                mb.m0Hi mb.m0Lo mb.m1Hi mb.m1Lo mb.m2Hi mb.m2Lo mb.m3Hi mb.m3Lo
                mb.m4Hi mb.m4Lo mb.m5Hi mb.m5Lo mb.m6Hi mb.m6Lo mb.m7Hi mb.m7Lo
                mb.m8Hi mb.m8Lo mb.m9Hi mb.m9Lo mb.m10Hi mb.m10Lo mb.m11Hi mb.m11Lo
                mb.m12Hi mb.m12Lo mb.m13Hi mb.m13Lo mb.m14Hi mb.m14Lo mb.m15Hi mb.m15Lo
                vR9

        -- Round 11: same as round 1
        vR11 =
            round
                mb.m14Hi mb.m14Lo mb.m10Hi mb.m10Lo mb.m4Hi mb.m4Lo mb.m8Hi mb.m8Lo
                mb.m9Hi mb.m9Lo mb.m15Hi mb.m15Lo mb.m13Hi mb.m13Lo mb.m6Hi mb.m6Lo
                mb.m1Hi mb.m1Lo mb.m12Hi mb.m12Lo mb.m0Hi mb.m0Lo mb.m2Hi mb.m2Lo
                mb.m11Hi mb.m11Lo mb.m7Hi mb.m7Lo mb.m5Hi mb.m5Lo mb.m3Hi mb.m3Lo
                vR10
    in
    -- Finalize: h'[i] = h[i] XOR v[i] XOR v[i+8]
    { h0Hi = Bitwise.xor (Bitwise.xor h.h0Hi vR11.v0Hi) vR11.v8Hi
    , h0Lo = Bitwise.xor (Bitwise.xor h.h0Lo vR11.v0Lo) vR11.v8Lo
    , h1Hi = Bitwise.xor (Bitwise.xor h.h1Hi vR11.v1Hi) vR11.v9Hi
    , h1Lo = Bitwise.xor (Bitwise.xor h.h1Lo vR11.v1Lo) vR11.v9Lo
    , h2Hi = Bitwise.xor (Bitwise.xor h.h2Hi vR11.v2Hi) vR11.v10Hi
    , h2Lo = Bitwise.xor (Bitwise.xor h.h2Lo vR11.v2Lo) vR11.v10Lo
    , h3Hi = Bitwise.xor (Bitwise.xor h.h3Hi vR11.v3Hi) vR11.v11Hi
    , h3Lo = Bitwise.xor (Bitwise.xor h.h3Lo vR11.v3Lo) vR11.v11Lo
    , h4Hi = Bitwise.xor (Bitwise.xor h.h4Hi vR11.v4Hi) vR11.v12Hi
    , h4Lo = Bitwise.xor (Bitwise.xor h.h4Lo vR11.v4Lo) vR11.v12Lo
    , h5Hi = Bitwise.xor (Bitwise.xor h.h5Hi vR11.v5Hi) vR11.v13Hi
    , h5Lo = Bitwise.xor (Bitwise.xor h.h5Lo vR11.v5Lo) vR11.v13Lo
    , h6Hi = Bitwise.xor (Bitwise.xor h.h6Hi vR11.v6Hi) vR11.v14Hi
    , h6Lo = Bitwise.xor (Bitwise.xor h.h6Lo vR11.v6Lo) vR11.v14Lo
    , h7Hi = Bitwise.xor (Bitwise.xor h.h7Hi vR11.v7Hi) vR11.v15Hi
    , h7Lo = Bitwise.xor (Bitwise.xor h.h7Lo vR11.v7Lo) vR11.v15Lo
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
            { h0Hi = iv0Hi
            , h0Lo = Bitwise.xor iv0Lo paramWord
            , h1Hi = iv1Hi
            , h1Lo = iv1Lo
            , h2Hi = iv2Hi
            , h2Lo = iv2Lo
            , h3Hi = iv3Hi
            , h3Lo = iv3Lo
            , h4Hi = iv4Hi
            , h4Lo = iv4Lo
            , h5Hi = iv5Hi
            , h5Lo = iv5Lo
            , h6Hi = iv6Hi
            , h6Lo = iv6Lo
            , h7Hi = iv7Hi
            , h7Lo = iv7Lo
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
        finalState.h0Hi
        finalState.h0Lo
        finalState.h1Hi
        finalState.h1Lo
        finalState.h2Hi
        finalState.h2Lo
        finalState.h3Hi
        finalState.h3Lo
        finalState.h4Hi
        finalState.h4Lo
        finalState.h5Hi
        finalState.h5Lo
        finalState.h6Hi
        finalState.h6Lo
        finalState.h7Hi
        finalState.h7Lo


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
