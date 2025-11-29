{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

module Crypto.ECC.Types
  ( ECCParams (..)
  , ECCGroupId (..)
  , ECCBlock (..)
  ) where

import Data.ByteString (ByteString)
import Data.Word (Word32)
import GHC.Generics (Generic)

-- | Parameters for the erasure-coding (FEC) layer.
--
-- * 'requiredBlocks' = k  (blocks needed to reconstruct)
-- * 'totalBlocks'    = n  (total blocks produced by FEC)
-- * 'maxBlockSize'   = maximum allowed block size (bytes) after FEC;
--                      used to choose segment size.
data ECCParams = ECCParams
  { requiredBlocks :: Int
  , totalBlocks :: Int
  , maxBlockSize :: Int
  }
  deriving stock (Eq, Show, Generic)

-- | Identifier for an ECC group (one segment of the original data that
-- was encoded into 'totalBlocks' blocks by FEC).
newtype ECCGroupId = ECCGroupId
  { unECCGroupId :: Int
  }
  deriving stock (Eq, Ord, Show, Generic)

-- | A single ECC-protected block of bytes.
--
-- * 'eccGroupId' identifies which ECC group this block belongs to.
-- * 'eccBlockIndex' is a simple index 0..(totalBlocks-1) within the group.
--   FEC itself does not need this when using 'enFEC'/'deFEC', but it is
--   useful for layout, debugging, and sanity checks.
-- * 'eccBlockBytes' are the bytes to be printed in one or several tiles.
-- * 'eccBlockCrc32' is a CRC-32 checksum of 'eccBlockBytes' used to turn
--   bit-errors into erasures (by discarding blocks with wrong CRC).
data ECCBlock = ECCBlock
  { eccGroupId :: ECCGroupId
  , eccBlockIndex :: Int
  , eccBlockBytes :: ByteString
  , eccBlockCrc32 :: Word32
  }
  deriving stock (Eq, Show, Generic)
