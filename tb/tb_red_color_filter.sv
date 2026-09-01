`timescale 1ns / 1ps

module tb_red_color_filter;

    // ------------------------------------------------------------
    // DUT inputs
    // ------------------------------------------------------------
    logic   [15:0] pixel_rgb565;
    logic          pixel_valid;

    // ------------------------------------------------------------
    // DUT outputs
    // ------------------------------------------------------------
    logic          red_mask;
    logic          red_valid;

    // ------------------------------------------------------------
    // Test counters
    // ------------------------------------------------------------
    integer        test_count;
    integer        pass_count;
    integer        fail_count;


    // ------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------
    red_color_filter #(
        .R_MIN  (8'b1001_1110),
        .RG_DIFF(8'd40),
        .RB_DIFF(8'd40)
    ) dut (
        .pixel_rgb565(pixel_rgb565),
        .pixel_valid (pixel_valid),

        .red_mask (red_mask),
        .red_valid(red_valid)
    );


    // ------------------------------------------------------------
    // RGB888 -> RGB565
    //
    // RGB888:
    // RRRRRRRR GGGGGGGG BBBBBBBB
    //
    // RGB565:
    // RRRRR GGGGGG BBBBB
    // ------------------------------------------------------------
    function automatic logic [15:0] rgb888_to_rgb565(
        input logic [7:0] r, input logic [7:0] g, input logic [7:0] b);
        begin
            rgb888_to_rgb565 = {r[7:3], g[7:2], b[7:3]};
        end
    endfunction


    // ------------------------------------------------------------
    // Color test task
    // ------------------------------------------------------------
    task automatic test_color(input string test_name, input logic [7:0] r,
                              input logic [7:0] g, input logic [7:0] b,
                              input logic expected_red);

        logic [15:0] test_pixel;

        begin
            test_count   = test_count + 1;

            test_pixel   = rgb888_to_rgb565(r, g, b);

            pixel_rgb565 = test_pixel;
            pixel_valid  = 1'b1;

            // DUT is combinational.
            #1;

            if ((red_mask == expected_red) && (red_valid == 1'b1)) begin

                pass_count = pass_count + 1;

                $display(
                    "[PASS] %-12s RGB888=(%3d,%3d,%3d) RGB565=0x%04h red_mask=%0b",
                    test_name, r, g, b, test_pixel, red_mask);

            end else begin

                fail_count = fail_count + 1;

                $display(
                    "[FAIL] %-12s RGB888=(%3d,%3d,%3d) RGB565=0x%04h expected=%0b actual=%0b valid=%0b",
                    test_name, r, g, b, test_pixel, expected_red, red_mask,
                    red_valid);
            end

            pixel_valid = 1'b0;

            #1;
        end
    endtask


    // ------------------------------------------------------------
    // Main test sequence
    // ------------------------------------------------------------
    initial begin

        // Initial values
        pixel_rgb565 = 16'h0000;
        pixel_valid  = 1'b0;

        test_count   = 0;
        pass_count   = 0;
        fail_count   = 0;

        #10;

        $display("");
        $display(
            "============================================================");
        $display("          RED COLOR FILTER TEST START");
        $display(
            "============================================================");
        $display("");


        // --------------------------------------------------------
        // 1. Pure Red
        // Expected: RED
        // --------------------------------------------------------
        test_color("PURE RED", 8'd255, 8'd0, 8'd0, 1'b1);


        // --------------------------------------------------------
        // 2. White
        //
        // R is high, but G and B are also high.
        // Expected: NOT RED
        // --------------------------------------------------------
        test_color("WHITE", 8'd255, 8'd255, 8'd255, 1'b0);


        // --------------------------------------------------------
        // 3. Black
        //
        // Red intensity is below R_MIN.
        // Expected: NOT RED
        // --------------------------------------------------------
        test_color("BLACK", 8'd0, 8'd0, 8'd0, 1'b0);


        // --------------------------------------------------------
        // 4. Green
        // Expected: NOT RED
        // --------------------------------------------------------
        test_color("GREEN", 8'd0, 8'd255, 8'd0, 1'b0);


        // --------------------------------------------------------
        // 5. Blue
        // Expected: NOT RED
        // --------------------------------------------------------
        test_color("BLUE", 8'd0, 8'd0, 8'd255, 1'b0);


        // --------------------------------------------------------
        // 6. Dark Red
        //
        // Red dominance exists,
        // but R is below R_MIN = 158.
        //
        // Expected: NOT RED
        // --------------------------------------------------------
        test_color("DARK RED", 8'd80, 8'd10, 8'd10, 1'b0);


        // --------------------------------------------------------
        // 7. Orange
        //
        // R is high, but green is also relatively high.
        //
        // RGB = (255, 165, 0)
        //
        // R >= G + 40:
        // 255 >= 205 -> PASS
        //
        // Therefore, with the current thresholds,
        // orange is intentionally classified as RED.
        //
        // Expected: RED
        // --------------------------------------------------------
        test_color("ORANGE", 8'd255, 8'd165, 8'd0, 1'b1);


        // --------------------------------------------------------
        // pixel_valid behavior test
        //
        // Even if the input color is red,
        // red_mask must be 0 when pixel_valid = 0.
        // --------------------------------------------------------
        test_count   = test_count + 1;

        pixel_rgb565 = rgb888_to_rgb565(8'd255, 8'd0, 8'd0);

        pixel_valid  = 1'b0;

        #1;

        if ((red_mask == 1'b0) && (red_valid == 1'b0)) begin

            pass_count = pass_count + 1;

            $display("[PASS] %-12s red_mask=%0b red_valid=%0b", "VALID LOW",
                     red_mask, red_valid);

        end else begin

            fail_count = fail_count + 1;

            $display(
                "[FAIL] %-12s expected mask=0 valid=0, actual mask=%0b valid=%0b",
                "VALID LOW", red_mask, red_valid);
        end


        // --------------------------------------------------------
        // Final result
        // --------------------------------------------------------
        $display("");
        $display(
            "============================================================");
        $display("              TEST SUMMARY");
        $display(
            "============================================================");
        $display("Total : %0d", test_count);
        $display("PASS  : %0d", pass_count);
        $display("FAIL  : %0d", fail_count);
        $display(
            "============================================================");

        if (fail_count == 0) begin
            $display("");
            $display("*************** ALL TESTS PASSED ***************");
            $display("");
        end else begin
            $display("");
            $display("*************** TEST FAILED ***************");
            $display("");
            $fatal(1, "red_color_filter test failed.");
        end

        $finish;
    end

endmodule
