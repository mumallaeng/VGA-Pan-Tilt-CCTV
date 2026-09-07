#!/usr/bin/env python3
"""Any image (PNG/JPG/...) -> 320x240 P6 PPM for the golden-model flow.

Needs Pillow (run setup_env.bat first, or use a Python that has PIL).
The PPM is the pipeline's canonical input; img2hex.py turns it into the
RGB565 .hex the frame buffer / $readmemh load.

Usage:  python png2ppm.py <in image> [out.ppm]
"""
import sys
from PIL import Image

IMG_W, IMG_H = 320, 240


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: png2ppm.py <in image> [out.ppm]")
    src = sys.argv[1]
    dst = sys.argv[2] if len(sys.argv) > 2 else "greenball_320x240.ppm"
    img = Image.open(src).convert("RGB")
    if img.size != (IMG_W, IMG_H):
        # NEAREST: no smoothing -> keeps the blocky low-res OV7670 look and
        # does not invent interpolated green pixels along the ball edge.
        print("resizing %s %s -> %dx%d (nearest)" % (src, img.size, IMG_W, IMG_H))
        img = img.resize((IMG_W, IMG_H), Image.NEAREST)
    img.save(dst, format="PPM")   # Pillow writes binary P6
    print("wrote", dst)


if __name__ == "__main__":
    main()
