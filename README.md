# paperbp

**Paper-based, threshold-recoverable offline backup for BeeBod cryptographic
material.**

`paperbp` is a Haskell application and library for converting a binary
**bitpad** into redundant, independently storable paper shares that can
eventually be reconstructed after loss of the original digital copy.

The project combines three different protection mechanisms:

1. **Shamir secret sharing** separates the original bitpad into independent
   threshold shares;
2. **forward-error correction (FEC)** adds redundancy inside every share so
   damaged or unreadable printed blocks can be reconstructed; and
3. a **page/tile encoding layer** converts those protected blocks into dense
   machine-readable bit grids that can be rendered onto paper.

The intended recovery model is therefore:

```text
                     original bitpad
                           |
                           v
                    Shamir sharing
                     threshold 2
                      shares 3
                    /     |     \
                   /      |      \
                  v       v       v
             Share 1   Share 2   Share 3
                |         |         |
                v         v         v
               FEC       FEC       FEC
                |         |         |
                v         v         v
              pages     pages     pages
                |         |         |
                v         v         v
              paper     paper     paper
                |         |         |
        separate physical locations
```

Recovery requires any sufficiently complete **two share sets**:

```text
paper share A                 paper share B
      |                             |
      v                             v
scan / decode                 scan / decode
      |                             |
      v                             v
FEC recovery                  FEC recovery
      |                             |
      +-------------+---------------+
                    |
                    v
            Shamir reconstruction
                    |
                    v
              original bitpad
```

The current repository implements substantial parts of the **forward**
pipeline:

```text
ByteString
    ->
Shamir shares
    ->
ECC/FEC blocks
    ->
page assignment
    ->
bit-grid tiles
    ->
PDF
```

The inverse scanner/recovery pipeline is **not yet implemented**.

The project is therefore an early but meaningful prototype of the complete
BeeBod paper-backup system.

Current package version:

```text
0.1.0.0
```

---

## Contents

- [Role in BeeBod](#role-in-beebod)
- [Why paper backup?](#why-paper-backup)
- [Protection model](#protection-model)
- [Current implementation status](#current-implementation-status)
- [Architecture](#architecture)
- [Getting started](#getting-started)
- [Current CLI](#current-cli)
- [End-to-end prototype workflow](#end-to-end-prototype-workflow)
- [Shamir secret sharing](#shamir-secret-sharing)
- [Forward-error correction](#forward-error-correction)
- [Page and tile layout](#page-and-tile-layout)
- [PDF generation](#pdf-generation)
- [Target physical format](#target-physical-format)
- [Recovery pipeline](#recovery-pipeline)
- [Metadata and self-description](#metadata-and-self-description)
- [Integrity and authenticity](#integrity-and-authenticity)
- [Physical storage model](#physical-storage-model)
- [Capacity and paper efficiency](#capacity-and-paper-efficiency)
- [Performance](#performance)
- [Module map](#module-map)
- [Testing](#testing)
- [Security considerations](#security-considerations)
- [Development roadmap](#development-roadmap)
- [Design principles](#design-principles)
- [Current limitations](#current-limitations)
- [Repository housekeeping](#repository-housekeeping)
- [License](#license)

---

# Role in BeeBod

BeeBod uses cryptographic material whose loss can be more serious than the
loss of an ordinary application file.

Some digital information can be restored from:

```text
database replicas
object storage
cloud backups
Git repositories
other online systems
```

but the highest-value recovery material should not depend entirely on the
same digital infrastructure it is intended to recover.

`paperbp` therefore provides a deliberately different recovery medium:

> **machine-readable information printed onto ordinary archival paper and
> stored offline in physically separated locations.**

Paper has several useful properties for this role.

It is:

```text
offline
vendor-independent
human-custodiable
not remotely erasable
not dependent on a filesystem
not dependent on a cloud account
visually inspectable
easy to place in physically separated secure storage
```

The project is not intended to replace ordinary digital backups.

It provides an **independent last-resort recovery layer**.

---

# Why paper backup?

A digital backup can fail together with the primary system.

Examples include:

```text
credential compromise
ransomware
malicious deletion
cloud-account loss
operator mistakes
filesystem corruption
storage-controller failure
provider shutdown
long-term format/platform disappearance
```

A properly designed paper backup has a different failure mode.

An attacker capable of remotely deleting digital copies cannot remotely
erase sheets stored in separate physical locations.

At the same time, raw binary data cannot simply be printed as ordinary
text.

A practical paper system must survive:

```text
printer defects
scanner defects
dust
scratches
folds
partial page damage
missing pages
slight geometric distortion
contrast variation
individual bit errors
entire unreadable blocks
```

That is why `paperbp` combines threshold sharing with local
error-correction.

---

# Protection model

The system uses two distinct forms of redundancy.

They solve different problems.

---

## 1. Shamir secret sharing

Shamir sharing protects against:

```text
loss of one storage location
compromise of one storage location
```

With the current prototype policy:

```text
threshold   = 2
totalShares = 3
```

the original bitpad is converted into:

```text
Share 1
Share 2
Share 3
```

Any two can reconstruct the original.

One share alone should reveal no useful information about the secret under
the Shamir model.

This gives the physical-storage system a useful property:

```text
one location lost       -> recoverable
one location stolen     -> secret remains protected
two locations available -> recoverable
```

---

## 2. Forward-error correction

FEC protects each individual share from media damage.

The current prototype uses:

```text
requiredBlocks = 6
totalBlocks    = 10
```

for every encoded segment.

A segment therefore produces ten FEC blocks but only six valid blocks are
required for reconstruction.

Conceptually:

```text
share segment
      |
      v
+-------------------+
| FEC 6-of-10       |
+-------------------+
      |
      +--> block 0
      +--> block 1
      +--> block 2
      +--> ...
      `--> block 9
```

Up to four blocks in a group can therefore be missing or rejected while the
segment remains reconstructable.

---

## The two layers are complementary

Shamir protects against **share-level loss or disclosure**.

FEC protects against **damage inside one share**.

```text
                     BITPAD
                       |
                  Shamir 2/3
            +----------+----------+
            |          |          |
            v          v          v
         Share 1    Share 2    Share 3
            |          |          |
         FEC 6/10   FEC 6/10   FEC 6/10
            |          |          |
          pages      pages      pages
```

Using only FEC would not provide threshold secrecy.

Using only Shamir would make every printed share vulnerable to local print
or scan damage.

---

# Current implementation status

| Capability | Status |
| --- | --- |
| Binary bitpad input | Implemented |
| Shamir secret sharing | Implemented |
| Configurable `k-of-n` Shamir parameters | Implemented |
| GF(256) arithmetic | Implemented |
| Cryptographic random Shamir coefficients | Implemented |
| Shamir reconstruction | Implemented |
| Hedgehog Shamir round-trip property | Implemented |
| FEC encoding | Implemented |
| FEC decoding | Implemented |
| Configurable `k-of-n` FEC | Implemented |
| CRC-32 per in-memory FEC block | Implemented |
| Hedgehog FEC round-trip property | Implemented |
| ECC block segmentation | Implemented |
| Stable page assignment | Implemented |
| Tile bit-grid encoding | Implemented |
| PDF rendering | Implemented |
| Multi-page output | Implemented |
| One PDF per Shamir share | Implemented in prototype command |
| Self-describing paper format | Partial |
| CRC serialized onto paper | Not yet |
| Original bitpad length on paper | Not yet |
| SSS parameters on paper | Not yet |
| ECC parameters on paper | Not yet |
| Share ID encoded in page payload | Not yet |
| Page numbering encoded in grid | Not yet |
| Finder/alignment patterns | Not yet |
| Scanner/image ingestion | Not yet |
| Perspective correction | Not yet |
| Tile detection | Not yet |
| Grid binarization | Not yet |
| Printed-block decoder | Not yet |
| End-to-end paper recovery | Not yet |
| Strong whole-bitpad digest | Not yet |
| Page/share manifest | Not yet |
| Production layout optimization | Not yet |
| Automated package test runner | Placeholder |

The project should therefore currently be viewed as:

> **a working prototype of the cryptographic encoding and PDF-generation
> half of the paper-backup system.**

---

# Architecture

The implemented pipeline is:

```text
                     input ByteString
                           |
                           v
             Crypto.SecretSharing.Shamir
                           |
                           v
              [(ShareId, ByteString)]
                           |
                    for each share
                           |
                           v
                 Crypto.ECC.Chunking
                           |
                           v
                     [ECCBlock]
                           |
                           v
                    Layout.Page
                           |
                           v
              [(PageNumber,[ECCBlock])]
                           |
                           v
                     Output.PDF
                           |
                           v
                  share-<id>.pdf
```

The major architectural layers are intentionally independent.

```text
+---------------------------------------------------+
|               Secret-sharing layer                |
|                                                   |
| bitpad -> threshold shares                        |
+-------------------------+-------------------------+
                          |
                          v
+---------------------------------------------------+
|               Error-correction layer              |
|                                                   |
| share -> segments -> redundant ECC blocks         |
+-------------------------+-------------------------+
                          |
                          v
+---------------------------------------------------+
|                    Layout layer                   |
|                                                   |
| blocks -> tiles -> pages -> bit grids             |
+-------------------------+-------------------------+
                          |
                          v
+---------------------------------------------------+
|                    Output layer                   |
|                                                   |
| logical bit cells -> printable PDF geometry       |
+---------------------------------------------------+
```

This separation is important.

The cryptographic layer should not need to understand PDF coordinates.

The ECC layer should not need to know paper size.

The page layer should not need to know how Shamir interpolation works.

And future scanner code should be able to reconstruct `ECCBlock` values
without modifying the secret-sharing implementation.

---

# Getting started

## Requirements

The current Stack configuration uses:

```text
Stackage: LTS 22.44
GHC:      9.6.7
```

with:

```yaml
system-ghc: true
```

Important dependencies include:

```text
fec
digest
entropy
HPDF
hedgehog
bytestring
aeson
yaml
optparse-applicative
```

The current FEC dependency is pinned explicitly:

```yaml
fec-0.2.0
```

---

## Clone

```bash
git clone git@github.com:whatsupfudd/bb_paperbp.git
cd bb_paperbp
```

---

## Build

```bash
stack build
```

---

## CLI help

```bash
stack exec -- paperbp --help
```

The current executable exposes:

```text
help
version
test
```

---

# Current CLI

## Version

```bash
stack exec -- paperbp version
```

The command reports the package version and Git revision/date.

---

## Help

```bash
stack exec -- paperbp help
```

The command currently contains only placeholder output.

Use:

```bash
stack exec -- paperbp --help
```

for the useful option-parser help.

---

## Test / prototype generation

The principal operational command at present is:

```bash
stack exec -- paperbp test bitpad.bin
```

where:

```text
bitpad.bin
```

is the binary input to protect.

The command currently performs the complete implemented forward pipeline.

It generates files such as:

```text
share-1.pdf
share-2.pdf
share-3.pdf
```

in the current working directory.

---

# End-to-end prototype workflow

The current `test` command is particularly useful because it demonstrates
how the project's layers are intended to compose.

The hard-coded prototype parameters are currently:

```text
Shamir
-------

threshold   = 2
totalShares = 3


FEC
---

requiredBlocks = 6
totalBlocks    = 10
maxBlockSize   = 502 bytes
```

The execution path is:

```text
bitpad.bin
    |
    v
read ByteString
    |
    v
splitSecret
    |
    +----------+----------+
    |          |          |
    v          v          v
 share 1    share 2    share 3
    |          |          |
    v          v          v
 encodeECC  encodeECC  encodeECC
    |          |          |
    v          v          v
 page       page       page
 layout     layout     layout
    |          |          |
    v          v          v
 PDF        PDF        PDF
```

The relevant code is approximately:

```haskell
bitpad <- Bs.readFile testOpts.testArg

shares <- splitSecret sssParams bitpad

forM_ shares $ \(shareId, shareBytes) -> do
  eccBlocks <-
    either fail pure $
      encodeECC eccParams shareBytes

  let pages =
        assignBlocksToPages layoutParams eccBlocks

  renderShareToPdf
    layoutParams
    shareId
    pages
    ("share-" <> show shareId.unShareId <> ".pdf")
```

This is currently the clearest executable example of the package API.

---

# Shamir secret sharing

The secret-sharing implementation lives under:

```text
Crypto.SecretSharing.*
```

The major public operations are:

```haskell
splitSecret
  :: SSSParams
  -> Bitpad
  -> IO [(ShareId, ByteString)]

combineShares
  :: SSSParams
  -> [(ShareId, ByteString)]
  -> Either String Bitpad
```

---

## Parameters

```haskell
data SSSParams = SSSParams
  { threshold   :: Int
  , totalShares :: Int
  }
```

The implementation requires:

```text
threshold >= 1

totalShares >= threshold

totalShares <= 255
```

The upper bound follows from the use of GF(256) share coordinates.

---

## Bitpad

The current representation is deliberately simple:

```haskell
type Bitpad = ByteString
```

The secret-sharing layer therefore does not care whether the bytes represent:

```text
a finite one-time bitpad
keys
recovery material
an encrypted archive
another binary recovery payload
```

The BeeBod use case is the bitpad.

---

## GF(256)

The implementation contains its own finite-field layer in:

```text
Crypto.SecretSharing.GF256
```

with:

```haskell
add
mul
pow
inv
divide
```

Addition is XOR.

Multiplication uses the irreducible polynomial associated with the
AES-style GF(2^8) representation.

---

## Share generation

For a threshold greater than one, each byte position is protected by a
random polynomial.

Conceptually:

```text
f(x) = secret + a1*x + a2*x² + ...
```

over GF(256).

The coefficient vectors are generated using:

```text
System.Entropy.getEntropy
```

so every share set receives cryptographically generated random
coefficients.

Shares use coordinates:

```text
1 .. totalShares
```

and `ShareId 0` is invalid.

---

## Share reconstruction

`combineShares` uses Lagrange interpolation at:

```text
x = 0
```

to recover the original constant term.

Only:

```text
threshold
```

shares are consumed.

For example, under the prototype 2-of-3 policy, all of these combinations
can recover the bitpad:

```text
share 1 + share 2
share 1 + share 3
share 2 + share 3
```

---

## Current Shamir tests

A Hedgehog property already verifies:

```text
secret
  ->
split into N shares
  ->
select random threshold subset
  ->
combine
  ->
original secret
```

across randomized:

```text
thresholds
share counts
secret contents
```

This is an important foundation.

However, the test is currently housed in a library module rather than wired
into the package's normal `test/Spec.hs` runner.

---

# Forward-error correction

The FEC layer lives in:

```text
Crypto.ECC.*
```

and uses the `fec` Haskell package.

---

## ECC parameters

```haskell
data ECCParams = ECCParams
  { requiredBlocks :: Int
  , totalBlocks    :: Int
  , maxBlockSize   :: Int
  }
```

The parameters correspond to:

```text
k = requiredBlocks
n = totalBlocks
```

For the current prototype:

```text
k = 6
n = 10
```

---

## Segment size

One encoded segment can carry:

```text
requiredBlocks * maxBlockSize
```

raw bytes.

The helper:

```haskell
segmentPayloadBytes
```

calculates that capacity.

With the current prototype parameters:

```text
6 * 502 = 3012 bytes
```

of share content can be represented by one ten-block ECC group.

---

## Encoding

```haskell
encodeECC
  :: ECCParams
  -> ByteString
  -> Either String [ECCBlock]
```

splits a share into appropriately sized segments.

Each segment is passed to:

```haskell
Codec.FEC.enFEC
```

and becomes:

```text
ECC group
   |
   +-- block 0
   +-- block 1
   +-- ...
   `-- block n-1
```

---

## ECC block

```haskell
data ECCBlock = ECCBlock
  { eccGroupId    :: ECCGroupId
  , eccBlockIndex :: Int
  , eccBlockBytes :: ByteString
  , eccBlockCrc32 :: Word32
  }
```

The group ID identifies the original segment.

The block index identifies a block within that group.

The byte payload is what ultimately needs to be encoded onto paper.

A CRC-32 is calculated over the FEC block bytes.

---

## Turning errors into erasures

FEC recovery is much easier when the decoder can distinguish:

```text
known-good block
```

from:

```text
damaged block
```

The intended role of CRC-32 is therefore:

```text
scan block
    |
    v
reconstruct bytes
    |
    v
CRC check
   / \
  /   \
good   bad
 |      |
 v      v
use   discard
```

A rejected block becomes an erasure.

As long as enough valid FEC blocks remain, the group can still be decoded.

CRC-32 is used here for **error detection**, not cryptographic
authentication.

---

## Decoding

```haskell
decodeECC
  :: ECCParams
  -> Int
  -> [ECCBlock]
  -> Either String ByteString
```

requires the original byte length because the final FEC segment may contain
padding.

The decoder:

```text
groups blocks by ECCGroupId

checks CRC-32

removes duplicates

requires at least k blocks per group

calls FEC.deFEC

concatenates reconstructed segments

trims the result to original length
```

---

## FEC initialization

The `fec` package requires:

```haskell
FEC.initialize
```

before use.

The current prototype command performs this initialization before encoding.

Applications using the library directly must do the same.

---

## Current ECC tests

`Crypto.ECC.Test` contains a Hedgehog property that exercises:

```text
random ECC parameters
+
random binary payload
       |
       v
encodeECC
       |
       v
decodeECC
       |
       v
original payload
```

The property currently uses payloads up to:

```text
16384 bytes
```

for test speed.

As with the Shamir property, this test is not yet wired into
`test/Spec.hs`.

---

# Page and tile layout

`Layout.Page` converts ECC blocks into a physical page-oriented bit
representation.

The most important abstractions are:

```haskell
type PageNumber = Int

type PageGrid = [[Bool]]
```

and:

```haskell
data Params = Params
  { dpi            :: Int
  , pageWidthMM    :: Double
  , pageHeightMM   :: Double
  , marginLeftMM   :: Double
  , marginRightMM  :: Double
  , marginTopMM    :: Double
  , marginBottomMM :: Double
  , cellSizeMM     :: Double
  , cellSpacingMM  :: Double
  , tilesPerPage   :: (Int, Int)
  , tileGridSize   :: (Int, Int)
  }
```

---

## One block per tile

The current layout model intentionally starts with a simple rule:

```text
one ECCBlock = one tile
```

Therefore:

```text
blocksPerPage = tilesX * tilesY
```

For the current prototype:

```text
tilesPerPage = (8, 12)
```

so:

```text
96 ECC blocks / page
```

can be assigned logically.

---

## Deterministic pagination

Before pagination, ECC blocks are sorted by:

```text
ECCGroupId
ECCBlockIndex
```

This guarantees that page allocation does not depend on the order in which
blocks happen to arrive from the encoder.

Determinism is particularly important for archival output.

The same logical share and layout should produce the same page ordering.

---

## Tile structure

The current tile has:

```text
header bits
+
ECC payload bits
+
zero padding
```

The prototype tile grid is:

```text
64 x 64 cells
```

giving:

```text
4096 bits
```

of total tile capacity.

The current ECC block size is:

```text
502 bytes
```

or:

```text
4016 bits
```

and the current tile header is:

```text
6 bytes
```

or:

```text
48 bits
```

giving:

```text
4064 bits
```

before padding.

The current parameters therefore intentionally fit just below a 4096-bit
tile boundary.

---

## Current tile header

A populated tile currently begins with:

```text
byte 0      magic = 0xA5

bytes 1..3  ECC group ID
            24-bit big-endian

byte 4      ECC block index

byte 5      tile format version = 0x01
```

This is a useful start because it allows a future scanner to recognize:

```text
this is a paperbp tile
which FEC group it belongs to
which FEC block it represents
which tile format version is in use
```

---

## Blank tiles

Unused page positions are currently represented by all-light tiles.

This allows the final page in a share to contain fewer blocks than its
maximum capacity without changing the overall page-grid dimensions.

---

# PDF generation

`Output.PDF` converts the logical page grid into an HPDF document.

The primary public operation is:

```haskell
renderShareToPdf
  :: Layout.Params
  -> ShareId
  -> [(PageNumber, [ECCBlock])]
  -> FilePath
  -> IO ()
```

Each Shamir share becomes an independent PDF.

---

## Physical units

The layout model uses millimetres.

PDF internally uses points.

The conversion is:

```text
1 inch  = 25.4 mm
1 point = 1/72 inch
```

so:

```text
points = mm * 72 / 25.4
```

---

## Rendering model

The current renderer:

```text
creates a white page

constructs PageGrid

converts PageGrid to Cell values

draws one black PDF rectangle for every dark cell
```

Light cells require no explicit drawing because the page background is
white.

---

## PDF metadata

The current PDF includes metadata containing:

```text
author  = "bitpad-sss"
subject = "bitpad share <ShareId>"
```

This helps a human identify the document.

However, PDF metadata is not sufficient for disaster recovery because it may
be absent after:

```text
printing
photocopying
scanning
image conversion
physical separation
```

Critical recovery metadata must therefore eventually be encoded directly
into the printed page itself.

---

# Target physical format

The original BeeBod design is a **dense machine-readable grid**, not a
collection of human-readable hexadecimal values.

The target medium is standard printed paper produced and recovered using
ordinary high-resolution office equipment.

The intended physical representation should eventually contain:

```text
page-level finder patterns
page orientation markers
tile boundaries
quiet zones
alignment markers
share identity
page identity
format version
ECC metadata
payload metadata
error-detection information
strong integrity digest references
```

The current grid is only the payload foundation for that richer format.

---

## Why a custom grid?

The backup payload can be large.

Encoding hundreds of MiB using low-density textual formats would require an
unreasonable amount of paper.

The objective is therefore to maximize useful binary information per page
while retaining enough physical redundancy to survive realistic printing and
scanning defects.

That trade-off is central to `paperbp`.

---

# Recovery pipeline

The complete project requires the reverse of the current generation
pipeline.

The intended recovery path is:

```text
printed page
    |
    v
scanner / camera image
    |
    v
page detection
    |
    v
perspective correction
    |
    v
orientation detection
    |
    v
tile localization
    |
    v
cell sampling
    |
    v
bit reconstruction
    |
    v
tile header decode
    |
    v
ECCBlock
    |
    v
CRC / integrity validation
    |
    v
FEC reconstruction
    |
    v
share reconstruction
    |
    v
Shamir combination
    |
    v
whole-bitpad verification
```

None of the image-processing stages are present in the current repository.

They represent the largest missing functional half of the project.

---

# Metadata and self-description

A long-lived archival format must not depend on a developer remembering the
parameters used decades earlier.

The paper itself needs enough information to explain how it should be
decoded.

The current tile format is not yet sufficiently self-describing.

---

## Metadata currently encoded in each tile

The printed bit payload currently contains:

```text
magic
ECC group ID
ECC block index
tile-format version
ECC payload
```

---

## Important metadata not yet encoded

The current physical tile does **not** yet encode:

```text
ShareId
Shamir threshold
total Shamir shares

ECC requiredBlocks
ECC totalBlocks
ECC maxBlockSize

original share length
original bitpad length

CRC-32 value
whole-share digest
whole-bitpad digest

page number
total page count

document/archive identity
creation timestamp
format/profile identity
```

Some of these may belong at page or document level rather than in every
tile.

But a recovery implementation must be able to reconstruct them from the
physical medium.

---

## Recommended hierarchy

A robust format should distinguish:

```text
Archive metadata
    |
    +-- format version
    +-- archive ID
    +-- original length
    +-- strong digest
    +-- SSS parameters
    `-- encoding profile

Share metadata
    |
    +-- ShareId
    +-- share length
    +-- page count
    `-- share digest

Page metadata
    |
    +-- ShareId
    +-- page number
    +-- page count
    +-- layout profile
    `-- page integrity data

Tile metadata
    |
    +-- magic/version
    +-- ECC group ID
    +-- block index
    +-- payload length
    +-- CRC/checksum
    `-- payload
```

Metadata should itself receive strong redundancy.

A damaged page header must not make an otherwise intact page unrecoverable.

---

# Integrity and authenticity

Several different integrity questions exist.

They should not be collapsed into one checksum.

---

## Local scan-error detection

CRC-32 is appropriate for answering:

```text
"did this recovered block contain accidental bit errors?"
```

It is fast and sufficient for turning damaged blocks into FEC erasures.

---

## Whole-share integrity

A cryptographic digest should answer:

```text
"did we recover exactly the intended share?"
```

For example:

```text
SHA-256
```

or the project-standard modern cryptographic hash.

---

## Whole-bitpad integrity

After Shamir reconstruction, the final bitpad should be compared with an
archived strong digest.

This provides the final end-to-end check:

```text
paper
  ->
scan
  ->
ECC
  ->
shares
  ->
Shamir
  ->
bitpad
  ->
cryptographic digest
  ->
EXPECTED
```

Recovery should not be declared successful merely because decoding returned
some bytes.

---

## Authentication

CRC does not protect against intentional modification.

If the paper format must detect malicious substitution rather than only
accidental damage, it needs cryptographic authentication or a separately
trusted digest/signature record.

That is distinct from error correction.

---

# Physical storage model

The Shamir design only provides its intended resilience if the shares are
stored independently.

A 2-of-3 policy should therefore normally mean:

```text
Share 1 -> physical location A
Share 2 -> physical location B
Share 3 -> physical location C
```

not:

```text
three binders on the same shelf
```

The physical threats to consider include:

```text
fire
flood
theft
building loss
storage-provider failure
localized disaster
unauthorized access
```

The locations should therefore avoid common-mode failure where practical.

---

## Share confidentiality

Under a correct 2-of-3 Shamir implementation:

```text
one share alone
```

does not reconstruct the bitpad.

That permits each share to be stored with a custodian who should not, alone,
be capable of recovering the secret.

Operational procedures must still protect against multiple shares being
combined without authorization.

---

## Paper quality

Long-term deployment should use:

```text
stable archival paper
stable high-contrast printing
protected physical storage
clear human-readable labeling
```

rather than treating ordinary disposable office output as sufficient for
multi-decade recovery.

The machine-readable region and the human-readable custody labels serve
different purposes and should both exist.

---

# Capacity and paper efficiency

The original BeeBod design target is a large bitpad, approximately:

```text
250 MiB
```

rather than a short recovery key.

That makes information density important.

A 2-of-3 Shamir scheme expands physical information by approximately:

```text
3x
```

before error correction.

The current 6-of-10 FEC layer adds an additional expansion of approximately:

```text
10 / 6 = 1.667x
```

before headers, page metadata, alignment structures, and unused cells.

The theoretical combined data expansion is therefore already around:

```text
3 * 10/6
=
5x
```

relative to the original bitpad.

For a 250 MiB input this means the paper representation is carrying on the
order of:

```text
1.25 GiB
```

of FEC/share block data before physical-format overhead.

That makes page density and scan reliability first-class engineering
concerns rather than cosmetic layout details.

---

# Layout geometry

The current prototype configuration declares:

```text
page          210 x 297 mm
margins       10 mm
tiles/page    8 x 12
tile cells    64 x 64
cell size     3 mm
cell spacing  1 mm
DPI           600
```

These values should be understood as **development values**, not a validated
production layout.

In particular, the logical grid contains:

```text
8 * 64 = 512 columns
```

and the current PDF renderer uses a pitch of:

```text
3 mm + 1 mm = 4 mm
```

which would imply:

```text
512 * 4 mm = 2048 mm
```

of horizontal grid width.

That clearly does not fit on an A4 page.

The current code does not validate this geometric inconsistency.

A production layout must derive its cell geometry from:

```text
printable page dimensions
printer resolution
scanner resolution
required quiet zones
finder/alignment structures
expected geometric distortion
minimum reliable cell size
```

rather than relying on independent hard-coded values.

---

## `dpi` is currently informational

The `Layout.Params` type contains:

```haskell
dpi :: Int
```

but the current PDF output logic does not use it when calculating cell
geometry.

This is appropriate for vector PDF output in one sense, but the eventual
physical-profile validator should relate:

```text
cell size
printer DPI
scanner DPI
```

to estimated samples/pixels per cell and recovery margins.

---

# Performance

The current PDF renderer creates one PDF rectangle for every dark cell.

A page containing:

```text
8 * 12 * 64 * 64
=
393,216 cells
```

can therefore require a very large number of individual drawing operations.

For dense pseudo-random data, roughly half of those cells may be dark.

This is expensive.

The current representation is useful for proving the layout pipeline, but
it is not the preferred production rendering strategy for hundreds or
thousands of dense pages.

---

## Target rendering strategy

The logical abstraction should remain:

```text
PageGrid
```

but the output backend should eventually render that grid more efficiently.

Possible implementation strategies include:

```text
one packed monochrome raster image per page
larger grouped vector runs/rectangles
tile-level rasterization
streamed page generation
```

The key design principle is:

> preserve the logical page representation while allowing the physical
> renderer to change independently.

A scanner does not care whether the black cell was produced by one PDF
rectangle or one pixel inside a raster image.

---

## Memory usage

A complete 250 MiB workflow should not require holding:

```text
all Shamir shares
all ECC blocks
all pages
all rendered images
```

simultaneously in memory.

The longer-term encoder should support a streaming or bounded-memory
pipeline where possible.

For example:

```text
input stream
   |
   v
share/chunk processing
   |
   v
ECC group
   |
   v
page accumulator
   |
   v
render page
   |
   v
release page memory
```

The exact interaction with Shamir generation requires deliberate design
because all shares depend on the same secret input, but full-document
materialization should not be accepted without measurement.

---

# Module map

## Secret sharing

| Module | Responsibility |
| --- | --- |
| `Crypto.SecretSharing.Types` | `Bitpad`, `SSSParams`, `ShareId` |
| `Crypto.SecretSharing.GF256` | Finite-field arithmetic |
| `Crypto.SecretSharing.Shamir` | Share generation and reconstruction |
| `Crypto.SecretSharing.Test` | Hedgehog round-trip property |

---

## Error correction

| Module | Responsibility |
| --- | --- |
| `Crypto.ECC.Types` | ECC parameters, group IDs, protected blocks |
| `Crypto.ECC.Chunking` | Segmentation, FEC encoding and decoding |
| `Crypto.ECC.Test` | FEC round-trip property |

---

## Physical layout

| Module | Responsibility |
| --- | --- |
| `Layout.Page` | Block pagination, tile encoding, page-grid construction |

---

## Output

| Module | Responsibility |
| --- | --- |
| `Output.PDF` | HPDF-based page rendering |

---

## Commands

| Module | Responsibility |
| --- | --- |
| `Commands.Test` | Current end-to-end prototype pipeline |
| `Commands.Version` | Version and Git information |
| `Commands.Help` | Placeholder help command |
| `Commands` | Command aggregation |

---

## Application configuration

| Module | Responsibility |
| --- | --- |
| `Options.Cli` | CLI parser |
| `Options.ConfFile` | YAML file configuration |
| `Options.Runtime` | Effective runtime values |
| `Options` | Configuration merging |
| `MainLogic` | Command dispatch |

---

## Template/unused infrastructure

| Module | Current status |
| --- | --- |
| `DB.Connect` | Empty placeholder |
| `DB.Opers` | Empty placeholder |
| `HttpSup.CorsPolicy` | Empty placeholder |

These modules are inherited application-template scaffolding and are not
currently part of the paper-backup architecture.

They should either gain a concrete role or be removed.

---

# Testing

The project contains useful property tests, but the normal Stack test target
does not currently run them.

---

## Current `test/Spec.hs`

The package test executable currently only prints:

```text
Test suite not yet implemented
```

so:

```bash
stack test
```

does not validate the cryptographic pipeline.

---

## Existing property tests

Two valuable Hedgehog suites already exist.

### Shamir

```text
random secret
   |
   v
random k-of-n split
   |
   v
random k-share subset
   |
   v
combine
   |
   v
original secret
```

### FEC

```text
random payload
   |
   v
random valid ECC parameters
   |
   v
encode
   |
   v
decode
   |
   v
original payload
```

These should be wired directly into the package test runner.

---

## Missing tests

The paper format needs substantially broader testing.

Priority areas include:

```text
GF(256) arithmetic against known vectors

Shamir known-answer tests
Shamir insufficient-share rejection
duplicate ShareId rejection

FEC missing-block recovery
FEC corruption/CRC rejection
FEC duplicate-block handling
multi-segment reconstruction

tile-header encoding
tile-header decoding
bit ordering
tile capacity
pagination determinism

page geometry validation
PDF smoke tests

scan simulation
blur/noise tests
perspective distortion
contrast variation
missing tiles
missing pages

complete:
bitpad -> paper image -> bitpad
```

The final category is the most important qualification test for the project.

---

# Security considerations

`paperbp` handles high-value cryptographic recovery material.

The security bar should therefore be higher than for an ordinary document
generator.

---

## Custom cryptography requires review

The repository currently contains a custom implementation of:

```text
GF(256)
Shamir splitting
Shamir interpolation
```

The implementation is compact and property-tested, but correctness tests
alone do not constitute a production cryptographic review.

Before protecting real high-value bitpads, the implementation should receive:

```text
independent review
known-answer testing
cross-validation against another implementation
analysis of random-number use
analysis of side-channel relevance
format-security review
```

Where a mature, well-reviewed implementation can meet the exact format
requirements, it should be preferred over unnecessary custom cryptographic
code.

---

## CRC-32 is not authentication

CRC-32 detects accidental corruption.

It does not defend against an attacker intentionally constructing a modified
block with a matching CRC.

Strong cryptographic digests or signatures should protect archive-level
integrity where adversarial modification is in scope.

---

## Threshold policy is part of security

Changing:

```text
2-of-3
```

to another threshold changes both:

```text
availability
confidentiality
```

properties.

The selected policy must therefore be written into the physical archive
format and custody documentation.

---

## Share IDs are security-relevant metadata

Combining duplicated or incorrectly labeled shares must fail cleanly.

The paper format must make ShareId unambiguous and resistant to accidental
mislabeling.

---

## Physical possession matters

Once two valid 2-of-3 shares are combined, the original bitpad can be
recovered.

Custody policy is therefore part of the effective security architecture.

Cryptography does not replace operational separation.

---

# Development roadmap

## Phase 0 — Stabilize the current encoder

Before adding scanner support:

1. connect the existing Hedgehog suites to `stack test`;
2. add known-answer tests for GF(256) and Shamir;
3. add FEC missing/corrupt-block tests;
4. remove unused generic app-template modules;
5. clean configuration paths;
6. replace hard-coded test parameters with explicit encoding profiles;
7. add geometry validation; and
8. make the current forward pipeline deterministic and reproducible.

---

## Phase 1 — Define Paper Format v1

The most important near-term architectural task is to freeze an explicit
versioned physical format.

Define:

```text
archive header
share header
page header
tile header
byte order
bit order
identifiers
length fields
SSS parameters
ECC parameters
payload lengths
CRC fields
cryptographic digests
format versions
```

Create a written binary-format specification independent of the Haskell
implementation.

The paper should be recoverable from that specification even if the original
`paperbp` executable no longer exists.

---

## Phase 2 — Correct physical page geometry

Replace experimental cell measurements with validated profiles.

A profile should define:

```text
paper size
printable area
printer DPI
minimum reliable cell size
scanner assumptions
tile size
tile spacing
quiet zones
finder patterns
alignment patterns
page metadata area
human-readable area
```

Reject impossible configurations before PDF generation.

---

## Phase 3 — Efficient renderer

Replace one-PDF-rectangle-per-dark-cell output with an efficient backend.

Prefer:

```text
packed monochrome raster page
```

or another representation whose complexity is closer to:

```text
O(page pixels)
```

than hundreds of thousands of independent PDF objects/drawing calls.

Retain `PageGrid` or a packed equivalent as the logical boundary.

---

## Phase 4 — Page detection

Implement the beginning of the inverse pipeline:

```text
scanner image
   |
   v
detect page
   |
   v
find orientation
   |
   v
perspective correction
```

Finder and alignment structures must be designed together with this decoder.

---

## Phase 5 — Tile decoder

Implement:

```text
tile localization
cell sampling
thresholding
bit reconstruction
header recognition
payload extraction
CRC verification
```

Output:

```haskell
ECCBlock
```

so that the existing FEC decoder can be reused.

---

## Phase 6 — FEC-based physical recovery

Test recovery under deliberate media damage.

Simulate:

```text
missing tiles
scratched regions
random flipped cells
scanner noise
blur
rotation
perspective skew
brightness variation
partial page loss
```

Demonstrate successful recovery whenever at least the configured number of
valid blocks per ECC group remains.

---

## Phase 7 — Complete share reconstruction

Recover:

```text
scanned pages
   |
   v
ECC blocks
   |
   v
share ByteString
```

and verify the result against a strong share digest.

---

## Phase 8 — Complete 2-of-3 recovery

Recover any two physical share sets and run:

```haskell
combineShares
```

to recreate the original bitpad.

Validate the output against the archived cryptographic digest.

This is the milestone at which `paperbp` becomes a true paper-backup
**recovery system**, rather than only a paper encoder.

---

## Phase 9 — Large-bitpad scalability

Validate the complete workflow against the intended approximately:

```text
250 MiB
```

bitpad size.

Measure:

```text
share-generation time
ECC time
page count
PDF/image size
render time
peak memory
print time
scan time
decode time
recovery time
```

Optimize bottlenecks based on measured data.

---

## Phase 10 — Archival qualification

Perform real physical tests using:

```text
multiple printers
multiple scanners
different paper
photocopies
aged/faded samples
folds
stains
partial page damage
different scan resolutions
```

A paper-backup system is not validated by software round trips alone.

The physical channel is part of the system.

---

# Encoding profiles

Hard-coded parameters should evolve into named, versioned profiles.

For example, conceptually:

```text
PaperBP Profile
---------------

formatVersion

SSS:
  threshold
  totalShares

ECC:
  requiredBlocks
  totalBlocks
  maxBlockSize

Page:
  size
  margins
  tiles
  cell geometry
  finder pattern

Integrity:
  block checksum
  share digest
  archive digest
```

A printed archive should identify the exact profile used.

Profiles permit format evolution without making old paper unreadable.

---

# Human-readable page information

The machine-readable grid should be accompanied by visible human information.

A page should eventually show information such as:

```text
PAPERBP
Archive ID: ...
Share: 2 of 3
Threshold: 2
Page: 137 of 842
Format: PaperBP v1
Created: ...
```

and potentially a short fingerprint of the archive.

This information helps operators:

```text
sort pages
detect mixed archives
identify missing pages
avoid combining wrong shares
understand recovery requirements
```

Human-readable labels must not replace machine-readable metadata.

Both should derive from the same canonical metadata structure.

---

# Page independence

Recovery should tolerate pages arriving:

```text
out of order
duplicated
partially missing
```

The decoder should therefore not rely on physical page ordering.

Every page should carry sufficient identity to determine:

```text
archive
share
page number
format
```

independently.

Likewise, every tile should carry sufficient identity to determine its FEC
group/block position after scanning.

---

# Interleaving

A useful future improvement is to deliberately distribute FEC blocks so that
localized physical damage affects several groups slightly rather than
destroying too many blocks from one group.

Without interleaving:

```text
adjacent tiles
    =
adjacent blocks from same/nearby FEC groups
```

A spill or tear could therefore remove several blocks needed by one segment.

A deterministic interleaver can instead distribute related blocks across:

```text
different tiles
different pages
```

subject to an explicitly documented layout policy.

The recovery format must make de-interleaving deterministic.

---

# Design principles

## Paper is a storage medium, not a presentation medium

The PDF may look unusual.

The primary criterion is reliable machine recovery, not visual aesthetics.

---

## Recovery comes before density

Increasing density is valuable only while the recovery error rate remains
acceptable.

The optimal grid is not necessarily the grid that contains the greatest
number of theoretical bits per square centimetre.

---

## Each layer solves one failure class

Keep:

```text
Shamir
FEC
physical grid
cryptographic integrity
custody policy
```

as separate concepts.

Each solves a different problem.

---

## The physical format must be documented independently

A future recovery implementation may be written in:

```text
Haskell
Python
Rust
C
```

or another language.

The format must not depend on undocumented properties of the original
Haskell data structures.

---

## Recovery metadata must live on the medium

Do not require:

```text
a database
the original configuration file
the original computer
PDF metadata
a cloud service
```

to interpret the paper.

The paper archive must explain itself.

---

## Fail on ambiguity

If a scanner cannot confidently determine a bit, tile identity, share, or
page:

```text
reject or mark uncertain
```

rather than silently guessing.

FEC exists specifically to permit questionable blocks to be discarded.

---

## Preserve deterministic output

For the same:

```text
share bytes
encoding profile
```

logical block/page assignment should be reproducible.

This makes testing and archival verification easier.

---

## Separate logical layout from output backend

`Layout.Page` and `Output.PDF` already move in the right direction.

The logical bit grid should not depend on HPDF.

That permits future output backends such as:

```text
PNG
TIFF
printer raster formats
alternative PDF generation
```

without changing the cryptographic encoding.

---

## Physical recovery is the definition of success

The important test is not:

```text
PDF generated successfully
```

or even:

```text
PDF can be decoded digitally
```

but:

```text
print
  ->
store
  ->
scan
  ->
recover
  ->
exact original bytes
```

under realistic degradation.

---

# Current limitations

## Only the forward pipeline exists

There is no image/scanner decoder.

---

## Printed tiles are not yet self-sufficient

The current tile payload does not contain several values needed for
standalone recovery.

---

## CRC-32 is not printed

Although every in-memory `ECCBlock` contains:

```haskell
eccBlockCrc32
```

the current:

```haskell
tileHeaderBytes
```

does not serialize that value.

A future scanner therefore cannot currently reconstruct the complete
`ECCBlock` required by `decodeECC` from the printed tile alone.

This must be corrected as part of the format specification.

---

## Original lengths are not printed

`decodeECC` requires the original encoded share length to remove padding.

The current paper format does not encode this value.

---

## Shamir parameters are not printed

Recovery requires the threshold/share configuration.

The current PDF metadata mentions a `ShareId`, but the grid itself does not
contain the SSS parameters.

---

## ECC parameters are not printed

The decoder must know:

```text
requiredBlocks
totalBlocks
maxBlockSize
```

but these are currently hard-coded in the prototype command.

---

## ShareId is not encoded into tiles

`ShareId` appears in PDF metadata and the filename but not the tile header.

Printed pages should not depend on filenames or PDF metadata for share
identity.

---

## Page number is not currently encoded

`renderPageGrid` accepts:

```haskell
PageNumber
```

but does not use it when constructing the grid.

---

## There are no finder patterns

The current grid provides no explicit mechanism for locating, orienting, or
geometrically correcting a scanned page.

---

## Layout parameters are not geometrically validated

The present hard-coded prototype geometry does not fit within the configured
A4 page dimensions.

---

## `dpi` is unused by layout/rendering logic

It currently serves only as configuration metadata.

---

## PDF rendering is inefficient for dense pages

One rectangle is emitted for every dark cell.

Large real archives will require a more compact renderer.

---

## Empty secrets are unsupported

The Shamir implementation rejects empty input.

This is reasonable for the target bitpad use case but is part of the current
API contract.

---

## GF(256) inversion is brute-force

`inv` searches candidates from 1 through 255.

That is acceptable at the current prototype scale but is not an optimized
finite-field implementation.

---

## FEC requires explicit initialization

Callers must invoke:

```haskell
Codec.FEC.initialize
```

before using the encoder/decoder.

This global requirement should eventually be hidden behind a safer
application/library initialization boundary.

---

## Package test runner is a placeholder

Existing property tests are not currently run by `stack test`.

---

## Configuration is inherited generic scaffolding

The runtime configuration currently contains almost nothing except:

```text
debug
```

while actual SSS/ECC/layout parameters remain hard-coded in
`Commands.Test`.

---

## Default configuration path is inconsistent

The CLI help says:

```text
~/.paperbp/config.yaml
```

while the implementation currently loads:

```text
~/.fudd/simple.yaml
```

The latter is clearly generic template residue and should be replaced.

---

## Configuration is required before command dispatch

The current `Main.hs` loads a YAML configuration file before executing
commands such as:

```text
version
```

so a missing default configuration can prevent otherwise configuration-free
commands from running.

That should be relaxed.

---

# Repository housekeeping

The package metadata still points to:

```text
hugdro/paperbp
```

instead of the current:

```text
whatsupfudd/bb_paperbp
```

repository.

Update:

```text
github
homepage
bug-reports
source-repository
README URL
```

accordingly.

---

## Package description

The current repository description:

```text
BeeBod paper-based information backup system.
```

is directionally correct but understates the important architecture.

The package metadata should eventually describe the project as something
closer to:

```text
Threshold-recoverable, error-corrected paper backup for BeeBod
cryptographic recovery material.
```

---

## Unused generic modules

These current modules are empty:

```text
DB.Connect
DB.Opers
HttpSup.CorsPolicy
```

They should be removed unless paperbp develops an actual need for them.

A standalone offline recovery tool should preferably have very few external
runtime dependencies.

---

## Changelog

The changelog should begin tracking meaningful format milestones such as:

```text
Shamir implementation
FEC implementation
Paper Format v1
scanner decoder
full physical round trip
250 MiB qualification
```

Format changes are particularly important because already-printed archives
must remain recoverable.

---

# Long-term position

`paperbp` should ultimately become BeeBod's **digital-to-physical recovery
compiler and physical-to-digital recovery decoder**.

The full architecture is:

```text
                         BACKUP
                         ======

                    BeeBod bitpad
                          |
                          v
                  +----------------+
                  | Shamir 2-of-3  |
                  +-------+--------+
                          |
            +-------------+-------------+
            |             |             |
            v             v             v
         Share A       Share B       Share C
            |             |             |
            v             v             v
           FEC           FEC           FEC
            |             |             |
            v             v             v
        tile/page      tile/page      tile/page
          encoding       encoding       encoding
            |             |             |
            v             v             v
           PDF           PDF           PDF
            |             |             |
            v             v             v
          PRINT         PRINT         PRINT
            |             |             |
            v             v             v
       Location A    Location B    Location C


                        RECOVERY
                        ========

        any two physical share collections
                       |
                       v
                 scan pages
                       |
                       v
          detect / correct / sample
                       |
                       v
                decode tiles
                       |
                       v
             reject corrupt blocks
                       |
                       v
                  FEC recover
                       |
                       v
               reconstruct shares
                       |
                       v
                 Shamir combine
                       |
                       v
                  recovered bitpad
                       |
                       v
             cryptographic verification
```

The architecture deliberately combines three kinds of resilience:

```text
Shamir
    survives loss or compromise of an entire share location

FEC
    survives missing or corrupt physical blocks

physical paper
    survives failures or compromise of the digital storage environment
```

The next major milestone should therefore **not** be additional PDF
presentation features.

It should be to define **Paper Format v1** completely enough that every byte
required for recovery is represented on the physical medium, and then build
the inverse tile/scanner decoder.

Once:

```text
bitpad
  ->
paper
  ->
scan
  ->
bitpad
```

is a fully automated, byte-exact, property-tested and physically tested
round trip, `paperbp` becomes the disaster-recovery system it was designed
to be.

---

# License

The package declares the **BSD-3-Clause** license.

See the repository's `LICENSE` file for the authoritative license terms.