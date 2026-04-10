module Blake2b.V3 exposing (hash, hash224, hash256, hash512)

{-| Pure Elm BLAKE2b implementation (RFC 7693) optimized for V8 performance.

Changes in V2:

  - Inlines the G mixing function into a single round function as raw
    hi/lo Int let-bindings. Sigma permutations are applied at the call site
    by constructing a permuted U64MessageBlock. This eliminates ~2000
    intermediate U64 record allocations per block while keeping code size
    small (one round function body instead of 10 copies).

Base:

  - Bitwise carry detection in add64 (avoids polymorphic _Utils_cmp)
  - Hoists IV U64 constructions to module level (evaluated once at load time)
  - Constructs a U64MessageBlock once per compress call, shared across all 12 rounds

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



-- PRIMITIVE OPERATIONS (xor64 used in compress finalization)


xor64 : U64 -> U64 -> U64
xor64 a b =
    { hi = Bitwise.xor a.hi b.hi, lo = Bitwise.xor a.lo b.lo }


{-| Detect carry from adding a known increment to a 32-bit counter.
Given the old value and the new sum, returns 1 if overflow occurred, 0 otherwise.
Uses the same bitwise carry trick as add64 to avoid \_Utils\_cmp.
-}
counterCarry : Int -> Int -> Int
counterCarry old new =
    Bitwise.shiftRightZfBy 31
        (Bitwise.and old (Bitwise.complement new))



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



-- ROUND FUNCTION
-- Single round function with inlined G mixing. Sigma permutations are
-- applied by the caller, which passes a permuted U64MessageBlock.
-- The function always reads m0..m15 in fixed order for G0..G7.


round : U64MessageBlock -> WorkingVector -> WorkingVector
round mb v =
    let
        -- Column G0: a=v0, b=v4, c=v8, d=v12, x=m0, y=m1
        -- a1 = add64(add64(a, b), x)
        g0_abLo =
            Bitwise.shiftRightZfBy 0 (v.v0.lo + v.v4.lo)

        g0_abCarry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and v.v0.lo v.v4.lo)
                    (Bitwise.and
                        (Bitwise.or v.v0.lo v.v4.lo)
                        (Bitwise.complement g0_abLo)
                    )
                )

        g0_abHi =
            Bitwise.shiftRightZfBy 0 (v.v0.hi + v.v4.hi + g0_abCarry)

        g0_a1Lo =
            Bitwise.shiftRightZfBy 0 (g0_abLo + mb.m0.lo)

        g0_a1Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g0_abLo mb.m0.lo)
                    (Bitwise.and
                        (Bitwise.or g0_abLo mb.m0.lo)
                        (Bitwise.complement g0_a1Lo)
                    )
                )

        g0_a1Hi =
            Bitwise.shiftRightZfBy 0 (g0_abHi + mb.m0.hi + g0_a1Carry)

        -- d1 = rotr32(xor64(d, a1))
        g0_d1Hi =
            Bitwise.xor v.v12.lo g0_a1Lo

        g0_d1Lo =
            Bitwise.xor v.v12.hi g0_a1Hi

        -- c1 = add64(c, d1)
        g0_c1Lo =
            Bitwise.shiftRightZfBy 0 (v.v8.lo + g0_d1Lo)

        g0_c1Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and v.v8.lo g0_d1Lo)
                    (Bitwise.and
                        (Bitwise.or v.v8.lo g0_d1Lo)
                        (Bitwise.complement g0_c1Lo)
                    )
                )

        g0_c1Hi =
            Bitwise.shiftRightZfBy 0 (v.v8.hi + g0_d1Hi + g0_c1Carry)

        -- b1 = rotr24(xor64(b, c1))
        g0_b1xHi =
            Bitwise.xor v.v4.hi g0_c1Hi

        g0_b1xLo =
            Bitwise.xor v.v4.lo g0_c1Lo

        g0_b1Hi =
            Bitwise.or (Bitwise.shiftRightZfBy 24 g0_b1xHi) (Bitwise.shiftLeftBy 8 g0_b1xLo)

        g0_b1Lo =
            Bitwise.or (Bitwise.shiftRightZfBy 24 g0_b1xLo) (Bitwise.shiftLeftBy 8 g0_b1xHi)

        -- a2 = add64(add64(a1, b1), y)
        g0_a1b1Lo =
            Bitwise.shiftRightZfBy 0 (g0_a1Lo + g0_b1Lo)

        g0_a1b1Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g0_a1Lo g0_b1Lo)
                    (Bitwise.and
                        (Bitwise.or g0_a1Lo g0_b1Lo)
                        (Bitwise.complement g0_a1b1Lo)
                    )
                )

        g0_a1b1Hi =
            Bitwise.shiftRightZfBy 0 (g0_a1Hi + g0_b1Hi + g0_a1b1Carry)

        g0_a2Lo =
            Bitwise.shiftRightZfBy 0 (g0_a1b1Lo + mb.m1.lo)

        g0_a2Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g0_a1b1Lo mb.m1.lo)
                    (Bitwise.and
                        (Bitwise.or g0_a1b1Lo mb.m1.lo)
                        (Bitwise.complement g0_a2Lo)
                    )
                )

        g0_a2Hi =
            Bitwise.shiftRightZfBy 0 (g0_a1b1Hi + mb.m1.hi + g0_a2Carry)

        -- d2 = rotr16(xor64(d1, a2))
        g0_d2xHi =
            Bitwise.xor g0_d1Hi g0_a2Hi

        g0_d2xLo =
            Bitwise.xor g0_d1Lo g0_a2Lo

        g0_d2Hi =
            Bitwise.or (Bitwise.shiftRightZfBy 16 g0_d2xHi) (Bitwise.shiftLeftBy 16 g0_d2xLo)

        g0_d2Lo =
            Bitwise.or (Bitwise.shiftRightZfBy 16 g0_d2xLo) (Bitwise.shiftLeftBy 16 g0_d2xHi)

        -- c2 = add64(c1, d2)
        g0_c2Lo =
            Bitwise.shiftRightZfBy 0 (g0_c1Lo + g0_d2Lo)

        g0_c2Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g0_c1Lo g0_d2Lo)
                    (Bitwise.and
                        (Bitwise.or g0_c1Lo g0_d2Lo)
                        (Bitwise.complement g0_c2Lo)
                    )
                )

        g0_c2Hi =
            Bitwise.shiftRightZfBy 0 (g0_c1Hi + g0_d2Hi + g0_c2Carry)

        -- b2 = rotr63(xor64(b1, c2))
        g0_b2xHi =
            Bitwise.xor g0_b1Hi g0_c2Hi

        g0_b2xLo =
            Bitwise.xor g0_b1Lo g0_c2Lo

        g0_b2Hi =
            Bitwise.or (Bitwise.shiftLeftBy 1 g0_b2xHi) (Bitwise.shiftRightZfBy 31 g0_b2xLo)

        g0_b2Lo =
            Bitwise.or (Bitwise.shiftLeftBy 1 g0_b2xLo) (Bitwise.shiftRightZfBy 31 g0_b2xHi)

        -- Column G1: a=v1, b=v5, c=v9, d=v13, x=m2, y=m3
        -- a1 = add64(add64(a, b), x)
        g1_abLo =
            Bitwise.shiftRightZfBy 0 (v.v1.lo + v.v5.lo)

        g1_abCarry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and v.v1.lo v.v5.lo)
                    (Bitwise.and
                        (Bitwise.or v.v1.lo v.v5.lo)
                        (Bitwise.complement g1_abLo)
                    )
                )

        g1_abHi =
            Bitwise.shiftRightZfBy 0 (v.v1.hi + v.v5.hi + g1_abCarry)

        g1_a1Lo =
            Bitwise.shiftRightZfBy 0 (g1_abLo + mb.m2.lo)

        g1_a1Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g1_abLo mb.m2.lo)
                    (Bitwise.and
                        (Bitwise.or g1_abLo mb.m2.lo)
                        (Bitwise.complement g1_a1Lo)
                    )
                )

        g1_a1Hi =
            Bitwise.shiftRightZfBy 0 (g1_abHi + mb.m2.hi + g1_a1Carry)

        -- d1 = rotr32(xor64(d, a1))
        g1_d1Hi =
            Bitwise.xor v.v13.lo g1_a1Lo

        g1_d1Lo =
            Bitwise.xor v.v13.hi g1_a1Hi

        -- c1 = add64(c, d1)
        g1_c1Lo =
            Bitwise.shiftRightZfBy 0 (v.v9.lo + g1_d1Lo)

        g1_c1Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and v.v9.lo g1_d1Lo)
                    (Bitwise.and
                        (Bitwise.or v.v9.lo g1_d1Lo)
                        (Bitwise.complement g1_c1Lo)
                    )
                )

        g1_c1Hi =
            Bitwise.shiftRightZfBy 0 (v.v9.hi + g1_d1Hi + g1_c1Carry)

        -- b1 = rotr24(xor64(b, c1))
        g1_b1xHi =
            Bitwise.xor v.v5.hi g1_c1Hi

        g1_b1xLo =
            Bitwise.xor v.v5.lo g1_c1Lo

        g1_b1Hi =
            Bitwise.or (Bitwise.shiftRightZfBy 24 g1_b1xHi) (Bitwise.shiftLeftBy 8 g1_b1xLo)

        g1_b1Lo =
            Bitwise.or (Bitwise.shiftRightZfBy 24 g1_b1xLo) (Bitwise.shiftLeftBy 8 g1_b1xHi)

        -- a2 = add64(add64(a1, b1), y)
        g1_a1b1Lo =
            Bitwise.shiftRightZfBy 0 (g1_a1Lo + g1_b1Lo)

        g1_a1b1Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g1_a1Lo g1_b1Lo)
                    (Bitwise.and
                        (Bitwise.or g1_a1Lo g1_b1Lo)
                        (Bitwise.complement g1_a1b1Lo)
                    )
                )

        g1_a1b1Hi =
            Bitwise.shiftRightZfBy 0 (g1_a1Hi + g1_b1Hi + g1_a1b1Carry)

        g1_a2Lo =
            Bitwise.shiftRightZfBy 0 (g1_a1b1Lo + mb.m3.lo)

        g1_a2Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g1_a1b1Lo mb.m3.lo)
                    (Bitwise.and
                        (Bitwise.or g1_a1b1Lo mb.m3.lo)
                        (Bitwise.complement g1_a2Lo)
                    )
                )

        g1_a2Hi =
            Bitwise.shiftRightZfBy 0 (g1_a1b1Hi + mb.m3.hi + g1_a2Carry)

        -- d2 = rotr16(xor64(d1, a2))
        g1_d2xHi =
            Bitwise.xor g1_d1Hi g1_a2Hi

        g1_d2xLo =
            Bitwise.xor g1_d1Lo g1_a2Lo

        g1_d2Hi =
            Bitwise.or (Bitwise.shiftRightZfBy 16 g1_d2xHi) (Bitwise.shiftLeftBy 16 g1_d2xLo)

        g1_d2Lo =
            Bitwise.or (Bitwise.shiftRightZfBy 16 g1_d2xLo) (Bitwise.shiftLeftBy 16 g1_d2xHi)

        -- c2 = add64(c1, d2)
        g1_c2Lo =
            Bitwise.shiftRightZfBy 0 (g1_c1Lo + g1_d2Lo)

        g1_c2Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g1_c1Lo g1_d2Lo)
                    (Bitwise.and
                        (Bitwise.or g1_c1Lo g1_d2Lo)
                        (Bitwise.complement g1_c2Lo)
                    )
                )

        g1_c2Hi =
            Bitwise.shiftRightZfBy 0 (g1_c1Hi + g1_d2Hi + g1_c2Carry)

        -- b2 = rotr63(xor64(b1, c2))
        g1_b2xHi =
            Bitwise.xor g1_b1Hi g1_c2Hi

        g1_b2xLo =
            Bitwise.xor g1_b1Lo g1_c2Lo

        g1_b2Hi =
            Bitwise.or (Bitwise.shiftLeftBy 1 g1_b2xHi) (Bitwise.shiftRightZfBy 31 g1_b2xLo)

        g1_b2Lo =
            Bitwise.or (Bitwise.shiftLeftBy 1 g1_b2xLo) (Bitwise.shiftRightZfBy 31 g1_b2xHi)

        -- Column G2: a=v2, b=v6, c=v10, d=v14, x=m4, y=m5
        -- a1 = add64(add64(a, b), x)
        g2_abLo =
            Bitwise.shiftRightZfBy 0 (v.v2.lo + v.v6.lo)

        g2_abCarry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and v.v2.lo v.v6.lo)
                    (Bitwise.and
                        (Bitwise.or v.v2.lo v.v6.lo)
                        (Bitwise.complement g2_abLo)
                    )
                )

        g2_abHi =
            Bitwise.shiftRightZfBy 0 (v.v2.hi + v.v6.hi + g2_abCarry)

        g2_a1Lo =
            Bitwise.shiftRightZfBy 0 (g2_abLo + mb.m4.lo)

        g2_a1Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g2_abLo mb.m4.lo)
                    (Bitwise.and
                        (Bitwise.or g2_abLo mb.m4.lo)
                        (Bitwise.complement g2_a1Lo)
                    )
                )

        g2_a1Hi =
            Bitwise.shiftRightZfBy 0 (g2_abHi + mb.m4.hi + g2_a1Carry)

        -- d1 = rotr32(xor64(d, a1))
        g2_d1Hi =
            Bitwise.xor v.v14.lo g2_a1Lo

        g2_d1Lo =
            Bitwise.xor v.v14.hi g2_a1Hi

        -- c1 = add64(c, d1)
        g2_c1Lo =
            Bitwise.shiftRightZfBy 0 (v.v10.lo + g2_d1Lo)

        g2_c1Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and v.v10.lo g2_d1Lo)
                    (Bitwise.and
                        (Bitwise.or v.v10.lo g2_d1Lo)
                        (Bitwise.complement g2_c1Lo)
                    )
                )

        g2_c1Hi =
            Bitwise.shiftRightZfBy 0 (v.v10.hi + g2_d1Hi + g2_c1Carry)

        -- b1 = rotr24(xor64(b, c1))
        g2_b1xHi =
            Bitwise.xor v.v6.hi g2_c1Hi

        g2_b1xLo =
            Bitwise.xor v.v6.lo g2_c1Lo

        g2_b1Hi =
            Bitwise.or (Bitwise.shiftRightZfBy 24 g2_b1xHi) (Bitwise.shiftLeftBy 8 g2_b1xLo)

        g2_b1Lo =
            Bitwise.or (Bitwise.shiftRightZfBy 24 g2_b1xLo) (Bitwise.shiftLeftBy 8 g2_b1xHi)

        -- a2 = add64(add64(a1, b1), y)
        g2_a1b1Lo =
            Bitwise.shiftRightZfBy 0 (g2_a1Lo + g2_b1Lo)

        g2_a1b1Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g2_a1Lo g2_b1Lo)
                    (Bitwise.and
                        (Bitwise.or g2_a1Lo g2_b1Lo)
                        (Bitwise.complement g2_a1b1Lo)
                    )
                )

        g2_a1b1Hi =
            Bitwise.shiftRightZfBy 0 (g2_a1Hi + g2_b1Hi + g2_a1b1Carry)

        g2_a2Lo =
            Bitwise.shiftRightZfBy 0 (g2_a1b1Lo + mb.m5.lo)

        g2_a2Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g2_a1b1Lo mb.m5.lo)
                    (Bitwise.and
                        (Bitwise.or g2_a1b1Lo mb.m5.lo)
                        (Bitwise.complement g2_a2Lo)
                    )
                )

        g2_a2Hi =
            Bitwise.shiftRightZfBy 0 (g2_a1b1Hi + mb.m5.hi + g2_a2Carry)

        -- d2 = rotr16(xor64(d1, a2))
        g2_d2xHi =
            Bitwise.xor g2_d1Hi g2_a2Hi

        g2_d2xLo =
            Bitwise.xor g2_d1Lo g2_a2Lo

        g2_d2Hi =
            Bitwise.or (Bitwise.shiftRightZfBy 16 g2_d2xHi) (Bitwise.shiftLeftBy 16 g2_d2xLo)

        g2_d2Lo =
            Bitwise.or (Bitwise.shiftRightZfBy 16 g2_d2xLo) (Bitwise.shiftLeftBy 16 g2_d2xHi)

        -- c2 = add64(c1, d2)
        g2_c2Lo =
            Bitwise.shiftRightZfBy 0 (g2_c1Lo + g2_d2Lo)

        g2_c2Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g2_c1Lo g2_d2Lo)
                    (Bitwise.and
                        (Bitwise.or g2_c1Lo g2_d2Lo)
                        (Bitwise.complement g2_c2Lo)
                    )
                )

        g2_c2Hi =
            Bitwise.shiftRightZfBy 0 (g2_c1Hi + g2_d2Hi + g2_c2Carry)

        -- b2 = rotr63(xor64(b1, c2))
        g2_b2xHi =
            Bitwise.xor g2_b1Hi g2_c2Hi

        g2_b2xLo =
            Bitwise.xor g2_b1Lo g2_c2Lo

        g2_b2Hi =
            Bitwise.or (Bitwise.shiftLeftBy 1 g2_b2xHi) (Bitwise.shiftRightZfBy 31 g2_b2xLo)

        g2_b2Lo =
            Bitwise.or (Bitwise.shiftLeftBy 1 g2_b2xLo) (Bitwise.shiftRightZfBy 31 g2_b2xHi)

        -- Column G3: a=v3, b=v7, c=v11, d=v15, x=m6, y=m7
        -- a1 = add64(add64(a, b), x)
        g3_abLo =
            Bitwise.shiftRightZfBy 0 (v.v3.lo + v.v7.lo)

        g3_abCarry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and v.v3.lo v.v7.lo)
                    (Bitwise.and
                        (Bitwise.or v.v3.lo v.v7.lo)
                        (Bitwise.complement g3_abLo)
                    )
                )

        g3_abHi =
            Bitwise.shiftRightZfBy 0 (v.v3.hi + v.v7.hi + g3_abCarry)

        g3_a1Lo =
            Bitwise.shiftRightZfBy 0 (g3_abLo + mb.m6.lo)

        g3_a1Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g3_abLo mb.m6.lo)
                    (Bitwise.and
                        (Bitwise.or g3_abLo mb.m6.lo)
                        (Bitwise.complement g3_a1Lo)
                    )
                )

        g3_a1Hi =
            Bitwise.shiftRightZfBy 0 (g3_abHi + mb.m6.hi + g3_a1Carry)

        -- d1 = rotr32(xor64(d, a1))
        g3_d1Hi =
            Bitwise.xor v.v15.lo g3_a1Lo

        g3_d1Lo =
            Bitwise.xor v.v15.hi g3_a1Hi

        -- c1 = add64(c, d1)
        g3_c1Lo =
            Bitwise.shiftRightZfBy 0 (v.v11.lo + g3_d1Lo)

        g3_c1Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and v.v11.lo g3_d1Lo)
                    (Bitwise.and
                        (Bitwise.or v.v11.lo g3_d1Lo)
                        (Bitwise.complement g3_c1Lo)
                    )
                )

        g3_c1Hi =
            Bitwise.shiftRightZfBy 0 (v.v11.hi + g3_d1Hi + g3_c1Carry)

        -- b1 = rotr24(xor64(b, c1))
        g3_b1xHi =
            Bitwise.xor v.v7.hi g3_c1Hi

        g3_b1xLo =
            Bitwise.xor v.v7.lo g3_c1Lo

        g3_b1Hi =
            Bitwise.or (Bitwise.shiftRightZfBy 24 g3_b1xHi) (Bitwise.shiftLeftBy 8 g3_b1xLo)

        g3_b1Lo =
            Bitwise.or (Bitwise.shiftRightZfBy 24 g3_b1xLo) (Bitwise.shiftLeftBy 8 g3_b1xHi)

        -- a2 = add64(add64(a1, b1), y)
        g3_a1b1Lo =
            Bitwise.shiftRightZfBy 0 (g3_a1Lo + g3_b1Lo)

        g3_a1b1Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g3_a1Lo g3_b1Lo)
                    (Bitwise.and
                        (Bitwise.or g3_a1Lo g3_b1Lo)
                        (Bitwise.complement g3_a1b1Lo)
                    )
                )

        g3_a1b1Hi =
            Bitwise.shiftRightZfBy 0 (g3_a1Hi + g3_b1Hi + g3_a1b1Carry)

        g3_a2Lo =
            Bitwise.shiftRightZfBy 0 (g3_a1b1Lo + mb.m7.lo)

        g3_a2Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g3_a1b1Lo mb.m7.lo)
                    (Bitwise.and
                        (Bitwise.or g3_a1b1Lo mb.m7.lo)
                        (Bitwise.complement g3_a2Lo)
                    )
                )

        g3_a2Hi =
            Bitwise.shiftRightZfBy 0 (g3_a1b1Hi + mb.m7.hi + g3_a2Carry)

        -- d2 = rotr16(xor64(d1, a2))
        g3_d2xHi =
            Bitwise.xor g3_d1Hi g3_a2Hi

        g3_d2xLo =
            Bitwise.xor g3_d1Lo g3_a2Lo

        g3_d2Hi =
            Bitwise.or (Bitwise.shiftRightZfBy 16 g3_d2xHi) (Bitwise.shiftLeftBy 16 g3_d2xLo)

        g3_d2Lo =
            Bitwise.or (Bitwise.shiftRightZfBy 16 g3_d2xLo) (Bitwise.shiftLeftBy 16 g3_d2xHi)

        -- c2 = add64(c1, d2)
        g3_c2Lo =
            Bitwise.shiftRightZfBy 0 (g3_c1Lo + g3_d2Lo)

        g3_c2Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g3_c1Lo g3_d2Lo)
                    (Bitwise.and
                        (Bitwise.or g3_c1Lo g3_d2Lo)
                        (Bitwise.complement g3_c2Lo)
                    )
                )

        g3_c2Hi =
            Bitwise.shiftRightZfBy 0 (g3_c1Hi + g3_d2Hi + g3_c2Carry)

        -- b2 = rotr63(xor64(b1, c2))
        g3_b2xHi =
            Bitwise.xor g3_b1Hi g3_c2Hi

        g3_b2xLo =
            Bitwise.xor g3_b1Lo g3_c2Lo

        g3_b2Hi =
            Bitwise.or (Bitwise.shiftLeftBy 1 g3_b2xHi) (Bitwise.shiftRightZfBy 31 g3_b2xLo)

        g3_b2Lo =
            Bitwise.or (Bitwise.shiftLeftBy 1 g3_b2xLo) (Bitwise.shiftRightZfBy 31 g3_b2xHi)

        -- Diagonal G4: a=g0.a, b=g1.b, c=g2.c, d=g3.d, x=m8, y=m9
        -- a1 = add64(add64(a, b), x)
        g4_abLo =
            Bitwise.shiftRightZfBy 0 (g0_a2Lo + g1_b2Lo)

        g4_abCarry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g0_a2Lo g1_b2Lo)
                    (Bitwise.and
                        (Bitwise.or g0_a2Lo g1_b2Lo)
                        (Bitwise.complement g4_abLo)
                    )
                )

        g4_abHi =
            Bitwise.shiftRightZfBy 0 (g0_a2Hi + g1_b2Hi + g4_abCarry)

        g4_a1Lo =
            Bitwise.shiftRightZfBy 0 (g4_abLo + mb.m8.lo)

        g4_a1Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g4_abLo mb.m8.lo)
                    (Bitwise.and
                        (Bitwise.or g4_abLo mb.m8.lo)
                        (Bitwise.complement g4_a1Lo)
                    )
                )

        g4_a1Hi =
            Bitwise.shiftRightZfBy 0 (g4_abHi + mb.m8.hi + g4_a1Carry)

        -- d1 = rotr32(xor64(d, a1))
        g4_d1Hi =
            Bitwise.xor g3_d2Lo g4_a1Lo

        g4_d1Lo =
            Bitwise.xor g3_d2Hi g4_a1Hi

        -- c1 = add64(c, d1)
        g4_c1Lo =
            Bitwise.shiftRightZfBy 0 (g2_c2Lo + g4_d1Lo)

        g4_c1Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g2_c2Lo g4_d1Lo)
                    (Bitwise.and
                        (Bitwise.or g2_c2Lo g4_d1Lo)
                        (Bitwise.complement g4_c1Lo)
                    )
                )

        g4_c1Hi =
            Bitwise.shiftRightZfBy 0 (g2_c2Hi + g4_d1Hi + g4_c1Carry)

        -- b1 = rotr24(xor64(b, c1))
        g4_b1xHi =
            Bitwise.xor g1_b2Hi g4_c1Hi

        g4_b1xLo =
            Bitwise.xor g1_b2Lo g4_c1Lo

        g4_b1Hi =
            Bitwise.or (Bitwise.shiftRightZfBy 24 g4_b1xHi) (Bitwise.shiftLeftBy 8 g4_b1xLo)

        g4_b1Lo =
            Bitwise.or (Bitwise.shiftRightZfBy 24 g4_b1xLo) (Bitwise.shiftLeftBy 8 g4_b1xHi)

        -- a2 = add64(add64(a1, b1), y)
        g4_a1b1Lo =
            Bitwise.shiftRightZfBy 0 (g4_a1Lo + g4_b1Lo)

        g4_a1b1Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g4_a1Lo g4_b1Lo)
                    (Bitwise.and
                        (Bitwise.or g4_a1Lo g4_b1Lo)
                        (Bitwise.complement g4_a1b1Lo)
                    )
                )

        g4_a1b1Hi =
            Bitwise.shiftRightZfBy 0 (g4_a1Hi + g4_b1Hi + g4_a1b1Carry)

        g4_a2Lo =
            Bitwise.shiftRightZfBy 0 (g4_a1b1Lo + mb.m9.lo)

        g4_a2Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g4_a1b1Lo mb.m9.lo)
                    (Bitwise.and
                        (Bitwise.or g4_a1b1Lo mb.m9.lo)
                        (Bitwise.complement g4_a2Lo)
                    )
                )

        g4_a2Hi =
            Bitwise.shiftRightZfBy 0 (g4_a1b1Hi + mb.m9.hi + g4_a2Carry)

        -- d2 = rotr16(xor64(d1, a2))
        g4_d2xHi =
            Bitwise.xor g4_d1Hi g4_a2Hi

        g4_d2xLo =
            Bitwise.xor g4_d1Lo g4_a2Lo

        g4_d2Hi =
            Bitwise.or (Bitwise.shiftRightZfBy 16 g4_d2xHi) (Bitwise.shiftLeftBy 16 g4_d2xLo)

        g4_d2Lo =
            Bitwise.or (Bitwise.shiftRightZfBy 16 g4_d2xLo) (Bitwise.shiftLeftBy 16 g4_d2xHi)

        -- c2 = add64(c1, d2)
        g4_c2Lo =
            Bitwise.shiftRightZfBy 0 (g4_c1Lo + g4_d2Lo)

        g4_c2Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g4_c1Lo g4_d2Lo)
                    (Bitwise.and
                        (Bitwise.or g4_c1Lo g4_d2Lo)
                        (Bitwise.complement g4_c2Lo)
                    )
                )

        g4_c2Hi =
            Bitwise.shiftRightZfBy 0 (g4_c1Hi + g4_d2Hi + g4_c2Carry)

        -- b2 = rotr63(xor64(b1, c2))
        g4_b2xHi =
            Bitwise.xor g4_b1Hi g4_c2Hi

        g4_b2xLo =
            Bitwise.xor g4_b1Lo g4_c2Lo

        g4_b2Hi =
            Bitwise.or (Bitwise.shiftLeftBy 1 g4_b2xHi) (Bitwise.shiftRightZfBy 31 g4_b2xLo)

        g4_b2Lo =
            Bitwise.or (Bitwise.shiftLeftBy 1 g4_b2xLo) (Bitwise.shiftRightZfBy 31 g4_b2xHi)

        -- Diagonal G5: a=g1.a, b=g2.b, c=g3.c, d=g0.d, x=m10, y=m11
        -- a1 = add64(add64(a, b), x)
        g5_abLo =
            Bitwise.shiftRightZfBy 0 (g1_a2Lo + g2_b2Lo)

        g5_abCarry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g1_a2Lo g2_b2Lo)
                    (Bitwise.and
                        (Bitwise.or g1_a2Lo g2_b2Lo)
                        (Bitwise.complement g5_abLo)
                    )
                )

        g5_abHi =
            Bitwise.shiftRightZfBy 0 (g1_a2Hi + g2_b2Hi + g5_abCarry)

        g5_a1Lo =
            Bitwise.shiftRightZfBy 0 (g5_abLo + mb.m10.lo)

        g5_a1Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g5_abLo mb.m10.lo)
                    (Bitwise.and
                        (Bitwise.or g5_abLo mb.m10.lo)
                        (Bitwise.complement g5_a1Lo)
                    )
                )

        g5_a1Hi =
            Bitwise.shiftRightZfBy 0 (g5_abHi + mb.m10.hi + g5_a1Carry)

        -- d1 = rotr32(xor64(d, a1))
        g5_d1Hi =
            Bitwise.xor g0_d2Lo g5_a1Lo

        g5_d1Lo =
            Bitwise.xor g0_d2Hi g5_a1Hi

        -- c1 = add64(c, d1)
        g5_c1Lo =
            Bitwise.shiftRightZfBy 0 (g3_c2Lo + g5_d1Lo)

        g5_c1Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g3_c2Lo g5_d1Lo)
                    (Bitwise.and
                        (Bitwise.or g3_c2Lo g5_d1Lo)
                        (Bitwise.complement g5_c1Lo)
                    )
                )

        g5_c1Hi =
            Bitwise.shiftRightZfBy 0 (g3_c2Hi + g5_d1Hi + g5_c1Carry)

        -- b1 = rotr24(xor64(b, c1))
        g5_b1xHi =
            Bitwise.xor g2_b2Hi g5_c1Hi

        g5_b1xLo =
            Bitwise.xor g2_b2Lo g5_c1Lo

        g5_b1Hi =
            Bitwise.or (Bitwise.shiftRightZfBy 24 g5_b1xHi) (Bitwise.shiftLeftBy 8 g5_b1xLo)

        g5_b1Lo =
            Bitwise.or (Bitwise.shiftRightZfBy 24 g5_b1xLo) (Bitwise.shiftLeftBy 8 g5_b1xHi)

        -- a2 = add64(add64(a1, b1), y)
        g5_a1b1Lo =
            Bitwise.shiftRightZfBy 0 (g5_a1Lo + g5_b1Lo)

        g5_a1b1Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g5_a1Lo g5_b1Lo)
                    (Bitwise.and
                        (Bitwise.or g5_a1Lo g5_b1Lo)
                        (Bitwise.complement g5_a1b1Lo)
                    )
                )

        g5_a1b1Hi =
            Bitwise.shiftRightZfBy 0 (g5_a1Hi + g5_b1Hi + g5_a1b1Carry)

        g5_a2Lo =
            Bitwise.shiftRightZfBy 0 (g5_a1b1Lo + mb.m11.lo)

        g5_a2Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g5_a1b1Lo mb.m11.lo)
                    (Bitwise.and
                        (Bitwise.or g5_a1b1Lo mb.m11.lo)
                        (Bitwise.complement g5_a2Lo)
                    )
                )

        g5_a2Hi =
            Bitwise.shiftRightZfBy 0 (g5_a1b1Hi + mb.m11.hi + g5_a2Carry)

        -- d2 = rotr16(xor64(d1, a2))
        g5_d2xHi =
            Bitwise.xor g5_d1Hi g5_a2Hi

        g5_d2xLo =
            Bitwise.xor g5_d1Lo g5_a2Lo

        g5_d2Hi =
            Bitwise.or (Bitwise.shiftRightZfBy 16 g5_d2xHi) (Bitwise.shiftLeftBy 16 g5_d2xLo)

        g5_d2Lo =
            Bitwise.or (Bitwise.shiftRightZfBy 16 g5_d2xLo) (Bitwise.shiftLeftBy 16 g5_d2xHi)

        -- c2 = add64(c1, d2)
        g5_c2Lo =
            Bitwise.shiftRightZfBy 0 (g5_c1Lo + g5_d2Lo)

        g5_c2Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g5_c1Lo g5_d2Lo)
                    (Bitwise.and
                        (Bitwise.or g5_c1Lo g5_d2Lo)
                        (Bitwise.complement g5_c2Lo)
                    )
                )

        g5_c2Hi =
            Bitwise.shiftRightZfBy 0 (g5_c1Hi + g5_d2Hi + g5_c2Carry)

        -- b2 = rotr63(xor64(b1, c2))
        g5_b2xHi =
            Bitwise.xor g5_b1Hi g5_c2Hi

        g5_b2xLo =
            Bitwise.xor g5_b1Lo g5_c2Lo

        g5_b2Hi =
            Bitwise.or (Bitwise.shiftLeftBy 1 g5_b2xHi) (Bitwise.shiftRightZfBy 31 g5_b2xLo)

        g5_b2Lo =
            Bitwise.or (Bitwise.shiftLeftBy 1 g5_b2xLo) (Bitwise.shiftRightZfBy 31 g5_b2xHi)

        -- Diagonal G6: a=g2.a, b=g3.b, c=g0.c, d=g1.d, x=m12, y=m13
        -- a1 = add64(add64(a, b), x)
        g6_abLo =
            Bitwise.shiftRightZfBy 0 (g2_a2Lo + g3_b2Lo)

        g6_abCarry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g2_a2Lo g3_b2Lo)
                    (Bitwise.and
                        (Bitwise.or g2_a2Lo g3_b2Lo)
                        (Bitwise.complement g6_abLo)
                    )
                )

        g6_abHi =
            Bitwise.shiftRightZfBy 0 (g2_a2Hi + g3_b2Hi + g6_abCarry)

        g6_a1Lo =
            Bitwise.shiftRightZfBy 0 (g6_abLo + mb.m12.lo)

        g6_a1Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g6_abLo mb.m12.lo)
                    (Bitwise.and
                        (Bitwise.or g6_abLo mb.m12.lo)
                        (Bitwise.complement g6_a1Lo)
                    )
                )

        g6_a1Hi =
            Bitwise.shiftRightZfBy 0 (g6_abHi + mb.m12.hi + g6_a1Carry)

        -- d1 = rotr32(xor64(d, a1))
        g6_d1Hi =
            Bitwise.xor g1_d2Lo g6_a1Lo

        g6_d1Lo =
            Bitwise.xor g1_d2Hi g6_a1Hi

        -- c1 = add64(c, d1)
        g6_c1Lo =
            Bitwise.shiftRightZfBy 0 (g0_c2Lo + g6_d1Lo)

        g6_c1Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g0_c2Lo g6_d1Lo)
                    (Bitwise.and
                        (Bitwise.or g0_c2Lo g6_d1Lo)
                        (Bitwise.complement g6_c1Lo)
                    )
                )

        g6_c1Hi =
            Bitwise.shiftRightZfBy 0 (g0_c2Hi + g6_d1Hi + g6_c1Carry)

        -- b1 = rotr24(xor64(b, c1))
        g6_b1xHi =
            Bitwise.xor g3_b2Hi g6_c1Hi

        g6_b1xLo =
            Bitwise.xor g3_b2Lo g6_c1Lo

        g6_b1Hi =
            Bitwise.or (Bitwise.shiftRightZfBy 24 g6_b1xHi) (Bitwise.shiftLeftBy 8 g6_b1xLo)

        g6_b1Lo =
            Bitwise.or (Bitwise.shiftRightZfBy 24 g6_b1xLo) (Bitwise.shiftLeftBy 8 g6_b1xHi)

        -- a2 = add64(add64(a1, b1), y)
        g6_a1b1Lo =
            Bitwise.shiftRightZfBy 0 (g6_a1Lo + g6_b1Lo)

        g6_a1b1Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g6_a1Lo g6_b1Lo)
                    (Bitwise.and
                        (Bitwise.or g6_a1Lo g6_b1Lo)
                        (Bitwise.complement g6_a1b1Lo)
                    )
                )

        g6_a1b1Hi =
            Bitwise.shiftRightZfBy 0 (g6_a1Hi + g6_b1Hi + g6_a1b1Carry)

        g6_a2Lo =
            Bitwise.shiftRightZfBy 0 (g6_a1b1Lo + mb.m13.lo)

        g6_a2Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g6_a1b1Lo mb.m13.lo)
                    (Bitwise.and
                        (Bitwise.or g6_a1b1Lo mb.m13.lo)
                        (Bitwise.complement g6_a2Lo)
                    )
                )

        g6_a2Hi =
            Bitwise.shiftRightZfBy 0 (g6_a1b1Hi + mb.m13.hi + g6_a2Carry)

        -- d2 = rotr16(xor64(d1, a2))
        g6_d2xHi =
            Bitwise.xor g6_d1Hi g6_a2Hi

        g6_d2xLo =
            Bitwise.xor g6_d1Lo g6_a2Lo

        g6_d2Hi =
            Bitwise.or (Bitwise.shiftRightZfBy 16 g6_d2xHi) (Bitwise.shiftLeftBy 16 g6_d2xLo)

        g6_d2Lo =
            Bitwise.or (Bitwise.shiftRightZfBy 16 g6_d2xLo) (Bitwise.shiftLeftBy 16 g6_d2xHi)

        -- c2 = add64(c1, d2)
        g6_c2Lo =
            Bitwise.shiftRightZfBy 0 (g6_c1Lo + g6_d2Lo)

        g6_c2Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g6_c1Lo g6_d2Lo)
                    (Bitwise.and
                        (Bitwise.or g6_c1Lo g6_d2Lo)
                        (Bitwise.complement g6_c2Lo)
                    )
                )

        g6_c2Hi =
            Bitwise.shiftRightZfBy 0 (g6_c1Hi + g6_d2Hi + g6_c2Carry)

        -- b2 = rotr63(xor64(b1, c2))
        g6_b2xHi =
            Bitwise.xor g6_b1Hi g6_c2Hi

        g6_b2xLo =
            Bitwise.xor g6_b1Lo g6_c2Lo

        g6_b2Hi =
            Bitwise.or (Bitwise.shiftLeftBy 1 g6_b2xHi) (Bitwise.shiftRightZfBy 31 g6_b2xLo)

        g6_b2Lo =
            Bitwise.or (Bitwise.shiftLeftBy 1 g6_b2xLo) (Bitwise.shiftRightZfBy 31 g6_b2xHi)

        -- Diagonal G7: a=g3.a, b=g0.b, c=g1.c, d=g2.d, x=m14, y=m15
        -- a1 = add64(add64(a, b), x)
        g7_abLo =
            Bitwise.shiftRightZfBy 0 (g3_a2Lo + g0_b2Lo)

        g7_abCarry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g3_a2Lo g0_b2Lo)
                    (Bitwise.and
                        (Bitwise.or g3_a2Lo g0_b2Lo)
                        (Bitwise.complement g7_abLo)
                    )
                )

        g7_abHi =
            Bitwise.shiftRightZfBy 0 (g3_a2Hi + g0_b2Hi + g7_abCarry)

        g7_a1Lo =
            Bitwise.shiftRightZfBy 0 (g7_abLo + mb.m14.lo)

        g7_a1Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g7_abLo mb.m14.lo)
                    (Bitwise.and
                        (Bitwise.or g7_abLo mb.m14.lo)
                        (Bitwise.complement g7_a1Lo)
                    )
                )

        g7_a1Hi =
            Bitwise.shiftRightZfBy 0 (g7_abHi + mb.m14.hi + g7_a1Carry)

        -- d1 = rotr32(xor64(d, a1))
        g7_d1Hi =
            Bitwise.xor g2_d2Lo g7_a1Lo

        g7_d1Lo =
            Bitwise.xor g2_d2Hi g7_a1Hi

        -- c1 = add64(c, d1)
        g7_c1Lo =
            Bitwise.shiftRightZfBy 0 (g1_c2Lo + g7_d1Lo)

        g7_c1Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g1_c2Lo g7_d1Lo)
                    (Bitwise.and
                        (Bitwise.or g1_c2Lo g7_d1Lo)
                        (Bitwise.complement g7_c1Lo)
                    )
                )

        g7_c1Hi =
            Bitwise.shiftRightZfBy 0 (g1_c2Hi + g7_d1Hi + g7_c1Carry)

        -- b1 = rotr24(xor64(b, c1))
        g7_b1xHi =
            Bitwise.xor g0_b2Hi g7_c1Hi

        g7_b1xLo =
            Bitwise.xor g0_b2Lo g7_c1Lo

        g7_b1Hi =
            Bitwise.or (Bitwise.shiftRightZfBy 24 g7_b1xHi) (Bitwise.shiftLeftBy 8 g7_b1xLo)

        g7_b1Lo =
            Bitwise.or (Bitwise.shiftRightZfBy 24 g7_b1xLo) (Bitwise.shiftLeftBy 8 g7_b1xHi)

        -- a2 = add64(add64(a1, b1), y)
        g7_a1b1Lo =
            Bitwise.shiftRightZfBy 0 (g7_a1Lo + g7_b1Lo)

        g7_a1b1Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g7_a1Lo g7_b1Lo)
                    (Bitwise.and
                        (Bitwise.or g7_a1Lo g7_b1Lo)
                        (Bitwise.complement g7_a1b1Lo)
                    )
                )

        g7_a1b1Hi =
            Bitwise.shiftRightZfBy 0 (g7_a1Hi + g7_b1Hi + g7_a1b1Carry)

        g7_a2Lo =
            Bitwise.shiftRightZfBy 0 (g7_a1b1Lo + mb.m15.lo)

        g7_a2Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g7_a1b1Lo mb.m15.lo)
                    (Bitwise.and
                        (Bitwise.or g7_a1b1Lo mb.m15.lo)
                        (Bitwise.complement g7_a2Lo)
                    )
                )

        g7_a2Hi =
            Bitwise.shiftRightZfBy 0 (g7_a1b1Hi + mb.m15.hi + g7_a2Carry)

        -- d2 = rotr16(xor64(d1, a2))
        g7_d2xHi =
            Bitwise.xor g7_d1Hi g7_a2Hi

        g7_d2xLo =
            Bitwise.xor g7_d1Lo g7_a2Lo

        g7_d2Hi =
            Bitwise.or (Bitwise.shiftRightZfBy 16 g7_d2xHi) (Bitwise.shiftLeftBy 16 g7_d2xLo)

        g7_d2Lo =
            Bitwise.or (Bitwise.shiftRightZfBy 16 g7_d2xLo) (Bitwise.shiftLeftBy 16 g7_d2xHi)

        -- c2 = add64(c1, d2)
        g7_c2Lo =
            Bitwise.shiftRightZfBy 0 (g7_c1Lo + g7_d2Lo)

        g7_c2Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g7_c1Lo g7_d2Lo)
                    (Bitwise.and
                        (Bitwise.or g7_c1Lo g7_d2Lo)
                        (Bitwise.complement g7_c2Lo)
                    )
                )

        g7_c2Hi =
            Bitwise.shiftRightZfBy 0 (g7_c1Hi + g7_d2Hi + g7_c2Carry)

        -- b2 = rotr63(xor64(b1, c2))
        g7_b2xHi =
            Bitwise.xor g7_b1Hi g7_c2Hi

        g7_b2xLo =
            Bitwise.xor g7_b1Lo g7_c2Lo

        g7_b2Hi =
            Bitwise.or (Bitwise.shiftLeftBy 1 g7_b2xHi) (Bitwise.shiftRightZfBy 31 g7_b2xLo)

        g7_b2Lo =
            Bitwise.or (Bitwise.shiftLeftBy 1 g7_b2xLo) (Bitwise.shiftRightZfBy 31 g7_b2xHi)
    in
    { v0 = { hi = g4_a2Hi, lo = g4_a2Lo }
    , v1 = { hi = g5_a2Hi, lo = g5_a2Lo }
    , v2 = { hi = g6_a2Hi, lo = g6_a2Lo }
    , v3 = { hi = g7_a2Hi, lo = g7_a2Lo }
    , v4 = { hi = g7_b2Hi, lo = g7_b2Lo }
    , v5 = { hi = g4_b2Hi, lo = g4_b2Lo }
    , v6 = { hi = g5_b2Hi, lo = g5_b2Lo }
    , v7 = { hi = g6_b2Hi, lo = g6_b2Lo }
    , v8 = { hi = g6_c2Hi, lo = g6_c2Lo }
    , v9 = { hi = g7_c2Hi, lo = g7_c2Lo }
    , v10 = { hi = g4_c2Hi, lo = g4_c2Lo }
    , v11 = { hi = g5_c2Hi, lo = g5_c2Lo }
    , v12 = { hi = g5_d2Hi, lo = g5_d2Lo }
    , v13 = { hi = g6_d2Hi, lo = g6_d2Lo }
    , v14 = { hi = g7_d2Hi, lo = g7_d2Lo }
    , v15 = { hi = g4_d2Hi, lo = g4_d2Lo }
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

        -- Round 0 (SIGMA[0] = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 })
        vR0 =
            round u64mb initV

        -- Round 1 (SIGMA[1] = { 14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3 })
        vR1 =
            round
                { m0 = u64mb.m14
                , m1 = u64mb.m10
                , m2 = u64mb.m4
                , m3 = u64mb.m8
                , m4 = u64mb.m9
                , m5 = u64mb.m15
                , m6 = u64mb.m13
                , m7 = u64mb.m6
                , m8 = u64mb.m1
                , m9 = u64mb.m12
                , m10 = u64mb.m0
                , m11 = u64mb.m2
                , m12 = u64mb.m11
                , m13 = u64mb.m7
                , m14 = u64mb.m5
                , m15 = u64mb.m3
                }
                vR0

        -- Round 2 (SIGMA[2] = { 11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4 })
        vR2 =
            round
                { m0 = u64mb.m11
                , m1 = u64mb.m8
                , m2 = u64mb.m12
                , m3 = u64mb.m0
                , m4 = u64mb.m5
                , m5 = u64mb.m2
                , m6 = u64mb.m15
                , m7 = u64mb.m13
                , m8 = u64mb.m10
                , m9 = u64mb.m14
                , m10 = u64mb.m3
                , m11 = u64mb.m6
                , m12 = u64mb.m7
                , m13 = u64mb.m1
                , m14 = u64mb.m9
                , m15 = u64mb.m4
                }
                vR1

        -- Round 3 (SIGMA[3] = { 7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8 })
        vR3 =
            round
                { m0 = u64mb.m7
                , m1 = u64mb.m9
                , m2 = u64mb.m3
                , m3 = u64mb.m1
                , m4 = u64mb.m13
                , m5 = u64mb.m12
                , m6 = u64mb.m11
                , m7 = u64mb.m14
                , m8 = u64mb.m2
                , m9 = u64mb.m6
                , m10 = u64mb.m5
                , m11 = u64mb.m10
                , m12 = u64mb.m4
                , m13 = u64mb.m0
                , m14 = u64mb.m15
                , m15 = u64mb.m8
                }
                vR2

        -- Round 4 (SIGMA[4] = { 9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13 })
        vR4 =
            round
                { m0 = u64mb.m9
                , m1 = u64mb.m0
                , m2 = u64mb.m5
                , m3 = u64mb.m7
                , m4 = u64mb.m2
                , m5 = u64mb.m4
                , m6 = u64mb.m10
                , m7 = u64mb.m15
                , m8 = u64mb.m14
                , m9 = u64mb.m1
                , m10 = u64mb.m11
                , m11 = u64mb.m12
                , m12 = u64mb.m6
                , m13 = u64mb.m8
                , m14 = u64mb.m3
                , m15 = u64mb.m13
                }
                vR3

        -- Round 5 (SIGMA[5] = { 2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9 })
        vR5 =
            round
                { m0 = u64mb.m2
                , m1 = u64mb.m12
                , m2 = u64mb.m6
                , m3 = u64mb.m10
                , m4 = u64mb.m0
                , m5 = u64mb.m11
                , m6 = u64mb.m8
                , m7 = u64mb.m3
                , m8 = u64mb.m4
                , m9 = u64mb.m13
                , m10 = u64mb.m7
                , m11 = u64mb.m5
                , m12 = u64mb.m15
                , m13 = u64mb.m14
                , m14 = u64mb.m1
                , m15 = u64mb.m9
                }
                vR4

        -- Round 6 (SIGMA[6] = { 12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11 })
        vR6 =
            round
                { m0 = u64mb.m12
                , m1 = u64mb.m5
                , m2 = u64mb.m1
                , m3 = u64mb.m15
                , m4 = u64mb.m14
                , m5 = u64mb.m13
                , m6 = u64mb.m4
                , m7 = u64mb.m10
                , m8 = u64mb.m0
                , m9 = u64mb.m7
                , m10 = u64mb.m6
                , m11 = u64mb.m3
                , m12 = u64mb.m9
                , m13 = u64mb.m2
                , m14 = u64mb.m8
                , m15 = u64mb.m11
                }
                vR5

        -- Round 7 (SIGMA[7] = { 13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10 })
        vR7 =
            round
                { m0 = u64mb.m13
                , m1 = u64mb.m11
                , m2 = u64mb.m7
                , m3 = u64mb.m14
                , m4 = u64mb.m12
                , m5 = u64mb.m1
                , m6 = u64mb.m3
                , m7 = u64mb.m9
                , m8 = u64mb.m5
                , m9 = u64mb.m0
                , m10 = u64mb.m15
                , m11 = u64mb.m4
                , m12 = u64mb.m8
                , m13 = u64mb.m6
                , m14 = u64mb.m2
                , m15 = u64mb.m10
                }
                vR6

        -- Round 8 (SIGMA[8] = { 6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5 })
        vR8 =
            round
                { m0 = u64mb.m6
                , m1 = u64mb.m15
                , m2 = u64mb.m14
                , m3 = u64mb.m9
                , m4 = u64mb.m11
                , m5 = u64mb.m3
                , m6 = u64mb.m0
                , m7 = u64mb.m8
                , m8 = u64mb.m12
                , m9 = u64mb.m2
                , m10 = u64mb.m13
                , m11 = u64mb.m7
                , m12 = u64mb.m1
                , m13 = u64mb.m4
                , m14 = u64mb.m10
                , m15 = u64mb.m5
                }
                vR7

        -- Round 9 (SIGMA[9] = { 10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0 })
        vR9 =
            round
                { m0 = u64mb.m10
                , m1 = u64mb.m2
                , m2 = u64mb.m8
                , m3 = u64mb.m4
                , m4 = u64mb.m7
                , m5 = u64mb.m6
                , m6 = u64mb.m1
                , m7 = u64mb.m5
                , m8 = u64mb.m15
                , m9 = u64mb.m11
                , m10 = u64mb.m9
                , m11 = u64mb.m14
                , m12 = u64mb.m3
                , m13 = u64mb.m12
                , m14 = u64mb.m13
                , m15 = u64mb.m0
                }
                vR8

        -- Round 10 (SIGMA[0] = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 })
        vR10 =
            round u64mb vR9

        -- Round 11 (SIGMA[1] = { 14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3 })
        vR11 =
            round
                { m0 = u64mb.m14
                , m1 = u64mb.m10
                , m2 = u64mb.m4
                , m3 = u64mb.m8
                , m4 = u64mb.m9
                , m5 = u64mb.m15
                , m6 = u64mb.m13
                , m7 = u64mb.m6
                , m8 = u64mb.m1
                , m9 = u64mb.m12
                , m10 = u64mb.m0
                , m11 = u64mb.m2
                , m12 = u64mb.m11
                , m13 = u64mb.m7
                , m14 = u64mb.m5
                , m15 = u64mb.m3
                }
                vR10
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
                        acc.t0Hi + counterCarry acc.t0Lo newT0Lo

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
                        acc.t0Hi + counterCarry acc.t0Lo newT0Lo
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
                        acc.t0Hi + counterCarry acc.t0Lo newT0Lo

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
