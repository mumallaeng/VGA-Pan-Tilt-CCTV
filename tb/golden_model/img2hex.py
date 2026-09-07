#!/usr/bin/env python3
"""320x240 P6 PPM  ->  RGB565 .hex for $readmemh.

Pixel order matches frame_buffer.sv addressing: row-major,
addr = y*IMG_WIDTH + x (top row first, left to right), one 4-digit hex
value (RGB565, MSB first) per line.

RGB888 -> RGB565 uses the SAME truncation the hardware sees on the OV7670
bus: r>>3, g>>2, b>>3. Pure standard library.

Usage:  python img2hex.py [in.ppm] [out.hex]
"""
import sys

IMG_WIDTH = 320
IMG_HEIGHT = 240


def read_ppm_p6(path):
    with open(path, "rb") as f:
        data = f.read()
    if not data.startswith(b"P6"):
        raise ValueError("not a P6 PPM: " + path)
    # parse header: P6 <w> <h> <maxval>, whitespace/comment separated
    idx = 2
    fields = []
    while len(fields) < 3:
        while idx < len(data) and data[idx] in b" \t\r\n":
            idx += 1
        if idx < len(data) and data[idx:idx + 1] == b"#":
            while idx < len(data) and data[idx] not in b"\r\n":
                idx += 1
            continue
        start = idx
        while idx < len(data) and data[idx] not in b" \t\r\n":
            idx += 1
        fields.append(int(data[start:idx]))
    w, h, maxv = fields
    idx += 1  # single whitespace after maxval
    if (w, h) != (IMG_WIDTH, IMG_HEIGHT):
        raise ValueError("expected %dx%d, got %dx%d" %
                         (IMG_WIDTH, IMG_HEIGHT, w, h))
    if maxv != 255:
        raise ValueError("expected maxval 255, got %d" % maxv)
    pixels = data[idx:idx + w * h * 3]
    if len(pixels) != w * h * 3:
        raise ValueError("short pixel data")
    return w, h, pixels


def rgb888_to_rgb565(r, g, b):
    r5 = (r >> 3) & 0x1F
    g6 = (g >> 2) & 0x3F
    b5 = (b >> 3) & 0x1F
    return (r5 << 11) | (g6 << 5) | b5


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else "greenball_320x240.ppm"
    dst = sys.argv[2] if len(sys.argv) > 2 else "greenball_320x240.hex"
    w, h, px = read_ppm_p6(src)
    with open(dst, "w") as f:
        for p in range(0, len(px), 3):
            f.write("%04x\n" % rgb888_to_rgb565(px[p], px[p + 1], px[p + 2]))
    print("wrote %d pixels -> %s" % (w * h, dst))


if __name__ == "__main__":
    main()
