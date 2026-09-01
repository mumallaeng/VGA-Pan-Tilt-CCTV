//This file used for find red filter threshold
//r_min = 158 = 1001_1110


`timescale 1ns / 1ps

`default_nettype none

module red_color_filter_trs_find (
    // ------------------------------------------------------------
    // RGB565 pixel stream from OV7670 capture
    // ------------------------------------------------------------
    input wire [15:0] pixel_rgb565,
    input wire        pixel_valid,

    // ------------------------------------------------------------
    // Runtime-adjustable thresholds
    //
    // Recommended initial values:
    //   r_min   = 120
    //   rg_diff = 40
    //   rb_diff = 40
    //
    // These inputs can be connected to Vivado VIO.
    // ------------------------------------------------------------
    input wire [7:0] r_min,
    input wire [7:0] rg_diff,
    input wire [7:0] rb_diff,

    // ------------------------------------------------------------
    // Red detection result
    // ------------------------------------------------------------
    output logic red_mask,
    output logic red_valid,

    // ------------------------------------------------------------
    // Debug RGB888 values
    //
    // These outputs can also be connected to VIO/ILA
    // when checking the actual OV7670 pixel values.
    // ------------------------------------------------------------
    output logic [7:0] debug_r8,
    output logic [7:0] debug_g8,
    output logic [7:0] debug_b8,

    // ------------------------------------------------------------
    // Binary mask visualization output
    //
    // Red detected     -> White
    // Not red detected -> Black
    //
    // Directly usable as RGB444 VGA test data.
    // ------------------------------------------------------------
    output logic [3:0] mask_red,
    output logic [3:0] mask_green,
    output logic [3:0] mask_blue
);

    // ============================================================
    // RGB565 components
    // ============================================================

    logic [4:0] r5;
    logic [5:0] g6;
    logic [4:0] b5;

    logic [7:0] r8;
    logic [7:0] g8;
    logic [7:0] b8;


    // ============================================================
    // Extended values for safe comparison
    //
    // Example:
    //
    //   r8 >= g8 + rg_diff
    //
    // g8 + rg_diff may exceed 255.
    // Therefore, the comparison is performed with 9-bit values.
    // ============================================================

    logic [8:0] r_ext;
    logic [8:0] g_diff_threshold;
    logic [8:0] b_diff_threshold;


    // ============================================================
    // RGB565 extraction
    //
    // RGB565:
    //
    //   [15:11] RED   : 5 bits
    //   [10:5]  GREEN : 6 bits
    //   [4:0]   BLUE  : 5 bits
    // ============================================================

    always_comb begin
        r5 = pixel_rgb565[15:11];
        g6 = pixel_rgb565[10:5];
        b5 = pixel_rgb565[4:0];
    end


    // ============================================================
    // RGB565 -> approximately RGB888
    //
    // Bit replication is used instead of multiplication.
    //
    // 5-bit -> 8-bit
    //
    //   abcde
    //      ↓
    //   abcdeabc
    //
    // 6-bit -> 8-bit
    //
    //   abcdef
    //      ↓
    //   abcdefab
    //
    // This provides an inexpensive hardware approximation of
    // full-range RGB888 conversion.
    // ============================================================

    always_comb begin
        r8 = {r5, r5[4:2]};
        g8 = {g6, g6[5:4]};
        b8 = {b5, b5[4:2]};
    end


    // ============================================================
    // Debug outputs
    // ============================================================

    always_comb begin
        debug_r8 = r8;
        debug_g8 = g8;
        debug_b8 = b8;
    end


    // ============================================================
    // Threshold calculation
    // ============================================================

    always_comb begin
        r_ext = {1'b0, r8};

        g_diff_threshold = {1'b0, g8} + {1'b0, rg_diff};

        b_diff_threshold = {1'b0, b8} + {1'b0, rb_diff};
    end


    // ============================================================
    // Red color detection
    //
    // A pixel is classified as red when all three conditions
    // are satisfied.
    //
    //   1. R >= R_MIN
    //
    //      Rejects dark pixels.
    //
    //   2. R >= G + RG_DIFF
    //
    //      Ensures that red is sufficiently stronger than green.
    //
    //   3. R >= B + RB_DIFF
    //
    //      Ensures that red is sufficiently stronger than blue.
    //
    // Example initial thresholds:
    //
    //   R_MIN   = 120
    //   RG_DIFF = 40
    //   RB_DIFF = 40
    // ============================================================

    always_comb begin
        red_mask = 1'b0;

        if (pixel_valid) begin
            if (
                (r8    >= r_min) &&
                (r_ext >= g_diff_threshold) &&
                (r_ext >= b_diff_threshold)
            ) begin
                red_mask = 1'b1;
            end
        end
    end


    // ============================================================
    // Valid propagation
    //
    // The filter is entirely combinational, so no additional
    // pixel latency is introduced.
    // ============================================================

    assign red_valid = pixel_valid;


    // ============================================================
    // Binary-mask VGA visualization
    //
    // red_mask = 1:
    //
    //   RGB444 = 12'hFFF -> white
    //
    // red_mask = 0:
    //
    //   RGB444 = 12'h000 -> black
    //
    // This output is intended only for threshold tuning and
    // visual verification.
    // ============================================================

    always_comb begin
        mask_red   = 4'h0;
        mask_green = 4'h0;
        mask_blue  = 4'h0;

        if (pixel_valid && red_mask) begin
            mask_red   = 4'hF;
            mask_green = 4'hF;
            mask_blue  = 4'hF;
        end
    end

endmodule

`default_nettype wire
