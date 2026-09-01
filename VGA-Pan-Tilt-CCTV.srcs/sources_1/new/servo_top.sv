`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/09/01 11:47:50
// Design Name: 
// Module Name: servo_top
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


module servo_top(
    input [8:0] error_x,
    input [7:0] error_y,
    input vaild,
    input done,
    input mode,
    input [8:0] joy_x,
    input [7:0] joy_y,
    input joy_done,
    output pwm_pan,
    output pwn_tilt
    );
endmodule
