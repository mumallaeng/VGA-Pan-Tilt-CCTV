`timescale 1ns / 1ps

module draw_box (
    input  [ 9:0] x_pixel,
    input  [ 9:0] y_pixel,
    input  [15:0] rd_data,
    input  [ 8:0] draw_x,
    input  [ 7:0] draw_y,
    output        box_en
);
    // enable signal to select raw image or Red image
    wire x_en, y_en;

    assign x_en   = (x_pixel[9:1] == draw_x) ? 1'b1 : 1'b0;
    assign y_en   = (y_pixel[9:1] == {1'b0, draw_y}) ? 1'b1 : 1'b0;
    assign box_en = x_en & y_en;

endmodule
