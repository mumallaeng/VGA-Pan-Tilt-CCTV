#!/usr/bin/env python3
"""PPM (P6) / PGM (P5) -> PNG for slides. Needs Pillow; run on a machine that
has it (the remote Windows Python has no PIL). Usage: python ppm2png.py in out.png
"""
import sys
from PIL import Image

src = sys.argv[1]
dst = sys.argv[2] if len(sys.argv) > 2 else src.rsplit(".", 1)[0] + ".png"
Image.open(src).save(dst)
print(src, "->", dst)
