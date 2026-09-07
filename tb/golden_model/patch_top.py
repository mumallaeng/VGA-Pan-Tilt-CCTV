#!/usr/bin/env python3
"""Apply the detection-decimation minimal patch to rtl/top/top.sv in place,
preserving the file's CRLF line endings so git diff stays minimal.
Idempotent: refuses if already patched. Pass --revert to undo.
"""
import sys

P = "rtl/top/top.sv"
NL = "\r\n"

BLOCK = NL.join([
    "",
    "    // Detection decimation",
    "    // ---------------------------------------------",
    "    // MODE_FULLSCREEN presents every source pixel as a 2x2 display block,",
    "    // so feeding the display-rate valid to noise_filter_3x3 gives it a 2x",
    "    // upscaled image and the 3x3 majority stops rejecting isolated noise",
    "    // (a lone pixel manufactures >=5 neighbours from its own replicas).",
    "    // Accept only the first replica of each source pixel (x_pixel/y_pixel",
    "    // both even), registered one clock to align with the reader's",
    "    // pixel_valid / img_x / img_y. Other vga_sw modes are already 1:1, so",
    "    // det_phase stays high and the gate is transparent. Display + draw_box",
    "    // stay at 640x480; box coords now come from the clean native detection.",
    "    reg det_phase;",
    "    always_ff @(posedge vga_pclk or posedge rst) begin",
    "        if (rst) det_phase <= 1'b0;",
    "        else     det_phase <= (vga_sw == 2'b01) ? (~x_pixel[0] & ~y_pixel[0])",
    "                                                : 1'b1;",
    "    end",
    "    wire det_valid = red_valid & det_phase;",
    "",
]) + NL

ANCHOR = "    // Noise filter" + NL
GATED = "        .red_valid (det_valid),"
RAW = "        .red_valid (red_valid),"

d = open(P, "rb").read().decode("utf-8")

if "--revert" in sys.argv:
    if "det_phase" not in d:
        print("not patched, nothing to revert")
        sys.exit(0)
    d = d.replace(BLOCK + ANCHOR, ANCHOR, 1).replace(GATED, RAW, 1)
    open(P, "wb").write(d.encode("utf-8"))
    print("reverted")
    sys.exit(0)

if "det_phase" in d:
    print("already patched")
    sys.exit(0)
assert d.count(ANCHOR) == 1, "anchor not found uniquely"
assert d.count(RAW) == 1, "'.red_valid (red_valid),' not found uniquely"
d = d.replace(ANCHOR, BLOCK + ANCHOR, 1).replace(RAW, GATED, 1)
open(P, "wb").write(d.encode("utf-8"))
print("patched")
