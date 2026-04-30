module Blake2b224 exposing
    ( Digest
    , fromString, fromBytes, fromByteValues
    , toHex, toBase64
    , toBytes, toByteValues
    )

{-| [BLAKE2b-224] is a [cryptographic hash function] (RFC 7693) that gives
112 bits of security with a 28-byte digest.

[BLAKE2b-224]: https://datatracker.ietf.org/doc/html/rfc7693
[cryptographic hash function]: https://en.wikipedia.org/wiki/Cryptographic_hash_function

@docs Digest


# Creating digests

@docs fromString, fromBytes, fromByteValues


# Formatting digests

@docs toHex, toBase64


# To binary data

@docs toBytes, toByteValues

-}

import Base64
import Blake2b.V1
import Bytes exposing (Bytes)
import Bytes.Encode as Encode
import Hex


{-| An abstract BLAKE2b-224 digest (28 bytes).
-}
type Digest
    = Digest Bytes


{-| Create a digest from a `String`.

    import Blake2b224

    Blake2b224.fromString "abc"
        |> Blake2b224.toHex
    --> "9bd237b02a29e43bdd6738afa5b53ff0eee178d6210b618e4511aec8"

-}
fromString : String -> Digest
fromString str =
    fromBytes (Encode.encode (Encode.string str))


{-| Create a digest from [`Bytes`](https://package.elm-lang.org/packages/elm/bytes/latest/).
-}
fromBytes : Bytes -> Digest
fromBytes bytes =
    Digest (Blake2b.V1.hash224 bytes)


{-| Create a digest from a list of byte values (0-255).
-}
fromByteValues : List Int -> Digest
fromByteValues values =
    fromBytes (Encode.encode (Encode.sequence (List.map Encode.unsignedInt8 values)))


{-| Turn a digest into a hex string.
-}
toHex : Digest -> String
toHex (Digest b) =
    Hex.fromBytes b


{-| Turn a digest into a base64 encoded string.
-}
toBase64 : Digest -> String
toBase64 (Digest b) =
    Base64.fromBytes b


{-| Turn a digest into `Bytes`. The width is 28 bytes (224 bits).
-}
toBytes : Digest -> Bytes
toBytes (Digest b) =
    b


{-| Turn a digest into a list of byte values (0-255).
-}
toByteValues : Digest -> List Int
toByteValues (Digest b) =
    Blake2b.V1.bytesToList b
