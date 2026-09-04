interface green_color_filter_interface (
    input logic clk,
    input logic rst
);
    // Define Interface signals
    logic [15:0] pixel_rgb565;
    logic        pixel_valid;
    logic [ 3:0] vga_r;
    logic [ 3:0] vga_g;
    logic [ 3:0] vga_b;
    logic        green_mask;
    logic        green_valid;
    logic [ 3:0] original_r;
    logic [ 3:0] original_g;
    logic [ 3:0] original_b;
    logic [ 3:0] green_r;
    logic [ 3:0] green_g;
    logic [ 3:0] green_b;

endinterface
