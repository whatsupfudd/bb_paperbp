{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedRecordDot #-}

module Crypto.SecretSharing.Types
  ( Bitpad
  , SSSParams (..)
  , ShareId (..)
  ) where

import Data.ByteString (ByteString)
import GHC.Generics (Generic)

type Bitpad = ByteString

newtype ShareId = ShareId {unShareId :: Int}
  deriving stock (Eq, Ord, Show, Generic)

-- | Parameters for Shamir secret sharing.
--
-- Pre-conditions for the implementation below:
--
-- * threshold >= 1
-- * totalShares >= threshold
-- * totalShares <= 255 (GF(256) limit on distinct x-coordinates)
data SSSParams = SSSParams
  { threshold :: Int
  , totalShares :: Int
  }
  deriving stock (Eq, Show, Generic)
