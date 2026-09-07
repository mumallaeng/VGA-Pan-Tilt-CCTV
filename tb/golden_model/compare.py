#!/usr/bin/env python3
"""SHA-256 equivalence check: RTL harness dump vs software golden model.

Compares the 6 tagged artifact pairs (rtl_<stage>_<TAG>.* vs golden_<stage>_<TAG>.*)
byte for byte, prints a hash table, and for the images reports the first
differing pixel and writes diff_out_<TAG>.ppm when they differ.

Exit 0 iff all 6 stages match.  Pure standard library.

Usage:  python compare.py [dir] [TAG]     TAG default: 640x480
"""
import sys
import os
import hashlib

STAGES = [
    ("fb565",    "hex", "frame buffer (RGB565)      "),
    ("green",    "pgm", "green_color_filter mask    "),
    ("clean",    "pgm", "noise_filter_3x3 mask      "),
    ("bbox",     "txt", "centroid_filter bbox       "),
    ("preservo", "txt", "pre-servo frame_dx/dy/valid"),
    ("out",      "ppm", "final displayed image      "),
]


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        h.update(f.read())
    return h.hexdigest()


def read_ppm(path):
    with open(path, "rb") as f:
        d = f.read()
    assert d[:2] in (b"P6", b"P5")
    p5 = d[:2] == b"P5"
    i, fields = 2, []
    while len(fields) < 3:
        while d[i] in b" \t\r\n":
            i += 1
        s = i
        while d[i] not in b" \t\r\n":
            i += 1
        fields.append(int(d[s:i]))
    i += 1
    w, h, _ = fields
    n = w * h * (1 if p5 else 3)
    return w, h, (1 if p5 else 3), d[i:i + n]


def first_diff_pixel(a, b):
    w, h, ch, pa = read_ppm(a)
    _, _, _, pb = read_ppm(b)
    n = min(len(pa), len(pb))
    for k in range(0, n, ch):
        if pa[k:k + ch] != pb[k:k + ch]:
            px = (k // ch) % w
            py = (k // ch) // w
            return (px, py, tuple(pa[k:k + ch]), tuple(pb[k:k + ch]))
    return None


def write_diff(a, b, out):
    w, h, ch, pa = read_ppm(a)
    _, _, _, pb = read_ppm(b)
    n = min(len(pa), len(pb))
    dif = bytearray(n)
    for k in range(n):
        v = abs(pa[k] - pb[k]) * 8
        dif[k] = 255 if v > 255 else v
    magic = b"P5" if ch == 1 else b"P6"
    with open(out, "wb") as f:
        f.write(b"%s\n%d %d\n255\n" % (magic, w, h))
        f.write(bytes(dif))


def main():
    d = sys.argv[1] if len(sys.argv) > 1 else "."
    tag = sys.argv[2] if len(sys.argv) > 2 else "640x480"
    print()
    print("  [tag=%s]" % tag)
    print("  stage                        | rtl sha256 (12) | golden sha256(12)| result")
    print("  -----------------------------+-----------------+------------------+-------")
    all_ok = True
    for base, ext, label in STAGES:
        rp = os.path.join(d, "rtl_%s_%s.%s" % (base, tag, ext))
        gp = os.path.join(d, "golden_%s_%s.%s" % (base, tag, ext))
        if not (os.path.exists(rp) and os.path.exists(gp)):
            print("  %s| MISSING FILE(S)" % label)
            all_ok = False
            continue
        rh, gh = sha(rp), sha(gp)
        ok = rh == gh
        all_ok &= ok
        print("  %s| %s    | %s     | %s"
              % (label, rh[:12], gh[:12], "MATCH" if ok else "DIFF"))
        if not ok and ext in ("ppm", "pgm"):
            fdp = first_diff_pixel(rp, gp)
            if fdp:
                print("      first diff pixel (x=%d,y=%d): rtl=%s golden=%s" % fdp)
            write_diff(rp, gp, os.path.join(d, "diff_%s_%s.%s" % (base, tag, ext)))
    print()
    if all_ok:
        print("  RESULT: TEST PASSED  (all 6 stages bit-identical)")
        print()
        for base, ext, label in STAGES:
            rp = os.path.join(d, "rtl_%s_%s.%s" % (base, tag, ext))
            print("  %-24s %s" % ("%s_%s.%s" % (base, tag, ext), sha(rp)))
    else:
        print("  RESULT: TEST FAILED")
    print()
    sys.exit(0 if all_ok else 1)


if __name__ == "__main__":
    main()
