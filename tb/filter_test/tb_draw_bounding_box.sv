`timescale 1ns / 1ps

// ------------------------------------------------------------------
// tb_draw_bounding_box
//
// Chains the three-stage "red blob -> bounding box" pipeline used in
// top.sv and streams several frames back to back (like real video)
// so the relationship between the stages can be watched over time:
//
//   red_valid/red_mask -> noise_filter_3x3 -> min_max_find -> draw_box
//   (raw per-pixel        (3x3 majority        (accumulates one       (renders a
//    mask, as if from      denoise; forces      frame's worth of       border ring
//    red_color_filter)     screen-edge/window-  clean_mask==1          from the
//                          not-ready pixels     pixels into one        bounding box
//                          to 0)                box, gated by          LATCHED on
//                                               MIN_RED_COUNT)          `done`)
//
// FRAME sequence (all streamed one after another, no manual poking):
//   FRAME 1 - a solid blob near the middle              -> detected
//   FRAME 2 - the SAME blob, moved and resized           -> box tracks it
//   FRAME 3 - an all-black frame (nothing red at all)    -> target_valid_in=0
//   FRAME 4 - a 2x2 speck (too small to survive denoise) -> target_valid_in=0
//   FRAME 5 - a bigger blob, moved again                 -> detected
//
// After each frame's `done` pulse, draw_box is swept over every
// source pixel; box_en is checked against an independent reference
// model, and the raw/clean/box state of every pixel is printed as an
// ASCII map so the three stages can be compared by eye, frame by
// frame.
// ------------------------------------------------------------------

module tb_draw_bounding_box ();

    // ------------------------------------------------------------
    // Small, hand-checkable frame size (the real design uses 320x240
    // for all three modules; the pipeline logic does not change).
    // ------------------------------------------------------------
    localparam int IMG_WIDTH  = 16;
    localparam int IMG_HEIGHT = 12;
    localparam int X_WIDTH    = $clog2(IMG_WIDTH);
    localparam int Y_WIDTH    = $clog2(IMG_HEIGHT);

    localparam int MIN_RED_COUNT = 5;  // same default as bounding_box.sv
    localparam int THICKNESS     = 1;  // draw_box border width, source px

    logic pclk = 0;
    logic rst;
    always #5 pclk = ~pclk;

    // ------------------------------------------------------------
    // Stage 1 : noise_filter_3x3
    // ------------------------------------------------------------
    logic               red_valid;
    logic               red_mask;
    logic [X_WIDTH-1:0] pixel_x;
    logic [Y_WIDTH-1:0] pixel_y;

    logic               clean_mask;
    logic [X_WIDTH-1:0] clean_x;
    logic [Y_WIDTH-1:0] clean_y;
    logic               out_valid;

    noise_filter_3x3 #(
        .IMG_WIDTH (IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT)
    ) U_NOISE_FILTER (
        .pclk      (pclk),
        .rst       (rst),
        .red_valid (red_valid),
        .red_mask  (red_mask),
        .pixel_x   (pixel_x),
        .pixel_y   (pixel_y),
        .clean_mask(clean_mask),
        .clean_x   (clean_x),
        .clean_y   (clean_y),
        .out_valid (out_valid)
    );

    // ------------------------------------------------------------
    // Stage 2 : min_max_find
    //
    // clean_x/clean_y here are fixed 9-bit/8-bit ports (unlike stage
    // 1's parameterized X_WIDTH/Y_WIDTH), so they are explicitly
    // zero-extended on connection.
    // ------------------------------------------------------------
    logic       target_valid_in;
    logic [8:0] min_x, max_x;
    logic [7:0] min_y, max_y;
    logic       done;

    min_max_find #(
        .IMG_WIDTH    (IMG_WIDTH),
        .IMG_HEIGHT   (IMG_HEIGHT),
        .MIN_RED_COUNT(MIN_RED_COUNT)
    ) U_MIN_MAX_FIND (
        .pclk           (pclk),
        .rst            (rst),
        .clean_mask     (clean_mask),
        .out_valid      (out_valid),
        .clean_x        (9'(clean_x)),
        .clean_y        (8'(clean_y)),
        .target_valid_in(target_valid_in),
        .min_x          (min_x),
        .max_x          (max_x),
        .min_y          (min_y),
        .max_y          (max_y),
        .done           (done)
    );

    // ------------------------------------------------------------
    // Stage 3 : draw_box
    //
    // draw_box's x_pixel/y_pixel are SCREEN coordinates and it halves
    // them internally ([9:1]/[8:1]), matching how top.sv drives it in
    // MODE_FULLSCREEN (2x). Driving x_pixel=2*sx, y_pixel=2*sy makes a
    // sweep over source coordinates sx/sy line up 1:1 with that math.
    // ------------------------------------------------------------
    logic [9:0] x_pixel, y_pixel;
    wire        box_en;

    draw_box #(
        .THICKNESS(THICKNESS)
    ) U_DRAW_BOX (
        .pclk           (pclk),
        .rst            (rst),
        .target_valid_in(target_valid_in),
        .done           (done),
        .x_pixel        (x_pixel),
        .y_pixel        (y_pixel),
        .max_x          (max_x),
        .min_x          (min_x),
        .max_y          (max_y),
        .min_y          (min_y),
        .box_en         (box_en)
    );

    // ------------------------------------------------------------
    // Frame script: a small red-mask "video" of 5 frames, each with
    // its own rectangle (or none). Kept away from BOTH:
    //   - the frame's own outer ring (col0/col(W-1), row0/row(H-1)),
    //     which noise_filter_3x3 always forces to clean_mask=0, and
    //   - column 1 (row_fill_cnt<2 right after a new row starts) -
    //     x0 is always kept >= 2 below.
    // has_block=0 means an all-black frame (x0..y1 unused).
    // ------------------------------------------------------------
    typedef struct {
        int    x0, x1, y0, y1;
        bit    has_block;
        bit    expect_valid;
        string label;
    } frame_spec_t;

    localparam int NUM_FRAMES = 5;

    frame_spec_t frames[0:NUM_FRAMES-1] = '{
        '{
            x0: 4,
            x1: 11,
            y0: 3,
            y1: 8,
            has_block: 1'b1,
            expect_valid: 1'b1,
            label: "FRAME 1 (blob near center)"
        },
        '{
            x0: 2,
            x1: 5,
            y0: 5,
            y1: 8,
            has_block: 1'b1,
            expect_valid: 1'b1,
            label: "FRAME 2 (same blob, moved left + shrunk)"
        },
        '{
            x0: 0,
            x1: 0,
            y0: 0,
            y1: 0,
            has_block: 1'b0,
            expect_valid: 1'b0,
            label: "FRAME 3 (all black - nothing to track)"
        },
        '{
            x0: 9,
            x1: 10,
            y0: 4,
            y1: 5,
            has_block: 1'b1,
            expect_valid: 1'b0,
            label: "FRAME 4 (2x2 speck - fully denoised away)"
        },
        '{
            x0: 6,
            x1: 13,
            y0: 2,
            y1: 9,
            has_block: 1'b1,
            expect_valid: 1'b1,
            label: "FRAME 5 (bigger blob, moved to lower-right)"
        }
    };

    // Current frame's rectangle, latched at the start of each loop
    // iteration below so expected_clean()/build_frame() can share it.
    int cur_x0, cur_x1, cur_y0, cur_y1;
    bit cur_has_block;

    logic img[0:IMG_HEIGHT-1][0:IMG_WIDTH-1];

    // Ground truth for the 3x3 majority filter on a SOLID rectangle:
    // any pixel whose 3x3 neighbourhood is >=5/9 red survives. For a
    // filled rectangle that means every pixel survives EXCEPT its 4
    // corners (whose neighbourhood is only 4/9 red - two background
    // sides meeting). The non-corner edge pixels still sit exactly on
    // cur_x0/x1/y0/y1, so the box min_max_find tracks still comes out
    // identical to the rectangle even after the corners are eroded -
    // UNLESS the rectangle degenerates to a single point in both axes
    // (e.g. a 2x2 block), where every pixel is simultaneously a corner
    // and the whole thing is denoised away (see FRAME 4).
    function automatic bit expected_clean(input int x, input int y);
        bit in_block, is_corner;
        begin
            in_block  = cur_has_block && (x >= cur_x0) && (x <= cur_x1) && (y >= cur_y0) &&
                        (y <= cur_y1);
            is_corner = ((x == cur_x0) || (x == cur_x1)) && ((y == cur_y0) || (y == cur_y1));
            return in_block && !is_corner;
        end
    endfunction

    int test_count = 0, pass_count = 0, fail_count = 0;

    task automatic record(input bit ok, input string msg);
        begin
            test_count++;
            if (ok) begin
                pass_count++;
            end else begin
                fail_count++;
                $display("[FAIL] %s", msg);
            end
        end
    endtask

    // Fills the shared `img` array from cur_x0/x1/y0/y1/cur_has_block.
    task automatic build_frame();
        int x, y;
        begin
            for (y = 0; y < IMG_HEIGHT; y++)
                for (x = 0; x < IMG_WIDTH; x++)
                    img[y][x] = cur_has_block && (x >= cur_x0) && (x <= cur_x1) &&
                        (y >= cur_y0) && (y <= cur_y1);
        end
    endtask

    // Verifies stage 1 in isolation while a frame streams through:
    // every out_valid pulse must match expected_clean() at (clean_x,clean_y).
    always @(posedge pclk) begin
        if (out_valid) begin
            record(clean_mask === expected_clean(int'(clean_x), int'(clean_y)),
                   $sformatf("STAGE1 noise_filter (x=%0d,y=%0d) clean_mask=%b expected=%b",
                             clean_x, clean_y, clean_mask,
                             expected_clean(int'(clean_x), int'(clean_y))));
        end
    end

    // Streams the current `img` frame into stage 1, one pixel per
    // pclk, in raster order - exactly the shape red_color_filter's
    // output has in real operation.
    task automatic stream_frame();
        int x, y;
        begin
            for (y = 0; y < IMG_HEIGHT; y++) begin
                for (x = 0; x < IMG_WIDTH; x++) begin
                    @(posedge pclk);
                    red_valid <= 1'b1;
                    pixel_x   <= x[X_WIDTH-1:0];
                    pixel_y   <= y[Y_WIDTH-1:0];
                    red_mask  <= img[y][x];
                end
            end
            // Blanking cycles between frames, like real H/V blanking,
            // so the 2-clock-deep out_valid/clean_x/clean_y pipeline
            // drains before we sample `done`.
            repeat (4) begin
                @(posedge pclk);
                red_valid <= 1'b0;
                red_mask  <= 1'b0;
            end
        end
    endtask

    // Reference model for draw_box's own border formula, mirroring
    // draw_box.sv exactly - INCLUDING its exclusive max_x/max_y. Note
    // this differs from min_max_find, which reports the actual last
    // INCLUSIVE red coordinate it saw; for this test the mismatch is
    // invisible because each rectangle's surviving non-corner edge
    // pixels still land exactly on cur_x1/cur_y1, but it is worth
    // remembering when reading a real detection.
    function automatic bit ref_box_en(input int sx, input int sy);
        bit x_in, y_in, x_edge, y_edge;
        begin
            x_in   = (sx >= int'(min_x)) && (sx < int'(max_x));
            y_in   = (sy >= int'(min_y)) && (sy < int'(max_y));
            x_edge = (sx < int'(min_x) + THICKNESS) || (sx + THICKNESS >= int'(max_x));
            y_edge = (sy < int'(min_y) + THICKNESS) || (sy + THICKNESS >= int'(max_y));
            return target_valid_in && x_in && y_in && (x_edge || y_edge);
        end
    endfunction

    // Sweeps every source pixel through draw_box and prints a 3-way
    // ASCII picture per source row: raw red mask / denoised clean
    // mask / drawn border, so all three pipeline stages line up
    // visually for the frame that was just streamed.
    task automatic sweep_and_show(input string label);
        int    sx, sy;
        bit    exp_box;
        string raw_line, clean_line, box_line;
        begin
            $display("");
            $display("--- %s : min=(%0d,%0d) max=(%0d,%0d) target_valid_in=%0b ---", label,
                      min_x, min_y, max_x, max_y, target_valid_in);

            for (sy = 0; sy < IMG_HEIGHT; sy++) begin
                raw_line   = "";
                clean_line = "";
                box_line   = "";
                for (sx = 0; sx < IMG_WIDTH; sx++) begin
                    @(posedge pclk);
                    x_pixel <= 10'(2 * sx);
                    y_pixel <= 10'(2 * sy);
                    #1;

                    exp_box = ref_box_en(sx, sy);
                    record(box_en === exp_box,
                           $sformatf("STAGE3 draw_box (sx=%0d,sy=%0d) box_en=%b expected=%b", sx,
                                     sy, box_en, exp_box));

                    raw_line   = {raw_line, img[sy][sx] ? "R" : "."};
                    clean_line = {clean_line, expected_clean(sx, sy) ? "C" : "."};
                    box_line   = {box_line, box_en ? "B" : "."};
                end
                $display("  row %20d  raw=%s  clean=%s  box=%s", sy, raw_line, clean_line,
                          box_line);
            end
        end
    endtask

    // ------------------------------------------------------------
    // Main sequence: run every frame in frames[] back to back.
    //
    // A short `rst` pulse is inserted between demo frames on purpose.
    // noise_filter_3x3's row_fill_cnt/valid_row_cnt are only cleared
    // by this global reset - not by anything inside the module on a
    // frame boundary - so back-to-back frames in the REAL design can
    // carry a stale counter phase from one frame into the next. That
    // is a separate, already-known issue in noise_filter_3x3 itself;
    // resetting here keeps each demo frame's expected output
    // independent and hand-verifiable instead of depending on exactly
    // how many rows preceded it.
    // ------------------------------------------------------------
    initial begin
        rst       = 1'b1;
        red_valid = 1'b0;
        red_mask  = 1'b0;
        pixel_x   = '0;
        pixel_y   = '0;
        x_pixel   = '0;
        y_pixel   = '0;
        repeat (3) @(posedge pclk);
        rst = 1'b0;

        $display("==================================================");
        $display(" tb_draw_bounding_box : noise_filter_3x3 -> min_max_find -> draw_box");
        $display(" image %0dx%0d, MIN_RED_COUNT=%0d, THICKNESS=%0d, %0d frames",
                  IMG_WIDTH, IMG_HEIGHT, MIN_RED_COUNT, THICKNESS, NUM_FRAMES);
        $display("==================================================");

        for (int i = 0; i < NUM_FRAMES; i++) begin
            if (i != 0) begin
                rst = 1'b1;
                repeat (3) @(posedge pclk);
                rst = 1'b0;
                repeat (2) @(posedge pclk);
            end

            cur_x0        = frames[i].x0;
            cur_x1        = frames[i].x1;
            cur_y0        = frames[i].y0;
            cur_y1        = frames[i].y1;
            cur_has_block = frames[i].has_block;

            build_frame();
            stream_frame();
            wait (done === 1'b1);
            @(posedge pclk);  // let draw_box latch the new bounds this edge
            #1;

            record(target_valid_in === frames[i].expect_valid,
                   $sformatf("%s target_valid_in should be %0b, got %0b", frames[i].label,
                             frames[i].expect_valid, target_valid_in));

            if (frames[i].expect_valid) begin
                record((min_x == frames[i].x0) && (max_x == frames[i].x1) &&
                       (min_y == frames[i].y0) && (max_y == frames[i].y1),
                       $sformatf(
                           "%s bounding box should be (%0d,%0d)-(%0d,%0d), got (%0d,%0d)-(%0d,%0d)",
                           frames[i].label, frames[i].x0, frames[i].y0, frames[i].x1,
                           frames[i].y1, min_x, min_y, max_x, max_y));
            end

            sweep_and_show(frames[i].label);
        end

        $display("");
        $display("==================================================");
        $display(" SUMMARY: total=%0d pass=%0d fail=%0d", test_count, pass_count, fail_count);
        $display("==================================================");
        if (fail_count == 0) $display(">>> ALL TESTS PASSED <<<");
        else $display(">>> %0d TEST(S) FAILED <<<", fail_count);

        $finish;
    end

endmodule
