`timescale 1ns / 1ps

// ------------------------------------------------------------------
// tb_draw_box_img_test
//
// Runs draw_box + vga_frame_reader_v4 against a REAL image instead of
// a flat stub color, and saves the resulting 640x480 frame (box drawn
// on top of the picture) to a .ppm file so it can be opened and looked
// at directly.
//
// Pipeline:
//   1. tb/image_for_test/<...>.hex (RGB565, one pixel per line, row
//      major img_y*320+img_x) is loaded into img_mem via $readmemh.
//      That .hex file is NOT produced by this testbench - it comes
//      from a separate PNG -> hex conversion script.
//   2. img_mem is read the same way frame_buffer.sv reads real BRAM:
//      combinational address (fb_raddr, driven by vga_frame_reader_v4)
//      in, data registered out one clock later.
//   3. draw_box's box_en is combinational off the CURRENT vga_x/vga_y,
//      while vga_frame_reader_v4's fb_rdata/pixel_valid_d are one
//      clock behind (BRAM read latency). box_en is registered once
//      here (box_en_aligned) to line the two back up - the same
//      pattern vga_frame_reader_v4 already uses internally for
//      split_mode_aligned/quadrant_4_aligned.
//   4. The raster sweeps all 640x480 visible pixels, one pixel per
//      clock, exactly like the real VGA timing (see box_coordinate's
//      testbench for the same raster style). Each pixel's final
//      vga_r/vga_g/vga_b is written to a binary PPM (P6) file.
//
// The .hex/.ppm paths below are relative; $readmemh/$fopen resolve
// relative paths against the simulator's own working directory (e.g.
// .../vivado_prj.sim/sim_1/behav/xsim), NOT this source file's folder.
// Adjust IMG_HEX_FILE/OUT_PPM_FILE to absolute paths if the relative
// ones aren't found from wherever xsim is launched.
// ------------------------------------------------------------------

module tb_draw_box_img_test ();

    // ============================================================
    // >>> EDIT HERE: bounding box + border thickness to draw <<<
    //   min is inclusive, max is exclusive: box covers
    //   x in [BOX_MIN_X, BOX_MAX_X), y in [BOX_MIN_Y, BOX_MAX_Y)
    //   (source-image / 320x240 coordinates, same scale as min_x/max_x
    //   from a real tracker)
    // ============================================================
    localparam logic [8:0] BOX_MIN_X = 9'd100;
    localparam logic [8:0] BOX_MAX_X = 9'd200;
    localparam logic [7:0] BOX_MIN_Y = 8'd30;
    localparam logic [7:0] BOX_MAX_Y = 8'd100;
    localparam int         THICKNESS = 2;
    // ============================================================

    // ============================================================
    // >>> EDIT HERE: input image (hex) / output frame (ppm) paths <<<
    // ============================================================
    localparam string IMG_HEX_FILE = "tb/image_for_test/lenna_320x240.hex";
    localparam string OUT_PPM_FILE = "tb/image_for_test/lenna_boxed_640x480.ppm";
    // ============================================================

    localparam int ADDR_WIDTH = 17;
    localparam int IMG_WIDTH  = 320;
    localparam int IMG_HEIGHT = 240;
    localparam int FRAME_SIZE = IMG_WIDTH * IMG_HEIGHT;

    localparam int H_VISIBLE = 640;
    localparam int V_VISIBLE = 480;

    // ------------------------------------------------------------
    // Shared / DUT signals
    // ------------------------------------------------------------
    logic                  clk;
    logic                  rst;
    logic [          1:0]  vga_sw;
    logic [          9:0]  vga_x;
    logic [          9:0]  vga_y;
    logic                  video_on;

    logic                  target_valid;
    logic                  done;
    logic [          8:0]  max_x;
    logic [          8:0]  min_x;
    logic [          7:0]  max_y;
    logic [          7:0]  min_y;

    wire                   box_en_raw;
    logic                  box_en_aligned;

    wire  [ADDR_WIDTH-1:0] fb_raddr;
    logic [         15:0]  fb_rdata;

    wire  [          3:0]  vga_r;
    wire  [          3:0]  vga_g;
    wire  [          3:0]  vga_b;
    wire  [         15:0]  pixel_rgb565;
    wire                   pixel_valid;
    wire                   split_mode_aligned;
    wire                   quadrant_4_aligned;

    // ------------------------------------------------------------
    // Test image memory (stands in for frame_buffer.sv, preloaded from
    // a real picture instead of being written by a camera).
    // ------------------------------------------------------------
    logic [15:0] img_mem[0:FRAME_SIZE-1];

    initial $readmemh(IMG_HEX_FILE, img_mem);

    always_ff @(posedge clk) begin
        fb_rdata <= img_mem[fb_raddr];
    end

    // ------------------------------------------------------------
    // DUTs
    // ------------------------------------------------------------
    draw_box #(
        .THICKNESS(THICKNESS)
    ) u_draw_box (
        .pclk        (clk),
        .rst         (rst),
        .target_valid(target_valid),
        .done        (done),
        .x_pixel     (vga_x),
        .y_pixel     (vga_y),
        .max_x       (max_x),
        .min_x       (min_x),
        .max_y       (max_y),
        .min_y       (min_y),
        .box_en      (box_en_raw)
    );

    // Realign box_en with the 1-clock BRAM read latency that
    // fb_rdata/pixel_valid_d already carry inside vga_frame_reader_v4.
    // Without this the border lands one pixel_clk ahead of the image
    // data it is supposed to sit on top of.
    always_ff @(posedge clk or posedge rst) begin
        if (rst) box_en_aligned <= 1'b0;
        else box_en_aligned <= box_en_raw;
    end

    vga_frame_reader_v4 #(
        .IMG_WIDTH (IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_reader (
        .clk   (clk),
        .rst   (rst),
        .vga_sw(vga_sw),

        .vga_x   (vga_x),
        .vga_y   (vga_y),
        .video_on(video_on),

        .box_en(box_en_aligned),

        .fb_raddr(fb_raddr),
        .fb_rdata(fb_rdata),

        .vga_r(vga_r),
        .vga_g(vga_g),
        .vga_b(vga_b),

        .pixel_rgb565(pixel_rgb565),
        .pixel_valid (pixel_valid),

        .split_mode_aligned(split_mode_aligned),
        .quadrant_4_aligned(quadrant_4_aligned)
    );

    // ------------------------------------------------------------
    // Clock: 100 MHz
    // ------------------------------------------------------------
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ------------------------------------------------------------
    // PPM (P6) output file + pixel writer
    //
    // The pipeline (fb_rdata + box_en_aligned) is exactly 1 clock deep,
    // so at the moment coordinate (vx,vy) is being PRESENTED on
    // vga_x/vga_y, the valid/aligned sample on the outputs belongs to
    // the PREVIOUS raster coordinate. write_pixel is therefore always
    // called one iteration behind - see run_sweep below.
    // ------------------------------------------------------------
    integer fd;
    int     invalid_count;

    task automatic write_pixel();
        byte r8, g8, b8;
        begin
            if (pixel_valid) begin
                r8 = byte'(vga_r * 8'd17);  // 4-bit -> 8-bit (15*17=255)
                g8 = byte'(vga_g * 8'd17);
                b8 = byte'(vga_b * 8'd17);
            end else begin
                invalid_count = invalid_count + 1;
                r8 = 8'd0;
                g8 = 8'd0;
                b8 = 8'd0;
            end
            $fwrite(fd, "%c%c%c", r8, g8, b8);
        end
    endtask

    task automatic run_sweep();
        int  vx, vy;
        int  prev_vx, prev_vy;
        bit  has_prev;
        begin
            fd = $fopen(OUT_PPM_FILE, "wb");
            if (fd == 0) $fatal(1, "could not open %s for writing", OUT_PPM_FILE);

            $fwrite(fd, "P6\n%0d %0d\n255\n", H_VISIBLE, V_VISIBLE);

            has_prev      = 1'b0;
            invalid_count = 0;
            prev_vx       = 0;
            prev_vy       = 0;

            for (vy = 0; vy < V_VISIBLE; vy++) begin
                for (vx = 0; vx < H_VISIBLE; vx++) begin
                    @(posedge clk);
                    vga_x <= 10'(vx);
                    vga_y <= 10'(vy);
                    #1;

                    if (has_prev) write_pixel();

                    prev_vx  = vx;
                    prev_vy  = vy;
                    has_prev = 1'b1;
                end
                if ((vy % 60) == 0) $display("  row %0d / %0d", vy, V_VISIBLE);
            end

            // Flush the very last pixel (pipeline is 1 clock deep).
            @(posedge clk);
            #1;
            write_pixel();

            $fclose(fd);
        end
    endtask

    // ------------------------------------------------------------
    // Main sequence
    // ------------------------------------------------------------
    initial begin
        rst          = 1'b1;
        vga_sw       = 2'b01;  // MODE_FULLSCREEN (2x, matches draw_box's [9:1]/[8:1] halving)
        vga_x        = 10'd0;
        vga_y        = 10'd0;
        video_on     = 1'b0;
        target_valid = 1'b0;
        done         = 1'b0;
        min_x        = BOX_MIN_X;
        max_x        = BOX_MAX_X;
        min_y        = BOX_MIN_Y;
        max_y        = BOX_MAX_Y;

        $display("");
        $display("==================================================");
        $display(" DRAW_BOX IMAGE TEST");
        $display("   box   : x=[%0d,%0d) y=[%0d,%0d)  thickness=%0d",
                 BOX_MIN_X, BOX_MAX_X, BOX_MIN_Y, BOX_MAX_Y, THICKNESS);
        $display("   image : %s", IMG_HEX_FILE);
        $display("   output: %s", OUT_PPM_FILE);
        $display("==================================================");

        repeat (4) @(posedge clk);
        rst = 1'b0;

        // Let the vga_sw synchronizer settle into MODE_FULLSCREEN.
        repeat (4) @(posedge clk);
        video_on     = 1'b1;
        target_valid = 1'b1;

        // Load the box once.
        @(posedge clk);
        done <= 1'b1;
        @(posedge clk);
        done <= 1'b0;
        repeat (2) @(posedge clk);

        $display("");
        $display("sweeping %0dx%0d ...", H_VISIBLE, V_VISIBLE);
        run_sweep();

        $display("");
        $display("done. %0d pixels written (%0d had pixel_valid low).",
                 H_VISIBLE * V_VISIBLE, invalid_count);
        $display("==================================================");

        $finish;
    end

endmodule
