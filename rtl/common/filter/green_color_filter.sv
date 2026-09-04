module green_color_filter #(
    // Initial threshold values; tune using the real OV7670 image.
    parameter logic [7:0] G_MIN   = 8'b1001_1110,
    parameter logic [7:0] GR_DIFF = 8'd40,
    parameter logic [7:0] GB_DIFF = 8'd40
) (
    input  wire  [15:0] pixel_rgb565,
    input  wire         pixel_valid,
    input  wire  [ 3:0] vga_r,
    input  wire  [ 3:0] vga_g,
    input  wire  [ 3:0] vga_b,
    output logic        green_mask,
    output logic        green_valid,
    output wire  [ 3:0] original_r,
    output wire  [ 3:0] original_g,
    output wire  [ 3:0] original_b,
    output wire  [ 3:0] green_r,
    output wire  [ 3:0] green_g,
    output wire  [ 3:0] green_b
);
    logic [4:0] r5;
    logic [5:0] g6;
    logic [4:0] b5;
    logic [7:0] r8;
    logic [7:0] g8;
    logic [7:0] b8;
    logic [8:0] g_ext;
    logic [8:0] r_diff_threshold;
    logic [8:0] b_diff_threshold;

    always_comb begin : RGB_component
        r5 = pixel_rgb565[15:11];
        g6 = pixel_rgb565[10:5];
        b5 = pixel_rgb565[4:0];
        r8 = {r5, r5[4:2]};
        g8 = {g6, g6[5:4]};
        b8 = {b5, b5[4:2]};
    end

    always_comb begin : green_color_detector
        g_ext            = {1'b0, g8};
        r_diff_threshold = {1'b0, r8} + {1'b0, GR_DIFF};
        b_diff_threshold = {1'b0, b8} + {1'b0, GB_DIFF};
        green_mask = 1'b0;
        if (pixel_valid) begin
            if ((g8 >= G_MIN) &&
                (g_ext >= r_diff_threshold) &&
                (g_ext >= b_diff_threshold)) begin
                green_mask = 1'b1;
            end
        end
    end

    assign green_valid = pixel_valid;

    wire mask_en;
    assign mask_en = green_valid & green_mask;
    assign green_r = {4{mask_en}};
    assign green_g = {4{mask_en}};
    assign green_b = {4{mask_en}};
    assign original_r = vga_r;
    assign original_g = vga_g;
    assign original_b = vga_b;
endmodule
