`timescale 1ps / 1ps

module red_color_filter #(
    //Initial Threshold Value
    //Tuned later using real ov7670
    parameter logic [7:0] R_MIN   = 8'b1001_1110,
    parameter logic [7:0] RG_DIFF = 8'd40,
    parameter logic [7:0] RB_DIFF = 8'd40
) (
    input  wire [15:0] pixel_rgb565,
    input  wire        pixel_valid,
    output      [ 3:0] mask_r,
    output      [ 3:0] mask_g,
    output      [ 3:0] mask_b
);
    // red mask & valid signal
    logic red_mask;
    logic red_valid;
    //-------------------------------------------------
    // RGB565 extraction
    //-------------------------------------------------
    logic [4:0] r5;
    logic [5:0] g6;
    logic [4:0] b5;

    //expand rgb565 to rgb888
    logic [7:0] r8;
    logic [7:0] g8;
    logic [7:0] b8;

    //9-bit -> prevent overflow
    logic [8:0] r_ext;
    logic [8:0] g_diff_threshold;
    logic [8:0] b_diff_threshold;

    //-------------------------------------------------
    // RGB565 -> RGB Component
    //-------------------------------------------------
    always_comb begin : RGB_component
        r5 = pixel_rgb565[15:11];
        g6 = pixel_rgb565[10:5];
        b5 = pixel_rgb565[4:0];

        //rgb565 -> rgb888
        // Expand RGB565 components to 8-bit by replicating MSBs.
        // This approximates scaling to the full 0–255 range without multipliers/dividers.
        //
        // 5-bit -> 8-bit: abcde  -> abcdeabc
        // 6-bit -> 8-bit: abcdef -> abcdefab
        r8 = {r5, r5[4:2]};
        g8 = {g6, g6[5:4]};
        b8 = {b5, b5[4:2]};
    end

    always_comb begin : red_color_detector
        r_ext            = {1'b0, r8};
        g_diff_threshold = {1'b0, g8} + {1'b0, RG_DIFF};
        b_diff_threshold = {1'b0, b8} + {1'b0, RB_DIFF};

        red_mask         = 1'b0;
        if (pixel_valid) begin
            if((r8 >= R_MIN)&&(r_ext>=g_diff_threshold)&&(r_ext>=b_diff_threshold))begin
                red_mask = 1'b1;
            end
        end
    end

    assign red_valid = pixel_valid;

    //-------------------------------------------------
    // Convert the one-bit filter result to an RGB444 binary mask
    //-------------------------------------------------
    wire mask_en;
    assign mask_en = red_valid & red_mask;

    assign mask_r  = {4{mask_en}};
    assign mask_g  = {4{mask_en}};
    assign mask_b  = {4{mask_en}};
endmodule
