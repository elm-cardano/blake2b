module Blake2b exposing
    ( Digest
    , fromString, fromBytes, fromByteValues
    , toHex, toBase64
    , toBytes, toByteValues
    )

{-| [BLAKE2b] is a [cryptographic hash function] (RFC 7693) that supports
keyed hashing and variable-length output (1 to 64 bytes).

For fixed-length unkeyed hashes, prefer the dedicated modules
[`Blake2b224`](Blake2b224), [`Blake2b256`](Blake2b256), or
[`Blake2b512`](Blake2b512).

[BLAKE2b]: https://datatracker.ietf.org/doc/html/rfc7693
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


{-| An abstract BLAKE2b digest. Its length matches the `digestLength` passed
to the constructor.
-}
type Digest
    = Digest Bytes


{-| Create a digest from a `String`.

`digestLength` is the output length in bytes (1 to 64). Use empty `Bytes`
as `key` for unkeyed hashing, or a 1-to-64 byte key for a keyed hash (MAC).

    import Blake2b
    import Bytes.Encode as Encode

    Blake2b.fromString
        { digestLength = 32, key = Encode.encode (Encode.sequence []) }
        "hello"
        |> Blake2b.toHex
    --> "324dcf027dd4a30a932c441f365a25e86b173defa4b8e58948253471b81b72cf"

-}
fromString : { digestLength : Int, key : Bytes } -> String -> Digest
fromString config str =
    fromBytes config (Encode.encode (Encode.string str))


{-| Create a digest from [`Bytes`](https://package.elm-lang.org/packages/elm/bytes/latest/).
-}
fromBytes : { digestLength : Int, key : Bytes } -> Bytes -> Digest
fromBytes config bytes =
    Digest
        (Blake2b.V1.hash
            { digestLength = config.digestLength
            , key = config.key
            , data = bytes
            }
        )


{-| Create a digest from a list of byte values (0-255).
-}
fromByteValues : { digestLength : Int, key : Bytes } -> List Int -> Digest
fromByteValues config values =
    fromBytes config (Encode.encode (Encode.sequence (List.map Encode.unsignedInt8 values)))


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


{-| Turn a digest into `Bytes`. Width matches the `digestLength` used at
construction time.
-}
toBytes : Digest -> Bytes
toBytes (Digest b) =
    b


{-| Turn a digest into a list of byte values (0-255).
-}
toByteValues : Digest -> List Int
toByteValues (Digest b) =
    Blake2b.V1.bytesToList b
