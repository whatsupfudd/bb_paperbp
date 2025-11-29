
module Crypto.ECC.Chunking
  ( encodeECC
  , decodeECC
  , segmentCountForLength
  , segmentPayloadBytes
  ) where

import Control.Monad (forM, when)

import Data.Bifunctor (first)
import Data.ByteString (ByteString)
import qualified Data.ByteString as Bs
import qualified Data.Digest.CRC32 as CRC32
import qualified Data.List as L
import qualified Data.Map.Strict as Mp

import qualified Codec.FEC as FEC
import Crypto.ECC.Types
  ( ECCBlock (..)
  , ECCGroupId (..)
  , ECCParams (..)
  )


-- | Compute the raw payload capacity (in bytes) of a single ECC segment.
--
-- One segment is encoded into 'totalBlocks' blocks using a k-of-n FEC
-- with 'requiredBlocks' = k, 'totalBlocks' = n. If we limit each block
-- to at most 'maxBlockSize' bytes, then a single segment may contain at
-- most k * maxBlockSize raw bytes.
segmentPayloadBytes :: ECCParams -> Int
segmentPayloadBytes eccParams =
  eccParams.requiredBlocks * eccParams.maxBlockSize

-- | Given ECC parameters and a total original length, compute the number
-- of ECC segments that will be produced by 'encodeECC'.
segmentCountForLength :: ECCParams -> Int -> Either String Int
segmentCountForLength eccParams originalLength = do
  when (originalLength < 0) $
    Left "segmentCountForLength: negative original length"

  let payloadBytes = segmentPayloadBytes eccParams

  when (payloadBytes <= 0) $
    Left "segmentCountForLength: non-positive segment payload capacity"

  let count =
        if originalLength == 0
          then 0
          else (originalLength + payloadBytes - 1) `div` payloadBytes

  pure count

-- | Encode a 'ByteString' into ECC-protected blocks.
--
-- Pre-conditions:
--
-- * 'requiredBlocks' >= 1
-- * 'totalBlocks' >= requiredBlocks
-- * 'totalBlocks' < 256  (FEC library limit)
-- * 'maxBlockSize' > 0
--
-- The caller is responsible for:
--
-- * Calling 'Codec.FEC.initialize' once at program startup, before
--   using this function (per the 'fec' package documentation).
-- * Persisting / embedding the original byte length alongside the
--   list of 'ECCBlock's, so that 'decodeECC' can trim padding on the
--   last segment.
encodeECC
  :: ECCParams
  -> ByteString
  -> Either String [ECCBlock]
encodeECC eccParams inputBytes = do
  validateECCParams eccParams

  let
    payloadBytes = segmentPayloadBytes eccParams

  when (payloadBytes <= 0) $ Left "encodeECC: non-positive segment payload capacity"

  let
    segments = splitIntoSegments payloadBytes inputBytes

  encodedGroups <- forM (zip [0 ..] segments) (uncurry (encodeSegment eccParams))
  pure (concat encodedGroups)

-- | Decode ECC-protected blocks back into the original 'ByteString'.
--
-- Arguments:
--
-- * 'ECCParams' as used for encoding;
-- * original byte length (to trim padding introduced by FEC splitting);
-- * list of 'ECCBlock' values (in any order, possibly with duplicates).
--
-- Behaviour:
--
-- * Blocks are grouped by 'ECCGroupId';
-- * For each expected group, we:
--   - discard blocks whose CRC-32 does not match 'eccBlockCrc32';
--   - require at least 'requiredBlocks' surviving blocks;
--   - call 'FEC.deFEC' with those blocks;
-- * Segments are concatenated in ascending group-id order;
-- * The result is trimmed to the declared original length.
decodeECC
  :: ECCParams
  -> Int
  -> [ECCBlock]
  -> Either String ByteString
decodeECC eccParams originalLength eccBlocks = do
  validateECCParams eccParams

  segmentCount <- segmentCountForLength eccParams originalLength

  let groupsMap =
        groupBlocksById eccBlocks

  decodedSegments <-
    forM
      [0 .. segmentCount - 1]
      (decodeSegment eccParams groupsMap)

  let concatenated =
        Bs.concat decodedSegments

  pure (Bs.take originalLength concatenated)

-- INTERNALS ------------------------------------------------------------

validateECCParams :: ECCParams -> Either String ()
validateECCParams eccParams = do
  when (eccParams.requiredBlocks < 1) $
    Left "ECCParams: requiredBlocks must be at least 1"

  when (eccParams.totalBlocks < eccParams.requiredBlocks) $
    Left
      "ECCParams: totalBlocks must be >= requiredBlocks"

  when (eccParams.totalBlocks >= 256) $
    Left
      "ECCParams: totalBlocks must be < 256 (fec library limit)"

  when (eccParams.maxBlockSize <= 0) $
    Left "ECCParams: maxBlockSize must be positive"

splitIntoSegments :: Int -> ByteString -> [ByteString]
splitIntoSegments payloadBytes bytes
  | Bs.null bytes = []
  | otherwise =
      let (prefix, suffix) =
            Bs.splitAt payloadBytes bytes
       in prefix : splitIntoSegments payloadBytes suffix

encodeSegment
  :: ECCParams
  -> Int
  -> ByteString
  -> Either String [ECCBlock]
encodeSegment eccParams groupIndex segmentBytes = do
  when (Bs.null segmentBytes) $
    Left "encodeSegment: empty segment encountered"

  let requiredBlocks =
        eccParams.requiredBlocks

      totalBlocks =
        eccParams.totalBlocks

      fecBlocks =
        FEC.enFEC requiredBlocks totalBlocks segmentBytes

  when (length fecBlocks /= totalBlocks) $
    Left "encodeSegment: FEC returned unexpected number of blocks"

  let groupId = ECCGroupId groupIndex

      eccBlocks =
        [ ECCBlock
            { eccGroupId = groupId
            , eccBlockIndex = blockIndex
            , eccBlockBytes = blockBytes
            , eccBlockCrc32 = CRC32.crc32 blockBytes
            }
        | (blockIndex, blockBytes) <- zip [0 ..] fecBlocks
        ]

  pure eccBlocks

groupBlocksById :: [ECCBlock] -> Mp.Map ECCGroupId [ECCBlock]
groupBlocksById eccBlocks =
  Mp.fromListWith (++) [ (eccBlock.eccGroupId, [eccBlock]) | eccBlock <- eccBlocks ]

decodeSegment
  :: ECCParams
  -> Mp.Map ECCGroupId [ECCBlock]
  -> Int
  -> Either String ByteString
decodeSegment eccParams groupsMap groupIndex = do
  let
    groupId = ECCGroupId groupIndex
    blocksInGroup = Mp.findWithDefault [] groupId groupsMap

  when (null blocksInGroup) $
    Left
      ( "decodeSegment: no blocks found for ECCGroupId "
          <> show groupId
      )

  let
    validBlocks =
      L.nubBy sameBytes [ eccBlock | eccBlock <- blocksInGroup , CRC32.crc32 eccBlock.eccBlockBytes == eccBlock.eccBlockCrc32 ]

    requiredBlocks = eccParams.requiredBlocks

  when (length validBlocks < requiredBlocks) $
    Left
      ( "decodeSegment: not enough valid blocks for ECCGroupId "
          <> show groupId
          <> " (have "
          <> show (length validBlocks)
          <> ", need "
          <> show requiredBlocks
          <> ")"
      )

  let blocksBytes =
        map (.eccBlockBytes) validBlocks

      totalBlocks =
        eccParams.totalBlocks

      decoded =
        FEC.deFEC requiredBlocks totalBlocks blocksBytes

  pure decoded

sameBytes :: ECCBlock -> ECCBlock -> Bool
sameBytes leftBlock rightBlock =
  leftBlock.eccBlockBytes == rightBlock.eccBlockBytes
