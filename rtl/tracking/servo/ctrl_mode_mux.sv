`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/09/01 11:47:50
// Design Name: 
// Module Name: ctrl_mode_mux
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


module ctrl_mode_mux(
    input en,
    input [8:0] filter_delta_x,
    input [7:0] filter_delta_y,
    input filter_valid,
    input filter_done,
    input [8:0] joy_delta_x,
    input [7:0] joy_delta_y,
    input joy_done,
    output [8:0] delta_x,
    output [7:0] delta_y,
    output sel_done,
    output acc_en
    );
endmodule
