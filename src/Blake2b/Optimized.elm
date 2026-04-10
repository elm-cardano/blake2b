module Blake2b.Optimized exposing (hash, hash512, hash256, hash224)

{-| Pure Elm BLAKE2b implementation (RFC 7693) optimized for V8 performance.

Compared to the Record variant, this version:

  - Hoists IV U64 constructions to module level (evaluated once at load time)
  - Uses 10 specialized 2-arg round functions instead of one 17-arg generic round
  - Constructs a U64MessageBlock once per compress call, shared across all 12 rounds

These changes keep all function arities within Elm's 9-argument fast path (F2..F9),
eliminating ~96 closure allocations per block from curried overflow arguments.

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


type alias U64MessageBlock =
    { m0 : U64
    , m1 : U64
    , m2 : U64
    , m3 : U64
    , m4 : U64
    , m5 : U64
    , m6 : U64
    , m7 : U64
    , m8 : U64
    , m9 : U64
    , m10 : U64
    , m11 : U64
    , m12 : U64
    , m13 : U64
    , m14 : U64
    , m15 : U64
    }



-- MODULE-LEVEL IV U64s (evaluated once at load time, not per compress call)


iv0U : U64
iv0U =
    { hi = iv0Hi, lo = iv0Lo }


iv1U : U64
iv1U =
    { hi = iv1Hi, lo = iv1Lo }


iv2U : U64
iv2U =
    { hi = iv2Hi, lo = iv2Lo }


iv3U : U64
iv3U =
    { hi = iv3Hi, lo = iv3Lo }


iv4U : U64
iv4U =
    { hi = iv4Hi, lo = iv4Lo }


iv5U : U64
iv5U =
    { hi = iv5Hi, lo = iv5Lo }


iv6U : U64
iv6U =
    { hi = iv6Hi, lo = iv6Lo }


iv7U : U64
iv7U =
    { hi = iv7Hi, lo = iv7Lo }



-- ROUND FUNCTIONS
-- 10 specialized functions (rounds 10/11 reuse round0/round1).
-- Each takes only 2 args (U64MessageBlock + WorkingVector), well within
-- Elm's 9-argument fast path. Sigma permutations are hardcoded per round.


{-| SIGMA[0] = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 }
-}
round0 : U64MessageBlock -> WorkingVector -> WorkingVector
round0 mb v =
    let
        g0 =
            g v.v0 v.v4 v.v8 v.v12 mb.m0 mb.m1

        g1 =
            g v.v1 v.v5 v.v9 v.v13 mb.m2 mb.m3

        g2 =
            g v.v2 v.v6 v.v10 v.v14 mb.m4 mb.m5

        g3 =
            g v.v3 v.v7 v.v11 v.v15 mb.m6 mb.m7

        g4 =
            g g0.a g1.b g2.c g3.d mb.m8 mb.m9

        g5 =
            g g1.a g2.b g3.c g0.d mb.m10 mb.m11

        g6 =
            g g2.a g3.b g0.c g1.d mb.m12 mb.m13

        g7 =
            g g3.a g0.b g1.c g2.d mb.m14 mb.m15
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


{-| SIGMA[1] = { 14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3 }
-}
round1 : U64MessageBlock -> WorkingVector -> WorkingVector
round1 mb v =
    let
        g0 =
            g v.v0 v.v4 v.v8 v.v12 mb.m14 mb.m10

        g1 =
            g v.v1 v.v5 v.v9 v.v13 mb.m4 mb.m8

        g2 =
            g v.v2 v.v6 v.v10 v.v14 mb.m9 mb.m15

        g3 =
            g v.v3 v.v7 v.v11 v.v15 mb.m13 mb.m6

        g4 =
            g g0.a g1.b g2.c g3.d mb.m1 mb.m12

        g5 =
            g g1.a g2.b g3.c g0.d mb.m0 mb.m2

        g6 =
            g g2.a g3.b g0.c g1.d mb.m11 mb.m7

        g7 =
            g g3.a g0.b g1.c g2.d mb.m5 mb.m3
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


{-| SIGMA[2] = { 11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4 }
-}
round2 : U64MessageBlock -> WorkingVector -> WorkingVector
round2 mb v =
    let
        g0 =
            g v.v0 v.v4 v.v8 v.v12 mb.m11 mb.m8

        g1 =
            g v.v1 v.v5 v.v9 v.v13 mb.m12 mb.m0

        g2 =
            g v.v2 v.v6 v.v10 v.v14 mb.m5 mb.m2

        g3 =
            g v.v3 v.v7 v.v11 v.v15 mb.m15 mb.m13

        g4 =
            g g0.a g1.b g2.c g3.d mb.m10 mb.m14

        g5 =
            g g1.a g2.b g3.c g0.d mb.m3 mb.m6

        g6 =
            g g2.a g3.b g0.c g1.d mb.m7 mb.m1

        g7 =
            g g3.a g0.b g1.c g2.d mb.m9 mb.m4
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


{-| SIGMA[3] = { 7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8 }
-}
round3 : U64MessageBlock -> WorkingVector -> WorkingVector
round3 mb v =
    let
        g0 =
            g v.v0 v.v4 v.v8 v.v12 mb.m7 mb.m9

        g1 =
            g v.v1 v.v5 v.v9 v.v13 mb.m3 mb.m1

        g2 =
            g v.v2 v.v6 v.v10 v.v14 mb.m13 mb.m12

        g3 =
            g v.v3 v.v7 v.v11 v.v15 mb.m11 mb.m14

        g4 =
            g g0.a g1.b g2.c g3.d mb.m2 mb.m6

        g5 =
            g g1.a g2.b g3.c g0.d mb.m5 mb.m10

        g6 =
            g g2.a g3.b g0.c g1.d mb.m4 mb.m0

        g7 =
            g g3.a g0.b g1.c g2.d mb.m15 mb.m8
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


{-| SIGMA[4] = { 9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13 }
-}
round4 : U64MessageBlock -> WorkingVector -> WorkingVector
round4 mb v =
    let
        g0 =
            g v.v0 v.v4 v.v8 v.v12 mb.m9 mb.m0

        g1 =
            g v.v1 v.v5 v.v9 v.v13 mb.m5 mb.m7

        g2 =
            g v.v2 v.v6 v.v10 v.v14 mb.m2 mb.m4

        g3 =
            g v.v3 v.v7 v.v11 v.v15 mb.m10 mb.m15

        g4 =
            g g0.a g1.b g2.c g3.d mb.m14 mb.m1

        g5 =
            g g1.a g2.b g3.c g0.d mb.m11 mb.m12

        g6 =
            g g2.a g3.b g0.c g1.d mb.m6 mb.m8

        g7 =
            g g3.a g0.b g1.c g2.d mb.m3 mb.m13
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


{-| SIGMA[5] = { 2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9 }
-}
round5 : U64MessageBlock -> WorkingVector -> WorkingVector
round5 mb v =
    let
        g0 =
            g v.v0 v.v4 v.v8 v.v12 mb.m2 mb.m12

        g1 =
            g v.v1 v.v5 v.v9 v.v13 mb.m6 mb.m10

        g2 =
            g v.v2 v.v6 v.v10 v.v14 mb.m0 mb.m11

        g3 =
            g v.v3 v.v7 v.v11 v.v15 mb.m8 mb.m3

        g4 =
            g g0.a g1.b g2.c g3.d mb.m4 mb.m13

        g5 =
            g g1.a g2.b g3.c g0.d mb.m7 mb.m5

        g6 =
            g g2.a g3.b g0.c g1.d mb.m15 mb.m14

        g7 =
            g g3.a g0.b g1.c g2.d mb.m1 mb.m9
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


{-| SIGMA[6] = { 12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11 }
-}
round6 : U64MessageBlock -> WorkingVector -> WorkingVector
round6 mb v =
    let
        g0 =
            g v.v0 v.v4 v.v8 v.v12 mb.m12 mb.m5

        g1 =
            g v.v1 v.v5 v.v9 v.v13 mb.m1 mb.m15

        g2 =
            g v.v2 v.v6 v.v10 v.v14 mb.m14 mb.m13

        g3 =
            g v.v3 v.v7 v.v11 v.v15 mb.m4 mb.m10

        g4 =
            g g0.a g1.b g2.c g3.d mb.m0 mb.m7

        g5 =
            g g1.a g2.b g3.c g0.d mb.m6 mb.m3

        g6 =
            g g2.a g3.b g0.c g1.d mb.m9 mb.m2

        g7 =
            g g3.a g0.b g1.c g2.d mb.m8 mb.m11
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


{-| SIGMA[7] = { 13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10 }
-}
round7 : U64MessageBlock -> WorkingVector -> WorkingVector
round7 mb v =
    let
        g0 =
            g v.v0 v.v4 v.v8 v.v12 mb.m13 mb.m11

        g1 =
            g v.v1 v.v5 v.v9 v.v13 mb.m7 mb.m14

        g2 =
            g v.v2 v.v6 v.v10 v.v14 mb.m12 mb.m1

        g3 =
            g v.v3 v.v7 v.v11 v.v15 mb.m3 mb.m9

        g4 =
            g g0.a g1.b g2.c g3.d mb.m5 mb.m0

        g5 =
            g g1.a g2.b g3.c g0.d mb.m15 mb.m4

        g6 =
            g g2.a g3.b g0.c g1.d mb.m8 mb.m6

        g7 =
            g g3.a g0.b g1.c g2.d mb.m2 mb.m10
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


{-| SIGMA[8] = { 6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5 }
-}
round8 : U64MessageBlock -> WorkingVector -> WorkingVector
round8 mb v =
    let
        g0 =
            g v.v0 v.v4 v.v8 v.v12 mb.m6 mb.m15

        g1 =
            g v.v1 v.v5 v.v9 v.v13 mb.m14 mb.m9

        g2 =
            g v.v2 v.v6 v.v10 v.v14 mb.m11 mb.m3

        g3 =
            g v.v3 v.v7 v.v11 v.v15 mb.m0 mb.m8

        g4 =
            g g0.a g1.b g2.c g3.d mb.m12 mb.m2

        g5 =
            g g1.a g2.b g3.c g0.d mb.m13 mb.m7

        g6 =
            g g2.a g3.b g0.c g1.d mb.m1 mb.m4

        g7 =
            g g3.a g0.b g1.c g2.d mb.m10 mb.m5
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


{-| SIGMA[9] = { 10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0 }
-}
round9 : U64MessageBlock -> WorkingVector -> WorkingVector
round9 mb v =
    let
        g0 =
            g v.v0 v.v4 v.v8 v.v12 mb.m10 mb.m2

        g1 =
            g v.v1 v.v5 v.v9 v.v13 mb.m8 mb.m4

        g2 =
            g v.v2 v.v6 v.v10 v.v14 mb.m7 mb.m6

        g3 =
            g v.v3 v.v7 v.v11 v.v15 mb.m1 mb.m5

        g4 =
            g g0.a g1.b g2.c g3.d mb.m15 mb.m11

        g5 =
            g g1.a g2.b g3.c g0.d mb.m9 mb.m14

        g6 =
            g g2.a g3.b g0.c g1.d mb.m3 mb.m12

        g7 =
            g g3.a g0.b g1.c g2.d mb.m13 mb.m0
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
        -- Build U64MessageBlock once, shared across all 12 rounds
        u64mb =
            { m0 = { hi = mb.m0Hi, lo = mb.m0Lo }
            , m1 = { hi = mb.m1Hi, lo = mb.m1Lo }
            , m2 = { hi = mb.m2Hi, lo = mb.m2Lo }
            , m3 = { hi = mb.m3Hi, lo = mb.m3Lo }
            , m4 = { hi = mb.m4Hi, lo = mb.m4Lo }
            , m5 = { hi = mb.m5Hi, lo = mb.m5Lo }
            , m6 = { hi = mb.m6Hi, lo = mb.m6Lo }
            , m7 = { hi = mb.m7Hi, lo = mb.m7Lo }
            , m8 = { hi = mb.m8Hi, lo = mb.m8Lo }
            , m9 = { hi = mb.m9Hi, lo = mb.m9Lo }
            , m10 = { hi = mb.m10Hi, lo = mb.m10Lo }
            , m11 = { hi = mb.m11Hi, lo = mb.m11Lo }
            , m12 = { hi = mb.m12Hi, lo = mb.m12Lo }
            , m13 = { hi = mb.m13Hi, lo = mb.m13Lo }
            , m14 = { hi = mb.m14Hi, lo = mb.m14Lo }
            , m15 = { hi = mb.m15Hi, lo = mb.m15Lo }
            }

        -- Initialize working vector (IVs from module-level constants)
        initV =
            { v0 = h.h0
            , v1 = h.h1
            , v2 = h.h2
            , v3 = h.h3
            , v4 = h.h4
            , v5 = h.h5
            , v6 = h.h6
            , v7 = h.h7
            , v8 = iv0U
            , v9 = iv1U
            , v10 = iv2U
            , v11 = iv3U
            , v12 = xor64 iv4U { hi = t0Hi, lo = t0Lo }
            , v13 = xor64 iv5U { hi = t1Hi, lo = t1Lo }
            , v14 =
                if isLastBlock then
                    { hi = Bitwise.xor iv6Hi 0xFFFFFFFF, lo = Bitwise.xor iv6Lo 0xFFFFFFFF }

                else
                    iv6U
            , v15 = iv7U
            }

        -- 12 rounds: 0-9 unique, 10 = round0, 11 = round1
        vR0 =
            round0 u64mb initV

        vR1 =
            round1 u64mb vR0

        vR2 =
            round2 u64mb vR1

        vR3 =
            round3 u64mb vR2

        vR4 =
            round4 u64mb vR3

        vR5 =
            round5 u64mb vR4

        vR6 =
            round6 u64mb vR5

        vR7 =
            round7 u64mb vR6

        vR8 =
            round8 u64mb vR7

        vR9 =
            round9 u64mb vR8

        vR10 =
            round0 u64mb vR9

        vR11 =
            round1 u64mb vR10
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
            , h1 = iv1U
            , h2 = iv2U
            , h3 = iv3U
            , h4 = iv4U
            , h5 = iv5U
            , h6 = iv6U
            , h7 = iv7U
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
