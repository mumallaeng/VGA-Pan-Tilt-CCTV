`timescale 1ns / 1ps

// ------------------------------------------------------------------
// Integration test: box_coordinate + draw_box + vga_frame_reader_v4
//
//   box_coordinate      : now raster-driven. It takes x_pixel/y_pixel and
//                         only advances while the raster sits inside the
//                         bounding box; outside it parks at (min_x,min_y).
//   draw_box            : compares draw_x/draw_y against the VGA raster
//                         position and asserts box_en
//   vga_frame_reader_v4 : forces vga_r/g/b to pure red while box_en is high,
//                         otherwise passes the frame-buffer pixel through
//
// ------------------------------------------------------------------
// Because box_coordinate is now driven by x_pixel/y_pixel, it can no
// longer be exercised with the raster stopped - every phase runs the
// raster. The testbench recomputes box_coordinate's own in-box condition
//
//     x_en = (x_pixel[8:0] >= min_x) && (x_pixel[8:0] < max_x)
//     y_en = (y_pixel[7:0] >= min_y) && (y_pixel[7:0] < max_y)
//
// independently (see the statistics collector) so that three separate
// things can be told apart:
//   - which screen pixels box_coordinate thinks are inside the box
//   - which screen pixels draw_box actually lights up
//   - how much those two sets overlap
// ------------------------------------------------------------------
// target_valid is modelled as STICKY
//
// In the real system target_valid rises once the tracker has seen a
// target and never returns to 0 afterwards. This testbench enforces that:
//   - target_valid is only ever cleared while rst is asserted
//   - a 1 -> 0 transition outside reset is reported as a failure
//     (see the stickiness monitor below)
// ------------------------------------------------------------------
//
// The VGA raster (800x525 counters, video_on = visible area) is modelled
// inside this testbench instead of instantiating vga_core, because
// vga_core contains pixel_clk_gen (a clock divider) which would only add
// simulation time without changing what is being verified here.
//
// frame_buffer is NOT instantiated either: fb_rdata is stubbed with a
// fixed pure-green RGB565 pixel so that the red box overlay is trivially
// distinguishable from pass-through video.
//
// vga_sw is held at MODE_FULLSCREEN (2'b01) - the only reader mode whose
// img_x/img_y use the same vga_x[9:1] / vga_y[9:1] halving that draw_box
// applies, so a source pixel (draw_x,draw_y) maps to the 2x2 screen block
// (2*draw_x .. 2*draw_x+1, 2*draw_y .. 2*draw_y+1).
//
// Four phases:
//   PHASE A - box_coordinate behaviour under a live raster: parking
//             outside the box, tracking inside it, and how much of the
//             box the (draw_x,draw_y) pair actually sweeps in one frame
//   PHASE B - full chain with a 1x1 box, one full frame scanned, exact
//             red-pixel positions checked
//   PHASE C - full chain with a real 20x20 box: what reaches the screen,
//             and how it lines up with box_coordinate's own in-box region
//   PHASE D - target moves while target_valid stays high: how quickly
//             does box_coordinate re-park onto the new bounds?
// ------------------------------------------------------------------

module tb_box_coordinate ();

    // ------------------------------------------------------------
    // Parameters
    // ------------------------------------------------------------
    localparam int ADDR_WIDTH = 17;
    localparam int IMG_WIDTH = 320;
    localparam int IMG_HEIGHT = 240;

    localparam int H_VISIBLE = 640;
    localparam int V_VISIBLE = 480;
    localparam int H_TOTAL = 800;
    localparam int V_TOTAL = 525;

    // Pure green RGB565 stub pixel: 0x07E0 -> RGB444 pass-through is
    // r=0x0, g=0xF, b=0x0 (clearly not the box overlay's 0xF,0x0,0x0).
    localparam logic [15:0] FB_STUB_RGB565 = 16'h07E0;
    localparam logic [3:0] PASS_R = 4'h0;
    localparam logic [3:0] PASS_G = 4'hF;
    localparam logic [3:0] PASS_B = 4'h0;

    // PHASE A box: small, and placed so that BOTH truncation aliases
    // (x_pixel[8:0] and y_pixel[7:0]) land inside the visible area.
    localparam int A_MIN_X = 100;
    localparam int A_MAX_X = 104;
    localparam int A_MIN_Y = 50;
    localparam int A_MAX_Y = 53;

    // PHASE B box: 1x1
    localparam int B_MIN_X = 150;
    localparam int B_MAX_X = 151;
    localparam int B_MIN_Y = 100;
    localparam int B_MAX_Y = 101;

    // PHASE C box: 20x20 source pixels
    localparam int C_MIN_X = 140;
    localparam int C_MAX_X = 160;
    localparam int C_MIN_Y = 90;
    localparam int C_MAX_Y = 110;

    // PHASE D: the same target moving, target_valid never drops.
    localparam int D1_MIN_X = 200;
    localparam int D1_MAX_X = 220;
    localparam int D1_MIN_Y = 150;
    localparam int D1_MAX_Y = 170;

    localparam int D2_MIN_X = 40;
    localparam int D2_MAX_X = 60;
    localparam int D2_MIN_Y = 20;
    localparam int D2_MAX_Y = 40;

    localparam int LOCK_LIMIT = 100000;

    // ------------------------------------------------------------
    // DUT signals
    // ------------------------------------------------------------
    logic                  pclk;
    logic                  rst;

    logic                  target_valid;
    logic [          8:0]  max_x;
    logic [          8:0]  min_x;
    logic [          7:0]  max_y;
    logic [          7:0]  min_y;

    wire  [          8:0]  draw_x;
    wire  [          7:0]  draw_y;
    wire                   box_en;

    logic [          1:0]  vga_sw;
    wire  [          9:0]  vga_x;
    wire  [          9:0]  vga_y;
    wire                   video_on;

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
    // Scoreboard
    // ------------------------------------------------------------
    int                    test_count;
    int                    pass_count;
    int                    fail_count;
    int                    warn_count;

    // ------------------------------------------------------------
    // DUTs
    // ------------------------------------------------------------
    box_coordinate u_box_coordinate (
        .pclk        (pclk),
        .rst         (rst),
        .target_valid(target_valid),
        .x_pixel     (vga_x),
        .y_pixel     (vga_y),
        .max_x       (max_x),
        .min_x       (min_x),
        .max_y       (max_y),
        .min_y       (min_y),
        .draw_x      (draw_x),
        .draw_y      (draw_y)
    );

    draw_box u_draw_box (
        .target_valid(target_valid),
        .x_pixel     (vga_x),
        .y_pixel     (vga_y),
        .rd_data     (fb_rdata),
        .draw_x      (draw_x),
        .draw_y      (draw_y),
        .box_en      (box_en)
    );

    vga_frame_reader_v4 #(
        .IMG_WIDTH (IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_reader (
        .clk   (pclk),
        .rst   (rst),
        .vga_sw(vga_sw),

        .vga_x   (vga_x),
        .vga_y   (vga_y),
        .video_on(video_on),

        .box_en(box_en),

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
    // Clock (100 MHz, used as the pixel clock for the whole chain)
    // ------------------------------------------------------------
    initial pclk = 1'b0;
    always #5 pclk = ~pclk;

    // ------------------------------------------------------------
    // target_valid stickiness monitor
    //
    // tv_violations is only ever written here (its declaration initialiser
    // aside), so the scoreboard counters stay single-process.
    // ------------------------------------------------------------
    logic tv_seen;
    int   tv_violations = 0;

    always @(posedge pclk or posedge rst) begin
        if (rst) begin
            tv_seen <= 1'b0;
        end else begin
            if (tv_seen && !target_valid) begin
                tv_violations = tv_violations + 1;
                $display("       !! target_valid fell to 0 outside reset at %0t",
                         $time);
            end
            if (target_valid) tv_seen <= 1'b1;
        end
    end

    // ------------------------------------------------------------
    // VGA raster model (stands in for vga_core / pixel_counter)
    // ------------------------------------------------------------
    logic       raster_en;
    logic [9:0] h_cnt;
    logic [9:0] v_cnt;

    always_ff @(posedge pclk or posedge rst) begin
        if (rst) begin
            h_cnt <= 10'd0;
            v_cnt <= 10'd0;
        end else if (raster_en) begin
            if (h_cnt == H_TOTAL - 1) begin
                h_cnt <= 10'd0;
                if (v_cnt == V_TOTAL - 1) v_cnt <= 10'd0;
                else v_cnt <= v_cnt + 10'd1;
            end else begin
                h_cnt <= h_cnt + 10'd1;
            end
        end
    end

    assign vga_x    = h_cnt;
    assign vga_y    = v_cnt;
    assign video_on = raster_en && (h_cnt < H_VISIBLE) && (v_cnt < V_VISIBLE);

    // ------------------------------------------------------------
    // Independent model of box_coordinate's in-box condition.
    //
    // Deliberately written from the RTL equation rather than reusing any
    // DUT signal, so a wiring or width mistake shows up as a mismatch.
    // ------------------------------------------------------------
    wire tb_x_en = (vga_x[8:0] >= min_x) && (vga_x[8:0] < max_x);
    wire tb_y_en = (vga_y[7:0] >= min_y) && (vga_y[7:0] < max_y);
    wire tb_in_region = tb_x_en && tb_y_en;

    // ------------------------------------------------------------
    // Frame-scan statistics collector
    //
    // Sampled 1 ns after posedge so every registered value has already
    // been updated and every combinational output has settled.
    // ------------------------------------------------------------
    logic mon_en;

    // --- what the screen shows -------------------------------------
    int   red_cnt;  // visible pixels painted red
    int   red_xmin, red_xmax, red_ymin, red_ymax;
    int   row_hits              [0:V_VISIBLE-1];
    int   valid_cnt;  // visible pixels with pixel_valid high
    int   blank_box_cnt;  // box_en high while nothing is displayed
    int   badcolor_cnt;  // colour did not match box_en

    // --- what box_coordinate thinks the box is ---------------------
    int   region_cnt;  // visible pixels inside box_coordinate's region
    int   region_blank_cnt;  // same, but during blanking
    int   region_xmin, region_xmax, region_ymin, region_ymax;
    int   region_row_hits       [0:V_VISIBLE-1];

    // --- how the two line up ---------------------------------------
    int   red_in_region;
    int   red_out_region;

    // --- box_coordinate behavioural checks -------------------------
    int   park_err;  // outside the box but draw != (min_x,min_y)
    int   track_err;  // inside the box but draw_x != x_pixel[8:0]
    bit   drawy_seen            [0:255];  // which draw_y values appeared
    bit   in_region_d;  // previous sample, for the exit overshoot

    initial mon_en = 1'b0;

    always @(posedge pclk) begin
        #1;
        if (mon_en) begin

            // ---- screen side ------------------------------------
            if (box_en && !pixel_valid) blank_box_cnt = blank_box_cnt + 1;

            if (pixel_valid) begin
                valid_cnt = valid_cnt + 1;

                if (box_en) begin
                    red_cnt = red_cnt + 1;
                    if (int'(vga_x) < red_xmin) red_xmin = int'(vga_x);
                    if (int'(vga_x) > red_xmax) red_xmax = int'(vga_x);
                    if (int'(vga_y) < red_ymin) red_ymin = int'(vga_y);
                    if (int'(vga_y) > red_ymax) red_ymax = int'(vga_y);
                    if (int'(vga_y) < V_VISIBLE)
                        row_hits[int'(vga_y)] = row_hits[int'(vga_y)] + 1;

                    if (tb_in_region) red_in_region = red_in_region + 1;
                    else red_out_region = red_out_region + 1;

                    if (!((vga_r == 4'hF) && (vga_g == 4'h0) && (vga_b == 4'h0)))
                        badcolor_cnt = badcolor_cnt + 1;
                end else begin
                    if (!((vga_r == PASS_R) && (vga_g == PASS_G) && (vga_b == PASS_B)))
                        badcolor_cnt = badcolor_cnt + 1;
                end
            end

            // ---- box_coordinate side ----------------------------
            if (tb_in_region) begin
                if (video_on) begin
                    region_cnt = region_cnt + 1;
                    if (int'(vga_x) < region_xmin) region_xmin = int'(vga_x);
                    if (int'(vga_x) > region_xmax) region_xmax = int'(vga_x);
                    if (int'(vga_y) < region_ymin) region_ymin = int'(vga_y);
                    if (int'(vga_y) > region_ymax) region_ymax = int'(vga_y);
                    region_row_hits[int'(vga_y)] =
                        region_row_hits[int'(vga_y)] + 1;
                end else begin
                    region_blank_cnt = region_blank_cnt + 1;
                end

                // Inside the box the counter should follow the raster.
                if (draw_x !== vga_x[8:0]) track_err = track_err + 1;

                drawy_seen[int'(draw_y)] = 1'b1;
            end else begin
                // Outside the box the counter should sit on the origin.
                // The very first cycle after leaving still carries the
                // last increment, so that one is exempt.
                if (!in_region_d) begin
                    if ((draw_x !== min_x) || (draw_y !== min_y))
                        park_err = park_err + 1;
                end
            end

            in_region_d = tb_in_region;
        end
    end

    // ------------------------------------------------------------
    // Helper tasks
    // ------------------------------------------------------------
    task automatic report(input string name, input bit ok, input string info);
        begin
            test_count = test_count + 1;
            if (ok) begin
                pass_count = pass_count + 1;
                $display("[PASS] %-22s %s", name, info);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] %-22s %s", name, info);
            end
        end
    endtask

    // The only legal way to clear target_valid. rst is raised first so the
    // stickiness monitor sees a reset, not a spurious deassertion.
    task automatic apply_reset();
        begin
            rst = 1'b1;
            @(negedge pclk);
            target_valid = 1'b0;
            repeat (4) @(negedge pclk);
            rst = 1'b0;
            // let the reader's vga_sw synchroniser settle into MODE_FULLSCREEN
            repeat (4) @(negedge pclk);
        end
    endtask

    // Update the box bounds only. target_valid is deliberately untouched:
    // it is sticky, so this is what a moving target really looks like.
    task automatic set_box(input int lo_x, input int hi_x, input int lo_y,
                           input int hi_y);
        begin
            min_x = 9'(lo_x);
            max_x = 9'(hi_x);
            min_y = 8'(lo_y);
            max_y = 8'(hi_y);
        end
    endtask

    // Count clocks until draw_x/draw_y first sit on the new origin.
    task automatic measure_park(input int lo_x, input int lo_y, input int limit,
                                output int clocks, output bit parked);
        int n;
        begin
            clocks = 0;
            parked = 1'b0;
            n      = 0;
            while ((n < limit) && !parked) begin
                @(negedge pclk);
                n = n + 1;
                if ((draw_x == 9'(lo_x)) && (draw_y == 8'(lo_y)))
                    parked = 1'b1;
            end
            clocks = n;
        end
    endtask

    task automatic clear_stats();
        int r;
        begin
            red_cnt          = 0;
            valid_cnt        = 0;
            blank_box_cnt    = 0;
            badcolor_cnt     = 0;
            red_xmin         = H_TOTAL;
            red_xmax         = -1;
            red_ymin         = V_TOTAL;
            red_ymax         = -1;

            region_cnt       = 0;
            region_blank_cnt = 0;
            region_xmin      = H_TOTAL;
            region_xmax      = -1;
            region_ymin      = V_TOTAL;
            region_ymax      = -1;

            red_in_region    = 0;
            red_out_region   = 0;

            park_err         = 0;
            track_err        = 0;
            in_region_d      = 1'b0;

            for (r = 0; r < V_VISIBLE; r = r + 1) begin
                row_hits[r]        = 0;
                region_row_hits[r] = 0;
            end
            for (r = 0; r < 256; r = r + 1) drawy_seen[r] = 1'b0;
        end
    endtask

    // Monitor exactly one full frame: arm on the last pixel of a frame,
    // disarm on the last pixel of the next one.
    task automatic scan_one_frame();
        begin
            @(negedge pclk);
            while (!((h_cnt == H_TOTAL - 1) && (v_cnt == V_TOTAL - 1)))
                @(negedge pclk);
            clear_stats();
            mon_en = 1'b1;
            @(negedge pclk);
            while (!((h_cnt == H_TOTAL - 1) && (v_cnt == V_TOTAL - 1)))
                @(negedge pclk);
            mon_en = 1'b0;
            @(negedge pclk);
        end
    endtask

    // Number of separate horizontal bands (groups of consecutive rows)
    // that the given per-row histogram covers.
    function automatic int count_bands(ref int hist[0:V_VISIBLE-1]);
        int  y;
        int  bands;
        bit  prev;
        begin
            bands = 0;
            prev  = 1'b0;
            for (y = 0; y < V_VISIBLE; y = y + 1) begin
                if ((hist[y] != 0) && !prev) bands = bands + 1;
                prev = (hist[y] != 0);
            end
            return bands;
        end
    endfunction

    function automatic int count_drawy();
        int v;
        int n;
        begin
            n = 0;
            for (v = 0; v < 256; v = v + 1) if (drawy_seen[v]) n = n + 1;
            return n;
        end
    endfunction

    task automatic start_phase(input int lo_x, input int hi_x, input int lo_y,
                               input int hi_y);
        begin
            apply_reset();
            set_box(lo_x, hi_x, lo_y, hi_y);
            repeat (3) @(negedge pclk);
            target_valid = 1'b1;  // rises once, never falls again
            raster_en    = 1'b1;
        end
    endtask

    // ------------------------------------------------------------
    // PHASE A - box_coordinate under a live raster
    // ------------------------------------------------------------
    task automatic phase_a();
        int box_w, box_h;
        int exp_region;
        int bands;
        int copies;
        int distinct_y;
        begin
            box_w      = A_MAX_X - A_MIN_X;
            box_h      = A_MAX_Y - A_MIN_Y;
            exp_region = box_w * box_h;

            $display("");
            $display("--------------------------------------------------");
            $display(" PHASE A : box_coordinate under a live raster");
            $display("           box x=[%0d,%0d) y=[%0d,%0d)  (%0dx%0d)", A_MIN_X,
                     A_MAX_X, A_MIN_Y, A_MAX_Y, box_w, box_h);
            $display("--------------------------------------------------");

            start_phase(A_MIN_X, A_MAX_X, A_MIN_Y, A_MAX_Y);
            scan_one_frame();

            // 1) parking: outside the box the counter must hold the origin
            report("A-park-outside", (park_err == 0),
                   $sformatf("%0d clocks outside the box with draw != (min_x,min_y)",
                             park_err));

            // 2) tracking: inside the box draw_x must follow the raster
            report("A-track-inside", (track_err == 0),
                   $sformatf("%0d clocks inside the box with draw_x != x_pixel[8:0]",
                             track_err));

            // 3) how big is the region box_coordinate actually recognises?
            bands  = count_bands(region_row_hits);
            copies = (exp_region > 0) ? (region_cnt / exp_region) : 0;

            $display("");
            $display("  --- box_coordinate's in-box region, one frame ---");
            $display("  visible pixels judged in-box : %0d  (a %0dx%0d box is %0d)",
                     region_cnt, box_w, box_h, exp_region);
            $display("  same during blanking         : %0d", region_blank_cnt);
            if (region_cnt > 0)
                $display("  bounding box                 : x=%0d..%0d y=%0d..%0d",
                         region_xmin, region_xmax, region_ymin, region_ymax);
            $display("  copies on screen             : %0d  (%0d row band(s))",
                     copies, bands);

            if (copies <= 1) begin
                report("A-region-single-copy", (region_cnt == exp_region),
                       $sformatf("region appears once, %0d pixels", region_cnt));
            end else begin
                warn_count = warn_count + 1;
                $display("");
                $display("[WARN] A-region-aliasing      the box region appears %0d times",
                         copies);
                $display("       on screen instead of once. x_en/y_en compare");
                $display("       TRUNCATED raster coordinates:");
                $display("         x_pixel[8:0] folds screen x 512..799 onto 0..287");
                $display("         y_pixel[7:0] folds screen y 256..511 onto 0..255");
                $display("       so this box also matches at x=%0d and at y=%0d,",
                         A_MIN_X + 512, A_MIN_Y + 256);
                $display("       both still inside the 640x480 visible area.");
                $display("       Compare the full 10-bit coordinate (or the halved");
                $display("       one - see PHASE C) instead of truncating.");
            end

            // 4) does the sweep ever leave the first row of the box?
            distinct_y = count_drawy();
            $display("");
            $display("  distinct draw_y values seen  : %0d  (box is %0d rows tall)",
                     distinct_y, box_h);

            if (distinct_y >= box_h) begin
                test_count = test_count + 1;
                pass_count = pass_count + 1;
                $display("[PASS] A-y-sweep              draw_y covers the box height");
            end else begin
                warn_count = warn_count + 1;
                $display("[WARN] A-y-sweep              draw_y never leaves min_y.");
                $display("       max_x_reg/min_x_reg/max_y_reg/min_y_reg reset to 0");
                $display("       and are only reloaded when");
                $display("         x_cnt == max_x_reg-1 && y_cnt == max_y_reg-1");
                $display("       which, with max_x_reg = 0, means x_cnt == 511. The");
                $display("       counter never gets near 511, so the latches stay 0");
                $display("       forever and the y increment never fires. The latch");
                $display("       needs a bootstrap - load it while target_valid is");
                $display("       low, or on a frame boundary, not from itself.");
            end
        end
    endtask

    // ------------------------------------------------------------
    // PHASE B - full chain, 1x1 box
    // ------------------------------------------------------------
    task automatic phase_b();
        int exp_x0, exp_x1, exp_y0, exp_y1;
        begin
            exp_x0 = 2 * B_MIN_X;
            exp_x1 = 2 * B_MIN_X + 1;
            exp_y0 = 2 * B_MIN_Y;
            exp_y1 = 2 * B_MIN_Y + 1;

            $display("");
            $display("--------------------------------------------------");
            $display(" PHASE B : chain with a 1x1 box at source (%0d,%0d)",
                     B_MIN_X, B_MIN_Y);
            $display("           expected screen block x=%0d..%0d y=%0d..%0d",
                     exp_x0, exp_x1, exp_y0, exp_y1);
            $display("--------------------------------------------------");

            start_phase(B_MIN_X, B_MAX_X, B_MIN_Y, B_MAX_Y);
            scan_one_frame();

            report("B-visible-pixels", (valid_cnt > 0),
                   $sformatf("%0d displayed pixels in the frame", valid_cnt));

            report("B-red-pixel-count", (red_cnt == 4),
                   $sformatf("%0d red pixels (expected 4 = one 2x2 block)",
                             red_cnt));

            report("B-red-position",
                   (red_cnt == 4) && (red_xmin == exp_x0) &&
                   (red_xmax == exp_x1) && (red_ymin == exp_y0) &&
                   (red_ymax == exp_y1),
                   $sformatf("red area x=%0d..%0d y=%0d..%0d", red_xmin,
                             red_xmax, red_ymin, red_ymax));

            report("B-colour-consistency", (badcolor_cnt == 0),
                   $sformatf("%0d pixels whose colour disagreed with box_en",
                             badcolor_cnt));

            $display("        info: box_en asserted %0d times outside the",
                     blank_box_cnt);
            $display("              displayed area (blanking / pipeline gap)");
        end
    endtask

    // ------------------------------------------------------------
    // PHASE C - full chain, real 20x20 box
    // ------------------------------------------------------------
    task automatic phase_c();
        int box_w, box_h;
        int ideal_red;
        int shown_rows;
        int y;
        begin
            box_w     = C_MAX_X - C_MIN_X;
            box_h     = C_MAX_Y - C_MIN_Y;
            ideal_red = box_w * box_h * 4;  // each source pixel = 2x2 screen

            $display("");
            $display("--------------------------------------------------");
            $display(" PHASE C : chain with a %0dx%0d box  x=[%0d,%0d) y=[%0d,%0d)",
                     box_w, box_h, C_MIN_X, C_MAX_X, C_MIN_Y, C_MAX_Y);
            $display("           a filled overlay would be x=%0d..%0d y=%0d..%0d",
                     2 * C_MIN_X, 2 * C_MAX_X - 1, 2 * C_MIN_Y, 2 * C_MAX_Y - 1);
            $display("--------------------------------------------------");

            start_phase(C_MIN_X, C_MAX_X, C_MIN_Y, C_MAX_Y);
            scan_one_frame();

            report("C-colour-consistency", (badcolor_cnt == 0),
                   $sformatf("%0d pixels whose colour disagreed with box_en",
                             badcolor_cnt));

            $display("");
            $display("  --- what actually reached the screen ---");
            $display("  displayed pixels in frame : %0d", valid_cnt);
            $display("  red pixels in frame       : %0d", red_cnt);
            $display("  red pixels for a filled");
            $display("  %0dx%0d overlay             : %0d", box_w, box_h,
                     ideal_red);
            if (red_cnt > 0)
                $display("  red bounding box          : x=%0d..%0d y=%0d..%0d",
                         red_xmin, red_xmax, red_ymin, red_ymax);
            else $display("  red bounding box          : (none)");
            $display("  box_en during blanking    : %0d", blank_box_cnt);

            shown_rows = 0;
            for (y = 0; y < V_VISIBLE; y = y + 1) begin
                if ((row_hits[y] != 0) && (shown_rows < 16)) begin
                    $display("    screen row %0d : %0d red pixel(s)", y,
                             row_hits[y]);
                    shown_rows = shown_rows + 1;
                end
            end

            // ---- the coordinate-scale cross-check ----------------
            $display("");
            $display("  --- box_coordinate's region vs. what draw_box lit ---");
            $display("  pixels box_coordinate calls in-box : %0d", region_cnt);
            if (region_cnt > 0)
                $display("    at screen x=%0d..%0d y=%0d..%0d", region_xmin,
                         region_xmax, region_ymin, region_ymax);
            $display("  red pixels inside that region      : %0d", red_in_region);
            $display("  red pixels outside that region     : %0d", red_out_region);

            $display("");
            if ((region_cnt > 0) && (red_in_region == 0)) begin
                warn_count = warn_count + 1;
                $display("[WARN] C-scale-mismatch       the two modules disagree on scale.");
                $display("       box_coordinate compares the RAW raster position:");
                $display("           x_pixel[8:0] vs min_x/max_x");
                $display("       draw_box compares the HALVED position:");
                $display("           x_pixel[9:1] vs draw_x");
                $display("       In MODE_FULLSCREEN a source pixel covers 2 screen");
                $display("       pixels, so the region box_coordinate recognises");
                $display("       (screen x=%0d..%0d) and the pixels draw_box lights",
                         region_xmin, region_xmax);
                $display("       (screen x=%0d..%0d) can never overlap. Pick one",
                         red_xmin, red_xmax);
                $display("       scale: either halve in box_coordinate too, or stop");
                $display("       halving in draw_box.");
            end

            if (red_cnt == ideal_red) begin
                test_count = test_count + 1;
                pass_count = pass_count + 1;
                $display("[PASS] C-box-rendering        the box region is fully painted");
            end else begin
                warn_count = warn_count + 1;
                $display("[WARN] C-box-rendering        %0d red pixels instead of %0d.",
                         red_cnt, ideal_red);
                $display("       Whatever survives is the parked origin being matched");
                $display("       by draw_box, not a swept box outline. Note also that");
                $display("       box_coordinate sweeps the FILLED rectangle, so even");
                $display("       a working sweep would cover the target rather than");
                $display("       outline it.");
            end
        end
    endtask

    // ------------------------------------------------------------
    // PHASE D - the target moves while target_valid stays high
    //
    // Continues straight on from PHASE C: no reset, target_valid still 1.
    // With the raster-driven design the counter re-parks on the new
    // min_x/min_y as soon as the raster is outside the box, so this
    // should now be almost immediate.
    // ------------------------------------------------------------
    task automatic move_target(input string name, input int lo_x, input int hi_x,
                               input int lo_y, input int hi_y);
        int park_clk;
        bit parked;
        int from_x, from_y;
        begin
            from_x = int'(draw_x);
            from_y = int'(draw_y);

            set_box(lo_x, hi_x, lo_y, hi_y);
            measure_park(lo_x, lo_y, LOCK_LIMIT, park_clk, parked);

            report(name, parked && (park_clk <= 4),
                   $sformatf("from (%0d,%0d) to (%0d,%0d) in %0d pclk", from_x,
                             from_y, lo_x, lo_y, park_clk));
        end
    endtask

    task automatic phase_d();
        begin
            $display("");
            $display("--------------------------------------------------");
            $display(" PHASE D : target moves, target_valid stays high");
            $display("--------------------------------------------------");
            $display("  No reset, target_valid untouched since PHASE C.");
            $display("");

            move_target("D1-move-right-down", D1_MIN_X, D1_MAX_X, D1_MIN_Y,
                        D1_MAX_Y);
            move_target("D2-move-left-up", D2_MIN_X, D2_MAX_X, D2_MIN_Y,
                        D2_MAX_Y);

            $display("");
            $display("  Re-parking is immediate now: outside the box the next-state");
            $display("  logic drives draw_x/draw_y straight from the live min_x/min_y,");
            $display("  so a moving target no longer costs a settling walk.");
        end
    endtask

    // ------------------------------------------------------------
    // Main sequence
    // ------------------------------------------------------------
    initial begin
        rst          = 1'b1;
        raster_en    = 1'b0;
        target_valid = 1'b0;
        vga_sw       = 2'b01;  // MODE_FULLSCREEN
        min_x        = 9'd0;
        max_x        = 9'd0;
        min_y        = 8'd0;
        max_y        = 8'd0;
        fb_rdata     = FB_STUB_RGB565;

        test_count   = 0;
        pass_count   = 0;
        fail_count   = 0;
        warn_count   = 0;
        clear_stats();

        $display("");
        $display("==================================================");
        $display(" box_coordinate + draw_box + vga_frame_reader_v4");
        $display(" raster-driven box_coordinate, sticky target_valid");
        $display("==================================================");

        phase_a();
        phase_b();
        phase_c();
        phase_d();

        raster_en = 1'b0;

        $display("");
        report("tv-sticky", (tv_violations == 0),
               $sformatf("%0d illegal target_valid deassertions over the whole run",
                         tv_violations));

        $display("");
        $display("==================================================");
        $display(" SUMMARY : total=%0d pass=%0d fail=%0d warn=%0d", test_count,
                 pass_count, fail_count, warn_count);
        $display("==================================================");

        if (fail_count == 0) begin
            if (warn_count == 0) $display("*** ALL CHECKS PASSED ***");
            else $display("*** WIRING OK, BUT SEE THE WARNINGS ABOVE ***");
        end else begin
            $fatal(1, "box_coordinate integration test failed.");
        end

        $finish;
    end

endmodule
