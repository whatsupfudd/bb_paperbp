
module Layout.Page where


import qualified Data.Bits as Bits
import qualified Data.ByteString as Bs
import qualified Data.List as L
import Data.Word (Word8)

import Crypto.ECC.Types (ECCBlock, eccGroupId, eccBlockIndex, unECCGroupId, eccBlockBytes)
import Data.Bits ((.&.))

type PageNumber = Int

-- Bit grid for a page; you will probably switch to something more
-- efficient later (e.g. a packed representation).
type PageGrid = [[Bool]]

data Params = Params
  { dpi :: Int
  , pageWidthMM :: !Double
  , pageHeightMM :: !Double
  , marginLeftMM :: !Double
  , marginRightMM :: !Double
  , marginTopMM :: !Double
  , marginBottomMM :: !Double
  , cellSizeMM :: !Double
  , cellSpacingMM :: !Double
  , tilesPerPage :: (Int, Int) -- (tilesX, tilesY)
  , tileGridSize :: (Int, Int) -- (cellsX, cellsY) per tile
  }
  deriving (Show)

data Cell = Cell
  { row :: !Int  -- 0-based row index in the PageGrid
  , col :: !Int  -- 0-based column index in the PageGrid
  , bit :: !Bool -- True = dark, False = light
  }
  deriving (Eq, Show)


-- | Flatten a PageGrid ([[Bool]]) into a list of Cells.
--
-- Row 0 is the first row in the outer list, column 0 is the first
-- element in the inner list. 'renderPageGrid' already builds the grid
-- in row-major order, so this is just a structured view on that.
pageGridCells :: PageGrid -> [Cell]
pageGridCells rows =
  [ Cell
      { row = rowIndex
      , col = colIndex
      , bit = value
      }
  | (rowIndex, rowBits) <- zip [0 ..] rows
  , (colIndex, value)   <- zip [0 ..] rowBits
  ]


-- | Assign ECC blocks to pages, based on the number of tiles available
-- per page. This implementation assumes a simple "one block per tile"
-- mapping, so:
--
--   blocksPerPage = tilesX * tilesY
--
-- It preserves all blocks (no dropping) and returns pages numbered from
-- 1 upwards. The order of blocks is normalised first so that:
--
--   * blocks are sorted by (eccGroupId, eccBlockIndex);
--   * pagination is stable and deterministic.
assignBlocksToPages :: Params -> [ECCBlock] -> [(PageNumber, [ECCBlock])]
assignBlocksToPages params blocks =
  case blocksPerPage params of
    0 ->
      -- This is a configuration error: with zero blocks per page we can
      -- never assign anything. Fail loudly.
      error "assignBlocksToPages: tilesPerPage yields 0 blocks per page"
    capacity ->
      let
        sortedBlocks = sortBlocks blocks
        pagesBlocks = chunkList capacity sortedBlocks
        pageNumbers = [1 ..]
      in
      zip pageNumbers pagesBlocks

-- | Compute how many ECC blocks can be placed on a single page, based
-- purely on the number of tiles.
--
-- Currently we use a very simple model: one ECCBlock per tile.
blocksPerPage :: Params -> Int
blocksPerPage params =
  let
    (tilesX, tilesY) = params.tilesPerPage
  in tilesX * tilesY

-- | Sort ECC blocks in a stable, deterministic way.
--
-- We sort primarily by ECC group ID and then by block index. This
-- ensures that pagination is independent of the order in which blocks
-- arrived from the ECC encoder.
sortBlocks :: [ECCBlock] -> [ECCBlock]
sortBlocks = L.sortOn (\block -> (block.eccGroupId, block.eccBlockIndex))

-- | Split a list into chunks of at most the given size.
--
-- The last chunk may be shorter than the requested size; all elements
-- are preserved.
chunkList :: Int -> [a] -> [[a]]
chunkList size elements
  | size <= 0 = error "chunkList: non-positive chunk size"
  | otherwise = chunk elements
  where
    chunk [] = []
    chunk xs =
      let
        (prefix, suffix) = splitAt size xs
      in
      prefix : chunk suffix


-- | Turn a list of ECC blocks (for a single page) into a 2D bit grid.
--
-- Tiles are arranged row-major across the page:
--
--   tile index = tileY * tilesX + tileX
--
-- Block i goes to tile index i; if there are fewer blocks than tiles,
-- remaining tiles are blank (all False).
--
-- Within each tile, bits are laid out row-major across the tile
-- grid. The first bits are tile header bits, then payload bits, and
-- finally padding bits as needed.
renderPageGrid :: Params -> PageNumber -> [ECCBlock] -> PageGrid
renderPageGrid params pageNumber blocks =
  let (tilesX, tilesY) =
        params.tilesPerPage

      (tileCellsX, tileCellsY) =
        params.tileGridSize

      tileCapacityBits =
        tileCellsX * tileCellsY

      capacityBlocksPerPage =
        tilesX * tilesY

   in if capacityBlocksPerPage <= 0
        then
          error "renderPageGrid: tilesPerPage yields 0 tiles"
        else
          let blocksWithPadding =
                padBlocks capacityBlocksPerPage blocks

              tileGridsFlat =
                [ encodeBlockIntoTile (tileCellsX, tileCellsY) tileCapacityBits maybeBlock
                | maybeBlock <- blocksWithPadding
                ]

              tileGrids2D =
                chunkList tilesX tileGridsFlat

              pageRows =
                mergeTileRows tileCellsY tileGrids2D
           in pageRows

-- | Ensure we have exactly 'capacity' tiles: take existing blocks and
-- pad with 'Nothing' for blank tiles.
padBlocks :: Int -> [ECCBlock] -> [Maybe ECCBlock]
padBlocks capacity blocks =
  let presentBlocks =
        map Just blocks

      missingCount =
        max 0 (capacity - length presentBlocks)

      missingTiles =
        replicate missingCount Nothing
   in take capacity (presentBlocks <> missingTiles)

-- | Encode one tile (maybe containing a block) into a tile grid
-- (2D bit array).
encodeBlockIntoTile :: (Int, Int) -> Int -> Maybe ECCBlock -> [[Bool]]
encodeBlockIntoTile (tileCellsX, tileCellsY) tileCapacityBits maybeBlock =
  case maybeBlock of
    Nothing ->
      blankTileGrid (tileCellsX, tileCellsY)
    Just eccBlock ->
      let
        headerBytes = tileHeaderBytes eccBlock
        payloadBytes = eccBlock.eccBlockBytes
        headerBits = bytesToBits headerBytes
        payloadBits = bytesToBits (Bs.unpack payloadBytes)
        allBits = headerBits <> payloadBits
        totalBits = length allBits
      in
      if totalBits > tileCapacityBits then
        error
          ( "encodeBlockIntoTile: block (groupId="
              <> show eccBlock.eccGroupId
              <> ", index="
              <> show eccBlock.eccBlockIndex
              <> ") does not fit into tile capacity (bits="
              <> show tileCapacityBits
              <> ", needed="
              <> show totalBits
              <> ")"
          )
      else
        let
          paddingBits = replicate (tileCapacityBits - totalBits) False
          paddedBits = allBits <> paddingBits
          rows = chunkList tileCellsX paddedBits
          in take tileCellsY rows

-- | Blank tile grid filled with False bits.
blankTileGrid :: (Int, Int) -> [[Bool]]
blankTileGrid (tileCellsX, tileCellsY) = replicate tileCellsY (replicate tileCellsX False)

-- | Merge a 2D array of tiles into page rows.
--
-- 'tileRows' has shape:
--
--   [ [ tile00, tile01, ... tile0N ]
--   , [ tile10, tile11, ... tile1N ]
--   , ...
--   ]
--
-- where each tile is a [[Bool]] of size (tileCellsY x tileCellsX).
--
-- We produce a PageGrid by concatenating tiles horizontally for each
-- row of tiles, and vertically bumping by tileCellsY.
  -- tileRows: [ [ tileGrid ] ]
mergeTileRows :: Int -> [[[ [Bool] ]]] -> PageGrid
mergeTileRows tileCellsY  =
  concatMap mergeTileRow 
  where
    mergeTileRow :: [[ [Bool] ]] -> [[Bool]]
    mergeTileRow tileRowGrids =
      [ concat [ tileGrid !! localRow | tileGrid <- tileRowGrids ] | localRow <- [0 .. tileCellsY - 1] ]

-- ----------------------------------------------------------------------
-- Bit-level helpers and tile header encoding
-- ----------------------------------------------------------------------

tileMagic :: Word8
tileMagic = 0xA5

tileHeaderVersion :: Word8
tileHeaderVersion = 0x01

-- | Construct the fixed 6-byte header for a tile carrying 'ECCBlock'.
--
-- Layout:
--
-- * b0: magic (0xA5)
-- * b1..b3: ECCGroupId (24-bit big-endian)
-- * b4: eccBlockIndex
-- * b5: header version (0x01)
tileHeaderBytes :: ECCBlock -> [Word8]
tileHeaderBytes eccBlock =
  let 
    groupIndex = eccBlock.eccGroupId.unECCGroupId
    groupMasked = groupIndex .&. 0xFFFFFF
    b0 = tileMagic
    b1 = fromIntegral ((groupMasked `Bits.shiftR` 16) .&. 0xFF)
    b2 = fromIntegral ((groupMasked `Bits.shiftR` 8) .&. 0xFF)
    b3 = fromIntegral (groupMasked .&. 0xFF)
    b4 = fromIntegral (eccBlock.eccBlockIndex .&. 0xFF)
    b5 = tileHeaderVersion
  in
  [b0, b1, b2, b3, b4, b5]

-- | Convert a list of bytes into a list of bits (MSB-first per byte).
bytesToBits :: [Word8] -> [Bool]
bytesToBits = concatMap byteToBits

byteToBits :: Word8 -> [Bool]
byteToBits word8 = [ Bits.testBit word8 bitIndex | bitIndex <- [7, 6 .. 0] ]
