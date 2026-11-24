# caustic-image

**A from-scratch image codec library in [Caustic](https://github.com/Caua726/Caustic) — no libc, no libpng, no libjpeg, no libwebp.**

![version](https://img.shields.io/badge/version-0.1.0-blue)
![dependencies](https://img.shields.io/badge/dependencies-caustic--compact-brightgreen)
![decode](https://img.shields.io/badge/decode-11%20formats-success)
![encode](https://img.shields.io/badge/encode-9%20formats-success)
![suites](https://img.shields.io/badge/suites-38-lightgrey)
![license](https://img.shields.io/badge/license-MIT-blue)

Eleven formats decode and nine encode, checked against the reference
implementations rather than against themselves: PNG, GIF, TIFF, BMP and QOI
decode **byte-exact** against libpng, giflib and libtiff; WebP — VP8L, VP8 lossy
*and* ALPH alpha — is **bit-exact** against libwebp; JPEG lands within ±3 of
libjpeg. Every encoder is verified twice, by an internal round-trip and by
decoding its output in the reference library.

It also carries **CSIF**, a native format designed here rather than
reimplemented: tiling, 16-bit, animation, and four codecs over a shared rANS
substrate.

The only dependency is the sibling
[`caustic-compact`](https://github.com/Caua726/caustic-compact), which supplies
the entropy layer — DEFLATE, CRC-32, LZW and rANS — so no compression algorithm
is written twice.

```sh
build/identify photo.png     # -> PNG 1920x1080
build/convert photo.png out.csif
```

---

## Contents

- [Formats](#formats)
- [CSIF, the native format](#csif-the-native-format)
- [Quick start](#quick-start)
- [Using it in a project](#using-it-in-a-project)
- [Correctness](#correctness)
- [Project layout](#project-layout)
- [Test surface](#test-surface)
- [Conventions](#conventions)
- [License](#license)

---

## Formats

| Format | Decode | Encode | Notes |
|---|---|---|---|
| QOI  | yes | yes | full (RGB/RGBA, run/index/diff/luma) |
| BMP  | yes | yes | 1/4/8-bit palette + RLE4/RLE8 + 24/32-bit, top-down and bottom-up; encode 24/32 |
| PNM  | yes | yes | P1–P6 decode; P5/P6 encode; 8-bit samples |
| TGA  | yes | yes | decode uncompressed + RLE 24/32/gray; encode uncompressed (no magic, so it decodes when named) |
| PNG  | yes | yes | 1/2/4/8/16-bit, colour types 0/2/3/4/6, all filters, Adam7, APNG; encode 8/16-bit non-interlaced |
| GIF  | yes | yes | decode single-frame and animation (compositing); encode exact-palette single-frame and animation (NETSCAPE loop) |
| JPEG | yes | yes | decode baseline and progressive, fancy chroma upsampling (±3 of libjpeg); encode baseline 4:4:4, Annex-K tables, quality 90 (PSNR ~45 dB) |
| TIFF | yes | — | II/MM, strips, uncompressed / PackBits / LZW / DEFLATE (+ predictor 2); 8-bit gray/RGB/RGBA |
| ICO  | yes | — | favicon: largest entry, embedded-PNG or DIB + AND-mask |
| WebP | yes | yes | decode VP8L, VP8 lossy, VP8X + **ALPH alpha** (raw and lossless, all unfilters) — bit-exact vs libwebp; encode VP8L |
| CSIF | yes | yes | the native format — tiling, 16-bit, animation (below) |
| AVIF | — | — | a later phase (AV1 intra) |

**Animation:** GIF (decode and encode, full compositing with disposal and
transparency) and APNG (decode, OP_SOURCE/OP_OVER blend, all disposals).
**Deep colour:** PNG 16-bit decode and encode, CSIF 16-bit RAW and MODULAR.

## CSIF, the native format

A byte-exact container — 64-byte header with CRC, a chunk directory, TLV chunks
each carrying their own CRC, mandatory `ILIM` resource limits, `IHDR` geometry,
and `ICOL`/`CICP` colour with "Unspecified" banned — over a codec registry:

| Codec | Kind | Notes |
|---|---|---|
| RAW (0)     | lossless | identity (8/16-bit) |
| QOI (1)     | lossless | the QOI op-stream as a tile codec (8-bit) |
| MODULAR (2) | lossless | subtract-green + MED predictor, then the best of DEFLATE / rANS / context-rANS (8/16-bit) |
| DCT (3)     | lossy    | YCbCr 4:2:0, forward DCT, quality-scaled luma/chroma quantisation, rANS; ~42 dB PSNR, and it beats our own JPEG on photographs (8-bit) |

Tiled images (an `ICOD` tile grid plus a `TIDX` per-tile index with CRCs and byte
ranges) decode each tile independently, which is the substrate for partial and
parallel decode.

**Animation is designed in, not bolted on.** An `IANI` header declares the
timeline — frame count, loop, an *explicit* tick base (never implied
centiseconds), canvas, background, and a bounded reference-slot count — and an
`IFRM` array carries per-frame control records whose `blend_op` and `dispose_op`
are closed enums with no default. Each frame is its own coded item with its own
`IDAT`, so any frame is directly addressable, and because `IANI`/`IFRM` are
non-critical a still-only reader skips them and renders the primary item — frame
0 — as the canonical rendition.

Decoding is fail-loud: bad magic, CRC, geometry, colour, codec or tick base each
return a distinct numbered error, exercised by a corruption corpus. Every decoder
validates dimensions in widened arithmetic **before allocating**
(`image_check_dims`, the ILIM posture), so a malformed header cannot trigger an
allocation overflow.

## Quick start

Requires the [Caustic toolchain](https://github.com/Caua726/Caustic) on `PATH`.

```sh
git clone https://github.com/Caua726/caustic-image
cd caustic-image

caustic-mk run test        # build and run all 38 suites
caustic-mk run test-opt    # the same, through the optimizing backend
```

`caustic-compact` is a declared dependency, so `caustic-mk` clones it into
`.caustic/deps` at the pinned tag on the first build. Nothing else is needed, and
nothing depends on where this repository sits on disk.

## Using it in a project

```
target "myapp" {
    src "src/main.cst"
    out "build/myapp"
    depend "caustic-image" in "https://github.com/Caua726/caustic-image" tag "v0.1.0"
}
```

```cst
use "caustic-image/decode.cst" as decode;
use "caustic-image/encode.cst" as encode;
```

`decode.cst` sniffs the format and dispatches; `encode.cst` dispatches on a
format id. Take a single format directly (`caustic-image/formats/png.cst`) when
you know what you have and want none of the rest linked in.

### While the bytes arrive

```cst
use "caustic-image/progressive.cst" as pg;

let is pg.Progressive as p = pg.progressive();
pg.feed(&p, chunk, n);          // per arrival: NEED, HEADER, ROWS, DONE or <0
pg.width(&p); pg.rows(&p);      // size from the header; finished top rows
pg.finish(&p);                  // no more bytes: decode()'s image, or its error
pg.take(&p, &image);            // the image is yours
pg.close(&p);                   // any time; also the cancel
```

Width and height are known from the header (PNG, JPEG, GIF, BMP, QOI). A
non-interlaced PNG shows its finished rows as its stream inflates
(caustic-compact's `inflate_stream`, never decoding a byte twice), and when it
arrived whole `finish` keeps them. Everything else is decoded at `finish`. The
final image, or the refusal, is always the one `decode()` gives for the same
bytes. A Progressive owns its state; separate ones on separate threads are
independent (finishing JPEG/WebP on two threads at once needs the lock
`decode()` needs).

## Correctness

A format is not considered done because it round-trips against itself — that only
proves the encoder and decoder share a misunderstanding. Each one is pinned to an
external reference:

| Checked against | Formats |
|---|---|
| **Byte-exact** vs libpng / giflib / libtiff | PNG, GIF, TIFF, BMP, QOI |
| **Bit-exact** vs libwebp | WebP: VP8L, VP8 lossy, ALPH alpha |
| **Within ±3** of libjpeg | JPEG baseline and progressive |
| Internal round-trip **and** reference decode | every encoder |
| Corruption corpus | CSIF: each failure mode returns its own numbered error |

## Project layout

```
core/       errno · image (mmap-backed pixel buffer) · pixfmt · buf (offset-driven cursor) · sniff
formats/    qoi · bmp · pnm · tga · png (+APNG) · gif (+anim) · jpeg · tiff · webp · vp8 · ico
transform/  dct (the shared fixed-point 8x8 FDCT/IDCT — JPEG and the CSIF DCT codec)
csif/       container (header/directory/chunks/TIDX tiling) · modular · dctc · errno
ops/        convert · crop · flips · rotations · resize (nearest + bilinear) · premultiply
decode.cst  sniff -> decoder dispatch      encode.cst  format id -> encoder dispatch
caustic_image.cst                          the library facade
examples/   identify ("FMT WxH") · convert (transcode anything to anything)
tests/      run.cst (the runner) + 38 suites with embedded vectors
```

Entropy coding is not here. DEFLATE/zlib, CRC-32, LZW (both the GIF and TIFF
flavours) and the static and context rANS coders all live in `caustic-compact`
and are shared rather than duplicated.

## Test surface

| Command | What it does |
|---|---|
| `caustic-mk run test` | All 38 suites |
| `caustic-mk run test-opt` | The same, through the optimizing backend (`-O1`) |
| `caustic-mk run clean` | Build artifacts and resolved dependencies |
| `caustic-mk run distclean` | Generated assembly and objects too |

The runner is `tests/run.cst`, written in Caustic. It replaced a bash script that
existed only to compute a `--path` into a sibling directory — which quietly made
the test suite pass on one machine and nowhere else.

## Conventions

Shared with the sibling libraries: negative `i64` error codes
(`core/errno.cst`), `snake_case` functions, `PascalCase` structs, `_prefix` for
private, `SCREAMING` for constants, and no generic `Result`/`Option`.

## License

MIT — see [LICENSE](LICENSE).
