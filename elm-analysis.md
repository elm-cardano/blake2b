# Analysis of elm/bytes, Elm's Number Types, and Bitwise Limitations

## 1. Elm's Integer and Float Type System

### Int

Elm's `Int` is defined as an opaque type in `Basics.elm`. At runtime (JavaScript target), integers are IEEE 754 64-bit doubles -- there is no separate integer representation. The documented well-defined range is **-2^31 to 2^31 - 1** (32-bit signed). On the JavaScript target, some operations are safe up to ±(2^53 - 1), but this is target-dependent and not guaranteed.

Key implementation details from `Elm/Kernel/Basics.js`:

```javascript
var _Basics_idiv = F2(function(a, b) { return (a / b) | 0; });
function _Basics_truncate(n) { return n | 0; }
function _Basics_toFloat(x) { return x; }  // no-op: Int IS a JS number
```

Integer division uses `| 0` to truncate the floating-point result back to a 32-bit signed integer. The `toFloat` conversion is a no-op because both types are JavaScript numbers internally.

### Float

Elm's `Float` follows IEEE 754 double-precision (64-bit). It supports `NaN` and `Infinity`. All math operations delegate directly to JavaScript's `Math` object. There is no single-precision float type at the language level.

### Implications

- Elm has **no 64-bit integer type**. The `Int` type is semantically 32-bit.
- Conversion between Int and Float is explicit (`toFloat`, `round`, `floor`, `ceiling`, `truncate`), even though both are JavaScript doubles at runtime.
- Integers beyond 2^31 - 1 silently become imprecise or wrap depending on the operation.

---

## 2. Bitwise Module

### API

All functions in `Bitwise.elm`, implemented in `Elm/Kernel/Bitwise.js`:

| Function | Elm Signature | JS Operator |
|----------|--------------|-------------|
| `and` | `Int -> Int -> Int` | `a & b` |
| `or` | `Int -> Int -> Int` | `a \| b` |
| `xor` | `Int -> Int -> Int` | `a ^ b` |
| `complement` | `Int -> Int` | `~a` |
| `shiftLeftBy` | `Int -> Int -> Int` | `a << offset` |
| `shiftRightBy` | `Int -> Int -> Int` | `a >> offset` (arithmetic, sign-propagating) |
| `shiftRightZfBy` | `Int -> Int -> Int` | `a >>> offset` (logical, zero-fill) |

### Limitations

1. **32-bit only**: All JavaScript bitwise operators implicitly convert operands to 32-bit signed integers. There is no way to perform 64-bit bitwise operations.

2. **No rotation operators**: There are no `rotateLeft` or `rotateRight` functions. BLAKE2b's G function requires 64-bit rotations by 32, 24, 16, and 63 bits -- none of which can be expressed natively.

3. **Signed semantics**: `shiftRightZfBy` (the `>>>` operator) returns an **unsigned** 32-bit result, but Elm treats it as a signed `Int`. For example: `-32 |> shiftRightZfBy 1 == 2147483632`. This creates a value outside the documented Int range.

4. **No bit counting**: No `popcount`, `clz` (count leading zeros), or `ctz` (count trailing zeros).

5. **No byte-level extraction**: No built-in way to extract individual bytes from an integer.

---

## 3. elm/bytes Package

### Overview

Package `elm/bytes` v1.0.8 exposes three modules: `Bytes`, `Bytes.Encode`, and `Bytes.Decode`. Internally, bytes are JavaScript `DataView` objects wrapping `ArrayBuffer`.

### Bytes Type

```elm
type Bytes = Bytes          -- opaque; backed by JS DataView
type Endianness = LE | BE   -- explicit in all multi-byte operations

width : Bytes -> Int
getHostEndianness : Task x Endianness
```

Host endianness is detected at runtime by writing a `Uint32Array([1])` and reading it back as `Uint8Array`.

### Encoding API

| Function | Width | Range |
|----------|-------|-------|
| `signedInt8` | 1 byte | -128 to 127 |
| `signedInt16 Endianness` | 2 bytes | -32,768 to 32,767 |
| `signedInt32 Endianness` | 4 bytes | -2,147,483,648 to 2,147,483,647 |
| `unsignedInt8` | 1 byte | 0 to 255 |
| `unsignedInt16 Endianness` | 2 bytes | 0 to 65,535 |
| `unsignedInt32 Endianness` | 4 bytes | 0 to 4,294,967,295 |
| `float32 Endianness` | 4 bytes | IEEE 754 single-precision |
| `float64 Endianness` | 8 bytes | IEEE 754 double-precision |
| `string` | variable | UTF-8 encoded |
| `bytes` | variable | raw copy |
| `sequence` | variable | list of encoders |

The `Encoder` type is a tagged union:

```elm
type Encoder
    = I8 Int | I16 Endianness Int | I32 Endianness Int
    | U8 Int | U16 Endianness Int | U32 Endianness Int
    | F32 Endianness Float | F64 Endianness Float
    | Seq Int (List Encoder) | Utf8 Int String | Bytes Bytes
```

The `Seq` variant stores a pre-calculated total width, allowing `encode` to allocate the `ArrayBuffer` in a single allocation with no resizing.

### Decoding API

```elm
type Decoder a = Decoder (Bytes -> Int -> (Int, a))
```

A decoder is a function from `(Bytes, offset)` to `(newOffset, value)`. Decoding integer/float types mirrors encoding. Combinators include `map`, `map2`..`map5`, `andThen`, `succeed`, `fail`, and `loop`. Out-of-bounds reads throw JS exceptions caught by the top-level `decode`:

```javascript
function _Bytes_decode(decoder, bytes) {
    try { return Just(A2(decoder, bytes, 0).b); }
    catch(e) { return Nothing; }
}
```

### Key Design Choices

- **Endianness is always explicit** for multi-byte values. No default byte order.
- **Pre-computed widths** avoid buffer reallocations during encoding.
- **Bytes copy optimization**: copies 4 bytes at a time via `setUint32`, then handles the remainder byte-by-byte.
- **UTF-8 width calculation**: handles surrogate pairs correctly, counting 1/2/3/4 bytes per code point.

### Limitations

1. **No 64-bit integer encoding/decoding**: Maximum integer width is 32 bits. There is no `signedInt64` or `unsignedInt64`.
2. **No variable-length integer encoding**: Protocols using varint (protobuf, etc.) must implement custom encoding.
3. **No bit-level access**: Cannot read/write individual bits or sub-byte fields.
4. **No float16**: Only 32-bit and 64-bit floats.

---

## 4. Implications for BLAKE2b Implementation in Elm

BLAKE2b operates on **64-bit unsigned integers** with additions modulo 2^64, XOR, and rotations. Elm's type system and standard library present fundamental obstacles:

### The 64-bit Problem

| BLAKE2b Requirement | Elm Capability | Gap |
|---------------------|---------------|-----|
| 64-bit unsigned integers | 32-bit signed Int | No native 64-bit type |
| 64-bit addition mod 2^64 | 32-bit addition | Must be emulated with hi/lo word pairs |
| 64-bit XOR | 32-bit XOR | Must XOR hi and lo halves separately |
| 64-bit rotation (>>>32, >>>24, >>>16, >>>63) | No rotation operator; 32-bit shifts only | Must be emulated with shifts + OR on word pairs |
| 64-bit byte counter (128-bit total) | 32-bit Int | Must track carry manually |
| Little-endian 64-bit serialization | 32-bit max in elm/bytes | Must encode as two 32-bit words in correct order |

### Emulating 64-bit Arithmetic

A 64-bit word must be represented as a pair of 32-bit integers `(hi, lo)`:

```elm
type alias U64 = { hi : Int, lo : Int }
```

**Addition mod 2^64** requires carry propagation:

```elm
add64 : U64 -> U64 -> U64
add64 a b =
    let
        lo = Bitwise.shiftRightZfBy 0 (a.lo + b.lo)  -- force unsigned 32-bit
        carry = if lo < Bitwise.shiftRightZfBy 0 a.lo then 1 else 0
        hi = Bitwise.shiftRightZfBy 0 (a.hi + b.hi + carry)
    in
    { hi = hi, lo = lo }
```

Note: the carry detection `lo < a.lo` relies on unsigned comparison, which is tricky since Elm `Int` is signed. The `shiftRightZfBy 0` trick forces unsigned interpretation.

**Rotation** must be decomposed. For example, BLAKE2b's rotation by 32:

```elm
rotr64by32 : U64 -> U64
rotr64by32 { hi, lo } = { hi = lo, lo = hi }  -- just swap words
```

Rotation by 24 (general case for r < 32):

```elm
rotr64 : Int -> U64 -> U64
rotr64 r { hi, lo } =
    if r == 0 then { hi = hi, lo = lo }
    else if r == 32 then { hi = lo, lo = hi }
    else if r < 32 then
        { hi = Bitwise.or (Bitwise.shiftRightZfBy r hi) (Bitwise.shiftLeftBy (32 - r) lo)
        , lo = Bitwise.or (Bitwise.shiftRightZfBy r lo) (Bitwise.shiftLeftBy (32 - r) hi)
        }
    else -- r > 32
        let r2 = r - 32 in
        { hi = Bitwise.or (Bitwise.shiftRightZfBy r2 lo) (Bitwise.shiftLeftBy (32 - r2) hi)
        , lo = Bitwise.or (Bitwise.shiftRightZfBy r2 hi) (Bitwise.shiftLeftBy (32 - r2) lo)
        }
```

### Serialization Gap

elm/bytes maxes out at 32-bit integers. To encode/decode a 64-bit value in little-endian:

```elm
encodeU64LE : U64 -> Encoder
encodeU64LE { hi, lo } =
    Bytes.Encode.sequence
        [ Bytes.Encode.unsignedInt32 LE lo
        , Bytes.Encode.unsignedInt32 LE hi
        ]
```

### Performance Cost

Each BLAKE2b G function call performs 8 additions, 4 XORs, and 4 rotations on 64-bit words. Emulating these with 32-bit pairs roughly **doubles or triples the operation count**, plus overhead from Elm's functional data structures (record allocation, no mutation). A pure Elm BLAKE2b implementation would likely be **10-30x slower** than a JavaScript implementation using `BigInt` or `DataView` tricks, and **100-1000x slower** than native C/Rust with SIMD.

### Summary

Elm's type system is fundamentally 32-bit for integers and bitwise operations, and elm/bytes mirrors this limitation. Implementing BLAKE2b in pure Elm requires emulating all 64-bit arithmetic with hi/lo word pairs, which is feasible but costly. The main alternatives are:

1. **Pure Elm with U64 emulation** -- correct but slow
2. **Elm kernel code (JS)** -- use `BigInt` or manual 64-bit arithmetic in JavaScript, exposed as native functions
3. **Ports/Web Workers** -- delegate hashing to JavaScript entirely

---

## References

- `/Users/piz/git/elm/core/src/Basics.elm` -- Int and Float type definitions
- `/Users/piz/git/elm/core/src/Bitwise.elm` -- Bitwise operations API
- `/Users/piz/git/elm/core/src/Elm/Kernel/Basics.js` -- JS implementation of arithmetic
- `/Users/piz/git/elm/core/src/Elm/Kernel/Bitwise.js` -- JS implementation of bitwise ops
- `/Users/piz/git/elm/bytes/src/Bytes.elm` -- Bytes type and endianness
- `/Users/piz/git/elm/bytes/src/Bytes/Encode.elm` -- Encoder API
- `/Users/piz/git/elm/bytes/src/Bytes/Decode.elm` -- Decoder API
- `/Users/piz/git/elm/bytes/src/Elm/Kernel/Bytes.js` -- JS implementation of byte operations
