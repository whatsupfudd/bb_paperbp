{-# LANGUAGE OverloadedRecordDot #-}

module Crypto.SecretSharing.Shamir
  ( splitSecret
  , combineShares
  ) where

import Control.Monad (replicateM, when)
import Data.ByteString (ByteString)
import qualified Data.ByteString as Bs
import qualified Data.List as L
import Data.Word (Word8)
import qualified System.Entropy as Ent

import qualified Crypto.SecretSharing.GF256 as GF256
import Crypto.SecretSharing.Types (Bitpad, SSSParams (..), ShareId (..))

-- | Split a secret bitpad into Shamir shares over GF(256).
--
-- Pre-conditions (enforced by 'validateParameters'):
--
-- * threshold >= 1
-- * totalShares >= threshold
-- * totalShares <= 255
-- * secret is non-empty
--
-- The secret is treated as an element of a GF(256)-vector space. We pick
-- a random polynomial f(x) of degree threshold - 1 with the secret as
-- constant term, but coefficients are full ByteStrings ("vectors").
--
-- Each share is the evaluation of that vector-valued polynomial at
-- x = 1 .. totalShares.
splitSecret :: SSSParams -> Bitpad -> IO [(ShareId, ByteString)]
splitSecret parameters secret = do
  validateParameters parameters secret

  if parameters.threshold <= 1
    then
      pure
        [ (ShareId shareIndex, secret)
        | shareIndex <- [1 .. parameters.totalShares]
        ]
    else do
      let secretLength = Bs.length secret
          degree = parameters.threshold - 1

      coefficientVectors <-
        replicateM degree (Ent.getEntropy secretLength)

      let shares =
            [ ( ShareId shareIndex
              , evaluatePolynomialAt secret coefficientVectors (fromIntegral shareIndex)
              )
            | shareIndex <- [1 .. parameters.totalShares]
            ]

      pure shares

-- | Combine Shamir shares to reconstruct the original bitpad.
--
-- Requirements:
--
-- * 'threshold' >= 1;
-- * the list of shares contains at least 'threshold' elements;
-- * all shares have the same length;
-- * share IDs are distinct and between 1 and 255.
--
-- For threshold == 1, any single share is equal to the secret, and that
-- is what is returned (after basic sanity checks).
combineShares
  :: SSSParams
  -> [(ShareId, ByteString)]
  -> Either String Bitpad
combineShares parameters allShares = do
  when (parameters.threshold < 1) $
    Left "combineShares: threshold must be at least 1"

  when (null allShares) $
    Left "combineShares: no shares provided"

  when (length allShares < parameters.threshold) $
    Left "combineShares: not enough shares to reconstruct the secret"

  let sharesUsed =
        take parameters.threshold allShares

      shareByteStrings =
        map snd sharesUsed

      lengthVariants =
        L.nub (map Bs.length shareByteStrings)

  shareLength <-
    case lengthVariants of
      [] ->
        Left "combineShares: internal error, empty share length set"
      [lengthBytes] ->
        Right lengthBytes
      _ ->
        Left "combineShares: shares have inconsistent lengths"

  let xCoordinates =
        [ fromIntegral shareId.unShareId :: Word8
        | (shareId, _) <- sharesUsed
        ]

  when (any (== 0) xCoordinates) $
    Left "combineShares: share IDs must be >= 1"

  when (length xCoordinates /= length (L.nub xCoordinates)) $
    Left "combineShares: duplicate share IDs are not allowed"

  lambdaCoefficients <- lagrangeCoefficientsAtZero xCoordinates

  let
    step index
      | index >= shareLength = Nothing
      | otherwise =
          let shareBytesAtIndex =
                [ Bs.index shareBytes index
                | shareBytes <- shareByteStrings
                ]

              resultByte =
                foldl
                  GF256.add
                  0
                  ( zipWith
                      GF256.mul
                      lambdaCoefficients
                      shareBytesAtIndex
                  )
            in Just (resultByte, index + 1)

    secret = Bs.unfoldrN shareLength step (0 :: Int)

  pure $ fst secret

-- INTERNAL HELPERS -----------------------------------------------------

-- | Validate Shamir parameters and the secret.
validateParameters :: SSSParams -> Bitpad -> IO ()
validateParameters parameters secret = do
  when (parameters.threshold < 1) $
    error "splitSecret: threshold must be at least 1"

  when (parameters.totalShares < parameters.threshold) $
    error "splitSecret: totalShares must be >= threshold"

  when (parameters.totalShares > 255) $
    error "splitSecret: totalShares must be <= 255 (GF(256) limit)"

  when (Bs.null secret) $
    error "splitSecret: empty secret is not supported"

-- | Evaluate the vector-valued polynomial at a given x-coordinate.
--
-- 'constant' is the secret vector (degree 0 coefficient).
-- 'coefficientVectors' are the coefficients for degrees 1..d.
evaluatePolynomialAt
  :: ByteString
  -> [ByteString]
  -> Word8
  -> ByteString
evaluatePolynomialAt constant coefficientVectors x =
  let degreeCount = length coefficientVectors

      powers =
        [ GF256.pow x powerExponent
        | powerExponent <- [1 .. degreeCount]
        ]

      coefficientsWithPowers =
        zip coefficientVectors powers
   in combineVectors constant coefficientsWithPowers

-- | Combine the constant term and scalar-multiplied coefficients into
-- a single ByteString share.
--
-- For each byte position i:
--
--   result[i] = constant[i] + Σ (scalar_k * coefficient_k[i])
--
-- where '+' and '*' are operations in GF(256).
combineVectors :: ByteString -> [(ByteString, Word8)] -> ByteString
combineVectors constant coefficientsWithPowers =
  fst $ Bs.unfoldrN secretLength step (0 :: Int)
  where
    secretLength = Bs.length constant

    step index
      | index >= secretLength = Nothing
      | otherwise =
          let constantByte =
                Bs.index constant index

              termBytes =
                [ GF256.mul (Bs.index coefficient index) scalar
                | (coefficient, scalar) <- coefficientsWithPowers
                ]

              resultByte =
                foldl GF256.add constantByte termBytes
           in Just (resultByte, index + 1)

-- | Compute Lagrange basis coefficients l_j(0) for the provided
-- x-coordinates, i.e. the scalars λ_j such that:
--
--   f(0) = Σ_j λ_j * f(x_j)
--
-- for a polynomial f of degree < length xCoordinates.
--
-- In characteristic 2, for a single x_j, we have:
--
--   l_j(0) = Π_{i≠j} x_i / (x_j - x_i)
--          = Π_{i≠j} x_i / (x_j + x_i)
--
-- because subtraction is the same as addition.
lagrangeCoefficientsAtZero :: [Word8] -> Either String [Word8]
lagrangeCoefficientsAtZero xCoordinates = do
  traverse (lagrangeCoefficient xCoordinates) (zip [0 ..] xCoordinates)

lagrangeCoefficient :: [Word8] -> (Int, Word8) -> Either String Word8
lagrangeCoefficient xCoordinates (indexJ, xj) = do
  let indexedCoordinates =
        zip [0 ..] xCoordinates

      otherCoordinates =
        [ x
        | (indexI, x) <- indexedCoordinates
        , indexI /= indexJ
        ]

  factors <- traverse (basisFactor xj) otherCoordinates

  let coefficient =
        foldl GF256.mul 1 factors

  pure coefficient

basisFactor :: Word8 -> Word8 -> Either String Word8
basisFactor xj xi = do
  let denominator =
        GF256.add xj xi

  when (denominator == 0) $
    Left "lagrangeCoefficientsAtZero: duplicate x-coordinates"

  divisionResult <-
    maybeToEither
      "lagrangeCoefficientsAtZero: denominator has no inverse"
      (GF256.divide xi denominator)

  pure divisionResult

maybeToEither :: e -> Maybe a -> Either e a
maybeToEither errorMessage = maybe (Left errorMessage) Right
