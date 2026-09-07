#!/usr/bin/env python3
"""Generate a 320x240 P6 PPM test frame: a shaded green ball (real-sphere
look: highlight, terminator, ambient-occlusion, ground shadow) on a bench,
degraded to roughly what an OV7670 delivers. Pure standard library.

Why the colours -- green_color_filter.sv (G_MIN=128, GR_DIFF=GB_DIFF=40):
a pixel is "green" iff, on the RGB565->RGB888 expanded channels,
    g8 >= 128  AND  g8 - r8 >= 40  AND  g8 - b8 >= 40
    r8 = (r5<<3)|(r5>>2)   r5 = R>>3
    g8 = (g6<<2)|(g6>>4)   g6 = G>>2
    b8 = (b5<<3)|(b5>>2)   b5 = B>>3
i.e. roughly  G >= 128,  G-R >= 40,  G-B >= 40  in plain 8-bit RGB.

The ball is shaded for a genuine 3D look, but shading only scales LUMINANCE
while hue stays locked: every pixel keeps G in [~150,255] and R,B <= G-58
(pre-noise), so the whole ball -- highlight to shadow side -- still clears
all three thresholds after noise + the RGB565 crush. The bench is
near-neutral grey and never trips the filter.

OV7670-ish degradation:
  * QVGA 320x240, hard RGB565 quantisation (R>>3, G>>2, B>>3)
  * per-pixel sensor noise (heavier in shadow), lens vignetting
  * mild warm/green colour cast, limited contrast (~16..235)
  * a few isolated hot pixels incl. green-ish ones on the floor, to exercise
    noise_filter_3x3 / the detection-decimation gate

Usage:  python make_synth_ppm.py [out.ppm]
"""
import sys
import math

W, H = 320, 240
BX, BY, BR = 165, 122, 46           # ball centre / radius
LIGHT = (-0.52, -0.60, 0.61)        # key light: upper-left, toward camera
G_MIN, GR_DIFF, GB_DIFF = 128, 40, 40


def lcg(seed):
    s = seed & 0x7FFFFFFF
    while True:
        s = (1103515245 * s + 12345) & 0x7FFFFFFF
        yield s


def rgb565_crush(r, g, b):
    r5, g6, b5 = r >> 3, g >> 2, b >> 3
    return ((r5 << 3) | (r5 >> 2),
            (g6 << 2) | (g6 >> 4),
            (b5 << 3) | (b5 >> 2))


def clamp(v, lo=0, hi=255):
    return lo if v < lo else hi if v > hi else int(v)


def contrast(v, lo=16, hi=235):
    return lo + (v * (hi - lo)) // 255


def is_green(r, g, b):
    r8, g8, b8 = rgb565_crush(r, g, b)
    return g8 >= G_MIN and g8 - r8 >= GR_DIFF and g8 - b8 >= GB_DIFF


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "greenball_320x240.ppm"
    rnd = lcg(0x5EED_1234)
    cx, cy = W / 2.0, H / 2.0
    maxd2 = cx * cx + cy * cy
    lx, ly, lz = LIGHT
    ln = math.sqrt(lx * lx + ly * ly + lz * lz)
    lx, ly, lz = lx / ln, ly / ln, lz / ln
    # halfway vector between light and view(0,0,1) for the specular term
    hx, hy, hz = lx, ly, lz + 1.0
    hn = math.sqrt(hx * hx + hy * hy + hz * hz)
    hx, hy, hz = hx / hn, hy / hn, hz / hn

    px = bytearray(W * H * 3)
    ball_tot = ball_pass = bg_falsepos = 0

    for y in range(H):
        for x in range(W):
            i = (y * W + x) * 3
            dx, dy = (x - BX) / float(BR), (y - BY) / float(BR)
            rho2 = dx * dx + dy * dy
            on_ball = rho2 <= 1.0

            if on_ball:
                nz = math.sqrt(max(0.0, 1.0 - rho2))
                ndl = max(0.0, dx * lx + dy * ly + nz * lz)
                # ambient + diffuse -> luminance factor of the ball's green
                lit = 0.42 + 0.58 * ndl                     # 0.42 .. 1.0
                # ambient occlusion: slightly darker toward the bottom rim
                lit *= 1.0 - 0.12 * max(0.0, dy) * math.sqrt(rho2)
                g = 150 + 95 * lit                          # ~150 .. ~245
                r = 0.28 * g - 4
                b = 0.26 * g - 2
                # specular highlight (white-ish, but kept hue-safe below)
                spec = max(0.0, dx * hx + dy * hy + nz * hz) ** 22
                g += 40 * spec
                r += 26 * spec
                b += 24 * spec
                # hue lock: guarantee the green-detect margins pre-noise
                g = clamp(g, 150, 255)
                r = clamp(min(r, g - 58), 12, 210)
                b = clamp(min(b, g - 58), 10, 210)
                noise_amp = 3
            else:
                vgrad = (y * 26) // H
                base = 150 - vgrad
                # soft contact shadow on the bench under the ball
                sx, sy = (x - BX) / 62.0, (y - (BY + BR - 6)) / 20.0
                if sx * sx + sy * sy < 1.0 and y > BY:
                    base -= int(34 * (1.0 - (sx * sx + sy * sy)))
                r = base + 3                                # mild warm/green
                g = base + 5                                # cast, |g-r|<=~7
                b = base - 3
                noise_amp = 8

            vig = 1.0 - 0.20 * ((x - cx) ** 2 + (y - cy) ** 2) / maxd2
            r, g, b = r * vig, g * vig, b * vig
            r, g, b = contrast(r), contrast(g), contrast(b)

            n = (next(rnd) % (2 * noise_amp + 1)) - noise_amp
            r = clamp(r + n + (next(rnd) % 3) - 1)
            g = clamp(g + n + (next(rnd) % 3) - 1)
            b = clamp(b + n + (next(rnd) % 3) - 1)

            r, g, b = rgb565_crush(r, g, b)
            px[i], px[i + 1], px[i + 2] = r, g, b

            if on_ball:
                ball_tot += 1
                ball_pass += is_green(r, g, b)
            elif is_green(r, g, b):
                bg_falsepos += 1

    hots = [((40, 200), (70, 150, 96)),
            ((252, 206), (66, 148, 92)),
            ((150, 58), (72, 152, 100)),
            ((300, 120), (248, 248, 248)),
            ((70, 150), (200, 64, 64))]
    for (hx0, hy0), (hr, hg, hb) in hots:
        j = (hy0 * W + hx0) * 3
        px[j], px[j + 1], px[j + 2] = rgb565_crush(hr, hg, hb)

    with open(out, "wb") as f:
        f.write(b"P6\n%d %d\n255\n" % (W, H))
        f.write(bytes(px))

    print("wrote %s  %dx%d  (shaded ball, OV7670-style: RGB565/noise/vignette)"
          % (out, W, H))
    print("  ball pixels passing green_color_filter : %d / %d  (%.2f%%)"
          % (ball_pass, ball_tot, 100.0 * ball_pass / max(1, ball_tot)))
    print("  background false-positives             : %d" % bg_falsepos)
    print("  + 3 isolated green hot pixels on the floor (noise-filter test)")


if __name__ == "__main__":
    main()
