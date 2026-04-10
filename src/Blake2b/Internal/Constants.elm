module Blake2b.Internal.Constants exposing
    ( iv0Hi
    , iv0Lo
    , iv1Hi
    , iv1Lo
    , iv2Hi
    , iv2Lo
    , iv3Hi
    , iv3Lo
    , iv4Hi
    , iv4Lo
    , iv5Hi
    , iv5Lo
    , iv6Hi
    , iv6Lo
    , iv7Hi
    , iv7Lo
    )

{-| BLAKE2b initialization vectors — first 64 bits of fractional parts
of the square roots of the first 8 primes (same as SHA-512).
Stored as hi/lo 32-bit Int pairs.
-}


iv0Hi : Int
iv0Hi =
    0x6A09E667


iv0Lo : Int
iv0Lo =
    0xF3BCC908


iv1Hi : Int
iv1Hi =
    0xBB67AE85


iv1Lo : Int
iv1Lo =
    0x84CAA73B


iv2Hi : Int
iv2Hi =
    0x3C6EF372


iv2Lo : Int
iv2Lo =
    0xFE94F82B


iv3Hi : Int
iv3Hi =
    0xA54FF53A


iv3Lo : Int
iv3Lo =
    0x5F1D36F1


iv4Hi : Int
iv4Hi =
    0x510E527F


iv4Lo : Int
iv4Lo =
    0xADE682D1


iv5Hi : Int
iv5Hi =
    0x9B05688C


iv5Lo : Int
iv5Lo =
    0x2B3E6C1F


iv6Hi : Int
iv6Hi =
    0x1F83D9AB


iv6Lo : Int
iv6Lo =
    0xFB41BD6B


iv7Hi : Int
iv7Hi =
    0x5BE0CD19


iv7Lo : Int
iv7Lo =
    0x137E2179
