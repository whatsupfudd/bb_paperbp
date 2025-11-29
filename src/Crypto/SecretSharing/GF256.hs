
module Crypto.SecretSharing.GF256
  ( add
  , mul
  , pow
  , inv
  , divide
  ) where

import Data.Bits (shiftL, shiftR, (.&.), xor)
import qualified Data.List  as List
import Data.Word (Word8)

-- | Addition in GF(2^8) is just XOR.
add :: Word8 -> Word8 -> Word8
add = xor

-- | Multiplication in GF(2^8) using the AES-style "Russian peasant"
-- algorithm with the irreducible polynomial x^8 + x^4 + x^3 + x + 1.
mul :: Word8 -> Word8 -> Word8
mul a0 b0 = iterateMultiplication 0 a0 b0 0
  where
    iterateMultiplication :: Int -> Word8 -> Word8 -> Word8 -> Word8
    iterateMultiplication bitIndex a b accumulator
      | bitIndex == 8 = accumulator
      | otherwise =
          let accumulator'
                | b .&. 1 /= 0 = accumulator `xor` a
                | otherwise = accumulator

              highBitSet = a .&. 0x80 /= 0
              aShifted = shiftL a 1
              aReduced
                | highBitSet = aShifted `xor` 0x1b
                | otherwise = aShifted

              bShifted = shiftR b 1
           in iterateMultiplication (bitIndex + 1) aReduced bShifted accumulator'

-- | Exponentiation in GF(2^8) by repeated squaring.
pow :: Word8 -> Int -> Word8
pow _ 0 = 1
pow base exponent
  | exponent < 0 =
      error "GF256.pow: negative exponents are not supported"
  | otherwise =
      iterateExponentiation exponent base 1
  where
    iterateExponentiation :: Int -> Word8 -> Word8 -> Word8
    iterateExponentiation remaining current result
      | remaining == 0 = result
      | otherwise =
          let result'
                | remaining .&. 1 /= 0 = mul result current
                | otherwise = result

              current' = mul current current
              remaining' = shiftR remaining 1
           in iterateExponentiation remaining' current' result'

-- | Multiplicative inverse in GF(2^8), if it exists.
--
-- There is no inverse for 0.
inv :: Word8 -> Maybe Word8
inv 0 = Nothing
inv value =
  List.find (\candidate -> mul value candidate == 1) [1 .. 255]

-- | Division in GF(2^8). Returns 'Nothing' if the denominator has no
-- inverse (i.e. is 0).
divide :: Word8 -> Word8 -> Maybe Word8
divide _ 0 = Nothing
divide numerator denominator = do
  denominatorInverse <- inv denominator
  pure (mul numerator denominatorInverse)
