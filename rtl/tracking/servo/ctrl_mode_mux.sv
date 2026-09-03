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

    logic signed scaled_joy_dx = joy_dx * 32;  // -10~10 -> -320~320
    logic signed scaled_joy_dy = joy_dy * 24;  // -10~10 -> -240~240

    assign delta_x  = mode ? scaled_joy_dx : frame_dx;
    assign delta_y  = mode ? scaled_joy_dy : frame_dy;
    assign sel_done = mode ? joy_done : (frame_done & frame_valid);

endmodule
