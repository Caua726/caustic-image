#!/usr/bin/env bash
# Build + run each caustic-image test, checking exit codes.
# A test passes iff its binary exits 0. Run from anywhere.
#
# caustic-image imports the sibling caustic-compact repo. Cross-repo modules
# ("caustic-compact/...") resolve only when the workspace root (the parent dir
# holding both repos) is on the compiler's module search path, so we pass it
# via --path as an absolute path.
set -u
ulimit -c 0 2>/dev/null || true         # don't litter core dumps on a crash
cd "$(dirname "$0")/.."                 # repo root: .../caustic-image
ROOT="$(cd .. && pwd)"                  # workspace root: .../Projetos-Pessoais
mkdir -p build
fail=0

run_case() {
    local name="$1" src="$2"
    printf '[build] %-16s ' "$name"
    if ! caustic --path "$ROOT" "$src" -o "build/$name" > "build/$name.log" 2>&1; then
        echo "COMPILE FAIL"
        tail -12 "build/$name.log" | sed 's/^/    /'
        fail=1
        return
    fi
    "build/$name"
    local rc=$?
    if [ "$rc" -eq 0 ]; then
        echo "PASS"
    else
        echo "FAIL (exit $rc)"
        fail=1
    fi
}

# --- test cases (added as decoders land) --------------------------------
run_case test_buf            tests/test_buf.cst
run_case test_qoi            tests/test_qoi.cst
run_case test_bmp            tests/test_bmp.cst
run_case test_pnm            tests/test_pnm.cst
run_case test_tga            tests/test_tga.cst
run_case test_png            tests/test_png.cst
run_case test_png_filters    tests/test_png_filters.cst
run_case test_png_adv        tests/test_png_adv.cst
run_case test_gif            tests/test_gif.cst
run_case test_gif_interlace  tests/test_gif_interlace.cst
run_case test_gif_anim       tests/test_gif_anim.cst
run_case test_limit          tests/test_limit.cst
run_case test_qoi_rt         tests/test_qoi_rt.cst
run_case test_encode_rt      tests/test_encode_rt.cst
run_case test_csif_rt        tests/test_csif_rt.cst
run_case test_csif_corrupt   tests/test_csif_corrupt.cst
run_case test_rans           tests/test_rans.cst
run_case test_dispatch       tests/test_dispatch.cst
run_case test_dct            tests/test_dct.cst
run_case test_jpeg           tests/test_jpeg.cst
run_case test_jpeg_prog      tests/test_jpeg_prog.cst
run_case test_csif_dct       tests/test_csif_dct.cst
run_case test_tiff           tests/test_tiff.cst
run_case test_webp           tests/test_webp.cst
run_case test_ops            tests/test_ops.cst
run_case test_lowbit         tests/test_lowbit.cst
run_case test_modular_ctx    tests/test_modular_ctx.cst

if [ "$fail" -eq 0 ]; then echo "all green"; else echo "FAILURES"; fi
exit $fail
