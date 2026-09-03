`timescale 1ns / 1ps

module ctrl_mode_mux (
    // 0: AUTO(frame), 1: MANUAL(joystick)
    input  logic              mode,
    input  logic signed [9:0] frame_dx,
    input  logic signed [8:0] frame_dy,
    input  logic              frame_valid,
    input  logic              frame_done,
    input  logic signed [4:0] joy_dx,
    input  logic signed [4:0] joy_dy,
    input  logic              joy_done,
    output logic signed [9:0] delta_x,
    output logic signed [8:0] delta_y,
    output logic              sel_done
);

    logic signed [9:0] scaled_joy_dx;
    logic signed [8:0] scaled_joy_dy;

    // Map the joystick's nominal -10..+10 range onto the centered
    // 320x240 image-coordinate ranges: X -160..+160, Y -120..+120.
    assign scaled_joy_dx = $signed(joy_dx) * 10'sd16;
    assign scaled_joy_dy = $signed(joy_dy) * 9'sd12;

    assign delta_x  = mode ? scaled_joy_dx : frame_dx;
    assign delta_y  = mode ? scaled_joy_dy : frame_dy;
    assign sel_done = mode ? joy_done : (frame_done & frame_valid);

endmodule
