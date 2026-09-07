#!/usr/bin/env python3
"""Golden model for the VGA-Pan-Tilt-CCTV video pipeline, servo input excluded.

CYCLE-FAITHFUL PORT of the RTL (registers, shift chains, counters and all),
driven by the exact same 640x480 FULLSCREEN raster as the SystemVerilog
harness tb_top_video_golden.sv. Equivalence is expected bit for bit; a
mismatch localises a real RTL bug (or a bug in this port).

Ported modules:
  vga_frame_reader_v4  rtl/video/vga_frame_reader_v4.sv        MODE_FULLSCREEN
  green_color_filter   rtl/common/filter/green_color_filter.sv
  noise_filter_3x3     rtl/common/filter/noise_filter_3x3.sv + line_buffer.sv
  min_max_find         rtl/common/filter/bounding_box.sv
  object_center        rtl/common/filter/object_center.sv
  center_error         rtl/common/filter/center_error.sv
  draw_box             rtl/video/draw_box.sv                    THICKNESS=2
  (display_control is pass-through for non-split, red_filter_en=0, so the
   final image is vga_frame_reader_v4's vga_r/g/b with the box burned in.)

Outputs (byte-identical to the harness dump, prefix golden_):
  golden_fb565.hex golden_green.pgm golden_clean.pgm
  golden_bbox.txt golden_preservo.txt golden_out.ppm

Pure standard library (remote Windows Python 3.14, no PIL/numpy).

Usage:  python gmodel.py [in.hex] [out_dir]
"""
import sys
import os

IMG_W, IMG_H = 320, 240
DISP_W, DISP_H = 640, 480
FRAME_SIZE = IMG_W * IMG_H
MIN_RED_COUNT = 10
THICKNESS = 2
G_MIN, GR_DIFF, GB_DIFF = 0x80, 40, 40

NFRAMES = 3
GAP = 8
CAPTURE_FRAME = 1  # 0-based: 2nd pass -> draw_box primed by pass 0, steady state


def sdiv(a, b):
    """Verilog signed '/' : truncate toward zero."""
    q = abs(a) // abs(b)
    return q if (a < 0) == (b < 0) else -q


def load_hex(path):
    mem = [0] * FRAME_SIZE
    i = 0
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            mem[i] = int(line, 16) & 0xFFFF
            i += 1
            if i == FRAME_SIZE:
                break
    if i != FRAME_SIZE:
        raise ValueError("hex has %d pixels, need %d" % (i, FRAME_SIZE))
    return mem


class Pipe:
    def __init__(self, mem, fs=1, raw=0):
        self.mem = mem
        self.fs = fs     # 1 = MODE_FULLSCREEN (2x), 0 = MODE_ORIGINAL (1:1)
        self.raw = raw    # 1 = disable the detection-decimation gate (pre-patch)
        self.det_phase = 0
        # vga_frame_reader_v4
        self.fb_rdata = 0
        self.pixel_valid_d = 0
        self.img_x = 0
        self.img_y = 0
        # noise_filter_3x3 + line_buffer
        self.buf1 = [0] * IMG_W
        self.buf2 = [0] * IMG_W
        self.r0a = self.r0b = self.r0c = 0
        self.r1a = self.r1b = self.r1c = 0
        self.r2a = self.r2b = self.r2c = 0
        self.x_d1 = self.y_d1 = 0
        self.clean_x = self.clean_y = 0
        self.rows_seen = 0
        self.valid_d1 = 0
        self.out_valid = 0
        # min_max_find
        self.frame_synced = 0
        self.frame_end_d = 0
        self.found_pixel = 0
        self.mask_count = 0
        self.min_x_reg = self.max_x_reg = 0
        self.min_y_reg = self.max_y_reg = 0
        self.target_valid_in = 0
        self.mm_min_x = self.mm_max_x = 0
        self.mm_min_y = self.mm_max_y = 0
        self.done = 0
        # center_error
        self.x_d = [0, 0, 0, 0]     # x_d1..x_d4
        self.y_d = [0, 0, 0, 0]
        self.rect_x_hold = 0
        self.rect_y_hold = 0
        self.sample_count = 0
        # draw_box
        self.draw_min_x = self.draw_max_x = 0
        self.draw_min_y = self.draw_max_y = 0
        # harness box_en 1-clock realign
        self.box_en_aligned = 0

    def step(self, vga_x, vga_y, video_on):
        # ---- vga_frame_reader_v4 : combinational request ----
        if self.fs:                      # MODE_FULLSCREEN (vga_sw=2'b01)
            img_x_comb = (vga_x >> 1) & 0x1FF
            img_y_comb = (vga_y >> 1) & 0xFF
            mode_active = 1 if (vga_x < 640 and vga_y < 480) else 0
        else:                            # MODE_ORIGINAL (vga_sw=2'b00)
            img_x_comb = vga_x & 0x1FF
            img_y_comb = vga_y & 0xFF
            mode_active = 1 if (vga_x < 320 and vga_y < 240) else 0
        pixel_req_valid = 1 if (video_on and mode_active) else 0
        addr_calc = img_y_comb * IMG_W + img_x_comb
        fb_raddr = addr_calc if (pixel_req_valid and addr_calc < FRAME_SIZE) else 0

        # ---- reader combinational OUTPUTS (pre-edge regs) ----
        pixel_valid = self.pixel_valid_d
        pixel_rgb565 = self.fb_rdata if pixel_valid else 0
        out_img_x = self.img_x
        out_img_y = self.img_y

        # ---- green_color_filter : pure combinational ----
        r5 = (pixel_rgb565 >> 11) & 0x1F
        g6 = (pixel_rgb565 >> 5) & 0x3F
        b5 = pixel_rgb565 & 0x1F
        r8 = (r5 << 3) | (r5 >> 2)
        g8 = (g6 << 2) | (g6 >> 4)
        b8 = (b5 << 3) | (b5 >> 2)
        green_mask = 0
        if pixel_valid and g8 >= G_MIN and g8 >= r8 + GR_DIFF and g8 >= b8 + GB_DIFF:
            green_mask = 1
        # detection-decimation gate (models top.sv patch): one sample per
        # source pixel. det_phase is registered, aligned like pixel_valid.
        red_valid = pixel_valid & self.det_phase   # feeds noise_filter_3x3
        red_mask = green_mask

        # ---- noise_filter_3x3 : combinational clean_mask from CURRENT regs ----
        left_valid = 1 if self.clean_x != 0 else 0
        right_valid = 1 if self.clean_x != IMG_W - 1 else 0
        top_valid = 1 if self.clean_y != 0 else 0
        bottom_valid = 1 if self.clean_y != IMG_H - 1 else 0
        nsum = ((self.r2a & left_valid & top_valid)
                + (self.r2b & top_valid)
                + (self.r2c & right_valid & top_valid)
                + (self.r1a & left_valid)
                + self.r1b
                + (self.r1c & right_valid)
                + (self.r0a & left_valid & bottom_valid)
                + (self.r0b & bottom_valid)
                + (self.r0c & right_valid & bottom_valid))
        rows_ready = self.rows_seen >= 2
        clean_mask = 1 if (rows_ready and nsum >= 5) else 0
        out_valid = self.out_valid
        clean_x, clean_y = self.clean_x, self.clean_y

        # line_buffer combinational reads (pre-write) at CURRENT pixel_x = img_x
        px = out_img_x
        line1_val = self.buf1[px] if px < IMG_W else 0
        line2_val = self.buf2[px] if px < IMG_W else 0

        # ---- min_max_find : combinational ----
        frame_start = 1 if (out_valid and clean_x == 0 and clean_y == 0) else 0
        frame_end = 1 if (self.frame_synced and out_valid
                          and clean_x == IMG_W - 2 and clean_y == IMG_H - 2) else 0
        pixel_hit = 1 if (out_valid and clean_mask
                          and (self.frame_synced or frame_start)) else 0
        frame_done = self.done   # registered output, pre-edge value

        # ---- object_center + center_error : combinational ----
        oc_valid = self.target_valid_in
        tx = (self.mm_min_x + self.mm_max_x) >> 1
        ty = (self.mm_min_y + self.mm_max_y) >> 1
        current_x = tx - 160
        current_y = 120 - ty
        sc = self.sample_count
        if sc == 0:
            avg_x, avg_y = current_x, current_y
        elif sc == 1:
            avg_x = sdiv(self.x_d[0] + current_x, 2)
            avg_y = sdiv(self.y_d[0] + current_y, 2)
        elif sc == 2:
            avg_x = sdiv(self.x_d[1] + self.x_d[0] + current_x, 3)
            avg_y = sdiv(self.y_d[1] + self.y_d[0] + current_y, 3)
        elif sc == 3:
            avg_x = sdiv(self.x_d[2] + self.x_d[1] + self.x_d[0] + current_x, 4)
            avg_y = sdiv(self.y_d[2] + self.y_d[1] + self.y_d[0] + current_y, 4)
        else:
            avg_x = sdiv(self.x_d[3] + self.x_d[2] + self.x_d[1]
                         + self.x_d[0] + current_x, 5)
            avg_y = sdiv(self.y_d[3] + self.y_d[2] + self.y_d[1]
                         + self.y_d[0] + current_y, 5)
        if frame_done and oc_valid:
            rect_x, rect_y = avg_x, avg_y
        else:
            rect_x, rect_y = self.rect_x_hold, self.rect_y_hold

        # ---- draw_box : combinational box_en from CURRENT raster coord ----
        xs, ys = vga_x >> 1, vga_y >> 1
        x_in = (xs >= self.draw_min_x) and (xs < self.draw_max_x)
        y_in = (ys >= self.draw_min_y) and (ys < self.draw_max_y)
        inbound = x_in and y_in
        x_edge = (xs < self.draw_min_x + THICKNESS) or (xs + THICKNESS >= self.draw_max_x)
        y_edge = (ys < self.draw_min_y + THICKNESS) or (ys + THICKNESS >= self.draw_max_y)
        border = inbound and (x_edge or y_edge)
        box_en_raw = 1 if (oc_valid and border) else 0

        # ---- reader display combinational : uses box_en_aligned ----
        be = self.box_en_aligned
        if pixel_valid:
            vga_r = 0xF if be else (self.fb_rdata >> 12) & 0xF
            vga_g = 0x0 if be else (self.fb_rdata >> 7) & 0xF
            vga_b = 0x0 if be else (self.fb_rdata >> 1) & 0xF
        else:
            vga_r = vga_g = vga_b = 0

        outs = dict(pixel_valid=pixel_valid, img_x=out_img_x, img_y=out_img_y,
                    green_mask=green_mask, out_valid=out_valid,
                    clean_x=clean_x, clean_y=clean_y, clean_mask=clean_mask,
                    done=frame_done, target_valid=oc_valid,
                    min_x=self.mm_min_x, max_x=self.mm_max_x,
                    min_y=self.mm_min_y, max_y=self.mm_max_y,
                    rect_x=rect_x, rect_y=rect_y, ce_valid=oc_valid,
                    vga_r=vga_r, vga_g=vga_g, vga_b=vga_b)

        # ===================== CLOCK EDGE =====================
        # pre-edge snapshots for min_max_find commit (nonblocking semantics)
        fe_d_pre = self.frame_end_d
        pf_pre = self.found_pixel
        mc_pre = self.mask_count
        mnx, mxx = self.min_x_reg, self.max_x_reg
        mny, mxy = self.min_y_reg, self.max_y_reg

        # reader registers
        self.fb_rdata = self.mem[fb_raddr] if fb_raddr < FRAME_SIZE else 0
        self.pixel_valid_d = pixel_req_valid
        self.img_x = img_x_comb
        self.img_y = img_y_comb

        # detection-decimation phase register (top.sv patch)
        if self.fs and not self.raw:
            self.det_phase = 1 if ((vga_x & 1) == 0 and (vga_y & 1) == 0) else 0
        else:
            self.det_phase = 1

        # noise_filter_3x3 + line_buffer registers
        if red_valid:
            self.r2a, self.r2b, self.r2c = self.r2b, self.r2c, line2_val
            self.r1a, self.r1b, self.r1c = self.r1b, self.r1c, line1_val
            self.r0a, self.r0b, self.r0c = self.r0b, self.r0c, red_mask
            nxd1, nyd1 = px, out_img_y
            self.clean_x = self.x_d1
            self.clean_y = 0 if self.y_d1 == 0 else self.y_d1 - 1
            self.x_d1, self.y_d1 = nxd1, nyd1
            if px == IMG_W - 1 and self.rows_seen < 2:
                self.rows_seen += 1
            if px < IMG_W:
                self.buf2[px] = self.buf1[px]
                self.buf1[px] = red_mask
        self.valid_d1 = red_valid
        self.out_valid = self.valid_d1

        # min_max_find registers
        self.frame_end_d = frame_end
        self.done = 0
        if frame_start:
            self.frame_synced = 1
            self.found_pixel = 0
            self.mask_count = 0
        if pixel_hit:
            if frame_start or not pf_pre:
                self.min_x_reg = self.max_x_reg = clean_x
                self.min_y_reg = self.max_y_reg = clean_y
                self.found_pixel = 1
            else:
                if clean_x < self.min_x_reg:
                    self.min_x_reg = clean_x
                if clean_x > self.max_x_reg:
                    self.max_x_reg = clean_x
                if clean_y < self.min_y_reg:
                    self.min_y_reg = clean_y
                if clean_y > self.max_y_reg:
                    self.max_y_reg = clean_y
            if frame_start:
                self.mask_count = 1
            elif mc_pre < MIN_RED_COUNT:
                self.mask_count = mc_pre + 1
        if fe_d_pre:
            self.done = 1
            if pf_pre and mc_pre >= MIN_RED_COUNT:
                self.target_valid_in = 1
                self.mm_min_x, self.mm_max_x = mnx, mxx
                self.mm_min_y, self.mm_max_y = mny, mxy
            else:
                self.target_valid_in = 0
                self.mm_min_x = self.mm_max_x = 0
                self.mm_min_y = self.mm_max_y = 0

        # center_error registers
        if frame_done and oc_valid:
            self.x_d = [current_x, self.x_d[0], self.x_d[1], self.x_d[2]]
            self.y_d = [current_y, self.y_d[0], self.y_d[1], self.y_d[2]]
            self.rect_x_hold = avg_x
            self.rect_y_hold = avg_y
            if self.sample_count < 4:
                self.sample_count += 1

        # draw_box registers
        if frame_done:
            self.draw_min_x = outs["min_x"]
            self.draw_max_x = outs["max_x"]
            self.draw_min_y = outs["min_y"]
            self.draw_max_y = outs["max_y"]

        # harness box_en realign register
        self.box_en_aligned = box_en_raw
        return outs


def s9(v):
    v &= 0x1FF
    return v - 512 if v & 0x100 else v


def s8(v):
    v &= 0xFF
    return v - 256 if v & 0x80 else v


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else "greenball_320x240.hex"
    out_dir = sys.argv[2] if len(sys.argv) > 2 else "."
    fs = int(sys.argv[3]) if len(sys.argv) > 3 else int(os.environ.get("FS", "1"))
    tag = sys.argv[4] if len(sys.argv) > 4 else None
    raw = int(sys.argv[5]) if len(sys.argv) > 5 else int(os.environ.get("RAW", "0"))
    if tag is None:
        tag = "320x240" if not fs else ("640x480_raw" if raw else "640x480")
    os.makedirs(out_dir, exist_ok=True)
    mem = load_hex(src)
    p = Pipe(mem, fs=fs, raw=raw)
    print("mode:", "FULLSCREEN 2x" if fs else "ORIGINAL 1:1",
          "| decimation gate:", "OFF (raw)" if (raw and fs) else "on",
          "| tag:", tag)

    green = bytearray(FRAME_SIZE)          # 320x240, capture frame
    clean = bytearray(FRAME_SIZE)
    out_img = bytearray(DISP_W * DISP_H * 3)
    bbox = None
    preservo = None

    # reset: hold a few idle cycles (regs already 0 == reset state)
    for _ in range(8):
        p.step(0, 0, 0)

    prev = None  # (frame, vx, vy, active) from previous cycle
    for frame in range(NFRAMES):
        for vy in range(DISP_H):
            for vx in range(DISP_W):
                o = p.step(vx, vy, 1)
                if frame == CAPTURE_FRAME:
                    if o["pixel_valid"]:
                        ix, iy = o["img_x"], o["img_y"]
                        if ix < IMG_W and iy < IMG_H:
                            green[iy * IMG_W + ix] = 255 if o["green_mask"] else 0
                    if o["out_valid"]:
                        cx, cy = o["clean_x"], o["clean_y"]
                        if cx < IMG_W and cy < IMG_H:
                            clean[cy * IMG_W + cx] = 255 if o["clean_mask"] else 0
                    if o["done"]:
                        bbox = (o["min_x"], o["max_x"], o["min_y"], o["max_y"],
                                o["target_valid"])
                        preservo = (s9(o["rect_x"]), s8(o["rect_y"]), o["ce_valid"])
                    # output image: outputs describe PREVIOUS raster coord
                    if prev is not None and prev[0] == CAPTURE_FRAME and prev[3]:
                        _, pvx, pvy, _ = prev
                        j = (pvy * DISP_W + pvx) * 3
                        if o["pixel_valid"]:
                            out_img[j] = o["vga_r"] * 17
                            out_img[j + 1] = o["vga_g"] * 17
                            out_img[j + 2] = o["vga_b"] * 17
                        else:
                            out_img[j] = out_img[j + 1] = out_img[j + 2] = 0
                prev = (frame, vx, vy, True)
        for _ in range(GAP):
            o = p.step(0, 0, 0)
            if prev is not None and prev[0] == CAPTURE_FRAME and prev[3]:
                _, pvx, pvy, _ = prev
                j = (pvy * DISP_W + pvx) * 3
                if o["pixel_valid"]:
                    out_img[j] = o["vga_r"] * 17
                    out_img[j + 1] = o["vga_g"] * 17
                    out_img[j + 2] = o["vga_b"] * 17
                else:
                    out_img[j] = out_img[j + 1] = out_img[j + 2] = 0
            prev = (frame, 0, 0, False)

    if bbox is None:
        raise RuntimeError("no 'done' pulse seen in capture frame")

    def w(base, ext, data):
        with open(os.path.join(out_dir, "golden_%s_%s.%s" % (base, tag, ext)), "wb") as f:
            f.write(data)

    w("fb565", "hex", ("".join("%04x\n" % v for v in mem)).encode("ascii"))
    w("green", "pgm", b"P5\n%d %d\n255\n" % (IMG_W, IMG_H) + bytes(green))
    w("clean", "pgm", b"P5\n%d %d\n255\n" % (IMG_W, IMG_H) + bytes(clean))
    w("bbox", "txt", ("%d %d %d %d %d\n" % bbox).encode("ascii"))
    w("preservo", "txt", ("%d %d %d\n" % preservo).encode("ascii"))
    # out image resolution follows the mode (full 640x480 / active 320x240)
    ow, oh = (DISP_W, DISP_H) if fs else (IMG_W, IMG_H)
    crop = bytearray(ow * oh * 3)
    for oy in range(oh):
        s = (oy * DISP_W) * 3
        crop[oy * ow * 3:(oy + 1) * ow * 3] = out_img[s:s + ow * 3]
    w("out", "ppm", b"P6\n%d %d\n255\n" % (ow, oh) + bytes(crop))

    print("golden[%s]: bbox(min_x,max_x,min_y,max_y,valid) =" % tag, bbox)
    print("golden[%s]: preservo(frame_dx,frame_dy,valid)  =" % tag, preservo)
    print("wrote 6 artifacts (golden_*_%s) to %s" % (tag, out_dir))


if __name__ == "__main__":
    main()
