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
    output logic signed [9:0] delta_x,
    output logic signed [8:0] delta_y,
    output logic              sel_done
);

    logic signed [9:0] scaled_joy_dx;
    logic signed [8:0] scaled_joy_dy;

    assign scaled_joy_dx = joy_dx <<< 5;  // joy_dx * 32
    assign scaled_joy_dy = (joy_dy <<< 4) + (joy_dy <<< 3); // joy_dy * 16 + joy_dy * 8 = (joy_dy * 24)

    assign delta_x = mode ? scaled_joy_dx : frame_dx;
    assign delta_y = mode ? scaled_joy_dy : frame_dy;
    assign sel_done = mode ? 1'b1 : (frame_done & frame_valid);

endmodule
