module Blake2b512 exposing
    ( Digest
    , fromString, fromBytes, fromByteValues
    , toHex, toBase64
    , toBytes, toByteValues
    )

{-| [BLAKE2b-512] is a [cryptographic hash function] (RFC 7693) that gives
256 bits of security with a 64-byte digest.

[BLAKE2b-512]: https://datatracker.ietf.org/doc/html/rfc7693
[cryptographic hash function]: https://en.wikipedia.org/wiki/Cryptographic_hash_function

@docs Digest


# Creating digests

@docs fromString, fromBytes, fromByteValues


# Formatting digests

@docs toHex, toBase64


# To binary data

@docs toBytes, toByteValues

-}

import Blake2b.DecodeV1 exposing (HashState)
import Blake2b.V1
import Bytes exposing (Bytes)
import Bytes.Encode as Encode


{-| An abstract BLAKE2b-512 digest (64 bytes).
-}
type Digest
    = Digest HashState


{-| Create a digest from a `String`.

    import Blake2b512

    Blake2b512.fromString "abc"
        |> Blake2b512.toHex
    --> "ba80a53f981c4d0d6a2797b69f12f6e94c212f14685ac4b74b12bb6fdbffa2d17d87c5392aab792dc252d5de4533cc9518d38aa8dbf1925ab92386edd4009923"

-}
fromString : String -> Digest
fromString str =
    fromBytes (Encode.encode (Encode.string str))


{-| Create a digest from [`Bytes`](https://package.elm-lang.org/packages/elm/bytes/latest/).
-}
fromBytes : Bytes -> Digest
fromBytes bytes =
    Digest (Blake2b.V1.hash { digestLength = 64, key = emptyBytes } bytes)


emptyBytes : Bytes
emptyBytes =
    Encode.encode (Encode.sequence [])


{-| Create a digest from a list of byte values (0-255).
-}
fromByteValues : List Int -> Digest
fromByteValues values =
    fromBytes (Encode.encode (Encode.sequence (List.map Encode.unsignedInt8 values)))


{-| Turn a digest into a hex string.
-}
toHex : Digest -> String
toHex (Digest s) =
    Blake2b.V1.stateToHex 64 s


{-| Turn a digest into a base64 encoded string.
-}
toBase64 : Digest -> String
toBase64 (Digest s) =
    Blake2b.V1.stateToBase64 64 s


{-| Turn a digest into `Bytes`. The width is 64 bytes (512 bits).
-}
toBytes : Digest -> Bytes
toBytes (Digest s) =
    Blake2b.V1.stateToBytes 64 s


{-| Turn a digest into a list of byte values (0-255).
-}
toByteValues : Digest -> List Int
toByteValues (Digest s) =
    Blake2b.V1.stateToByteValues 64 s
