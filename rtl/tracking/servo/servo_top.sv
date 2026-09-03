`timescale 1ns / 1ps

module servo_top (
    input  logic [8:0] frame_dx,
    input  logic [7:0] frame_dy,
    input  logic       frame_valid,
    input  logic       frame_done,
    input  logic       mode,
    input  logic [4:0] joy_dx,
    input  logic [4:0] joy_dy,
    input  logic       joy_done,
    output logic       pwm_pan,
    output logic       pwm_tilt
);
endmodule
