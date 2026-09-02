`timescale 1ns / 1ps

// ------------------------------------------------------------------
// Integration test: draw_box + vga_frame_reader_v4
//
// draw_box now latches a bounding box (min_x/max_x/min_y/max_y) on a
// `done` pulse and draws only its BORDER (THICKNESS source-pixels wide)
// while target_valid is high. vga_frame_reader_v4 is the consumer:
// box_en forces vga_r/g/b to pure red, otherwise the frame-buffer pixel
// passes through.
//
//   draw_box.x_pixel/y_pixel <- same vga_x/vga_y fed to the reader
//   draw_box.box_en          -> vga_frame_reader_v4.box_en
//
// vga_sw is held at MODE_FULLSCREEN (2'b01): it's the only mode where
// the reader's img_x/img_y use the same x[9:1]/y[8:1] halving that
// draw_box itself uses, so one source pixel (sx,sy) maps to the 2x2
// screen block (2*sx .. 2*sx+1, 2*sy .. 2*sy+1).
//
// frame_buffer is NOT instantiated: fb_rdata is stubbed with a fixed
// pure-green RGB565 pixel so the red box overlay is trivially
// distinguishable from pass-through video.
//
// Two draw_box instances are driven from the SAME stimulus so that the
// THICKNESS parameter itself is verified: THICKNESS=2 (the DUT wired to
// the reader) and THICKNESS=1 (border-width reference).
//
// Phases:
//   PHASE 0 - after reset the latched bounds are 0 -> box_en never rises
//   PHASE 1 - bounds present on the inputs but `done` low -> still 0
//             (the latch must not be transparent)
//   PHASE 2 - `done` pulse loads the bounds; directed checks on corners,
//             border ring, interior, just-outside pixels and the 2x2
//             screen block, including the red/pass-through VGA color
//   PHASE 3 - target_valid low blanks the box, high restores it
//   PHASE 4 - full 640x480 screen sweep, one screen pixel per pixel clock
//             (the real VGA raster's own pace): every pixel compared
//             against an independent model, and the lit-pixel count
//             compared against the analytic perimeter area (x4, since a
//             source-pixel border cell covers a 2x2 screen block) for
//             both THICKNESS values
//   PHASE 5 - the box moves (new bounds + `done`); the old box must be
//             gone and the new one drawn
//   PHASE 6 - asynchronous reset clears the latched bounds mid-stream
// ------------------------------------------------------------------

module tb_draw_box ();

    localparam int ADDR_WIDTH = 17;
    localparam logic [1:0] THICKNESS = 2;  // DUT under the reader
    localparam logic [1:0] THICKNESS_T1 = 1;  // second instance

    // Pure green RGB565 stub pixel: RGB565=0x07E0 -> RGB444 pass-through
    // vga_r=0x0, vga_g=0xF, vga_b=0x0 (clearly not the box's red 0xF,0x0,0x0).
    localparam logic [15:0] FB_STUB_RGB565 = 16'h07E0;
    localparam logic [ 3:0] PASS_R = 4'h0;
    localparam logic [ 3:0] PASS_G = 4'hF;
    localparam logic [ 3:0] PASS_B = 4'h0;

    // Box #1: 40x40 source pixels, well inside the 320x240 image.
    localparam logic [8:0] BOX0_MIN_X = 9'd100;
    localparam logic [8:0] BOX0_MAX_X = 9'd140;
    localparam logic [7:0] BOX0_MIN_Y = 8'd60;
    localparam logic [7:0] BOX0_MAX_Y = 8'd100;

    // Box #2: moved and resized (24 x 30).
    localparam logic [8:0] BOX1_MIN_X = 9'd200;
    localparam logic [8:0] BOX1_MAX_X = 9'd224;
    localparam logic [7:0] BOX1_MIN_Y = 8'd150;
    localparam logic [7:0] BOX1_MAX_Y = 8'd180;

    localparam int IMG_W = 320;
    localparam int IMG_H = 240;

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

    wire                   box_en;  // THICKNESS = 2
    wire                   box_en_t1;  // THICKNESS = 1

    wire  [ADDR_WIDTH-1:0] fb_raddr;
    logic [         15:0]  fb_rdata;

    wire  [          3:0]  vga_r;
    wire  [          3:0]  vga_g;
    wire  [          3:0]  vga_b;
    wire  [         15:0]  pixel_rgb565;
    wire                   pixel_valid;
    wire                   split_mode_aligned;
    wire                   quadrant_4_aligned;

    int                    test_count;
    int                    pass_count;
    int                    fail_count;


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
        .box_en      (box_en)
    );

    // Same stimulus, thinner border: proves THICKNESS actually controls
    // the border width instead of being ignored.
    draw_box #(
        .THICKNESS(THICKNESS_T1)
    ) u_draw_box_t1 (
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
        .box_en      (box_en_t1)
    );

    vga_frame_reader_v4 #(
        .IMG_WIDTH (IMG_W),
        .IMG_HEIGHT(IMG_H),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_reader (
        .clk   (clk),
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
    // Clock: 100 MHz
    // ------------------------------------------------------------
    initial clk = 1'b0;
    always #5 clk = ~clk;


    // ------------------------------------------------------------
    // Independent model of the latched bounds.
    //
    // Written from the SPEC ("load on done, hold otherwise, clear on
    // asynchronous reset") rather than from the DUT's internal signals,
    // so a broken latch shows up as a box_en mismatch.
    // ------------------------------------------------------------
    logic [8:0] mdl_max_x, mdl_min_x;
    logic [7:0] mdl_max_y, mdl_min_y;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            mdl_max_x <= 9'd0;
            mdl_min_x <= 9'd0;
            mdl_max_y <= 8'd0;
            mdl_min_y <= 8'd0;
        end else if (done) begin
            mdl_max_x <= max_x;
            mdl_min_x <= min_x;
            mdl_max_y <= max_y;
            mdl_min_y <= min_y;
        end
    end

    // Expected box_en for a screen coordinate at a given border thickness.
    // The intermediate sums are declared at the RTL's own widths (9-bit for
    // x, 8-bit for y) so the model wraps exactly where the RTL wraps.
    function automatic logic ref_box_en(input logic [9:0] xp, input logic [9:0] yp,
                                        input logic [1:0] thick);
        logic [8:0] sx, x_lo, x_hi;
        logic [7:0] sy, y_lo, y_hi;
        logic       x_in, y_in, x_edge, y_edge;
        begin
            sx     = xp[9:1];
            sy     = yp[8:1];

            x_in   = (sx >= mdl_min_x) && (sx < mdl_max_x);
            y_in   = (sy >= mdl_min_y) && (sy < mdl_max_y);

            x_lo   = mdl_min_x + thick;
            x_hi   = sx + thick;
            y_lo   = mdl_min_y + thick;
            y_hi   = sy + thick;

            x_edge = (sx < x_lo) || (x_hi >= mdl_max_x);
            y_edge = (sy < y_lo) || (y_hi >= mdl_max_y);

            return target_valid && x_in && y_in && (x_edge || y_edge);
        end
    endfunction


    // ------------------------------------------------------------
    // Reporting helpers
    // ------------------------------------------------------------
    task automatic record(input logic ok, input string msg);
        begin
            test_count = test_count + 1;
            if (ok) begin
                pass_count = pass_count + 1;
                $display("[PASS] %s", msg);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] %s", msg);
            end
        end
    endtask


    // ------------------------------------------------------------
    // Drive one screen coordinate and hold it for two clocks.
    //
    // box_en is combinational on the CURRENT vga_x/vga_y, while the
    // reader's pixel_valid_d / fb_rdata path is one clock behind. Holding
    // the coordinate for two clocks lines both up on the same pixel, so
    // the color check below is meaningful.
    // ------------------------------------------------------------
    task automatic drive_pixel(input logic [9:0] cur_x, input logic [9:0] cur_y);
        begin
            @(posedge clk);
            vga_x <= cur_x;
            vga_y <= cur_y;
            @(posedge clk);
            #1;
        end
    endtask


    // ------------------------------------------------------------
    // Check box_en (both thicknesses) and the resulting VGA color for
    // one screen coordinate. `expect_box` is the hand-computed answer;
    // it is cross-checked against the model so a wrong expectation in
    // the test list is reported separately from an RTL bug.
    // ------------------------------------------------------------
    task automatic check_pixel(input string name, input logic [9:0] cur_x,
                               input logic [9:0] cur_y, input logic expect_box);
        logic model_box, model_box_t1;
        begin
            drive_pixel(cur_x, cur_y);

            model_box    = ref_box_en(cur_x, cur_y, THICKNESS);
            model_box_t1 = ref_box_en(cur_x, cur_y, THICKNESS_T1);

            if (model_box !== expect_box) begin
                record(1'b0, $sformatf(
                       "%-9s (x=%0d,y=%0d) TEST SETUP: model=%0b but test expects %0b",
                       name, cur_x, cur_y, model_box, expect_box));
            end else if (box_en !== model_box) begin
                record(1'b0, $sformatf(
                       "%-9s (x=%0d,y=%0d) box_en expected=%0b actual=%0b",
                       name, cur_x, cur_y, model_box, box_en));
            end else if (box_en_t1 !== model_box_t1) begin
                record(1'b0, $sformatf(
                       "%-9s (x=%0d,y=%0d) THICKNESS=1 box_en expected=%0b actual=%0b",
                       name, cur_x, cur_y, model_box_t1, box_en_t1));
            end else if (!pixel_valid) begin
                record(1'b0, $sformatf("%-9s (x=%0d,y=%0d) pixel_valid unexpectedly low",
                                       name, cur_x, cur_y));
            end else if (box_en) begin
                record(((vga_r == 4'hF) && (vga_g == 4'h0) && (vga_b == 4'h0)),
                       $sformatf("%-9s (x=%0d,y=%0d) red overlay (r=%h g=%h b=%h)",
                                 name, cur_x, cur_y, vga_r, vga_g, vga_b));
            end else begin
                record(((vga_r == PASS_R) && (vga_g == PASS_G) && (vga_b == PASS_B)),
                       $sformatf("%-9s (x=%0d,y=%0d) pass-through (r=%h g=%h b=%h)",
                                 name, cur_x, cur_y, vga_r, vga_g, vga_b));
            end
        end
    endtask


    // Same as check_pixel but addressed in SOURCE (320x240) coordinates:
    // checks the whole 2x2 screen block the source pixel expands into.
    task automatic check_src_block(input string name, input int sx, input int sy,
                                   input logic expect_box);
        begin
            check_pixel({name, "-TL"}, 10'(2 * sx), 10'(2 * sy), expect_box);
            check_pixel({name, "-TR"}, 10'(2 * sx + 1), 10'(2 * sy), expect_box);
            check_pixel({name, "-BL"}, 10'(2 * sx), 10'(2 * sy + 1), expect_box);
            check_pixel({name, "-BR"}, 10'(2 * sx + 1), 10'(2 * sy + 1), expect_box);
        end
    endtask


    // ------------------------------------------------------------
    // Load a new bounding box with a one-clock `done` pulse.
    // ------------------------------------------------------------
    task automatic load_box(input logic [8:0] new_min_x, input logic [8:0] new_max_x,
                            input logic [7:0] new_min_y, input logic [7:0] new_max_y);
        begin
            @(posedge clk);
            min_x <= new_min_x;
            max_x <= new_max_x;
            min_y <= new_min_y;
            max_y <= new_max_y;
            done  <= 1'b1;
            @(posedge clk);
            done <= 1'b0;
            @(posedge clk);
            #1;
        end
    endtask


    // ------------------------------------------------------------
    // Sweep the whole 640x480 VISIBLE SCREEN, one screen pixel per clock,
    // exactly like the real VGA raster does (vga_x/vga_y each advance by
    // 1 every pixel clock). Comparing both DUTs against the model and
    // counting the lit pixels so the border area can be checked
    // analytically.
    // ------------------------------------------------------------
    task automatic sweep_frame(input string name, input int exp_lit, input int exp_lit_t1);
        int   lit, lit_t1, mism, mism_t1;
        int   vx, vy;
        logic model_box, model_box_t1;
        begin
            lit     = 0;
            lit_t1  = 0;
            mism    = 0;
            mism_t1 = 0;

            for (vy = 0; vy < V_VISIBLE; vy++) begin
                for (vx = 0; vx < H_VISIBLE; vx++) begin
                    @(posedge clk);
                    vga_x <= 10'(vx);
                    vga_y <= 10'(vy);
                    #1;

                    model_box    = ref_box_en(10'(vx), 10'(vy), THICKNESS);
                    model_box_t1 = ref_box_en(10'(vx), 10'(vy), THICKNESS_T1);

                    if (box_en) lit = lit + 1;
                    if (box_en_t1) lit_t1 = lit_t1 + 1;

                    if (box_en !== model_box) begin
                        if (mism < 10)
                            $display("        mismatch  T=%0d screen(%0d,%0d) exp=%0b act=%0b",
                                     THICKNESS, vx, vy, model_box, box_en);
                        mism = mism + 1;
                    end
                    if (box_en_t1 !== model_box_t1) begin
                        if (mism_t1 < 10)
                            $display("        mismatch  T=%0d screen(%0d,%0d) exp=%0b act=%0b",
                                     THICKNESS_T1, vx, vy, model_box_t1, box_en_t1);
                        mism_t1 = mism_t1 + 1;
                    end
                end
            end

            record((mism == 0), $sformatf("%s: THICKNESS=%0d per-pixel match (%0d mismatches)",
                                          name, THICKNESS, mism));
            record((mism_t1 == 0), $sformatf("%s: THICKNESS=%0d per-pixel match (%0d mismatches)",
                                             name, THICKNESS_T1, mism_t1));
            record((lit == exp_lit), $sformatf("%s: THICKNESS=%0d lit pixels %0d (expected %0d)",
                                               name, THICKNESS, lit, exp_lit));
            record((lit_t1 == exp_lit_t1),
                   $sformatf("%s: THICKNESS=%0d lit pixels %0d (expected %0d)", name,
                             THICKNESS_T1, lit_t1, exp_lit_t1));
        end
    endtask


    // Border area of a WxH box with a T-wide border = W*H - (W-2T)*(H-2T).
    function automatic int border_area(input int w, input int h, input int t);
        int inner_w, inner_h;
        begin
            inner_w = (w > 2 * t) ? (w - 2 * t) : 0;
            inner_h = (h > 2 * t) ? (h - 2 * t) : 0;
            return (w * h) - (inner_w * inner_h);
        end
    endfunction


    // ------------------------------------------------------------
    // box_en must never rise while target_valid is low.
    // Sampled off the clock edge so combinational settling is done.
    // ------------------------------------------------------------
    always @(posedge clk) begin
        #2;
        if (!target_valid && box_en) begin
            fail_count = fail_count + 1;
            $display("[FAIL] MONITOR   box_en high while target_valid low @%0t", $time);
        end
    end


    // ------------------------------------------------------------
    // Main test sequence
    // ------------------------------------------------------------
    initial begin

        rst          = 1'b1;
        vga_sw       = 2'b01;  // MODE_FULLSCREEN
        vga_x        = 10'd0;
        vga_y        = 10'd0;
        video_on     = 1'b0;
        target_valid = 1'b0;
        done         = 1'b0;
        max_x        = 9'd0;
        min_x        = 9'd0;
        max_y        = 8'd0;
        min_y        = 8'd0;
        fb_rdata     = FB_STUB_RGB565;

        test_count   = 0;
        pass_count   = 0;
        fail_count   = 0;

        repeat (4) @(posedge clk);
        #1 rst = 1'b0;

        // Let the vga_sw synchronizer settle into MODE_FULLSCREEN.
        repeat (4) @(posedge clk);
        video_on     = 1'b1;
        target_valid = 1'b1;

        $display("");
        $display("==================================================");
        $display(" DRAW_BOX + VGA_FRAME_READER_V4 TEST");
        $display("   THICKNESS = %0d (wired to the reader) / %0d (reference)",
                 THICKNESS, THICKNESS_T1);
        $display("==================================================");


        // ------------------------------------------------------
        // PHASE 0 - after reset the latched bounds are 0
        // ------------------------------------------------------
        $display("\n--- PHASE 0: bounds cleared by reset ---");
        check_src_block("P0-ORIG", 0, 0, 1'b0);
        check_src_block("P0-MID", 160, 120, 1'b0);
        check_src_block("P0-BOX", int'(BOX0_MIN_X), int'(BOX0_MIN_Y), 1'b0);


        // ------------------------------------------------------
        // PHASE 1 - bounds on the inputs, but no `done` pulse
        // ------------------------------------------------------
        $display("\n--- PHASE 1: bounds driven with done=0 (latch must not be transparent) ---");
        @(posedge clk);
        min_x <= BOX0_MIN_X;
        max_x <= BOX0_MAX_X;
        min_y <= BOX0_MIN_Y;
        max_y <= BOX0_MAX_Y;
        repeat (3) @(posedge clk);

        check_src_block("P1-CORNER", int'(BOX0_MIN_X), int'(BOX0_MIN_Y), 1'b0);
        check_src_block("P1-EDGE", int'(BOX0_MAX_X) - 1, 80, 1'b0);


        // ------------------------------------------------------
        // PHASE 2 - load the box and check its shape
        //
        // Box0 = x[100,140) y[60,100), THICKNESS=2, so the lit source
        // columns are 100..101 / 138..139 and the lit rows 60..61 / 98..99.
        // ------------------------------------------------------
        $display("\n--- PHASE 2: done pulse loads the box, border is drawn ---");
        load_box(BOX0_MIN_X, BOX0_MAX_X, BOX0_MIN_Y, BOX0_MAX_Y);

        // Corners and the 2-pixel border ring.
        check_src_block("P2-TL0", 100, 60, 1'b1);
        check_src_block("P2-TL1", 101, 61, 1'b1);
        check_src_block("P2-TR", 139, 60, 1'b1);
        check_src_block("P2-BL", 100, 99, 1'b1);
        check_src_block("P2-BR", 139, 99, 1'b1);

        // Mid-edge pixels, inner-most lit column/row.
        check_pixel("P2-LEFT", 10'd202, 10'd160, 1'b1);  // src(101,80)
        check_pixel("P2-RIGHT", 10'd276, 10'd160, 1'b1);  // src(138,80)
        check_pixel("P2-TOP", 10'd240, 10'd122, 1'b1);  // src(120,61)
        check_pixel("P2-BOT", 10'd240, 10'd196, 1'b1);  // src(120,98)

        // First non-border pixel just inside each edge.
        check_pixel("P2-IN-L", 10'd204, 10'd160, 1'b0);  // src(102,80)
        check_pixel("P2-IN-R", 10'd274, 10'd160, 1'b0);  // src(137,80)
        check_pixel("P2-IN-T", 10'd240, 10'd124, 1'b0);  // src(120,62)
        check_pixel("P2-IN-B", 10'd240, 10'd194, 1'b0);  // src(120,97)
        check_src_block("P2-CENTER", 120, 80, 1'b0);

        // First pixel just OUTSIDE each edge.
        check_pixel("P2-OUT-L", 10'd198, 10'd160, 1'b0);  // src(99,80)
        check_pixel("P2-OUT-R", 10'd280, 10'd160, 1'b0);  // src(140,80)
        check_pixel("P2-OUT-T", 10'd240, 10'd118, 1'b0);  // src(120,59)
        check_pixel("P2-OUT-B", 10'd240, 10'd200, 1'b0);  // src(120,100)

        // Far screen corners: plain pass-through video.
        check_pixel("P2-SCR0", 10'd0, 10'd0, 1'b0);
        check_pixel("P2-SCR1", 10'd639, 10'd479, 1'b0);


        // ------------------------------------------------------
        // PHASE 3 - target_valid gating
        // ------------------------------------------------------
        $display("\n--- PHASE 3: target_valid gates the whole overlay ---");
        @(posedge clk);
        target_valid <= 1'b0;
        repeat (2) @(posedge clk);

        check_src_block("P3-OFF-TL", 100, 60, 1'b0);
        check_pixel("P3-OFF-L", 10'd202, 10'd160, 1'b0);

        @(posedge clk);
        target_valid <= 1'b1;
        repeat (2) @(posedge clk);

        check_src_block("P3-ON-TL", 100, 60, 1'b1);
        check_pixel("P3-ON-L", 10'd202, 10'd160, 1'b1);


        // ------------------------------------------------------
        // PHASE 4 - full-frame sweep of box0
        // ------------------------------------------------------
        $display("\n--- PHASE 4: full 640x480 screen sweep (box0 40x40 source px) ---");
        // Each source-pixel border cell covers a 2x2 screen block in
        // MODE_FULLSCREEN, so the screen-pixel lit count is 4x the
        // source-pixel border area.
        sweep_frame("P4-BOX0", 4 * border_area(40, 40, int'(THICKNESS)),
                    4 * border_area(40, 40, int'(THICKNESS_T1)));


        // ------------------------------------------------------
        // PHASE 5 - the box moves
        // ------------------------------------------------------
        $display("\n--- PHASE 5: box moves to a new position/size ---");
        load_box(BOX1_MIN_X, BOX1_MAX_X, BOX1_MIN_Y, BOX1_MAX_Y);

        // The old box must be gone...
        check_src_block("P5-OLD-TL", 100, 60, 1'b0);
        check_pixel("P5-OLD-L", 10'd202, 10'd160, 1'b0);

        // ...and the new one drawn: x[200,224) y[150,180), border 2.
        check_src_block("P5-NEW-TL", 200, 150, 1'b1);
        check_src_block("P5-NEW-BR", 223, 179, 1'b1);
        check_pixel("P5-NEW-R", 10'd444, 10'd330, 1'b1);  // src(222,165)
        check_pixel("P5-NEW-IN", 10'd440, 10'd330, 1'b0);  // src(220,165)
        check_src_block("P5-NEW-CTR", 212, 165, 1'b0);

        $display("\n--- PHASE 5b: full screen sweep of the moved box (24x30 source px) ---");
        sweep_frame("P5-BOX1", 4 * border_area(24, 30, int'(THICKNESS)),
                    4 * border_area(24, 30, int'(THICKNESS_T1)));


        // ------------------------------------------------------
        // PHASE 6 - asynchronous reset clears the latched bounds
        // ------------------------------------------------------
        $display("\n--- PHASE 6: asynchronous reset clears the latched box ---");

        // Park the raster on a lit border pixel first, so the reset has
        // something visible to clear.
        drive_pixel(10'(2 * 200), 10'(2 * 150));
        record((box_en === 1'b1), $sformatf("P6-PRE    box_en high before reset (box_en=%0b)",
                                            box_en));

        #2 rst = 1'b1;  // off a clock edge: exercise the async path
        #1
        record((box_en === 1'b0),
               $sformatf("P6-ASYNC  box_en cleared 1ns after rst rise, no clock edge (box_en=%0b)",
                         box_en));
        repeat (2) @(posedge clk);
        #1 rst = 1'b0;
        repeat (4) @(posedge clk);

        check_src_block("P6-TL", 200, 150, 1'b0);
        check_src_block("P6-BR", 223, 179, 1'b0);

        // ...and a fresh `done` re-loads it after reset.
        load_box(BOX0_MIN_X, BOX0_MAX_X, BOX0_MIN_Y, BOX0_MAX_Y);
        check_src_block("P6-RELOAD", 100, 60, 1'b1);

        video_on = 1'b0;


        // ------------------------------------------------------
        // Summary
        // ------------------------------------------------------
        $display("");
        $display("==================================================");
        $display(" TEST SUMMARY: total=%0d pass=%0d fail=%0d", test_count, pass_count,
                 fail_count);
        $display("==================================================");

        if (fail_count == 0) begin
            $display("*** ALL TESTS PASSED ***");
        end else begin
            $fatal(1, "draw_box + vga_frame_reader_v4 integration test failed.");
        end

        $finish;
    end

endmodule
