`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/09/02 13:33:10
// Design Name: 
// Module Name: centroid_filter
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module centroid_filter (
    input  logic              pclk,
    input  logic              rst,
    input  logic              clean_mask,
    input  logic              out_valid,
    input  logic        [8:0] clean_x,
    input  logic        [7:0] clean_y,

    output logic              done,
    output logic              target_valid_out,
    output logic              valid,
    output logic        [8:0] min_x,
    output logic        [8:0] max_x,
    output logic        [7:0] min_y,
    output logic        [7:0] max_y,
    output logic signed [8:0] rect_x,
    output logic signed [7:0] rect_y
);

    logic       target_valid_in;
    logic [8:0] target_x;
    logic [7:0] target_y;

    min_max_find u_min_max_find (
        .pclk            (pclk),
        .rst             (rst),
        .clean_mask      (clean_mask),
        .out_valid       (out_valid),
        .clean_x         (clean_x),
        .clean_y         (clean_y),
        .target_valid_in (target_valid_in),
        .min_x           (min_x),
        .max_x           (max_x),
        .min_y           (min_y),
        .max_y           (max_y),
        .done            (done)
    );

    object_center u_object_center (
        .target_valid_in  (target_valid_in),
        .min_x            (min_x),
        .max_x            (max_x),
        .min_y            (min_y),
        .max_y            (max_y),
        .target_valid_out (target_valid_out),
        .target_x         (target_x),
        .target_y         (target_y)
    );

    center_error u_center_error (
        .pclk             (pclk),
        .rst              (rst),
        .frame_done       (done),
        .target_valid_out (target_valid_out),
        .target_x         (target_x),
        .target_y         (target_y),
        .valid            (valid),
        .rect_x           (rect_x),
        .rect_y           (rect_y)
    );

endmodule

