# caustic-image

A from-scratch image (de)coding library written in [Caustic](https://github.com/Caua726/Caustic) —
no libc, no libpng/libjpeg/giflib, no external libraries. Just the Caustic standard library, Linux
syscalls, and the sibling [`caustic-compact`](../caustic-compact) for the heavy entropy/compression
work (DEFLATE, CRC-32, LZW, and later the CSIF rANS substrate).

The target is a world-class native format, **CSIF** (spec under `causticos/docs/`), plus decode/encode
of the common foreign formats at libpng/libjpeg-turbo quality.

Eleven formats decode and nine encode. Where a reference implementation exists, correctness is pinned
against it: PNG/GIF/TIFF/BMP/QOI decode **byte-exact** vs libpng/giflib/libtiff, WebP (VP8L *and* VP8
lossy *and* ALPH alpha) **bit-exact** vs libwebp, JPEG within ±3 of libjpeg. Every encoder is verified
both by an internal round-trip and by decoding its output in the reference library.

## Status

| Format | Decode | Encode | Notes |
|---|---|---|---|
| QOI  | yes | yes | full (RGB/RGBA, run/index/diff/luma) |
| BMP  | yes | yes | 1/4/8-bit palette + RLE4/RLE8 + 24/32-bit, top-down & bottom-up; encode 24/32 |
| PNM  | yes | yes | P1–P6 decode; P5/P6 encode; 8-bit samples |
| TGA  | yes | yes | decode uncompressed+RLE 24/32/gray; encode uncompressed (no magic → decode when named) |
| PNG  | yes | yes | 1/2/4/8/16-bit, colour types 0/2/3/4/6, all filters, Adam7, APNG; encode 8/16-bit non-interlaced |
| GIF  | yes | yes | decode single-frame + animation (compositing); encode exact-palette single-frame + animation (NETSCAPE loop) |
| JPEG | yes | yes | decode baseline + progressive, fancy chroma upsampling (±3 of libjpeg); encode baseline 4:4:4 Annex-K tables, quality 90 (PSNR ~45 dB) |
| TIFF | yes | — | II/MM, strips, uncompressed / PackBits / LZW / DEFLATE (+ predictor 2); 8-bit gray/RGB/RGBA |
| ICO  | yes | — | favicon: largest entry, embedded-PNG or DIB+AND-mask |
| CSIF | yes | yes | native flagship — see below |
| WebP | yes | yes | decode VP8L, VP8 lossy, VP8X + **ALPH alpha** (raw + lossless, all unfilters) — bit-exact vs libwebp; encode VP8L |
| AVIF | — | — | later phase (AV1 intra) |

**Animation**: GIF (decode + encode, full compositing with disposal/transparency) and APNG (decode,
OP_SOURCE/OP_OVER blend + all disposals). **Deep colour**: PNG 16-bit decode+encode, CSIF 16-bit RAW/MODULAR.

### CSIF (native flagship)

A byte-exact container (64-byte header + CRC, chunk directory, TLV chunks with per-chunk CRC, mandatory
ILIM resource limits, IHDR geometry, ICOL/CICP colour with "Unspecified" banned) carrying a codec registry:

| Codec | Kind | Notes |
|---|---|---|
| RAW (0)     | lossless | identity (8/16-bit) |
| QOI (1)     | lossless | the QOI op-stream as a tile codec (8-bit) |
| MODULAR (2) | lossless | subtract-green + MED predictor, then best of DEFLATE / rANS / context-rANS (8/16-bit, deep colour) |
| DCT (3)     | lossy    | YCbCr 4:2:0 + forward DCT + quality-scaled quant (luma/chroma) + rANS; ~42 dB PSNR, beats our JPEG on photos (8-bit) |

Tiled images (ICOD tile grid + TIDX per-tile index with CRC and byte ranges) decode each tile
independently — the scalability substrate for partial/parallel decode. Decode is fail-loud: bad
magic/CRC/geometry/colour/codec each return a distinct numbered error
(exercised by a corruption corpus). rANS lives in `caustic-compact/entropy`.

Every decoder validates dimensions in widened arithmetic **before allocating** (`image_check_dims`,
the ILIM posture), so a malformed header can never trigger an allocation overflow.

## Layout

```
core/       errno · image (mmap-backed pixel buffer) · pixfmt · buf (offset-driven cursor) · sniff
formats/    qoi · bmp · pnm · tga · png (+APNG) · gif (+anim) · jpeg · tiff · webp · vp8 · ico
transform/  dct (shared fixed-point 8x8 FDCT/IDCT — JPEG + the CSIF DCT codec)
csif/       container (header/directory/chunks/TIDX tiling) · modular · dctc · errno
ops/        convert · crop · flips · rotations · resize (nearest + bilinear) · premultiply
decode.cst  sniff -> decoder dispatch        encode.cst  format id -> encoder dispatch
caustic_image.cst   library facade
examples/   identify ("FMT WxH")   convert (transcode any -> any)
tests/      run.sh + 39 test_*.cst (embedded vectors, cross-checked against reference decoders)
```

Heavy entropy/compression lives in the sibling `caustic-compact` and is shared, never duplicated:
DEFLATE/zlib, CRC-32, LZW (GIF + TIFF flavours), and the static/context rANS coders the CSIF codecs use.

## Build & test

caustic-image imports the sibling `caustic-compact`; cross-repo modules resolve only when the
workspace root (the parent directory holding both repos) is on the compiler's module path. The test
runner passes it via `--path` automatically:

```sh
bash tests/run.sh                       # build + run every test; "all green" on success
caustic --path <workspace-root> -c caustic_image.cst   # compile-check the whole tree
caustic --path <workspace-root> examples/identify.cst -o build/identify
build/identify some.png                 # -> "PNG 1920x1080"
```

Conventions follow the sibling libs: negative `i64` error codes (`core/errno.cst`), `snake_case`
functions, `PascalCase` structs, `_prefix` private, `SCREAMING` constants; no generic `Result`/`Option`.

## License

MIT — © Cauã Alvarenga Neves.
