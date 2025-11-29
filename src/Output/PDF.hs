{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}

module Output.PDF
  ( renderShareToPdf
  ) where

import Control.Monad (forM_)
import Crypto.SecretSharing.Types (ShareId)
import Data.Complex ( Complex(..) )
import Data.Foldable (for_)
import Data.List (sortOn)
import qualified Data.Text as T
import qualified Graphics.PDF as Pdf
import qualified Graphics.PDF.Text as Pdt
import qualified Layout.Page as Lp
import qualified Crypto.ECC.Types as E


-- | Render a single share into a multi-page PDF.
--
--   'Params' describes the physical page and grid geometry (in mm),
--   'ShareId' is used for document metadata, and the list of pages
--   contains the already-laid-out grids of cells.
renderShareToPdf
  :: Lp.Params
  -> ShareId
  -> [(Lp.PageNumber, [E.ECCBlock])]
  -> FilePath
  -> IO ()
renderShareToPdf params shareId blocksOnPage outputPath = do
  let
    (pageWidthPts, pageHeightPts) = pageSizePoints params
    pageRect = Pdf.PDFRect
          (0 :: Pdf.PDFFloat)
          (0 :: Pdf.PDFFloat)
          (realToFrac (round pageWidthPts) :: Pdf.PDFFloat)
          (realToFrac (round pageHeightPts) :: Pdf.PDFFloat)
    docInfo = Pdf.standardDocInfo
          { Pdf.author = "bitpad-sss"
          , Pdf.subject =
              "bitpad share "
                <> T.pack (show shareId)
          , Pdf.compressed = True
          }
    sortedPages = sortOn fst blocksOnPage

  Pdf.runPdf outputPath docInfo pageRect $ do
    for_ sortedPages $ \(pageNumber, blocksOnPage) -> do
      page <- Pdf.addPage Nothing
      Pdf.drawWithPage page $ drawPage params pageWidthPts pageHeightPts pageNumber blocksOnPage

--------------------------------------------------------------------------------
-- Page drawing
--------------------------------------------------------------------------------

-- | Convert the configured page size (mm) to PDF points.
--
--   1 inch = 25.4 mm, 1 point = 1/72 inch.
pageSizePoints :: Lp.Params -> (Pdf.PDFFloat, Pdf.PDFFloat)
pageSizePoints params =
  ( mmToPt params.pageWidthMM
  , mmToPt params.pageHeightMM
  )

mmToPt :: Double -> Pdf.PDFFloat
mmToPt mm = mm * 72.0 / 25.4

-- | Draw a single page:
--   - clear background
--   - paint all dark cells as black squares.
drawPage
  :: Lp.Params
  -> Pdf.PDFFloat
  -> Pdf.PDFFloat
  -> Lp.PageNumber
  -> [E.ECCBlock]
  -> Pdf.Draw ()
drawPage params pageWidthPts pageHeightPts pageNumber blocks = do
  Pdf.setRGBColorSpace

  -- Background (explicit white fill is safer for printers/scanners).
  Pdf.fillColor Pdf.white
  Pdf.fill $
    Pdf.Rectangle
      (0 :+ 0)
      (pageWidthPts :+ pageHeightPts)

  -- Now draw all "dark" cells as black squares.
  let
    pageGrid = Lp.renderPageGrid params pageNumber blocks
    cells = Lp.pageGridCells pageGrid
  Pdf.fillColor Pdf.black

  forM_ cells $ \cell ->
    if cellIsDark cell
      then Pdf.fill (cellRectangle params cell)
      else pure ()

--------------------------------------------------------------------------------
-- Mapping logical cells to PDF rectangles
--------------------------------------------------------------------------------

-- | Decide whether a cell should be drawn dark.
--
--   Adjust this if you have a richer 'Cell' / 'CellRole' type
--   (for example to always draw finder patterns dark, or to leave
--   quiet-zone cells empty regardless of their bit value).
cellIsDark :: Lp.Cell -> Bool
cellIsDark cell =
  cell.bit

-- | Convert a logical cell (row/column) into a rectangle in PDF points.
--
--   Assumptions:
--   * 'row' and 'col' are 0-based indices;
--   * (row = 0, col = 0) is the bottom-left cell of the grid;
--   * cells are laid out in a regular grid with a fixed pitch
--     (cell size + spacing) both horizontally and vertically;
--   * the whole grid is anchored at (marginLeftMM, marginBottomMM).
--
--   If your coordinate conventions differ (e.g. row 0 is at the top),
--   adjust the mapping here; everything else can stay the same.
cellRectangle :: Lp.Params -> Lp.Cell -> Pdf.Rectangle
cellRectangle params cell =
  let cellSizeMM = params.cellSizeMM
      cellPitchMM = params.cellSizeMM + params.cellSpacingMM

      -- Anchor the grid at the bottom-left inside the margins.
      gridOriginXMM = params.marginLeftMM
      gridOriginYMM = params.marginBottomMM

      xMM =
        gridOriginXMM
          + fromIntegral cell.col * cellPitchMM
      yMM =
        gridOriginYMM
          + fromIntegral cell.row * cellPitchMM

      xPts = mmToPt xMM
      yPts = mmToPt yMM
      sPts = mmToPt cellSizeMM
   in Pdf.Rectangle
        (xPts :+ yPts)
        ((xPts + sPts) :+ (yPts + sPts))
