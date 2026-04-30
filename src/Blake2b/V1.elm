module Blake2b.V1 exposing (bytesToList, hash, hash224, hash256, hash512)

{-| Pure Elm BLAKE2b implementation (RFC 7693) optimized for V8 performance.

Changes in V6 (from V5):

  - Pre-pads input to a 128-byte boundary before entering the decode loop,
    so the loop always reads full blocks with blockDecoder. Eliminates the
    partial-block path that did padBlock (O(n) List.repeat) + Decode.decode
    (full re-decode). Uses u32-sized zero padding where possible (4x fewer
    list cons cells). ~9% faster on inputs with partial last blocks.
  - Hoists zero MessageBlock to module level for the empty-input path.

Changes in V5 (from V4):

  - Restructures blockDecoder into quarter-block sub-decoders (8 args each)
    to stay within Elm's F2..F9 fast path. Previous chained helpers had up
    to 28 arguments, creating ~55 curried closures per block decode.
  - Changes encodeDigest from 17 args to 2 (record-based). ~14% faster.

Changes in V4 (from V3):

  - Flattens all state types to raw hi/lo Int fields. WorkingVector goes from
    16 U64 record fields to 32 Int fields; HashState from 8 U64 to 16 Int.
    Eliminates U64MessageBlock entirely — round takes the raw MessageBlock
    (already 32 Int fields from Internal.Decode). This removes ~192 U64 record
    allocations per block (16 per round × 12 rounds) and eliminates nested
    field access (v.v0Hi instead of v.v0.hi). Sigma permutation constructs
    permuted MessageBlocks with 32 Int fields (just copying Int values).

Changes in V3 (from V2):

  - Consolidates 10 specialized round functions into a single round function.
    Sigma permutations applied at call site via permuted message blocks.

Changes in V2 (from V1):

  - Inlines G mixing function as raw hi/lo Int let-bindings (~55% faster).

Base (V1):

  - Bitwise carry detection in add64 (avoids polymorphic _Utils_cmp)
  - Hoists IV constructions to module level

-}

import Bitwise
import Blake2b.Constants exposing (iv0Hi, iv0Lo, iv1Hi, iv1Lo, iv2Hi, iv2Lo, iv3Hi, iv3Lo, iv4Hi, iv4Lo, iv5Hi, iv5Lo, iv6Hi, iv6Lo, iv7Hi, iv7Lo)
import Blake2b.DecodeV1 exposing (MessageBlock, blockDecoder, encodeDigest)
import Bytes exposing (Bytes, Endianness(..))
import Bytes.Decode as Decode
import Bytes.Encode as Encode



-- PRIMITIVE OPERATIONS


{-| Detect carry from adding a known increment to a 32-bit counter.
Given the old value and the new sum, returns 1 if overflow occurred, 0 otherwise.
-}
counterCarry : Int -> Int -> Int
counterCarry old new =
    Bitwise.shiftRightZfBy 31
        (Bitwise.and old (Bitwise.complement new))



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
-- Single round function with inlined G mixing. Sigma permutations are
-- applied by the caller, which passes a permuted MessageBlock.
-- The function always reads m0..m15 in fixed order for G0..G7.


round : MessageBlock -> WorkingVector -> WorkingVector
round mb v =
    let
        -- Column G0: a=v0, b=v4, c=v8, d=v12, x=m0, y=m1
        -- a1 = add64(add64(a, b), x)
        g0_abLo : Int
        g0_abLo =
            Bitwise.shiftRightZfBy 0 (v.v0Lo + v.v4Lo)

        g0_abCarry : Int
        g0_abCarry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and v.v0Lo v.v4Lo)
                    (Bitwise.and
                        (Bitwise.or v.v0Lo v.v4Lo)
                        (Bitwise.complement g0_abLo)
                    )
                )

        g0_abHi : Int
        g0_abHi =
            Bitwise.shiftRightZfBy 0 (v.v0Hi + v.v4Hi + g0_abCarry)

        g0_a1Lo : Int
        g0_a1Lo =
            Bitwise.shiftRightZfBy 0 (g0_abLo + mb.m0Lo)

        g0_a1Carry : Int
        g0_a1Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g0_abLo mb.m0Lo)
                    (Bitwise.and
                        (Bitwise.or g0_abLo mb.m0Lo)
                        (Bitwise.complement g0_a1Lo)
                    )
                )

        g0_a1Hi : Int
        g0_a1Hi =
            Bitwise.shiftRightZfBy 0 (g0_abHi + mb.m0Hi + g0_a1Carry)

        -- d1 = rotr32(xor64(d, a1))
        g0_d1Hi : Int
        g0_d1Hi =
            Bitwise.xor v.v12Lo g0_a1Lo

        g0_d1Lo : Int
        g0_d1Lo =
            Bitwise.xor v.v12Hi g0_a1Hi

        -- c1 = add64(c, d1)
        g0_c1Lo : Int
        g0_c1Lo =
            Bitwise.shiftRightZfBy 0 (v.v8Lo + g0_d1Lo)

        g0_c1Carry : Int
        g0_c1Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and v.v8Lo g0_d1Lo)
                    (Bitwise.and
                        (Bitwise.or v.v8Lo g0_d1Lo)
                        (Bitwise.complement g0_c1Lo)
                    )
                )

        g0_c1Hi : Int
        g0_c1Hi =
            Bitwise.shiftRightZfBy 0 (v.v8Hi + g0_d1Hi + g0_c1Carry)

        -- b1 = rotr24(xor64(b, c1))
        g0_b1xHi : Int
        g0_b1xHi =
            Bitwise.xor v.v4Hi g0_c1Hi

        g0_b1xLo : Int
        g0_b1xLo =
            Bitwise.xor v.v4Lo g0_c1Lo

        g0_b1Hi : Int
        g0_b1Hi =
            Bitwise.or (Bitwise.shiftRightZfBy 24 g0_b1xHi) (Bitwise.shiftLeftBy 8 g0_b1xLo)

        g0_b1Lo : Int
        g0_b1Lo =
            Bitwise.or (Bitwise.shiftRightZfBy 24 g0_b1xLo) (Bitwise.shiftLeftBy 8 g0_b1xHi)

        -- a2 = add64(add64(a1, b1), y)
        g0_a1b1Lo : Int
        g0_a1b1Lo =
            Bitwise.shiftRightZfBy 0 (g0_a1Lo + g0_b1Lo)

        g0_a1b1Carry : Int
        g0_a1b1Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g0_a1Lo g0_b1Lo)
                    (Bitwise.and
                        (Bitwise.or g0_a1Lo g0_b1Lo)
                        (Bitwise.complement g0_a1b1Lo)
                    )
                )

        g0_a1b1Hi : Int
        g0_a1b1Hi =
            Bitwise.shiftRightZfBy 0 (g0_a1Hi + g0_b1Hi + g0_a1b1Carry)

        g0_a2Lo : Int
        g0_a2Lo =
            Bitwise.shiftRightZfBy 0 (g0_a1b1Lo + mb.m1Lo)

        g0_a2Carry : Int
        g0_a2Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g0_a1b1Lo mb.m1Lo)
                    (Bitwise.and
                        (Bitwise.or g0_a1b1Lo mb.m1Lo)
                        (Bitwise.complement g0_a2Lo)
                    )
                )

        g0_a2Hi : Int
        g0_a2Hi =
            Bitwise.shiftRightZfBy 0 (g0_a1b1Hi + mb.m1Hi + g0_a2Carry)

        -- d2 = rotr16(xor64(d1, a2))
        g0_d2xHi : Int
        g0_d2xHi =
            Bitwise.xor g0_d1Hi g0_a2Hi

        g0_d2xLo : Int
        g0_d2xLo =
            Bitwise.xor g0_d1Lo g0_a2Lo

        g0_d2Hi : Int
        g0_d2Hi =
            Bitwise.or (Bitwise.shiftRightZfBy 16 g0_d2xHi) (Bitwise.shiftLeftBy 16 g0_d2xLo)

        g0_d2Lo : Int
        g0_d2Lo =
            Bitwise.or (Bitwise.shiftRightZfBy 16 g0_d2xLo) (Bitwise.shiftLeftBy 16 g0_d2xHi)

        -- c2 = add64(c1, d2)
        g0_c2Lo : Int
        g0_c2Lo =
            Bitwise.shiftRightZfBy 0 (g0_c1Lo + g0_d2Lo)

        g0_c2Carry : Int
        g0_c2Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g0_c1Lo g0_d2Lo)
                    (Bitwise.and
                        (Bitwise.or g0_c1Lo g0_d2Lo)
                        (Bitwise.complement g0_c2Lo)
                    )
                )

        g0_c2Hi : Int
        g0_c2Hi =
            Bitwise.shiftRightZfBy 0 (g0_c1Hi + g0_d2Hi + g0_c2Carry)

        -- b2 = rotr63(xor64(b1, c2))
        g0_b2xHi : Int
        g0_b2xHi =
            Bitwise.xor g0_b1Hi g0_c2Hi

        g0_b2xLo : Int
        g0_b2xLo =
            Bitwise.xor g0_b1Lo g0_c2Lo

        g0_b2Hi : Int
        g0_b2Hi =
            Bitwise.or (Bitwise.shiftLeftBy 1 g0_b2xHi) (Bitwise.shiftRightZfBy 31 g0_b2xLo)

        g0_b2Lo : Int
        g0_b2Lo =
            Bitwise.or (Bitwise.shiftLeftBy 1 g0_b2xLo) (Bitwise.shiftRightZfBy 31 g0_b2xHi)

        -- Column G1: a=v1, b=v5, c=v9, d=v13, x=m2, y=m3
        -- a1 = add64(add64(a, b), x)
        g1_abLo : Int
        g1_abLo =
            Bitwise.shiftRightZfBy 0 (v.v1Lo + v.v5Lo)

        g1_abCarry : Int
        g1_abCarry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and v.v1Lo v.v5Lo)
                    (Bitwise.and
                        (Bitwise.or v.v1Lo v.v5Lo)
                        (Bitwise.complement g1_abLo)
                    )
                )

        g1_abHi : Int
        g1_abHi =
            Bitwise.shiftRightZfBy 0 (v.v1Hi + v.v5Hi + g1_abCarry)

        g1_a1Lo : Int
        g1_a1Lo =
            Bitwise.shiftRightZfBy 0 (g1_abLo + mb.m2Lo)

        g1_a1Carry : Int
        g1_a1Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g1_abLo mb.m2Lo)
                    (Bitwise.and
                        (Bitwise.or g1_abLo mb.m2Lo)
                        (Bitwise.complement g1_a1Lo)
                    )
                )

        g1_a1Hi : Int
        g1_a1Hi =
            Bitwise.shiftRightZfBy 0 (g1_abHi + mb.m2Hi + g1_a1Carry)

        -- d1 = rotr32(xor64(d, a1))
        g1_d1Hi : Int
        g1_d1Hi =
            Bitwise.xor v.v13Lo g1_a1Lo

        g1_d1Lo : Int
        g1_d1Lo =
            Bitwise.xor v.v13Hi g1_a1Hi

        -- c1 = add64(c, d1)
        g1_c1Lo : Int
        g1_c1Lo =
            Bitwise.shiftRightZfBy 0 (v.v9Lo + g1_d1Lo)

        g1_c1Carry : Int
        g1_c1Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and v.v9Lo g1_d1Lo)
                    (Bitwise.and
                        (Bitwise.or v.v9Lo g1_d1Lo)
                        (Bitwise.complement g1_c1Lo)
                    )
                )

        g1_c1Hi : Int
        g1_c1Hi =
            Bitwise.shiftRightZfBy 0 (v.v9Hi + g1_d1Hi + g1_c1Carry)

        -- b1 = rotr24(xor64(b, c1))
        g1_b1xHi : Int
        g1_b1xHi =
            Bitwise.xor v.v5Hi g1_c1Hi

        g1_b1xLo : Int
        g1_b1xLo =
            Bitwise.xor v.v5Lo g1_c1Lo

        g1_b1Hi : Int
        g1_b1Hi =
            Bitwise.or (Bitwise.shiftRightZfBy 24 g1_b1xHi) (Bitwise.shiftLeftBy 8 g1_b1xLo)

        g1_b1Lo : Int
        g1_b1Lo =
            Bitwise.or (Bitwise.shiftRightZfBy 24 g1_b1xLo) (Bitwise.shiftLeftBy 8 g1_b1xHi)

        -- a2 = add64(add64(a1, b1), y)
        g1_a1b1Lo : Int
        g1_a1b1Lo =
            Bitwise.shiftRightZfBy 0 (g1_a1Lo + g1_b1Lo)

        g1_a1b1Carry : Int
        g1_a1b1Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g1_a1Lo g1_b1Lo)
                    (Bitwise.and
                        (Bitwise.or g1_a1Lo g1_b1Lo)
                        (Bitwise.complement g1_a1b1Lo)
                    )
                )

        g1_a1b1Hi : Int
        g1_a1b1Hi =
            Bitwise.shiftRightZfBy 0 (g1_a1Hi + g1_b1Hi + g1_a1b1Carry)

        g1_a2Lo : Int
        g1_a2Lo =
            Bitwise.shiftRightZfBy 0 (g1_a1b1Lo + mb.m3Lo)

        g1_a2Carry : Int
        g1_a2Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g1_a1b1Lo mb.m3Lo)
                    (Bitwise.and
                        (Bitwise.or g1_a1b1Lo mb.m3Lo)
                        (Bitwise.complement g1_a2Lo)
                    )
                )

        g1_a2Hi : Int
        g1_a2Hi =
            Bitwise.shiftRightZfBy 0 (g1_a1b1Hi + mb.m3Hi + g1_a2Carry)

        -- d2 = rotr16(xor64(d1, a2))
        g1_d2xHi : Int
        g1_d2xHi =
            Bitwise.xor g1_d1Hi g1_a2Hi

        g1_d2xLo : Int
        g1_d2xLo =
            Bitwise.xor g1_d1Lo g1_a2Lo

        g1_d2Hi : Int
        g1_d2Hi =
            Bitwise.or (Bitwise.shiftRightZfBy 16 g1_d2xHi) (Bitwise.shiftLeftBy 16 g1_d2xLo)

        g1_d2Lo : Int
        g1_d2Lo =
            Bitwise.or (Bitwise.shiftRightZfBy 16 g1_d2xLo) (Bitwise.shiftLeftBy 16 g1_d2xHi)

        -- c2 = add64(c1, d2)
        g1_c2Lo : Int
        g1_c2Lo =
            Bitwise.shiftRightZfBy 0 (g1_c1Lo + g1_d2Lo)

        g1_c2Carry : Int
        g1_c2Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g1_c1Lo g1_d2Lo)
                    (Bitwise.and
                        (Bitwise.or g1_c1Lo g1_d2Lo)
                        (Bitwise.complement g1_c2Lo)
                    )
                )

        g1_c2Hi : Int
        g1_c2Hi =
            Bitwise.shiftRightZfBy 0 (g1_c1Hi + g1_d2Hi + g1_c2Carry)

        -- b2 = rotr63(xor64(b1, c2))
        g1_b2xHi : Int
        g1_b2xHi =
            Bitwise.xor g1_b1Hi g1_c2Hi

        g1_b2xLo : Int
        g1_b2xLo =
            Bitwise.xor g1_b1Lo g1_c2Lo

        g1_b2Hi : Int
        g1_b2Hi =
            Bitwise.or (Bitwise.shiftLeftBy 1 g1_b2xHi) (Bitwise.shiftRightZfBy 31 g1_b2xLo)

        g1_b2Lo : Int
        g1_b2Lo =
            Bitwise.or (Bitwise.shiftLeftBy 1 g1_b2xLo) (Bitwise.shiftRightZfBy 31 g1_b2xHi)

        -- Column G2: a=v2, b=v6, c=v10, d=v14, x=m4, y=m5
        -- a1 = add64(add64(a, b), x)
        g2_abLo : Int
        g2_abLo =
            Bitwise.shiftRightZfBy 0 (v.v2Lo + v.v6Lo)

        g2_abCarry : Int
        g2_abCarry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and v.v2Lo v.v6Lo)
                    (Bitwise.and
                        (Bitwise.or v.v2Lo v.v6Lo)
                        (Bitwise.complement g2_abLo)
                    )
                )

        g2_abHi : Int
        g2_abHi =
            Bitwise.shiftRightZfBy 0 (v.v2Hi + v.v6Hi + g2_abCarry)

        g2_a1Lo : Int
        g2_a1Lo =
            Bitwise.shiftRightZfBy 0 (g2_abLo + mb.m4Lo)

        g2_a1Carry : Int
        g2_a1Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g2_abLo mb.m4Lo)
                    (Bitwise.and
                        (Bitwise.or g2_abLo mb.m4Lo)
                        (Bitwise.complement g2_a1Lo)
                    )
                )

        g2_a1Hi : Int
        g2_a1Hi =
            Bitwise.shiftRightZfBy 0 (g2_abHi + mb.m4Hi + g2_a1Carry)

        -- d1 = rotr32(xor64(d, a1))
        g2_d1Hi : Int
        g2_d1Hi =
            Bitwise.xor v.v14Lo g2_a1Lo

        g2_d1Lo : Int
        g2_d1Lo =
            Bitwise.xor v.v14Hi g2_a1Hi

        -- c1 = add64(c, d1)
        g2_c1Lo : Int
        g2_c1Lo =
            Bitwise.shiftRightZfBy 0 (v.v10Lo + g2_d1Lo)

        g2_c1Carry : Int
        g2_c1Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and v.v10Lo g2_d1Lo)
                    (Bitwise.and
                        (Bitwise.or v.v10Lo g2_d1Lo)
                        (Bitwise.complement g2_c1Lo)
                    )
                )

        g2_c1Hi : Int
        g2_c1Hi =
            Bitwise.shiftRightZfBy 0 (v.v10Hi + g2_d1Hi + g2_c1Carry)

        -- b1 = rotr24(xor64(b, c1))
        g2_b1xHi : Int
        g2_b1xHi =
            Bitwise.xor v.v6Hi g2_c1Hi

        g2_b1xLo : Int
        g2_b1xLo =
            Bitwise.xor v.v6Lo g2_c1Lo

        g2_b1Hi : Int
        g2_b1Hi =
            Bitwise.or (Bitwise.shiftRightZfBy 24 g2_b1xHi) (Bitwise.shiftLeftBy 8 g2_b1xLo)

        g2_b1Lo : Int
        g2_b1Lo =
            Bitwise.or (Bitwise.shiftRightZfBy 24 g2_b1xLo) (Bitwise.shiftLeftBy 8 g2_b1xHi)

        -- a2 = add64(add64(a1, b1), y)
        g2_a1b1Lo : Int
        g2_a1b1Lo =
            Bitwise.shiftRightZfBy 0 (g2_a1Lo + g2_b1Lo)

        g2_a1b1Carry : Int
        g2_a1b1Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g2_a1Lo g2_b1Lo)
                    (Bitwise.and
                        (Bitwise.or g2_a1Lo g2_b1Lo)
                        (Bitwise.complement g2_a1b1Lo)
                    )
                )

        g2_a1b1Hi : Int
        g2_a1b1Hi =
            Bitwise.shiftRightZfBy 0 (g2_a1Hi + g2_b1Hi + g2_a1b1Carry)

        g2_a2Lo : Int
        g2_a2Lo =
            Bitwise.shiftRightZfBy 0 (g2_a1b1Lo + mb.m5Lo)

        g2_a2Carry : Int
        g2_a2Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g2_a1b1Lo mb.m5Lo)
                    (Bitwise.and
                        (Bitwise.or g2_a1b1Lo mb.m5Lo)
                        (Bitwise.complement g2_a2Lo)
                    )
                )

        g2_a2Hi : Int
        g2_a2Hi =
            Bitwise.shiftRightZfBy 0 (g2_a1b1Hi + mb.m5Hi + g2_a2Carry)

        -- d2 = rotr16(xor64(d1, a2))
        g2_d2xHi : Int
        g2_d2xHi =
            Bitwise.xor g2_d1Hi g2_a2Hi

        g2_d2xLo : Int
        g2_d2xLo =
            Bitwise.xor g2_d1Lo g2_a2Lo

        g2_d2Hi : Int
        g2_d2Hi =
            Bitwise.or (Bitwise.shiftRightZfBy 16 g2_d2xHi) (Bitwise.shiftLeftBy 16 g2_d2xLo)

        g2_d2Lo : Int
        g2_d2Lo =
            Bitwise.or (Bitwise.shiftRightZfBy 16 g2_d2xLo) (Bitwise.shiftLeftBy 16 g2_d2xHi)

        -- c2 = add64(c1, d2)
        g2_c2Lo : Int
        g2_c2Lo =
            Bitwise.shiftRightZfBy 0 (g2_c1Lo + g2_d2Lo)

        g2_c2Carry : Int
        g2_c2Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g2_c1Lo g2_d2Lo)
                    (Bitwise.and
                        (Bitwise.or g2_c1Lo g2_d2Lo)
                        (Bitwise.complement g2_c2Lo)
                    )
                )

        g2_c2Hi : Int
        g2_c2Hi =
            Bitwise.shiftRightZfBy 0 (g2_c1Hi + g2_d2Hi + g2_c2Carry)

        -- b2 = rotr63(xor64(b1, c2))
        g2_b2xHi : Int
        g2_b2xHi =
            Bitwise.xor g2_b1Hi g2_c2Hi

        g2_b2xLo : Int
        g2_b2xLo =
            Bitwise.xor g2_b1Lo g2_c2Lo

        g2_b2Hi : Int
        g2_b2Hi =
            Bitwise.or (Bitwise.shiftLeftBy 1 g2_b2xHi) (Bitwise.shiftRightZfBy 31 g2_b2xLo)

        g2_b2Lo : Int
        g2_b2Lo =
            Bitwise.or (Bitwise.shiftLeftBy 1 g2_b2xLo) (Bitwise.shiftRightZfBy 31 g2_b2xHi)

        -- Column G3: a=v3, b=v7, c=v11, d=v15, x=m6, y=m7
        -- a1 = add64(add64(a, b), x)
        g3_abLo : Int
        g3_abLo =
            Bitwise.shiftRightZfBy 0 (v.v3Lo + v.v7Lo)

        g3_abCarry : Int
        g3_abCarry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and v.v3Lo v.v7Lo)
                    (Bitwise.and
                        (Bitwise.or v.v3Lo v.v7Lo)
                        (Bitwise.complement g3_abLo)
                    )
                )

        g3_abHi : Int
        g3_abHi =
            Bitwise.shiftRightZfBy 0 (v.v3Hi + v.v7Hi + g3_abCarry)

        g3_a1Lo : Int
        g3_a1Lo =
            Bitwise.shiftRightZfBy 0 (g3_abLo + mb.m6Lo)

        g3_a1Carry : Int
        g3_a1Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g3_abLo mb.m6Lo)
                    (Bitwise.and
                        (Bitwise.or g3_abLo mb.m6Lo)
                        (Bitwise.complement g3_a1Lo)
                    )
                )

        g3_a1Hi : Int
        g3_a1Hi =
            Bitwise.shiftRightZfBy 0 (g3_abHi + mb.m6Hi + g3_a1Carry)

        -- d1 = rotr32(xor64(d, a1))
        g3_d1Hi : Int
        g3_d1Hi =
            Bitwise.xor v.v15Lo g3_a1Lo

        g3_d1Lo : Int
        g3_d1Lo =
            Bitwise.xor v.v15Hi g3_a1Hi

        -- c1 = add64(c, d1)
        g3_c1Lo : Int
        g3_c1Lo =
            Bitwise.shiftRightZfBy 0 (v.v11Lo + g3_d1Lo)

        g3_c1Carry : Int
        g3_c1Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and v.v11Lo g3_d1Lo)
                    (Bitwise.and
                        (Bitwise.or v.v11Lo g3_d1Lo)
                        (Bitwise.complement g3_c1Lo)
                    )
                )

        g3_c1Hi : Int
        g3_c1Hi =
            Bitwise.shiftRightZfBy 0 (v.v11Hi + g3_d1Hi + g3_c1Carry)

        -- b1 = rotr24(xor64(b, c1))
        g3_b1xHi : Int
        g3_b1xHi =
            Bitwise.xor v.v7Hi g3_c1Hi

        g3_b1xLo : Int
        g3_b1xLo =
            Bitwise.xor v.v7Lo g3_c1Lo

        g3_b1Hi : Int
        g3_b1Hi =
            Bitwise.or (Bitwise.shiftRightZfBy 24 g3_b1xHi) (Bitwise.shiftLeftBy 8 g3_b1xLo)

        g3_b1Lo : Int
        g3_b1Lo =
            Bitwise.or (Bitwise.shiftRightZfBy 24 g3_b1xLo) (Bitwise.shiftLeftBy 8 g3_b1xHi)

        -- a2 = add64(add64(a1, b1), y)
        g3_a1b1Lo : Int
        g3_a1b1Lo =
            Bitwise.shiftRightZfBy 0 (g3_a1Lo + g3_b1Lo)

        g3_a1b1Carry : Int
        g3_a1b1Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g3_a1Lo g3_b1Lo)
                    (Bitwise.and
                        (Bitwise.or g3_a1Lo g3_b1Lo)
                        (Bitwise.complement g3_a1b1Lo)
                    )
                )

        g3_a1b1Hi : Int
        g3_a1b1Hi =
            Bitwise.shiftRightZfBy 0 (g3_a1Hi + g3_b1Hi + g3_a1b1Carry)

        g3_a2Lo : Int
        g3_a2Lo =
            Bitwise.shiftRightZfBy 0 (g3_a1b1Lo + mb.m7Lo)

        g3_a2Carry : Int
        g3_a2Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g3_a1b1Lo mb.m7Lo)
                    (Bitwise.and
                        (Bitwise.or g3_a1b1Lo mb.m7Lo)
                        (Bitwise.complement g3_a2Lo)
                    )
                )

        g3_a2Hi : Int
        g3_a2Hi =
            Bitwise.shiftRightZfBy 0 (g3_a1b1Hi + mb.m7Hi + g3_a2Carry)

        -- d2 = rotr16(xor64(d1, a2))
        g3_d2xHi : Int
        g3_d2xHi =
            Bitwise.xor g3_d1Hi g3_a2Hi

        g3_d2xLo : Int
        g3_d2xLo =
            Bitwise.xor g3_d1Lo g3_a2Lo

        g3_d2Hi : Int
        g3_d2Hi =
            Bitwise.or (Bitwise.shiftRightZfBy 16 g3_d2xHi) (Bitwise.shiftLeftBy 16 g3_d2xLo)

        g3_d2Lo : Int
        g3_d2Lo =
            Bitwise.or (Bitwise.shiftRightZfBy 16 g3_d2xLo) (Bitwise.shiftLeftBy 16 g3_d2xHi)

        -- c2 = add64(c1, d2)
        g3_c2Lo : Int
        g3_c2Lo =
            Bitwise.shiftRightZfBy 0 (g3_c1Lo + g3_d2Lo)

        g3_c2Carry : Int
        g3_c2Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g3_c1Lo g3_d2Lo)
                    (Bitwise.and
                        (Bitwise.or g3_c1Lo g3_d2Lo)
                        (Bitwise.complement g3_c2Lo)
                    )
                )

        g3_c2Hi : Int
        g3_c2Hi =
            Bitwise.shiftRightZfBy 0 (g3_c1Hi + g3_d2Hi + g3_c2Carry)

        -- b2 = rotr63(xor64(b1, c2))
        g3_b2xHi : Int
        g3_b2xHi =
            Bitwise.xor g3_b1Hi g3_c2Hi

        g3_b2xLo : Int
        g3_b2xLo =
            Bitwise.xor g3_b1Lo g3_c2Lo

        g3_b2Hi : Int
        g3_b2Hi =
            Bitwise.or (Bitwise.shiftLeftBy 1 g3_b2xHi) (Bitwise.shiftRightZfBy 31 g3_b2xLo)

        g3_b2Lo : Int
        g3_b2Lo =
            Bitwise.or (Bitwise.shiftLeftBy 1 g3_b2xLo) (Bitwise.shiftRightZfBy 31 g3_b2xHi)

        -- Diagonal G4: a=g0.a, b=g1.b, c=g2.c, d=g3.d, x=m8, y=m9
        -- a1 = add64(add64(a, b), x)
        g4_abLo : Int
        g4_abLo =
            Bitwise.shiftRightZfBy 0 (g0_a2Lo + g1_b2Lo)

        g4_abCarry : Int
        g4_abCarry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g0_a2Lo g1_b2Lo)
                    (Bitwise.and
                        (Bitwise.or g0_a2Lo g1_b2Lo)
                        (Bitwise.complement g4_abLo)
                    )
                )

        g4_abHi : Int
        g4_abHi =
            Bitwise.shiftRightZfBy 0 (g0_a2Hi + g1_b2Hi + g4_abCarry)

        g4_a1Lo : Int
        g4_a1Lo =
            Bitwise.shiftRightZfBy 0 (g4_abLo + mb.m8Lo)

        g4_a1Carry : Int
        g4_a1Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g4_abLo mb.m8Lo)
                    (Bitwise.and
                        (Bitwise.or g4_abLo mb.m8Lo)
                        (Bitwise.complement g4_a1Lo)
                    )
                )

        g4_a1Hi : Int
        g4_a1Hi =
            Bitwise.shiftRightZfBy 0 (g4_abHi + mb.m8Hi + g4_a1Carry)

        -- d1 = rotr32(xor64(d, a1))
        g4_d1Hi : Int
        g4_d1Hi =
            Bitwise.xor g3_d2Lo g4_a1Lo

        g4_d1Lo : Int
        g4_d1Lo =
            Bitwise.xor g3_d2Hi g4_a1Hi

        -- c1 = add64(c, d1)
        g4_c1Lo : Int
        g4_c1Lo =
            Bitwise.shiftRightZfBy 0 (g2_c2Lo + g4_d1Lo)

        g4_c1Carry : Int
        g4_c1Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g2_c2Lo g4_d1Lo)
                    (Bitwise.and
                        (Bitwise.or g2_c2Lo g4_d1Lo)
                        (Bitwise.complement g4_c1Lo)
                    )
                )

        g4_c1Hi : Int
        g4_c1Hi =
            Bitwise.shiftRightZfBy 0 (g2_c2Hi + g4_d1Hi + g4_c1Carry)

        -- b1 = rotr24(xor64(b, c1))
        g4_b1xHi : Int
        g4_b1xHi =
            Bitwise.xor g1_b2Hi g4_c1Hi

        g4_b1xLo : Int
        g4_b1xLo =
            Bitwise.xor g1_b2Lo g4_c1Lo

        g4_b1Hi : Int
        g4_b1Hi =
            Bitwise.or (Bitwise.shiftRightZfBy 24 g4_b1xHi) (Bitwise.shiftLeftBy 8 g4_b1xLo)

        g4_b1Lo : Int
        g4_b1Lo =
            Bitwise.or (Bitwise.shiftRightZfBy 24 g4_b1xLo) (Bitwise.shiftLeftBy 8 g4_b1xHi)

        -- a2 = add64(add64(a1, b1), y)
        g4_a1b1Lo : Int
        g4_a1b1Lo =
            Bitwise.shiftRightZfBy 0 (g4_a1Lo + g4_b1Lo)

        g4_a1b1Carry : Int
        g4_a1b1Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g4_a1Lo g4_b1Lo)
                    (Bitwise.and
                        (Bitwise.or g4_a1Lo g4_b1Lo)
                        (Bitwise.complement g4_a1b1Lo)
                    )
                )

        g4_a1b1Hi : Int
        g4_a1b1Hi =
            Bitwise.shiftRightZfBy 0 (g4_a1Hi + g4_b1Hi + g4_a1b1Carry)

        g4_a2Lo : Int
        g4_a2Lo =
            Bitwise.shiftRightZfBy 0 (g4_a1b1Lo + mb.m9Lo)

        g4_a2Carry : Int
        g4_a2Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g4_a1b1Lo mb.m9Lo)
                    (Bitwise.and
                        (Bitwise.or g4_a1b1Lo mb.m9Lo)
                        (Bitwise.complement g4_a2Lo)
                    )
                )

        g4_a2Hi : Int
        g4_a2Hi =
            Bitwise.shiftRightZfBy 0 (g4_a1b1Hi + mb.m9Hi + g4_a2Carry)

        -- d2 = rotr16(xor64(d1, a2))
        g4_d2xHi : Int
        g4_d2xHi =
            Bitwise.xor g4_d1Hi g4_a2Hi

        g4_d2xLo : Int
        g4_d2xLo =
            Bitwise.xor g4_d1Lo g4_a2Lo

        g4_d2Hi : Int
        g4_d2Hi =
            Bitwise.or (Bitwise.shiftRightZfBy 16 g4_d2xHi) (Bitwise.shiftLeftBy 16 g4_d2xLo)

        g4_d2Lo : Int
        g4_d2Lo =
            Bitwise.or (Bitwise.shiftRightZfBy 16 g4_d2xLo) (Bitwise.shiftLeftBy 16 g4_d2xHi)

        -- c2 = add64(c1, d2)
        g4_c2Lo : Int
        g4_c2Lo =
            Bitwise.shiftRightZfBy 0 (g4_c1Lo + g4_d2Lo)

        g4_c2Carry : Int
        g4_c2Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g4_c1Lo g4_d2Lo)
                    (Bitwise.and
                        (Bitwise.or g4_c1Lo g4_d2Lo)
                        (Bitwise.complement g4_c2Lo)
                    )
                )

        g4_c2Hi : Int
        g4_c2Hi =
            Bitwise.shiftRightZfBy 0 (g4_c1Hi + g4_d2Hi + g4_c2Carry)

        -- b2 = rotr63(xor64(b1, c2))
        g4_b2xHi : Int
        g4_b2xHi =
            Bitwise.xor g4_b1Hi g4_c2Hi

        g4_b2xLo : Int
        g4_b2xLo =
            Bitwise.xor g4_b1Lo g4_c2Lo

        g4_b2Hi : Int
        g4_b2Hi =
            Bitwise.or (Bitwise.shiftLeftBy 1 g4_b2xHi) (Bitwise.shiftRightZfBy 31 g4_b2xLo)

        g4_b2Lo : Int
        g4_b2Lo =
            Bitwise.or (Bitwise.shiftLeftBy 1 g4_b2xLo) (Bitwise.shiftRightZfBy 31 g4_b2xHi)

        -- Diagonal G5: a=g1.a, b=g2.b, c=g3.c, d=g0.d, x=m10, y=m11
        -- a1 = add64(add64(a, b), x)
        g5_abLo : Int
        g5_abLo =
            Bitwise.shiftRightZfBy 0 (g1_a2Lo + g2_b2Lo)

        g5_abCarry : Int
        g5_abCarry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g1_a2Lo g2_b2Lo)
                    (Bitwise.and
                        (Bitwise.or g1_a2Lo g2_b2Lo)
                        (Bitwise.complement g5_abLo)
                    )
                )

        g5_abHi : Int
        g5_abHi =
            Bitwise.shiftRightZfBy 0 (g1_a2Hi + g2_b2Hi + g5_abCarry)

        g5_a1Lo : Int
        g5_a1Lo =
            Bitwise.shiftRightZfBy 0 (g5_abLo + mb.m10Lo)

        g5_a1Carry : Int
        g5_a1Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g5_abLo mb.m10Lo)
                    (Bitwise.and
                        (Bitwise.or g5_abLo mb.m10Lo)
                        (Bitwise.complement g5_a1Lo)
                    )
                )

        g5_a1Hi : Int
        g5_a1Hi =
            Bitwise.shiftRightZfBy 0 (g5_abHi + mb.m10Hi + g5_a1Carry)

        -- d1 = rotr32(xor64(d, a1))
        g5_d1Hi : Int
        g5_d1Hi =
            Bitwise.xor g0_d2Lo g5_a1Lo

        g5_d1Lo : Int
        g5_d1Lo =
            Bitwise.xor g0_d2Hi g5_a1Hi

        -- c1 = add64(c, d1)
        g5_c1Lo : Int
        g5_c1Lo =
            Bitwise.shiftRightZfBy 0 (g3_c2Lo + g5_d1Lo)

        g5_c1Carry : Int
        g5_c1Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g3_c2Lo g5_d1Lo)
                    (Bitwise.and
                        (Bitwise.or g3_c2Lo g5_d1Lo)
                        (Bitwise.complement g5_c1Lo)
                    )
                )

        g5_c1Hi : Int
        g5_c1Hi =
            Bitwise.shiftRightZfBy 0 (g3_c2Hi + g5_d1Hi + g5_c1Carry)

        -- b1 = rotr24(xor64(b, c1))
        g5_b1xHi : Int
        g5_b1xHi =
            Bitwise.xor g2_b2Hi g5_c1Hi

        g5_b1xLo : Int
        g5_b1xLo =
            Bitwise.xor g2_b2Lo g5_c1Lo

        g5_b1Hi : Int
        g5_b1Hi =
            Bitwise.or (Bitwise.shiftRightZfBy 24 g5_b1xHi) (Bitwise.shiftLeftBy 8 g5_b1xLo)

        g5_b1Lo : Int
        g5_b1Lo =
            Bitwise.or (Bitwise.shiftRightZfBy 24 g5_b1xLo) (Bitwise.shiftLeftBy 8 g5_b1xHi)

        -- a2 = add64(add64(a1, b1), y)
        g5_a1b1Lo : Int
        g5_a1b1Lo =
            Bitwise.shiftRightZfBy 0 (g5_a1Lo + g5_b1Lo)

        g5_a1b1Carry : Int
        g5_a1b1Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g5_a1Lo g5_b1Lo)
                    (Bitwise.and
                        (Bitwise.or g5_a1Lo g5_b1Lo)
                        (Bitwise.complement g5_a1b1Lo)
                    )
                )

        g5_a1b1Hi : Int
        g5_a1b1Hi =
            Bitwise.shiftRightZfBy 0 (g5_a1Hi + g5_b1Hi + g5_a1b1Carry)

        g5_a2Lo : Int
        g5_a2Lo =
            Bitwise.shiftRightZfBy 0 (g5_a1b1Lo + mb.m11Lo)

        g5_a2Carry : Int
        g5_a2Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g5_a1b1Lo mb.m11Lo)
                    (Bitwise.and
                        (Bitwise.or g5_a1b1Lo mb.m11Lo)
                        (Bitwise.complement g5_a2Lo)
                    )
                )

        g5_a2Hi : Int
        g5_a2Hi =
            Bitwise.shiftRightZfBy 0 (g5_a1b1Hi + mb.m11Hi + g5_a2Carry)

        -- d2 = rotr16(xor64(d1, a2))
        g5_d2xHi : Int
        g5_d2xHi =
            Bitwise.xor g5_d1Hi g5_a2Hi

        g5_d2xLo : Int
        g5_d2xLo =
            Bitwise.xor g5_d1Lo g5_a2Lo

        g5_d2Hi : Int
        g5_d2Hi =
            Bitwise.or (Bitwise.shiftRightZfBy 16 g5_d2xHi) (Bitwise.shiftLeftBy 16 g5_d2xLo)

        g5_d2Lo : Int
        g5_d2Lo =
            Bitwise.or (Bitwise.shiftRightZfBy 16 g5_d2xLo) (Bitwise.shiftLeftBy 16 g5_d2xHi)

        -- c2 = add64(c1, d2)
        g5_c2Lo : Int
        g5_c2Lo =
            Bitwise.shiftRightZfBy 0 (g5_c1Lo + g5_d2Lo)

        g5_c2Carry : Int
        g5_c2Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g5_c1Lo g5_d2Lo)
                    (Bitwise.and
                        (Bitwise.or g5_c1Lo g5_d2Lo)
                        (Bitwise.complement g5_c2Lo)
                    )
                )

        g5_c2Hi : Int
        g5_c2Hi =
            Bitwise.shiftRightZfBy 0 (g5_c1Hi + g5_d2Hi + g5_c2Carry)

        -- b2 = rotr63(xor64(b1, c2))
        g5_b2xHi : Int
        g5_b2xHi =
            Bitwise.xor g5_b1Hi g5_c2Hi

        g5_b2xLo : Int
        g5_b2xLo =
            Bitwise.xor g5_b1Lo g5_c2Lo

        g5_b2Hi : Int
        g5_b2Hi =
            Bitwise.or (Bitwise.shiftLeftBy 1 g5_b2xHi) (Bitwise.shiftRightZfBy 31 g5_b2xLo)

        g5_b2Lo : Int
        g5_b2Lo =
            Bitwise.or (Bitwise.shiftLeftBy 1 g5_b2xLo) (Bitwise.shiftRightZfBy 31 g5_b2xHi)

        -- Diagonal G6: a=g2.a, b=g3.b, c=g0.c, d=g1.d, x=m12, y=m13
        -- a1 = add64(add64(a, b), x)
        g6_abLo : Int
        g6_abLo =
            Bitwise.shiftRightZfBy 0 (g2_a2Lo + g3_b2Lo)

        g6_abCarry : Int
        g6_abCarry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g2_a2Lo g3_b2Lo)
                    (Bitwise.and
                        (Bitwise.or g2_a2Lo g3_b2Lo)
                        (Bitwise.complement g6_abLo)
                    )
                )

        g6_abHi : Int
        g6_abHi =
            Bitwise.shiftRightZfBy 0 (g2_a2Hi + g3_b2Hi + g6_abCarry)

        g6_a1Lo : Int
        g6_a1Lo =
            Bitwise.shiftRightZfBy 0 (g6_abLo + mb.m12Lo)

        g6_a1Carry : Int
        g6_a1Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g6_abLo mb.m12Lo)
                    (Bitwise.and
                        (Bitwise.or g6_abLo mb.m12Lo)
                        (Bitwise.complement g6_a1Lo)
                    )
                )

        g6_a1Hi : Int
        g6_a1Hi =
            Bitwise.shiftRightZfBy 0 (g6_abHi + mb.m12Hi + g6_a1Carry)

        -- d1 = rotr32(xor64(d, a1))
        g6_d1Hi : Int
        g6_d1Hi =
            Bitwise.xor g1_d2Lo g6_a1Lo

        g6_d1Lo : Int
        g6_d1Lo =
            Bitwise.xor g1_d2Hi g6_a1Hi

        -- c1 = add64(c, d1)
        g6_c1Lo : Int
        g6_c1Lo =
            Bitwise.shiftRightZfBy 0 (g0_c2Lo + g6_d1Lo)

        g6_c1Carry : Int
        g6_c1Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g0_c2Lo g6_d1Lo)
                    (Bitwise.and
                        (Bitwise.or g0_c2Lo g6_d1Lo)
                        (Bitwise.complement g6_c1Lo)
                    )
                )

        g6_c1Hi : Int
        g6_c1Hi =
            Bitwise.shiftRightZfBy 0 (g0_c2Hi + g6_d1Hi + g6_c1Carry)

        -- b1 = rotr24(xor64(b, c1))
        g6_b1xHi : Int
        g6_b1xHi =
            Bitwise.xor g3_b2Hi g6_c1Hi

        g6_b1xLo : Int
        g6_b1xLo =
            Bitwise.xor g3_b2Lo g6_c1Lo

        g6_b1Hi : Int
        g6_b1Hi =
            Bitwise.or (Bitwise.shiftRightZfBy 24 g6_b1xHi) (Bitwise.shiftLeftBy 8 g6_b1xLo)

        g6_b1Lo : Int
        g6_b1Lo =
            Bitwise.or (Bitwise.shiftRightZfBy 24 g6_b1xLo) (Bitwise.shiftLeftBy 8 g6_b1xHi)

        -- a2 = add64(add64(a1, b1), y)
        g6_a1b1Lo : Int
        g6_a1b1Lo =
            Bitwise.shiftRightZfBy 0 (g6_a1Lo + g6_b1Lo)

        g6_a1b1Carry : Int
        g6_a1b1Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g6_a1Lo g6_b1Lo)
                    (Bitwise.and
                        (Bitwise.or g6_a1Lo g6_b1Lo)
                        (Bitwise.complement g6_a1b1Lo)
                    )
                )

        g6_a1b1Hi : Int
        g6_a1b1Hi =
            Bitwise.shiftRightZfBy 0 (g6_a1Hi + g6_b1Hi + g6_a1b1Carry)

        g6_a2Lo : Int
        g6_a2Lo =
            Bitwise.shiftRightZfBy 0 (g6_a1b1Lo + mb.m13Lo)

        g6_a2Carry : Int
        g6_a2Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g6_a1b1Lo mb.m13Lo)
                    (Bitwise.and
                        (Bitwise.or g6_a1b1Lo mb.m13Lo)
                        (Bitwise.complement g6_a2Lo)
                    )
                )

        g6_a2Hi : Int
        g6_a2Hi =
            Bitwise.shiftRightZfBy 0 (g6_a1b1Hi + mb.m13Hi + g6_a2Carry)

        -- d2 = rotr16(xor64(d1, a2))
        g6_d2xHi : Int
        g6_d2xHi =
            Bitwise.xor g6_d1Hi g6_a2Hi

        g6_d2xLo : Int
        g6_d2xLo =
            Bitwise.xor g6_d1Lo g6_a2Lo

        g6_d2Hi : Int
        g6_d2Hi =
            Bitwise.or (Bitwise.shiftRightZfBy 16 g6_d2xHi) (Bitwise.shiftLeftBy 16 g6_d2xLo)

        g6_d2Lo : Int
        g6_d2Lo =
            Bitwise.or (Bitwise.shiftRightZfBy 16 g6_d2xLo) (Bitwise.shiftLeftBy 16 g6_d2xHi)

        -- c2 = add64(c1, d2)
        g6_c2Lo : Int
        g6_c2Lo =
            Bitwise.shiftRightZfBy 0 (g6_c1Lo + g6_d2Lo)

        g6_c2Carry : Int
        g6_c2Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g6_c1Lo g6_d2Lo)
                    (Bitwise.and
                        (Bitwise.or g6_c1Lo g6_d2Lo)
                        (Bitwise.complement g6_c2Lo)
                    )
                )

        g6_c2Hi : Int
        g6_c2Hi =
            Bitwise.shiftRightZfBy 0 (g6_c1Hi + g6_d2Hi + g6_c2Carry)

        -- b2 = rotr63(xor64(b1, c2))
        g6_b2xHi : Int
        g6_b2xHi =
            Bitwise.xor g6_b1Hi g6_c2Hi

        g6_b2xLo : Int
        g6_b2xLo =
            Bitwise.xor g6_b1Lo g6_c2Lo

        g6_b2Hi : Int
        g6_b2Hi =
            Bitwise.or (Bitwise.shiftLeftBy 1 g6_b2xHi) (Bitwise.shiftRightZfBy 31 g6_b2xLo)

        g6_b2Lo : Int
        g6_b2Lo =
            Bitwise.or (Bitwise.shiftLeftBy 1 g6_b2xLo) (Bitwise.shiftRightZfBy 31 g6_b2xHi)

        -- Diagonal G7: a=g3.a, b=g0.b, c=g1.c, d=g2.d, x=m14, y=m15
        -- a1 = add64(add64(a, b), x)
        g7_abLo : Int
        g7_abLo =
            Bitwise.shiftRightZfBy 0 (g3_a2Lo + g0_b2Lo)

        g7_abCarry : Int
        g7_abCarry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g3_a2Lo g0_b2Lo)
                    (Bitwise.and
                        (Bitwise.or g3_a2Lo g0_b2Lo)
                        (Bitwise.complement g7_abLo)
                    )
                )

        g7_abHi : Int
        g7_abHi =
            Bitwise.shiftRightZfBy 0 (g3_a2Hi + g0_b2Hi + g7_abCarry)

        g7_a1Lo : Int
        g7_a1Lo =
            Bitwise.shiftRightZfBy 0 (g7_abLo + mb.m14Lo)

        g7_a1Carry : Int
        g7_a1Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g7_abLo mb.m14Lo)
                    (Bitwise.and
                        (Bitwise.or g7_abLo mb.m14Lo)
                        (Bitwise.complement g7_a1Lo)
                    )
                )

        g7_a1Hi : Int
        g7_a1Hi =
            Bitwise.shiftRightZfBy 0 (g7_abHi + mb.m14Hi + g7_a1Carry)

        -- d1 = rotr32(xor64(d, a1))
        g7_d1Hi : Int
        g7_d1Hi =
            Bitwise.xor g2_d2Lo g7_a1Lo

        g7_d1Lo : Int
        g7_d1Lo =
            Bitwise.xor g2_d2Hi g7_a1Hi

        -- c1 = add64(c, d1)
        g7_c1Lo : Int
        g7_c1Lo =
            Bitwise.shiftRightZfBy 0 (g1_c2Lo + g7_d1Lo)

        g7_c1Carry : Int
        g7_c1Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g1_c2Lo g7_d1Lo)
                    (Bitwise.and
                        (Bitwise.or g1_c2Lo g7_d1Lo)
                        (Bitwise.complement g7_c1Lo)
                    )
                )

        g7_c1Hi : Int
        g7_c1Hi =
            Bitwise.shiftRightZfBy 0 (g1_c2Hi + g7_d1Hi + g7_c1Carry)

        -- b1 = rotr24(xor64(b, c1))
        g7_b1xHi : Int
        g7_b1xHi =
            Bitwise.xor g0_b2Hi g7_c1Hi

        g7_b1xLo : Int
        g7_b1xLo =
            Bitwise.xor g0_b2Lo g7_c1Lo

        g7_b1Hi : Int
        g7_b1Hi =
            Bitwise.or (Bitwise.shiftRightZfBy 24 g7_b1xHi) (Bitwise.shiftLeftBy 8 g7_b1xLo)

        g7_b1Lo : Int
        g7_b1Lo =
            Bitwise.or (Bitwise.shiftRightZfBy 24 g7_b1xLo) (Bitwise.shiftLeftBy 8 g7_b1xHi)

        -- a2 = add64(add64(a1, b1), y)
        g7_a1b1Lo : Int
        g7_a1b1Lo =
            Bitwise.shiftRightZfBy 0 (g7_a1Lo + g7_b1Lo)

        g7_a1b1Carry : Int
        g7_a1b1Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g7_a1Lo g7_b1Lo)
                    (Bitwise.and
                        (Bitwise.or g7_a1Lo g7_b1Lo)
                        (Bitwise.complement g7_a1b1Lo)
                    )
                )

        g7_a1b1Hi : Int
        g7_a1b1Hi =
            Bitwise.shiftRightZfBy 0 (g7_a1Hi + g7_b1Hi + g7_a1b1Carry)

        g7_a2Lo : Int
        g7_a2Lo =
            Bitwise.shiftRightZfBy 0 (g7_a1b1Lo + mb.m15Lo)

        g7_a2Carry : Int
        g7_a2Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g7_a1b1Lo mb.m15Lo)
                    (Bitwise.and
                        (Bitwise.or g7_a1b1Lo mb.m15Lo)
                        (Bitwise.complement g7_a2Lo)
                    )
                )

        g7_a2Hi : Int
        g7_a2Hi =
            Bitwise.shiftRightZfBy 0 (g7_a1b1Hi + mb.m15Hi + g7_a2Carry)

        -- d2 = rotr16(xor64(d1, a2))
        g7_d2xHi : Int
        g7_d2xHi =
            Bitwise.xor g7_d1Hi g7_a2Hi

        g7_d2xLo : Int
        g7_d2xLo =
            Bitwise.xor g7_d1Lo g7_a2Lo

        g7_d2Hi : Int
        g7_d2Hi =
            Bitwise.or (Bitwise.shiftRightZfBy 16 g7_d2xHi) (Bitwise.shiftLeftBy 16 g7_d2xLo)

        g7_d2Lo : Int
        g7_d2Lo =
            Bitwise.or (Bitwise.shiftRightZfBy 16 g7_d2xLo) (Bitwise.shiftLeftBy 16 g7_d2xHi)

        -- c2 = add64(c1, d2)
        g7_c2Lo : Int
        g7_c2Lo =
            Bitwise.shiftRightZfBy 0 (g7_c1Lo + g7_d2Lo)

        g7_c2Carry : Int
        g7_c2Carry =
            Bitwise.shiftRightZfBy 31
                (Bitwise.or
                    (Bitwise.and g7_c1Lo g7_d2Lo)
                    (Bitwise.and
                        (Bitwise.or g7_c1Lo g7_d2Lo)
                        (Bitwise.complement g7_c2Lo)
                    )
                )

        g7_c2Hi : Int
        g7_c2Hi =
            Bitwise.shiftRightZfBy 0 (g7_c1Hi + g7_d2Hi + g7_c2Carry)

        -- b2 = rotr63(xor64(b1, c2))
        g7_b2xHi : Int
        g7_b2xHi =
            Bitwise.xor g7_b1Hi g7_c2Hi

        g7_b2xLo : Int
        g7_b2xLo =
            Bitwise.xor g7_b1Lo g7_c2Lo

        g7_b2Hi : Int
        g7_b2Hi =
            Bitwise.or (Bitwise.shiftLeftBy 1 g7_b2xHi) (Bitwise.shiftRightZfBy 31 g7_b2xLo)

        g7_b2Lo : Int
        g7_b2Lo =
            Bitwise.or (Bitwise.shiftLeftBy 1 g7_b2xLo) (Bitwise.shiftRightZfBy 31 g7_b2xHi)
    in
    { v0Hi = g4_a2Hi
    , v0Lo = g4_a2Lo
    , v1Hi = g5_a2Hi
    , v1Lo = g5_a2Lo
    , v2Hi = g6_a2Hi
    , v2Lo = g6_a2Lo
    , v3Hi = g7_a2Hi
    , v3Lo = g7_a2Lo
    , v4Hi = g7_b2Hi
    , v4Lo = g7_b2Lo
    , v5Hi = g4_b2Hi
    , v5Lo = g4_b2Lo
    , v6Hi = g5_b2Hi
    , v6Lo = g5_b2Lo
    , v7Hi = g6_b2Hi
    , v7Lo = g6_b2Lo
    , v8Hi = g6_c2Hi
    , v8Lo = g6_c2Lo
    , v9Hi = g7_c2Hi
    , v9Lo = g7_c2Lo
    , v10Hi = g4_c2Hi
    , v10Lo = g4_c2Lo
    , v11Hi = g5_c2Hi
    , v11Lo = g5_c2Lo
    , v12Hi = g5_d2Hi
    , v12Lo = g5_d2Lo
    , v13Hi = g6_d2Hi
    , v13Lo = g6_d2Lo
    , v14Hi = g7_d2Hi
    , v14Lo = g7_d2Lo
    , v15Hi = g4_d2Hi
    , v15Lo = g4_d2Lo
    }



-- COMPRESS FUNCTION


compress : HashState -> Int -> Int -> Int -> Int -> Bool -> MessageBlock -> HashState
compress h t0Hi t0Lo t1Hi t1Lo isLastBlock mb =
    let
        -- Initialize working vector (IVs from module-level constants)
        initV : WorkingVector
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
            , v12Hi = Bitwise.xor iv4Hi t0Hi
            , v12Lo = Bitwise.xor iv4Lo t0Lo
            , v13Hi = Bitwise.xor iv5Hi t1Hi
            , v13Lo = Bitwise.xor iv5Lo t1Lo
            , v14Hi =
                if isLastBlock then
                    Bitwise.xor iv6Hi 0xFFFFFFFF

                else
                    iv6Hi
            , v14Lo =
                if isLastBlock then
                    Bitwise.xor iv6Lo 0xFFFFFFFF

                else
                    iv6Lo
            , v15Hi = iv7Hi
            , v15Lo = iv7Lo
            }

        -- Round 0 (SIGMA[0] = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 })
        vR0 : WorkingVector
        vR0 =
            round mb initV

        -- Round 1 (SIGMA[1] = { 14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3 })
        vR1 : WorkingVector
        vR1 =
            round
                { m0Hi = mb.m14Hi
                , m0Lo = mb.m14Lo
                , m1Hi = mb.m10Hi
                , m1Lo = mb.m10Lo
                , m2Hi = mb.m4Hi
                , m2Lo = mb.m4Lo
                , m3Hi = mb.m8Hi
                , m3Lo = mb.m8Lo
                , m4Hi = mb.m9Hi
                , m4Lo = mb.m9Lo
                , m5Hi = mb.m15Hi
                , m5Lo = mb.m15Lo
                , m6Hi = mb.m13Hi
                , m6Lo = mb.m13Lo
                , m7Hi = mb.m6Hi
                , m7Lo = mb.m6Lo
                , m8Hi = mb.m1Hi
                , m8Lo = mb.m1Lo
                , m9Hi = mb.m12Hi
                , m9Lo = mb.m12Lo
                , m10Hi = mb.m0Hi
                , m10Lo = mb.m0Lo
                , m11Hi = mb.m2Hi
                , m11Lo = mb.m2Lo
                , m12Hi = mb.m11Hi
                , m12Lo = mb.m11Lo
                , m13Hi = mb.m7Hi
                , m13Lo = mb.m7Lo
                , m14Hi = mb.m5Hi
                , m14Lo = mb.m5Lo
                , m15Hi = mb.m3Hi
                , m15Lo = mb.m3Lo
                }
                vR0

        -- Round 2 (SIGMA[2] = { 11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4 })
        vR2 : WorkingVector
        vR2 =
            round
                { m0Hi = mb.m11Hi
                , m0Lo = mb.m11Lo
                , m1Hi = mb.m8Hi
                , m1Lo = mb.m8Lo
                , m2Hi = mb.m12Hi
                , m2Lo = mb.m12Lo
                , m3Hi = mb.m0Hi
                , m3Lo = mb.m0Lo
                , m4Hi = mb.m5Hi
                , m4Lo = mb.m5Lo
                , m5Hi = mb.m2Hi
                , m5Lo = mb.m2Lo
                , m6Hi = mb.m15Hi
                , m6Lo = mb.m15Lo
                , m7Hi = mb.m13Hi
                , m7Lo = mb.m13Lo
                , m8Hi = mb.m10Hi
                , m8Lo = mb.m10Lo
                , m9Hi = mb.m14Hi
                , m9Lo = mb.m14Lo
                , m10Hi = mb.m3Hi
                , m10Lo = mb.m3Lo
                , m11Hi = mb.m6Hi
                , m11Lo = mb.m6Lo
                , m12Hi = mb.m7Hi
                , m12Lo = mb.m7Lo
                , m13Hi = mb.m1Hi
                , m13Lo = mb.m1Lo
                , m14Hi = mb.m9Hi
                , m14Lo = mb.m9Lo
                , m15Hi = mb.m4Hi
                , m15Lo = mb.m4Lo
                }
                vR1

        -- Round 3 (SIGMA[3] = { 7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8 })
        vR3 : WorkingVector
        vR3 =
            round
                { m0Hi = mb.m7Hi
                , m0Lo = mb.m7Lo
                , m1Hi = mb.m9Hi
                , m1Lo = mb.m9Lo
                , m2Hi = mb.m3Hi
                , m2Lo = mb.m3Lo
                , m3Hi = mb.m1Hi
                , m3Lo = mb.m1Lo
                , m4Hi = mb.m13Hi
                , m4Lo = mb.m13Lo
                , m5Hi = mb.m12Hi
                , m5Lo = mb.m12Lo
                , m6Hi = mb.m11Hi
                , m6Lo = mb.m11Lo
                , m7Hi = mb.m14Hi
                , m7Lo = mb.m14Lo
                , m8Hi = mb.m2Hi
                , m8Lo = mb.m2Lo
                , m9Hi = mb.m6Hi
                , m9Lo = mb.m6Lo
                , m10Hi = mb.m5Hi
                , m10Lo = mb.m5Lo
                , m11Hi = mb.m10Hi
                , m11Lo = mb.m10Lo
                , m12Hi = mb.m4Hi
                , m12Lo = mb.m4Lo
                , m13Hi = mb.m0Hi
                , m13Lo = mb.m0Lo
                , m14Hi = mb.m15Hi
                , m14Lo = mb.m15Lo
                , m15Hi = mb.m8Hi
                , m15Lo = mb.m8Lo
                }
                vR2

        -- Round 4 (SIGMA[4] = { 9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13 })
        vR4 : WorkingVector
        vR4 =
            round
                { m0Hi = mb.m9Hi
                , m0Lo = mb.m9Lo
                , m1Hi = mb.m0Hi
                , m1Lo = mb.m0Lo
                , m2Hi = mb.m5Hi
                , m2Lo = mb.m5Lo
                , m3Hi = mb.m7Hi
                , m3Lo = mb.m7Lo
                , m4Hi = mb.m2Hi
                , m4Lo = mb.m2Lo
                , m5Hi = mb.m4Hi
                , m5Lo = mb.m4Lo
                , m6Hi = mb.m10Hi
                , m6Lo = mb.m10Lo
                , m7Hi = mb.m15Hi
                , m7Lo = mb.m15Lo
                , m8Hi = mb.m14Hi
                , m8Lo = mb.m14Lo
                , m9Hi = mb.m1Hi
                , m9Lo = mb.m1Lo
                , m10Hi = mb.m11Hi
                , m10Lo = mb.m11Lo
                , m11Hi = mb.m12Hi
                , m11Lo = mb.m12Lo
                , m12Hi = mb.m6Hi
                , m12Lo = mb.m6Lo
                , m13Hi = mb.m8Hi
                , m13Lo = mb.m8Lo
                , m14Hi = mb.m3Hi
                , m14Lo = mb.m3Lo
                , m15Hi = mb.m13Hi
                , m15Lo = mb.m13Lo
                }
                vR3

        -- Round 5 (SIGMA[5] = { 2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9 })
        vR5 : WorkingVector
        vR5 =
            round
                { m0Hi = mb.m2Hi
                , m0Lo = mb.m2Lo
                , m1Hi = mb.m12Hi
                , m1Lo = mb.m12Lo
                , m2Hi = mb.m6Hi
                , m2Lo = mb.m6Lo
                , m3Hi = mb.m10Hi
                , m3Lo = mb.m10Lo
                , m4Hi = mb.m0Hi
                , m4Lo = mb.m0Lo
                , m5Hi = mb.m11Hi
                , m5Lo = mb.m11Lo
                , m6Hi = mb.m8Hi
                , m6Lo = mb.m8Lo
                , m7Hi = mb.m3Hi
                , m7Lo = mb.m3Lo
                , m8Hi = mb.m4Hi
                , m8Lo = mb.m4Lo
                , m9Hi = mb.m13Hi
                , m9Lo = mb.m13Lo
                , m10Hi = mb.m7Hi
                , m10Lo = mb.m7Lo
                , m11Hi = mb.m5Hi
                , m11Lo = mb.m5Lo
                , m12Hi = mb.m15Hi
                , m12Lo = mb.m15Lo
                , m13Hi = mb.m14Hi
                , m13Lo = mb.m14Lo
                , m14Hi = mb.m1Hi
                , m14Lo = mb.m1Lo
                , m15Hi = mb.m9Hi
                , m15Lo = mb.m9Lo
                }
                vR4

        -- Round 6 (SIGMA[6] = { 12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11 })
        vR6 : WorkingVector
        vR6 =
            round
                { m0Hi = mb.m12Hi
                , m0Lo = mb.m12Lo
                , m1Hi = mb.m5Hi
                , m1Lo = mb.m5Lo
                , m2Hi = mb.m1Hi
                , m2Lo = mb.m1Lo
                , m3Hi = mb.m15Hi
                , m3Lo = mb.m15Lo
                , m4Hi = mb.m14Hi
                , m4Lo = mb.m14Lo
                , m5Hi = mb.m13Hi
                , m5Lo = mb.m13Lo
                , m6Hi = mb.m4Hi
                , m6Lo = mb.m4Lo
                , m7Hi = mb.m10Hi
                , m7Lo = mb.m10Lo
                , m8Hi = mb.m0Hi
                , m8Lo = mb.m0Lo
                , m9Hi = mb.m7Hi
                , m9Lo = mb.m7Lo
                , m10Hi = mb.m6Hi
                , m10Lo = mb.m6Lo
                , m11Hi = mb.m3Hi
                , m11Lo = mb.m3Lo
                , m12Hi = mb.m9Hi
                , m12Lo = mb.m9Lo
                , m13Hi = mb.m2Hi
                , m13Lo = mb.m2Lo
                , m14Hi = mb.m8Hi
                , m14Lo = mb.m8Lo
                , m15Hi = mb.m11Hi
                , m15Lo = mb.m11Lo
                }
                vR5

        -- Round 7 (SIGMA[7] = { 13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10 })
        vR7 : WorkingVector
        vR7 =
            round
                { m0Hi = mb.m13Hi
                , m0Lo = mb.m13Lo
                , m1Hi = mb.m11Hi
                , m1Lo = mb.m11Lo
                , m2Hi = mb.m7Hi
                , m2Lo = mb.m7Lo
                , m3Hi = mb.m14Hi
                , m3Lo = mb.m14Lo
                , m4Hi = mb.m12Hi
                , m4Lo = mb.m12Lo
                , m5Hi = mb.m1Hi
                , m5Lo = mb.m1Lo
                , m6Hi = mb.m3Hi
                , m6Lo = mb.m3Lo
                , m7Hi = mb.m9Hi
                , m7Lo = mb.m9Lo
                , m8Hi = mb.m5Hi
                , m8Lo = mb.m5Lo
                , m9Hi = mb.m0Hi
                , m9Lo = mb.m0Lo
                , m10Hi = mb.m15Hi
                , m10Lo = mb.m15Lo
                , m11Hi = mb.m4Hi
                , m11Lo = mb.m4Lo
                , m12Hi = mb.m8Hi
                , m12Lo = mb.m8Lo
                , m13Hi = mb.m6Hi
                , m13Lo = mb.m6Lo
                , m14Hi = mb.m2Hi
                , m14Lo = mb.m2Lo
                , m15Hi = mb.m10Hi
                , m15Lo = mb.m10Lo
                }
                vR6

        -- Round 8 (SIGMA[8] = { 6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5 })
        vR8 : WorkingVector
        vR8 =
            round
                { m0Hi = mb.m6Hi
                , m0Lo = mb.m6Lo
                , m1Hi = mb.m15Hi
                , m1Lo = mb.m15Lo
                , m2Hi = mb.m14Hi
                , m2Lo = mb.m14Lo
                , m3Hi = mb.m9Hi
                , m3Lo = mb.m9Lo
                , m4Hi = mb.m11Hi
                , m4Lo = mb.m11Lo
                , m5Hi = mb.m3Hi
                , m5Lo = mb.m3Lo
                , m6Hi = mb.m0Hi
                , m6Lo = mb.m0Lo
                , m7Hi = mb.m8Hi
                , m7Lo = mb.m8Lo
                , m8Hi = mb.m12Hi
                , m8Lo = mb.m12Lo
                , m9Hi = mb.m2Hi
                , m9Lo = mb.m2Lo
                , m10Hi = mb.m13Hi
                , m10Lo = mb.m13Lo
                , m11Hi = mb.m7Hi
                , m11Lo = mb.m7Lo
                , m12Hi = mb.m1Hi
                , m12Lo = mb.m1Lo
                , m13Hi = mb.m4Hi
                , m13Lo = mb.m4Lo
                , m14Hi = mb.m10Hi
                , m14Lo = mb.m10Lo
                , m15Hi = mb.m5Hi
                , m15Lo = mb.m5Lo
                }
                vR7

        -- Round 9 (SIGMA[9] = { 10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0 })
        vR9 : WorkingVector
        vR9 =
            round
                { m0Hi = mb.m10Hi
                , m0Lo = mb.m10Lo
                , m1Hi = mb.m2Hi
                , m1Lo = mb.m2Lo
                , m2Hi = mb.m8Hi
                , m2Lo = mb.m8Lo
                , m3Hi = mb.m4Hi
                , m3Lo = mb.m4Lo
                , m4Hi = mb.m7Hi
                , m4Lo = mb.m7Lo
                , m5Hi = mb.m6Hi
                , m5Lo = mb.m6Lo
                , m6Hi = mb.m1Hi
                , m6Lo = mb.m1Lo
                , m7Hi = mb.m5Hi
                , m7Lo = mb.m5Lo
                , m8Hi = mb.m15Hi
                , m8Lo = mb.m15Lo
                , m9Hi = mb.m11Hi
                , m9Lo = mb.m11Lo
                , m10Hi = mb.m9Hi
                , m10Lo = mb.m9Lo
                , m11Hi = mb.m14Hi
                , m11Lo = mb.m14Lo
                , m12Hi = mb.m3Hi
                , m12Lo = mb.m3Lo
                , m13Hi = mb.m12Hi
                , m13Lo = mb.m12Lo
                , m14Hi = mb.m13Hi
                , m14Lo = mb.m13Lo
                , m15Hi = mb.m0Hi
                , m15Lo = mb.m0Lo
                }
                vR8

        -- Round 10 (SIGMA[0] = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 })
        vR10 : WorkingVector
        vR10 =
            round mb vR9

        -- Round 11 (SIGMA[1] = { 14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3 })
        vR11 : WorkingVector
        vR11 =
            round
                { m0Hi = mb.m14Hi
                , m0Lo = mb.m14Lo
                , m1Hi = mb.m10Hi
                , m1Lo = mb.m10Lo
                , m2Hi = mb.m4Hi
                , m2Lo = mb.m4Lo
                , m3Hi = mb.m8Hi
                , m3Lo = mb.m8Lo
                , m4Hi = mb.m9Hi
                , m4Lo = mb.m9Lo
                , m5Hi = mb.m15Hi
                , m5Lo = mb.m15Lo
                , m6Hi = mb.m13Hi
                , m6Lo = mb.m13Lo
                , m7Hi = mb.m6Hi
                , m7Lo = mb.m6Lo
                , m8Hi = mb.m1Hi
                , m8Lo = mb.m1Lo
                , m9Hi = mb.m12Hi
                , m9Lo = mb.m12Lo
                , m10Hi = mb.m0Hi
                , m10Lo = mb.m0Lo
                , m11Hi = mb.m2Hi
                , m11Lo = mb.m2Lo
                , m12Hi = mb.m11Hi
                , m12Lo = mb.m11Lo
                , m13Hi = mb.m7Hi
                , m13Lo = mb.m7Lo
                , m14Hi = mb.m5Hi
                , m14Lo = mb.m5Lo
                , m15Hi = mb.m3Hi
                , m15Lo = mb.m3Lo
                }
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
        -- Not the last block
        Decode.map
            (\mb ->
                let
                    newT0Lo : Int
                    newT0Lo =
                        Bitwise.shiftRightZfBy 0 (acc.t0Lo + 128)

                    newT0Hi : Int
                    newT0Hi =
                        acc.t0Hi + counterCarry acc.t0Lo newT0Lo
                in
                Decode.Loop
                    { h = compress acc.h newT0Hi newT0Lo 0 0 False mb
                    , t0Lo = newT0Lo
                    , t0Hi = newT0Hi
                    , remaining = acc.remaining - 128
                    }
            )
            blockDecoder

    else
        -- Last block (input was pre-padded to 128-byte boundary)
        Decode.map
            (\mb ->
                let
                    newT0Lo : Int
                    newT0Lo =
                        Bitwise.shiftRightZfBy 0 (acc.t0Lo + acc.remaining)

                    newT0Hi : Int
                    newT0Hi =
                        acc.t0Hi + counterCarry acc.t0Lo newT0Lo
                in
                Decode.Done (compress acc.h newT0Hi newT0Lo 0 0 True mb)
            )
            blockDecoder



-- HASH FUNCTIONS


emptyBytes : Bytes
emptyBytes =
    Encode.encode (Encode.sequence [])


{-| Pre-decoded zero block (128 zero bytes), hoisted to module level.
Used for empty unkeyed input where we compress a single zero block.
-}
zeroMessageBlock : MessageBlock
zeroMessageBlock =
    { m0Hi = 0
    , m0Lo = 0
    , m1Hi = 0
    , m1Lo = 0
    , m2Hi = 0
    , m2Lo = 0
    , m3Hi = 0
    , m3Lo = 0
    , m4Hi = 0
    , m4Lo = 0
    , m5Hi = 0
    , m5Lo = 0
    , m6Hi = 0
    , m6Lo = 0
    , m7Hi = 0
    , m7Lo = 0
    , m8Hi = 0
    , m8Lo = 0
    , m9Hi = 0
    , m9Lo = 0
    , m10Hi = 0
    , m10Lo = 0
    , m11Hi = 0
    , m11Lo = 0
    , m12Hi = 0
    , m12Lo = 0
    , m13Hi = 0
    , m13Lo = 0
    , m14Hi = 0
    , m14Lo = 0
    , m15Hi = 0
    , m15Lo = 0
    }


{-| Compute a BLAKE2b hash with the given digest length, key, and data.

    - digestLength: 1 to 64 (number of output bytes)
    - key: 0 to 64 bytes (use empty Bytes for unkeyed hashing)
    - data: the message to hash

-}
hash : { digestLength : Int, key : Bytes, data : Bytes } -> Bytes
hash config =
    let
        keyLen : Int
        keyLen =
            Bytes.width config.key

        dataLen : Int
        dataLen =
            Bytes.width config.data

        totalLen : Int
        totalLen =
            if keyLen > 0 then
                128 + dataLen

            else
                dataLen

        -- Initialize hash state
        paramWord : Int
        paramWord =
            Bitwise.or (Bitwise.or 0x01010000 (Bitwise.shiftLeftBy 8 keyLen)) config.digestLength

        initState : HashState
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

        finalState : HashState
        finalState =
            if totalLen == 0 then
                -- Empty unkeyed: compress one zero block with counter=0, final
                compress initState 0 0 0 0 True zeroMessageBlock

            else
                let
                    -- Pre-pad input to a multiple of 128 bytes so the loop always
                    -- reads full blocks. Avoids the pad+re-decode round-trip for
                    -- partial last blocks.
                    paddedData : Bytes
                    paddedData =
                        let
                            -- Build full input data (key block prepended if keyed)
                            fullData : Bytes
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

                            remainder : Int
                            remainder =
                                remainderBy 128 totalLen
                        in
                        if remainder == 0 then
                            fullData

                        else
                            let
                                padNeeded : Int
                                padNeeded =
                                    128 - remainder

                                zeroU32s : Int
                                zeroU32s =
                                    padNeeded // 4

                                tailU8s : Int
                                tailU8s =
                                    remainderBy 4 padNeeded
                            in
                            Encode.encode
                                (Encode.sequence
                                    [ Encode.bytes fullData
                                    , Encode.sequence (List.repeat zeroU32s (Encode.unsignedInt32 LE 0))
                                    , Encode.sequence (List.repeat tailU8s (Encode.unsignedInt8 0))
                                    ]
                                )
                in
                case Decode.decode (Decode.loop { h = initState, t0Lo = 0, t0Hi = 0, remaining = totalLen } blockLoop) paddedData of
                    Just hs ->
                        hs

                    Nothing ->
                        initState
    in
    encodeDigest config.digestLength finalState


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


{-| Decode a `Bytes` value into a list of byte values (0-255).
-}
bytesToList : Bytes -> List Int
bytesToList bytes =
    let
        step : ( Int, List Int ) -> Decode.Decoder (Decode.Step ( Int, List Int ) (List Int))
        step ( remaining, acc ) =
            if remaining <= 0 then
                Decode.succeed (Decode.Done (List.reverse acc))

            else
                Decode.map
                    (\v -> Decode.Loop ( remaining - 1, v :: acc ))
                    Decode.unsignedInt8
    in
    Decode.decode (Decode.loop ( Bytes.width bytes, [] ) step) bytes
        |> Maybe.withDefault []
