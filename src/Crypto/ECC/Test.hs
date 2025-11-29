{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE NamedFieldPuns #-}

module Crypto.ECC.Test
  ( tests
  , prop_encode_decode_roundtrip
  ) where

import Data.ByteString (ByteString)
import qualified Data.ByteString as Bs

import GHC.Stack (withFrozenCallStack)

import qualified Hedgehog as H
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range

import qualified Codec.FEC as FEC
import qualified Crypto.ECC.Chunking as ECC
import Crypto.ECC.Types
  ( ECCParams (..)
  )


tests :: IO Bool
tests = do
  -- FEC library must be initialised before use
  FEC.initialize
  H.checkParallel $
    H.Group
      "Crypto.ECC.Chunking"
      [ ( "prop_encode_decode_roundtrip"
        , prop_encode_decode_roundtrip
        )
      ]

prop_encode_decode_roundtrip :: H.Property
prop_encode_decode_roundtrip =
  H.property $ do
    eccParams <- H.forAll genECCParams
    payload <- H.forAll (genPayloadBytes 1 16384)

    let originalLength =
          Bs.length payload

    case ECC.encodeECC eccParams payload of
      Left errorMessage ->
        withFrozenCallStack $ do
          H.footnote ("encodeECC error: " <> errorMessage)
          H.failure
      Right blocks -> do
        H.cover 5 "non-empty blocks" (not (null blocks))

        case ECC.decodeECC eccParams originalLength blocks of
          Left errorMessage ->
            withFrozenCallStack $ do
              H.footnote ("decodeECC error: " <> errorMessage)
              H.failure
          Right reconstructed ->
            reconstructed H.=== payload

-- GENERATORS -----------------------------------------------------------

genECCParams :: H.Gen ECCParams
genECCParams = do
  -- Keep the ranges tight for test speed; production parameters
  -- can be much larger (e.g. totalBlocks in the dozens).
  requiredBlocks <- Gen.int (Range.linear 2 5)
  totalBlocks <- Gen.int (Range.linear (requiredBlocks + 1) 8)
  maxBlockSize <- Gen.int (Range.linear 64 2048)
  pure ECCParams{requiredBlocks, totalBlocks, maxBlockSize}

genPayloadBytes :: Int -> Int -> H.Gen ByteString
genPayloadBytes minimumLength maximumLength =
  Gen.bytes (Range.linear minimumLength maximumLength)
