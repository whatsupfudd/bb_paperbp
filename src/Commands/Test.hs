module Commands.Test where

import qualified Data.ByteString as Bs
import Data.Foldable (forM_)
import qualified Data.Text as T

import qualified Options.Runtime as Rto
import qualified Options.Cli as Cl
import Options.Cli (TestOpts(..))

import qualified Codec.FEC as FEC
import System.Exit (die)

import qualified Crypto.SecretSharing.Test as CTest
import qualified Crypto.SecretSharing.Shamir as Sha
import qualified Crypto.SecretSharing.Types as S
import qualified Crypto.ECC.Chunking as Ecc
import qualified Crypto.ECC.Types as E
import qualified Layout.Page as Layout
import qualified Output.PDF as Output


sssParams :: S.SSSParams
sssParams = S.SSSParams { threshold = 2, totalShares = 3 }

-- -- k, totalBlocks = 10    -- n , maxBlockSize = 1024 -- bytes per FEC block
eccParams :: E.ECCParams
eccParams = E.ECCParams  {
    requiredBlocks = 6
    , totalBlocks = 10
    , maxBlockSize = 502
  }

layoutParams :: Layout.Params
layoutParams = Layout.Params {
      dpi = 600
    , pageWidthMM = 210.0
    , pageHeightMM = 297.0
    , marginLeftMM = 10.0
    , marginRightMM = 10.0
    , marginTopMM = 10.0
    , marginBottomMM = 10.0
    , cellSizeMM = 3.0
    , cellSpacingMM = 1.0
    , tilesPerPage = (8, 12)
    , tileGridSize = (64, 64)
    }

testCmd :: Cl.TestOpts -> Rto.RunOptions -> IO ()
testCmd testOpts rtOpts = do
  putStrLn "@[testCmd] starting."
  result <- CTest.tests
  putStrLn $ "@[testCmd] result: " <> show result
  FEC.initialize
  bitpad <- Bs.readFile testOpts.testArg
  shares <- Sha.splitSecret sssParams bitpad

  forM_ shares $ \(shareId, shareBytes) -> do
    case Ecc.encodeECC eccParams shareBytes of
      Left errorMessage -> do
        putStrLn ("encodeECC failed for share " <> show shareId <> ": " <> errorMessage)
        die ("encodeECC failed for share " <> show shareId <> ": " <> errorMessage)
      Right eccBlocks ->
        let
          pages = Layout.assignBlocksToPages layoutParams eccBlocks
          grids = [
              (pageNumber, Layout.renderPageGrid layoutParams pageNumber blocksOnPage)
              | (pageNumber, blocksOnPage) <- pages
            ]
          outputPath = "share-" <> show shareId.unShareId <> ".pdf"
        in do
        putStrLn $ "@[testCmd] rendering share " <> show shareId <> " to " <> outputPath
        -- Output.renderShareToPdf layoutParams shareId grids outputPath
        Output.renderShareToPdf layoutParams shareId pages outputPath

