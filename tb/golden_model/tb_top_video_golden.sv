`timescale 1ns / 1ps

module tb_top_video_golden;

    localparam int IMG_WIDTH = 320;
    localparam int IMG_HEIGHT = 240;
    localparam int ADDR_WIDTH = 17;
    localparam int FRAME_SIZE = IMG_WIDTH * IMG_HEIGHT;
    localparam int H_VISIBLE = 640;
    localparam int V_VISIBLE = 480;
    localparam int NFRAMES = 3;
    localparam int GAP = 8;
    localparam int CAPTURE_FRAME = 1;  // 0-based

    string HEX_FILE = "greenball_320x240.hex";
    string OUT_DIR = ".";
    string TAG = "640x480";

    // 1 = MODE_FULLSCREEN (vga_sw=2'b01, matches top.sv board demo);
    // 0 = MODE_ORIGINAL   (vga_sw=2'b00, native 320x240 detection stream)
    int    FS = 1;

    // 0 = model the top.sv detection-decimation patch (default);
    // 1 = raw pre-patch behaviour (noise_filter fed the 2x display stream)
    int    RAW = 0;

    // ------------------------------------------------------------
    logic  clk = 1'b0;
    always #5 clk = ~clk;
    logic rst;

    logic [9:0] vga_x, vga_y;
    logic                  video_on;
    logic [           1:0] vga_sw;

    // ---- image memory stands in for frame_buffer.sv ----
    logic [          15:0] img_mem  [0:FRAME_SIZE-1];
    wire  [ADDR_WIDTH-1:0] fb_raddr;
    logic [          15:0] fb_rdata;
    always_ff @(posedge clk) begin
        if (fb_raddr < FRAME_SIZE) fb_rdata <= img_mem[fb_raddr];
        else fb_rdata <= 16'h0000;
    end

    // ---- DUT wires ----
    wire [8:0] img_x;
    wire [7:0] img_y;
    wire [3:0] vga_r, vga_g, vga_b;
    wire [15:0] display_rgb565;
    wire        display_pixel_valid;
    wire split_mode_aligned, quadrant_4_aligned;

    wire green_mask, green_valid;
    wire [3:0] original_r, original_g, original_b;
    wire [3:0] green_r, green_g, green_b;

    wire clean_mask, out_valid;
    wire [8:0] clean_x;
    wire [7:0] clean_y;

    wire target_valid_out, frame_done, frame_valid;
    wire [8:0] max_x, min_x;
    wire [7:0] max_y, min_y;
    wire signed [8:0] frame_dx;
    wire signed [7:0] frame_dy;

    wire              box_en_raw;
    logic             box_en_aligned;

    // ================= DUT =================
    vga_frame_reader_v4 #(
        .IMG_WIDTH (IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) U_VGA_FRAME_READER (
        .clk               (clk),
        .rst               (rst),
        .vga_sw            (vga_sw),
        .vga_x             (vga_x),
        .vga_y             (vga_y),
        .video_on          (video_on),
        .box_en            (box_en_aligned),
        .fb_raddr          (fb_raddr),
        .fb_rdata          (fb_rdata),
        .img_x             (img_x),
        .img_y             (img_y),
        .vga_r             (vga_r),
        .vga_g             (vga_g),
        .vga_b             (vga_b),
        .pixel_rgb565      (display_rgb565),
        .pixel_valid       (display_pixel_valid),
        .split_mode_aligned(split_mode_aligned),
        .quadrant_4_aligned(quadrant_4_aligned)
    );

    green_color_filter U_GREEN_COLOR_FILTER (
        .pixel_rgb565(display_rgb565),
        .pixel_valid (display_pixel_valid),
        .vga_r       (vga_r),
        .vga_g       (vga_g),
        .vga_b       (vga_b),
        .green_mask  (green_mask),
        .green_valid (green_valid),
        .original_r  (original_r),
        .original_g  (original_g),
        .original_b  (original_b),
        .green_r     (green_r),
        .green_g     (green_g),
        .green_b     (green_b)
    );

    noise_filter_3x3 U_NOISE_FILTER (
        .pclk      (clk),
        .rst       (rst),
        .red_valid (red_valid),
        .red_mask  (green_mask),
        .pixel_x   (img_x),
        .pixel_y   (img_y),
        .clean_mask(clean_mask),
        .clean_x   (clean_x),
        .clean_y   (clean_y),
        .out_valid (out_valid)
    );

    centroid_filter U_CENTROID_FILTER (
        .pclk            (clk),
        .rst             (rst),
        .clean_mask      (clean_mask),
        .out_valid       (out_valid),
        .clean_x         (clean_x),
        .clean_y         (clean_y),
        .done            (frame_done),
        .target_valid_out(target_valid_out),
        .valid           (frame_valid),
        .min_x           (min_x),
        .max_x           (max_x),
        .min_y           (min_y),
        .max_y           (max_y),
        .rect_x          (frame_dx),
        .rect_y          (frame_dy)
    );

    draw_box U_DRAW_BOX (
        .pclk           (clk),
        .rst            (rst),
        .target_valid_in(target_valid_out),
        .done           (frame_done),
        .x_pixel        (vga_x),
        .y_pixel        (vga_y),
        .max_x          (max_x),
        .min_x          (min_x),
        .max_y          (max_y),
        .min_y          (min_y),
        .box_en         (box_en_raw)
    );

    always_ff @(posedge clk or posedge rst) begin
        if (rst) box_en_aligned <= 1'b0;
        else box_en_aligned <= box_en_raw;
    end

    // Capture buffers
    logic [7:0] g_mem[0:FRAME_SIZE-1];
    logic [7:0] c_mem[0:FRAME_SIZE-1];
    logic [7:0] o_mem[0:H_VISIBLE*V_VISIBLE*3-1];

    int cap_min_x, cap_max_x, cap_min_y, cap_max_y, cap_tv;
    int cap_dx, cap_dy, cap_fv;
    bit got_done;

    int p_vx, p_vy, p_frame;
    bit p_active, has_prev;

    // Record the previous frame's output
    task automatic record_output_prev();
        int j;
        if (has_prev && p_frame == CAPTURE_FRAME && p_active) begin
            j = (p_vy * H_VISIBLE + p_vx) * 3;
            if (display_pixel_valid) begin
                o_mem[j]   = vga_r * 8'd17;
                o_mem[j+1] = vga_g * 8'd17;
                o_mem[j+2] = vga_b * 8'd17;
            end else begin
                o_mem[j]   = 8'd0;
                o_mem[j+1] = 8'd0;
                o_mem[j+2] = 8'd0;
            end
        end
    endtask

    // Record detection results
    task automatic record_detect(input int frame);
        int gi, ci;
        if (frame != CAPTURE_FRAME) return;
        if (display_pixel_valid && img_x < IMG_WIDTH && img_y < IMG_HEIGHT) begin
            gi = img_y * IMG_WIDTH + img_x;
            g_mem[gi] = green_mask ? 8'd255 : 8'd0;
        end
        if (out_valid && clean_x < IMG_WIDTH && clean_y < IMG_HEIGHT) begin
            ci = clean_y * IMG_WIDTH + clean_x;
            c_mem[ci] = clean_mask ? 8'd255 : 8'd0;
        end
        if (frame_done) begin
            cap_min_x = min_x;
            cap_max_x = max_x;
            cap_min_y = min_y;
            cap_max_y = max_y;
            cap_tv    = target_valid_out;
            cap_dx    = frame_dx;  // signed
            cap_dy    = frame_dy;
            cap_fv    = frame_valid;
            got_done  = 1'b1;
        end
    endtask

    // ----------------- testbench stimulus -----------------
    integer fd, i;
    initial begin
        if ($value$plusargs("HEX=%s", HEX_FILE));
        if ($value$plusargs("OUT=%s", OUT_DIR));
        if ($value$plusargs("FS=%d", FS));  // 1=FULLSCREEN 0=ORIGINAL
        if ($value$plusargs("RAW=%d", RAW));  // 1=disable decimation gate
        // artifact filename tag: distinguishes the display/stream mode so runs
        // coexist in one folder (rtl_green_640x480.pgm vs _320x240 vs _640x480_raw).
        if (!$value$plusargs("TAG=%s", TAG)) begin
            if (FS == 0) TAG = "320x240";
            else if (RAW != 0) TAG = "640x480_raw";
            else TAG = "640x480";
        end

        for (i = 0; i < FRAME_SIZE; i++) begin
            g_mem[i] = 0;
            c_mem[i] = 0;
        end
        for (i = 0; i < H_VISIBLE * V_VISIBLE * 3; i++) o_mem[i] = 0;

        $readmemh(HEX_FILE, img_mem);

        vga_sw = (FS != 0) ? 2'b01 : 2'b00;  // FULLSCREEN : ORIGINAL
        $display("vga_sw = %02b  (%s)", vga_sw,
                 (FS != 0) ? "FULLSCREEN 2x" : "ORIGINAL 1:1");
        vga_x    = 0;
        vga_y    = 0;
        video_on = 1'b0;
        rst      = 1'b1;
        has_prev = 1'b0;
        got_done = 1'b0;

        repeat (8) @(posedge clk);
        #1 rst = 1'b0;
        repeat (4) @(posedge clk);

        for (int frame = 0; frame < NFRAMES; frame++) begin
            for (int vy = 0; vy < V_VISIBLE; vy++) begin
                for (int vx = 0; vx < H_VISIBLE; vx++) begin
                    @(posedge clk);
                    vga_x <= 10'(vx);
                    vga_y <= 10'(vy);
                    video_on <= 1'b1;
                    #1;
                    record_output_prev();
                    record_detect(frame);
                    p_vx = vx;
                    p_vy = vy;
                    p_frame = frame;
                    p_active = 1'b1;
                    has_prev = 1'b1;
                end
                if ((vy % 120) == 0) $display("  frame %0d row %0d", frame, vy);
            end
            for (int g = 0; g < GAP; g++) begin
                @(posedge clk);
                vga_x <= 10'd0;
                vga_y <= 10'd0;
                video_on <= 1'b0;
                #1;
                record_output_prev();
                record_detect(frame);
                p_frame  = frame;
                p_active = 1'b0;
                has_prev = 1'b1;
            end
        end

        if (!got_done)
            $fatal(
                1,
                "no frame_done pulse observed in capture frame %0d",
                CAPTURE_FRAME
            );

        // ---------------- dump artifacts (filenames carry TAG) ----------------
        fd = $fopen({OUT_DIR, "/rtl_fb565_", TAG, ".hex"}, "wb");
        for (i = 0; i < FRAME_SIZE; i++) $fwrite(fd, "%04x\n", img_mem[i]);
        $fclose(fd);

        fd = $fopen({OUT_DIR, "/rtl_green_", TAG, ".pgm"}, "wb");
        $fwrite(fd, "P5\n%0d %0d\n255\n", IMG_WIDTH, IMG_HEIGHT);
        for (i = 0; i < FRAME_SIZE; i++) $fwrite(fd, "%c", g_mem[i]);
        $fclose(fd);

        fd = $fopen({OUT_DIR, "/rtl_clean_", TAG, ".pgm"}, "wb");
        $fwrite(fd, "P5\n%0d %0d\n255\n", IMG_WIDTH, IMG_HEIGHT);
        for (i = 0; i < FRAME_SIZE; i++) $fwrite(fd, "%c", c_mem[i]);
        $fclose(fd);

        fd = $fopen({OUT_DIR, "/rtl_bbox_", TAG, ".txt"}, "wb");
        $fwrite(fd, "%0d %0d %0d %0d %0d\n", cap_min_x, cap_max_x, cap_min_y,
                cap_max_y, cap_tv);
        $fclose(fd);

        fd = $fopen({OUT_DIR, "/rtl_preservo_", TAG, ".txt"}, "wb");
        $fwrite(fd, "%0d %0d %0d\n", cap_dx, cap_dy, cap_fv);
        $fclose(fd);

        // out image resolution follows the mode: FULLSCREEN dumps the full
        // 640x480, ORIGINAL dumps just the active 320x240 (top-left) region.
        begin
            int ow, oh, ox, oy, jj;
            ow = (FS != 0) ? H_VISIBLE : IMG_WIDTH;
            oh = (FS != 0) ? V_VISIBLE : IMG_HEIGHT;
            fd = $fopen({OUT_DIR, "/rtl_out_", TAG, ".ppm"}, "wb");
            $fwrite(fd, "P6\n%0d %0d\n255\n", ow, oh);
            for (oy = 0; oy < oh; oy++)
            for (ox = 0; ox < ow; ox++) begin
                jj = (oy * H_VISIBLE + ox) * 3;
                $fwrite(fd, "%c%c%c", o_mem[jj], o_mem[jj+1], o_mem[jj+2]);
            end
            $fclose(fd);
        end

        $display(
            "rtl[%s]: bbox(min_x,max_x,min_y,max_y,valid) = %0d %0d %0d %0d %0d",
            TAG, cap_min_x, cap_max_x, cap_min_y, cap_max_y, cap_tv);
        $display("rtl[%s]: preservo(frame_dx,frame_dy,valid)   = %0d %0d %0d",
                 TAG, cap_dx, cap_dy, cap_fv);
        $display("wrote 6 artifacts (rtl_*_%s) to %s", TAG, OUT_DIR);
        $finish;
    end

endmodule
