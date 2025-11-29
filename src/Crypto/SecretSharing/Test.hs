{-# LANGUAGE OverloadedRecordDot #-}

module Crypto.SecretSharing.Test
  ( tests
  , prop_splitSecret_combineShares_roundtrip
  ) where

import qualified Crypto.SecretSharing.Shamir as Shamir
import Crypto.SecretSharing.Types (Bitpad, SSSParams (..))
import Data.ByteString (ByteString)
import qualified Data.ByteString as Bs
import qualified Hedgehog as H
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range
import GHC.Stack (withFrozenCallStack)


tests :: IO Bool
tests =
  H.checkParallel $
    H.Group
      "Crypto.SecretSharing.Shamir"
      [ ( "prop_splitSecret_combineShares_roundtrip"
        , prop_splitSecret_combineShares_roundtrip
        )
      ]


prop_splitSecret_combineShares_roundtrip :: H.Property
prop_splitSecret_combineShares_roundtrip =
  H.property $ do
    parameters <- H.forAll genParameters
    secret <- H.forAll (genSecretBytes 1 4096)

    shares <- H.evalIO (Shamir.splitSecret parameters secret)

    let shareCount = length shares
    H.assert (shareCount == parameters.totalShares)

    shuffledIndices <- H.forAll (Gen.shuffle [0 .. shareCount - 1])

    let chosenIndices =
          take parameters.threshold shuffledIndices

        chosenShares =
          [ shares !! index
          | index <- chosenIndices
          ]

    case Shamir.combineShares parameters chosenShares of
      Left errorMessage ->
        withFrozenCallStack $ do
          H.footnote ("combineShares error: " <> errorMessage)
          H.failure
      Right reconstructed ->
        reconstructed H.=== secret

-- GENERATORS -----------------------------------------------------------

genParameters :: H.Gen SSSParams
genParameters = do
  threshold <- Gen.int (Range.linear 1 5)
  totalShares <- Gen.int (Range.linear threshold 10)
  pure $ SSSParams { threshold = threshold, totalShares = totalShares }

genSecretBytes :: Int -> Int -> H.Gen ByteString
genSecretBytes minimumLength maximumLength =
  Gen.bytes (Range.linear minimumLength maximumLength)
