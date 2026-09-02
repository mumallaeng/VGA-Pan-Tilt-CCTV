`timescale 1ns / 1ps

module ctrl_mode_mux (
    // 0: AUTO(filter), 1: MANUAL(joystick)
    input  logic              en,
    input  logic signed [8:0] filter_delta_x,
    input  logic signed [7:0] filter_delta_y,
    input  logic              filter_valid,
    input  logic              filter_done,
    input  logic signed [8:0] joy_delta_x,
    input  logic signed [7:0] joy_delta_y,
    input  logic              joy_done,
    output logic signed [8:0] delta_x,
    output logic signed [7:0] delta_y,
    output logic              sel_done
);

    assign delta_x  = en ? joy_delta_x : filter_delta_x;
    assign delta_y  = en ? joy_delta_y : filter_delta_y;
    assign sel_done = en ? joy_done : (filter_done & filter_valid);

endmodule
