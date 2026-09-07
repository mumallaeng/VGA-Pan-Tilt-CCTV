#!/usr/bin/env bash
# Local bit-exact equivalence run: iverilog harness vs Python golden model.
# Runs BOTH display modes and tags every artifact:
#   FULLSCREEN 2x (vga_sw=01)  -> *_640x480.*
#   ORIGINAL 1:1  (vga_sw=00)  -> *_320x240.*
#   ./run_local.sh [image]     .ppm, or any image (needs PIL), or omit for synthetic
set -e
cd "$(dirname "$0")"

RTL=../../rtl
OUT=_work
mkdir -p "$OUT"

SRC="${1:-}"
if [ -z "$SRC" ] && [ -f golden_test_sample_img.png ]; then
    SRC=golden_test_sample_img.png          # official demo input
fi
if [ -z "$SRC" ]; then
    python3 make_synth_ppm.py "$OUT/src_320x240.ppm"
    SRC="$OUT/src_320x240.ppm"
elif [ "${SRC##*.}" != "ppm" ]; then
    python3 png2ppm.py "$SRC" "$OUT/src_320x240.ppm"
    SRC="$OUT/src_320x240.ppm"
fi
python3 img2hex.py "$SRC" "$OUT/src.hex"

echo "== iverilog build =="
iverilog -g2012 -o "$OUT/sim.vvp" \
    tb_top_video_golden.sv \
    "$RTL/video/vga_frame_reader_v4.sv" \
    "$RTL/video/draw_box.sv" \
    "$RTL/common/filter/green_color_filter.sv" \
    "$RTL/common/filter/noise_filter_3x3.sv" \
    "$RTL/common/filter/line_buffer.sv" \
    "$RTL/common/filter/centroid_filter.sv" \
    "$RTL/common/filter/bounding_box.sv" \
    "$RTL/common/filter/object_center.sv" \
    "$RTL/common/filter/center_error.sv"

# FS RAW TAG  --  patched FULLSCREEN / pre-patch FULLSCREEN / native ORIGINAL
for cfg in "1 0 640x480" "1 1 640x480_raw" "0 0 320x240"; do
    set -- $cfg; FS=$1; RAW=$2; TAG=$3
    echo
    echo "=================  $TAG  (FS=$FS RAW=$RAW)  ================="
    vvp "$OUT/sim.vvp" +HEX="$OUT/src.hex" +OUT="$OUT" +FS=$FS +RAW=$RAW +TAG=$TAG
    python3 gmodel.py "$OUT/src.hex" "$OUT" $FS $TAG $RAW
    python3 compare.py "$OUT" $TAG
done

echo
echo "== render PNGs =="
python3 render_images.py "$OUT"
