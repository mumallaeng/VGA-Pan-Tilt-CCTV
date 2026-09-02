`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/09/02 13:02:11
// Design Name: 
// Module Name: center_error
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


module center_error(
    input logic       target_valid_out,
    input logic [8:0] target_x,
    input logic [7:0] target_y,
    output logic              valid,
    output logic signed [8:0] rect_x,
    output logic signed [7:0] rect_y
    );
    assign valid  = target_valid_out;
    assign rect_x = $signed({1'b0, target_x}) - 10'sd160;
    // VGA y increases downward, so invert the sign for Cartesian-style y.
    // Above screen center: positive, below screen center: negative.
    assign rect_y = 9'sd120 - $signed({1'b0, target_y});
endmodule

