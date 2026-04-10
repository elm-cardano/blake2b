module Blake2b exposing (hash, hash512, hash256, hash224)

{-| Pure Elm BLAKE2b implementation (RFC 7693).

@docs hash, hash512, hash256, hash224

-}

import Blake2b.V1
import Bytes exposing (Bytes)


{-| Compute a BLAKE2b hash with the given digest length, key, and data.

    - digestLength: 1 to 64 (number of output bytes)
    - key: 0 to 64 bytes (use empty Bytes for unkeyed hashing)
    - data: the message to hash

-}
hash : { digestLength : Int, key : Bytes, data : Bytes } -> Bytes
hash =
    Blake2b.V1.hash


{-| Compute a 512-bit (64-byte) BLAKE2b hash.
-}
hash512 : Bytes -> Bytes
hash512 =
    Blake2b.V1.hash512


{-| Compute a 256-bit (32-byte) BLAKE2b hash.
-}
hash256 : Bytes -> Bytes
hash256 =
    Blake2b.V1.hash256


{-| Compute a 224-bit (28-byte) BLAKE2b hash.
-}
hash224 : Bytes -> Bytes
hash224 =
    Blake2b.V1.hash224
