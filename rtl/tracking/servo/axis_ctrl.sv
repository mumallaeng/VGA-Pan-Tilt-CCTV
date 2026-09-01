`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/09/01 11:47:50
// Design Name: 
// Module Name: axis_ctrl
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


module axis_ctrl (
    input  logic [8:0] delta_x,
    input  logic [7:0] delta_y,
    input  logic       update,
    output logic [7:0] angle_x,
    output logic [7:0] angle_y
);
endmodule
