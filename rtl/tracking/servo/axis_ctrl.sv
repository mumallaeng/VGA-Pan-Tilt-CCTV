`timescale 1ns / 1ps

module axis_ctrl (
    input  logic [8:0] delta_x,
    input  logic [7:0] delta_y,
    input  logic       update,
    output logic [7:0] angle_pan,
    output logic [7:0] angle_tilt
);
endmodule
