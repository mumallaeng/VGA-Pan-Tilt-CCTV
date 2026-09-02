#!/usr/bin/env python3
"""
Convert a 320x240 image into the RGB565 .hex file tb_draw_box_img_test.sv
loads with $readmemh.

Pixel order matches frame_buffer.sv's addressing: row-major,
addr = img_y * IMG_WIDTH + img_x (top row first, left to right), one
4-digit hex value (RGB565, MSB first) per line.

Usage:
    python img2hex.py [input.png] [output.hex]

Defaults to lenna_320x240.png -> lenna_320x240.hex in this folder.
Requires Pillow (pip install Pillow).
"""

import sys
from pathlib import Path

from PIL import Image

IMG_WIDTH = 320
IMG_HEIGHT = 240


def rgb888_to_rgb565(r, g, b):
    r5 = (r >> 3) & 0x1F
    g6 = (g >> 2) & 0x3F
    b5 = (b >> 3) & 0x1F
    return (r5 << 11) | (g6 << 5) | b5


def main():
    here = Path(__file__).resolve().parent
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else here / "lenna_320x240.png"
    dst = Path(sys.argv[2]) if len(sys.argv) > 2 else src.with_suffix(".hex")

    img = Image.open(src).convert("RGB")

    if img.size != (IMG_WIDTH, IMG_HEIGHT):
        print(f"warning: {src.name} is {img.size}, resizing to "
              f"{IMG_WIDTH}x{IMG_HEIGHT}")
        img = img.resize((IMG_WIDTH, IMG_HEIGHT))

    pixels = list(img.getdata())  # row-major, top-left first: matches addr order

    with open(dst, "w") as f:
        for r, g, b in pixels:
            f.write(f"{rgb888_to_rgb565(r, g, b):04x}\n")

    print(f"wrote {len(pixels)} pixels -> {dst}")


if __name__ == "__main__":
    main()
