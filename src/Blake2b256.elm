module Blake2b256 exposing
    ( Digest
    , fromString, fromBytes, fromByteValues
    , toHex, toBase64
    , toBytes, toByteValues
    )

{-| [BLAKE2b-256] is a [cryptographic hash function] (RFC 7693) that gives
128 bits of security with a 32-byte digest.

[BLAKE2b-256]: https://datatracker.ietf.org/doc/html/rfc7693
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


{-| An abstract BLAKE2b-256 digest (32 bytes).
-}
type Digest
    = Digest Bytes


{-| Create a digest from a `String`.

    import Blake2b256

    Blake2b256.fromString "abc"
        |> Blake2b256.toHex
    --> "bddd813c634239723171ef3fee98579b94964e3bb1cb3e427262c8c068d52319"

-}
fromString : String -> Digest
fromString str =
    fromBytes (Encode.encode (Encode.string str))


{-| Create a digest from [`Bytes`](https://package.elm-lang.org/packages/elm/bytes/latest/).
-}
fromBytes : Bytes -> Digest
fromBytes bytes =
    Digest (Blake2b.V1.hash256 bytes)


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


{-| Turn a digest into `Bytes`. The width is 32 bytes (256 bits).
-}
toBytes : Digest -> Bytes
toBytes (Digest b) =
    b


{-| Turn a digest into a list of byte values (0-255).
-}
toByteValues : Digest -> List Int
toByteValues (Digest b) =
    Blake2b.V1.bytesToList b
