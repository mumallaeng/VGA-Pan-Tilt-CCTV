`timescale 1ns / 1ps

// ------------------------------------------------------------------
// Integration test: draw_box + vga_frame_reader_v4
//
// draw_box is not instantiated anywhere in rtl/ yet. vga_frame_reader_v4
// is the only module wired to accept its box_en output (box_en forces
// vga_r/g/b to pure red). This testbench connects the two the way
// vga_frame_reader_v4's port comments imply:
//   draw_box.x_pixel/y_pixel <- same vga_x/vga_y fed to the reader
//   draw_box.box_en          -> vga_frame_reader_v4.box_en
//
// vga_sw is held at MODE_FULLSCREEN (2'b01): it's the only mode where
// the reader's img_x/img_y use the same x[9:1]/y[9:1] halving that
// draw_box itself uses.
//
// frame_buffer is NOT instantiated: fb_rdata is stubbed with a fixed
// non-red RGB565 color so the box overlay is trivially distinguishable
// from pass-through video.
//
// Instead of scanning all 640x480 pixels, only the coordinates that
// matter are checked: the 2x2 block where the box should light up,
// its four immediate neighbors (should NOT light up), and two far
// corners (pass-through sanity check).
// ------------------------------------------------------------------

module tb_draw_box();

    localparam ADDR_WIDTH = 17;

    // Pure green RGB565 stub pixel: RGB565=0x07E0 -> RGB444 pass-through
    // vga_r=0x0, vga_g=0xF, vga_b=0x0 (clearly not the box's red 0xF,0x0,0x0).
    localparam logic [15:0] FB_STUB_RGB565 = 16'h07E0;
    localparam logic [ 3:0] PASS_R = 4'h0;
    localparam logic [ 3:0] PASS_G = 4'hF;
    localparam logic [ 3:0] PASS_B = 4'h0;

    localparam logic [8:0]  DRAW_X = 9'd150;
    localparam logic [7:0]  DRAW_Y = 8'd100;

    // ------------------------------------------------------------
    // Shared / DUT signals
    // ------------------------------------------------------------
    logic                   clk;
    logic                   rst;
    logic [           1:0]  vga_sw;
    logic [           9:0]  vga_x;
    logic [           9:0]  vga_y;
    logic                   video_on;

    logic [           8:0]  draw_x;
    logic [           7:0]  draw_y;
    wire                    box_en;

    wire  [ADDR_WIDTH-1:0]  fb_raddr;
    logic [          15:0]  fb_rdata;

    wire  [           3:0]  vga_r;
    wire  [           3:0]  vga_g;
    wire  [           3:0]  vga_b;
    wire  [          15:0]  pixel_rgb565;
    wire                    pixel_valid;
    wire                    split_mode_aligned;
    wire                    quadrant_4_aligned;

    integer                 test_count;
    integer                 pass_count;
    integer                 fail_count;


    // ------------------------------------------------------------
    // DUTs
    // ------------------------------------------------------------
    draw_box u_draw_box (
        .x_pixel(vga_x),
        .y_pixel(vga_y),
        .rd_data(fb_rdata),
        .draw_x (draw_x),
        .draw_y (draw_y),
        .box_en (box_en)
    );

    vga_frame_reader_v4 #(
        .IMG_WIDTH (320),
        .IMG_HEIGHT(240),
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
    // Drive one pixel coordinate for a clock, then check box_en and
    // the resulting VGA color once the pipeline has settled.
    //
    // expected_box mirrors draw_box's own equation independently, so
    // this also catches wiring mistakes (wrong port/width) between
    // the TB and draw_box, not just draw_box's internal logic.
    // ------------------------------------------------------------
    task automatic check_pixel(input string name, input logic [9:0] cur_x,
                                input logic [9:0] cur_y, input logic expect_box);

        logic expected_box;

        begin
            @(posedge clk);
            vga_x <= cur_x;
            vga_y <= cur_y;
            #1;

            test_count   = test_count + 1;
            expected_box = (cur_x[9:1] == draw_x) && (cur_y[9:1] == {1'b0, draw_y});

            if (expected_box !== expect_box) begin
                fail_count = fail_count + 1;
                $display("[FAIL] %-10s test setup mismatch: expected_box=%0b expect_box=%0b",
                          name, expected_box, expect_box);
            end else if (box_en != expected_box) begin
                fail_count = fail_count + 1;
                $display("[FAIL] %-10s (x=%0d,y=%0d) box_en expected=%0b actual=%0b",
                          name, cur_x, cur_y, expected_box, box_en);
            end else if (!pixel_valid) begin
                fail_count = fail_count + 1;
                $display("[FAIL] %-10s (x=%0d,y=%0d) pixel_valid unexpectedly low",
                          name, cur_x, cur_y);
            end else if (box_en) begin
                if ((vga_r == 4'hF) && (vga_g == 4'h0) && (vga_b == 4'h0)) begin
                    pass_count = pass_count + 1;
                    $display("[PASS] %-10s (x=%0d,y=%0d) red overlay", name, cur_x, cur_y);
                end else begin
                    fail_count = fail_count + 1;
                    $display("[FAIL] %-10s (x=%0d,y=%0d) overlay color r=%h g=%h b=%h",
                              name, cur_x, cur_y, vga_r, vga_g, vga_b);
                end
            end else begin
                if ((vga_r == PASS_R) && (vga_g == PASS_G) && (vga_b == PASS_B)) begin
                    pass_count = pass_count + 1;
                    $display("[PASS] %-10s (x=%0d,y=%0d) pass-through color", name, cur_x, cur_y);
                end else begin
                    fail_count = fail_count + 1;
                    $display("[FAIL] %-10s (x=%0d,y=%0d) pass-through color r=%h g=%h b=%h",
                              name, cur_x, cur_y, vga_r, vga_g, vga_b);
                end
            end
        end
    endtask


    // ------------------------------------------------------------
    // Main test sequence
    // ------------------------------------------------------------
    initial begin

        rst      = 1'b1;
        vga_sw   = 2'b01;  // MODE_FULLSCREEN
        vga_x    = 10'd0;
        vga_y    = 10'd0;
        video_on = 1'b0;
        draw_x   = DRAW_X;
        draw_y   = DRAW_Y;
        fb_rdata = FB_STUB_RGB565;

        test_count = 0;
        pass_count = 0;
        fail_count = 0;

        repeat (4) @(posedge clk);
        rst = 1'b0;

        // Let the vga_sw synchronizer settle into MODE_FULLSCREEN.
        repeat (4) @(posedge clk);
        video_on = 1'b1;

        $display("");
        $display("==================================================");
        $display(" DRAW_BOX + VGA_FRAME_READER_V4 TEST (draw_x=%0d draw_y=%0d)",
                  DRAW_X, DRAW_Y);
        $display("==================================================");
        $display("");

        // 2x2 block that MUST light up (MODE_FULLSCREEN doubles each
        // source pixel: vga_x/y = 2*draw_x/y and 2*draw_x/y + 1).
        check_pixel("HIT-TL", 10'(2 * DRAW_X),     10'(2 * DRAW_Y),     1'b1);
        check_pixel("HIT-TR", 10'(2 * DRAW_X + 1), 10'(2 * DRAW_Y),     1'b1);
        check_pixel("HIT-BL", 10'(2 * DRAW_X),     10'(2 * DRAW_Y + 1), 1'b1);
        check_pixel("HIT-BR", 10'(2 * DRAW_X + 1), 10'(2 * DRAW_Y + 1), 1'b1);

        // Immediate neighbors that must NOT light up.
        check_pixel("MISS-L", 10'(2 * DRAW_X - 1), 10'(2 * DRAW_Y),     1'b0);
        check_pixel("MISS-R", 10'(2 * DRAW_X + 2), 10'(2 * DRAW_Y),     1'b0);
        check_pixel("MISS-U", 10'(2 * DRAW_X),     10'(2 * DRAW_Y - 1), 1'b0);
        check_pixel("MISS-D", 10'(2 * DRAW_X),     10'(2 * DRAW_Y + 2), 1'b0);

        // Far corners: pass-through sanity check.
        check_pixel("CORNER0", 10'd0,   10'd0,   1'b0);
        check_pixel("CORNER1", 10'd639, 10'd479, 1'b0);

        video_on = 1'b0;

        $display("");
        $display("==================================================");
        $display(" TEST SUMMARY: total=%0d pass=%0d fail=%0d",
                  test_count, pass_count, fail_count);
        $display("==================================================");

        if (fail_count == 0) begin
            $display("*** ALL TESTS PASSED ***");
        end else begin
            $fatal(1, "draw_box + vga_frame_reader_v4 integration test failed.");
        end

        $finish;
    end

endmodule
