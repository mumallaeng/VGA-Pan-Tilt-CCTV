#!/usr/bin/env python3
"""
Convert the binary PPM (P6) that tb_draw_box_img_test.sv writes into a
viewable .png.

Usage:
    python ppm2png.py [input.ppm] [output.png]

Defaults to lenna_boxed_640x480.ppm -> lenna_boxed_640x480.png in this
folder. Requires Pillow (pip install Pillow).
"""

import sys
from pathlib import Path

from PIL import Image


def main():
    here = Path(__file__).resolve().parent
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else here / "lenna_boxed_640x480.ppm"
    dst = Path(sys.argv[2]) if len(sys.argv) > 2 else src.with_suffix(".png")

    img = Image.open(src)
    img.save(dst)

    print(f"{src.name} ({img.size[0]}x{img.size[1]}) -> {dst}")


if __name__ == "__main__":
    main()
